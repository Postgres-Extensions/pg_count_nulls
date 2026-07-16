-- Add any test dependency statements here
-- IF NOT EXISTS will emit NOTICEs, which is annoying
SET client_min_messages = WARNING;
CREATE SCHEMA IF NOT EXISTS :schema;
SET search_path = :schema;
SET client_min_messages = NOTICE;

/*
 * Mode selection: 'fresh' installs the current version directly; 'upgrade'
 * installs the oldest version we still ship a full script for (0.9.6) and
 * runs ALTER EXTENSION UPDATE. Since every test file loads this via
 * test/load.sql, running the suite in each mode (make test / make
 * test-update) exercises the SAME tests against a fresh vs. an upgraded
 * install, with the same expected output either way.
 *
 * The Makefile always exports this GUC, so we read it without missing_ok:
 * if it failed to propagate we want a loud error here, not a silent
 * fall-through to 'fresh'.
 */
SELECT current_setting('count_nulls.test_load_mode') AS count_nulls_test_load_mode
\gset

DO $$
BEGIN
  IF current_setting('count_nulls.test_load_mode') NOT IN ('fresh', 'upgrade') THEN
    RAISE EXCEPTION
      'count_nulls.test_load_mode must be ''fresh'' or ''upgrade'', got ''%'''
      , current_setting('count_nulls.test_load_mode')
    ;
  END IF;
END
$$;

SELECT :'count_nulls_test_load_mode' = 'upgrade' AS count_nulls_upgrade_mode
\gset

\if :count_nulls_upgrade_mode
CREATE EXTENSION count_nulls VERSION '0.9.6';
-- Suppress the "already installed, no update" NOTICE class of messages any
-- upgrade script might emit.
SET client_min_messages = WARNING;
ALTER EXTENSION count_nulls UPDATE;
SET client_min_messages = NOTICE;
\else
CREATE EXTENSION count_nulls;
\endif
