/*
 * Installs count_nulls once, committed, before the main test/sql/ schedule
 * runs (see pgxntool/README.asc's "test/install" and "Update & Upgrade (U&U)
 * Testing" sections) - so every file under test/sql/ finds it already
 * present instead of each one installing (and dropping) it per-test.
 *
 * This file's own output is NOT tracked as expected output (see
 * test/install/.gitignore): pg_regress resolves both its expected and
 * actual-result paths to test/install/load.out, so the diff is always
 * self-identical regardless of content. Correctness here comes from this
 * file failing loudly (aborting the session) if something's wrong, not
 * from a textual comparison - matching cat_tools' test/install/load.sql.
 */

-- CRITICAL: without this an error goes undetected, causing unpredictable results
\set ON_ERROR_STOP on

-- TODO: this file's mode branching could move back to \if once PG10 is the floor

/*
 * Definitions only - safe to load before the test-user switch below.
 * Cleanup runs next, as the connecting role (a leftover schema can belong to
 * any role, and only the connecting one is sure to be able to drop it), then
 * the switch, then the actual install.
 */
\i test/helpers/extension_installer.sql

/*
 * count_nulls_load_mode is gset here rather than read again by
 * use_test_user.sql itself, for the same reason noted on that file: the
 * GUC isn't set for every invocation that \i's it, so every includer must
 * supply it explicitly.
 */
SELECT pg_temp.count_nulls_cleanup_test_schemas(
  current_setting('count_nulls.test_load_mode')
) AS count_nulls_cleaned_up
     , current_setting('count_nulls.test_load_mode') AS count_nulls_load_mode
\gset

\i test/helpers/use_test_user.sql

/*
 * Mode selection: 'fresh' installs the current version directly; 'update'
 * installs the oldest version we still ship a full script for and runs
 * ALTER EXTENSION UPDATE, committed (this file runs outside any per-test
 * rolled-back transaction - see pgxntool/README.asc's U&U section for why
 * the commit matters); 'existing' asserts count_nulls is already installed
 * (a real pg_upgrade run, or a pg_tle registration, external to this
 * invocation) and touches nothing.
 */
CREATE OR REPLACE FUNCTION pg_temp.count_nulls_load(
  p_mode text
  , p_deploy text
) RETURNS void LANGUAGE plpgsql AS $body$
DECLARE
  -- The oldest version we still ship a full install script for
  c_oldest_full_install CONSTANT text := '0.9.6';
  v_installed text;
  v_default   text;
BEGIN
  IF p_mode NOT IN ('fresh', 'update', 'existing') THEN
    RAISE EXCEPTION
      $msg$count_nulls.test_load_mode must be 'fresh', 'update' or 'existing', got '%'$msg$
      , p_mode
    ;
  END IF;

  IF p_mode = 'existing' THEN
    /*
     * Already installed by something external to this pg_regress invocation
     * (a real pg_upgrade run, or a pg_tle registration - see the
     * pg-upgrade-test / pg-tle-test CI jobs). Only assert it's present and
     * at the current version; do NOT drop/create/update it - the whole
     * point of this mode is testing the REAL migrated/deployed objects.
     */
    v_installed := (SELECT extversion FROM pg_extension WHERE extname = 'count_nulls');

    IF v_installed IS NULL THEN
      RAISE EXCEPTION 'count_nulls.test_load_mode=existing but count_nulls is not installed';
    END IF;

    /*
     * Where "the current version" comes from depends on how count_nulls got
     * here (see the TEST_EXISTING_DEPLOY comment in the Makefile):
     *
     *   - filesystem: pg_available_extensions.default_version, read straight
     *     from a real .control file on disk.
     *   - pgtle: count_nulls was registered purely through pg_tle's
     *     database-backed catalog, never touching the filesystem.
     *     pg_available_extensions does NOT see pg_tle registrations at all -
     *     it only ever reads .control files off disk - so it comes back NULL
     *     even though CREATE EXTENSION correctly resolves the default
     *     version through pg_tle. pg_tle ships its own separate,
     *     non-integrated analog: pgtle.available_extensions() (see pg_tle's
     *     tleextension.c, which documents pg_available_extensions as merely
     *     modeled on this SRF, not backed by it). Use that here rather than
     *     weakening the check for the filesystem case.
     *
     * plpgsql parses a statement only when it first executes, so the pgtle
     * reference below costs nothing on a cluster without pg_tle installed.
     */
    IF p_deploy = 'pgtle' THEN
      SELECT default_version INTO v_default
        FROM pgtle.available_extensions() WHERE name = 'count_nulls';
    ELSIF p_deploy = 'filesystem' THEN
      SELECT default_version INTO v_default
        FROM pg_available_extensions WHERE name = 'count_nulls';
    ELSE
      RAISE EXCEPTION
        $msg$count_nulls.test_existing_deploy must be 'filesystem' or 'pgtle', got '%'$msg$
        , p_deploy
      ;
    END IF;

    IF v_installed IS DISTINCT FROM v_default THEN
      RAISE EXCEPTION
        'count_nulls installed at % but default_version (deploy=%) is %'
        , v_installed, p_deploy, v_default
      ;
    END IF;

    RETURN;
  END IF;

  IF p_mode = 'update' THEN
    PERFORM pg_temp.count_nulls_install_extension(c_oldest_full_install);

    /*
     * Deliberately no client_min_messages suppression around this. Postgres
     * already raises it to at least WARNING for the duration of an update
     * script and restores the caller's setting afterwards, so setting it
     * here would be redundant - and, being unconditional, would lower the
     * level for a caller who had deliberately set something stricter.
     */
    ALTER EXTENSION count_nulls UPDATE;
  ELSE
    PERFORM pg_temp.count_nulls_install_extension('current');
  END IF;
END
$body$;

/*
 * Read without missing_ok: a genuinely unpropagated GUC must fail loudly,
 * not be indistinguishable from a deliberately empty one. (current_setting's
 * missing_ok argument is 9.6 anyway, and CI covers 9.4.)
 */
SELECT pg_temp.count_nulls_load(
    current_setting('count_nulls.test_load_mode')
    , current_setting('count_nulls.test_existing_deploy')
  ) AS count_nulls_loaded
\gset

-- vi: expandtab sw=2 ts=2
