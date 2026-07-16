-- Add any test dependency statements here
-- IF NOT EXISTS will emit NOTICEs, which is annoying
SET client_min_messages = WARNING;
CREATE SCHEMA IF NOT EXISTS :schema;
SET search_path = :schema;
SET client_min_messages = NOTICE;

/*
 * Mode selection: 'fresh' installs the current version directly; 'update'
 * installs the oldest version we still ship a full script for (0.9.6) and
 * runs ALTER EXTENSION UPDATE. Since every test file loads this via
 * test/load.sql, running the suite in each mode (make test / make
 * test-update) exercises the SAME tests against a fresh vs. an updated
 * install, with the same expected output either way.
 *
 * "update" here is extension-level (ALTER EXTENSION UPDATE); it is not
 * "upgrade" (cluster-level pg_upgrade), a separate axis this doesn't cover.
 *
 * The Makefile always exports this GUC, so we read it without missing_ok:
 * if it failed to propagate we want a loud error here, not a silent
 * fall-through to 'fresh'.
 */
SELECT current_setting('count_nulls.test_load_mode') AS count_nulls_test_load_mode
\gset

DO $$
BEGIN
  IF current_setting('count_nulls.test_load_mode') NOT IN ('fresh', 'update') THEN
    RAISE EXCEPTION
      'count_nulls.test_load_mode must be ''fresh'' or ''update'', got ''%'''
      , current_setting('count_nulls.test_load_mode')
    ;
  END IF;
END
$$;

SELECT :'count_nulls_test_load_mode' = 'update' AS count_nulls_update_mode
\gset

\if :count_nulls_update_mode
CREATE EXTENSION count_nulls VERSION '0.9.6';
-- Suppress the "already installed, no update" NOTICE class of messages any
-- update script might emit.
SET client_min_messages = WARNING;
ALTER EXTENSION count_nulls UPDATE;
SET client_min_messages = NOTICE;
\else
CREATE EXTENSION count_nulls;
\endif
