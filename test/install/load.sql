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

/*
 * Mode selection: 'fresh' installs the current version directly; 'update'
 * installs the oldest version we still ship a full script for (0.9.6) and
 * runs ALTER EXTENSION UPDATE, committed (this file runs outside any
 * per-test rolled-back transaction, unlike the old test/deps.sql approach -
 * see pgxntool/README.asc's U&U section for why the commit matters);
 * 'existing' asserts count_nulls is already installed (a real `pg_upgrade`
 * run, external to this invocation) and touches nothing.
 *
 * Read without missing_ok: a genuinely unpropagated GUC must fail loudly,
 * not be indistinguishable from a deliberately empty one.
 */
SELECT current_setting('count_nulls.test_load_mode')              AS count_nulls_test_load_mode
     , current_setting('count_nulls.test_load_mode') = 'update'   AS count_nulls_update_mode
     , current_setting('count_nulls.test_load_mode') = 'existing' AS count_nulls_existing_mode
\gset

DO $$
BEGIN
  IF current_setting('count_nulls.test_load_mode') NOT IN ('fresh', 'update', 'existing') THEN
    RAISE EXCEPTION
      'count_nulls.test_load_mode must be ''fresh'', ''update'' or ''existing'', got ''%'''
      , current_setting('count_nulls.test_load_mode')
    ;
  END IF;
END
$$;

\if :count_nulls_existing_mode
/*
 * Already installed by something external to this pg_regress invocation
 * (a real pg_upgrade run - see the pg-upgrade-test CI job). Only assert
 * it's present and at the current version; do NOT drop/create/update it -
 * the whole point of this mode is testing the REAL migrated objects.
 */
DO $$
DECLARE
  v_installed text := (SELECT extversion FROM pg_extension WHERE extname = 'count_nulls');
  v_default   text := (SELECT default_version FROM pg_available_extensions WHERE name = 'count_nulls');
BEGIN
  IF v_installed IS NULL THEN
    RAISE EXCEPTION 'count_nulls.test_load_mode=existing but count_nulls is not installed';
  END IF;
  IF v_installed IS DISTINCT FROM v_default THEN
    RAISE EXCEPTION 'count_nulls installed at % but default_version is %', v_installed, v_default;
  END IF;
END
$$;
\else
/*
 * fresh/update: creation (fresh, randomly named schema; install at
 * :version or current) is shared with bin/test_existing's prepare-old via
 * test/helpers/create_test_schema.sql - see that file for the full
 * rationale. 'update' additionally installs the oldest version we still
 * ship a full script for, then upgrades it in place.
 */
\if :count_nulls_update_mode
\set version '0.9.6'
\i test/helpers/create_test_schema.sql
/*
 * Suppress the "already installed, no update" NOTICE class of messages any
 * update script might emit.
 */
SET client_min_messages = WARNING;
ALTER EXTENSION count_nulls UPDATE;
SET client_min_messages = NOTICE;
\else
\set version ''
\i test/helpers/create_test_schema.sql
\endif
\endif
