-- Add any test dependency statements here

/*
 * Mode selection: 'fresh' installs the current version directly; 'update'
 * installs the oldest version we still ship a full script for (0.9.6) and
 * runs ALTER EXTENSION UPDATE; 'existing' asserts the extension is already
 * installed (a real `pg_upgrade` leg, or an out-of-band update) and touches
 * nothing. Since every test file loads this via test/load.sql, running the
 * suite in each mode (make test / make test-update / make test
 * TEST_LOAD_SOURCE=existing) exercises the SAME tests against a fresh vs.
 * updated vs. really-upgraded install, with the same expected output either
 * way.
 *
 * "update" here is extension-level (ALTER EXTENSION UPDATE); it is not
 * "upgrade" (cluster-level pg_upgrade) - 'existing' is how that axis is
 * exercised, via a real pg_upgrade run outside this test suite (see the
 * pg_upgrade CI job).
 *
 * The Makefile always exports this GUC, so we read it without missing_ok:
 * if it failed to propagate we want a loud error here, not a silent
 * fall-through to 'fresh'.
 */
SELECT current_setting('count_nulls.test_load_mode') AS count_nulls_test_load_mode
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

SELECT :'count_nulls_test_load_mode' = 'update'   AS count_nulls_update_mode
\gset
SELECT :'count_nulls_test_load_mode' = 'existing' AS count_nulls_existing_mode
\gset

/*
 * TEST_SCHEMA (the count_nulls.test_schema GUC, set via the Makefile):
 * which schema the extension is installed into, for the WHOLE test run -
 * the SAME schema for every test file, not a different literal hardcoded
 * per file. Empty (the default) means "don't target any schema at all" -
 * the extension lands wherever the session's own default search_path
 * already resolves. Non-empty explicitly creates and targets that schema,
 * including a schema whose name requires SQL identifier quoting (mixed
 * case - unquoted would fold to lowercase), to exercise test files' %I
 * schema-qualification rather than just their literal test data. Both the
 * empty and non-empty cases are exercised in CI - genuinely different code
 * paths, not one a redundant special case of the other.
 *
 * Read with :"schema" (quoted-identifier form) wherever used as a bare
 * identifier below and in the test files, since the quoting-required case
 * is exactly what the non-empty case exists to exercise.
 *
 * Read without missing_ok, same reasoning as count_nulls.test_load_mode
 * above: a genuinely unpropagated GUC must fail loudly, not be
 * indistinguishable from a deliberately empty one.
 */
SELECT current_setting('count_nulls.test_schema') AS schema
\gset
SELECT :'schema' <> '' AS count_nulls_has_schema
\gset

\if :count_nulls_has_schema
/*
 * :"schema" is created/searched in every mode that has one, including
 * 'existing' (even though 'existing' mode never installs the extension
 * into it): test files (e.g. test__shutdown__drop_all's
 * `DROP SCHEMA :"schema"`) expect it to exist regardless of mode, and an
 * empty schema is harmless. IF NOT EXISTS emits NOTICEs, which is annoying.
 */
SET client_min_messages = WARNING;
CREATE SCHEMA IF NOT EXISTS :"schema";
SET search_path = :"schema";
SET client_min_messages = NOTICE;
\endif

\if :count_nulls_existing_mode
/*
 * Extension is already installed (real pg_upgrade, or an out-of-band
 * update) - assert it's present and current, but do NOT drop/create/update
 * it. The CI job driving this mode is responsible for having installed the
 * real extension matching this run's TEST_SCHEMA (or the default location,
 * if empty) before getting here, so the rest of the suite sees the same
 * schema regardless of mode.
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
\elif :count_nulls_update_mode
CREATE EXTENSION count_nulls VERSION '0.9.6';
-- Suppress the "already installed, no update" NOTICE class of messages any
-- update script might emit.
SET client_min_messages = WARNING;
ALTER EXTENSION count_nulls UPDATE;
SET client_min_messages = NOTICE;
\else
CREATE EXTENSION count_nulls;
\endif
