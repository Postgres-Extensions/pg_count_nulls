\set ECHO none
\set VERBOSITY verbose

BEGIN;

-- Unlike the other test files, this one doesn't route through
-- test/deps.sql - it's meant to be a minimal, standalone smoke test. It
-- still has to respect TEST_SCHEMA/TEST_LOAD_SOURCE though: under 'existing'
-- mode the extension is already installed (CREATE EXTENSION would error),
-- and either way the calls below are unqualified, so search_path needs to
-- include wherever count_nulls actually lives.
SELECT current_setting('count_nulls.test_load_mode') = 'existing' AS count_nulls_existing_mode
\gset
SELECT current_setting('count_nulls.test_schema') AS schema
\gset

\if :count_nulls_existing_mode
SET search_path = :"schema";
\else
-- IF NOT EXISTS emits a NOTICE for the (very common) case of :"schema"
-- being 'public', which always already exists.
SET client_min_messages = WARNING;
CREATE SCHEMA IF NOT EXISTS :"schema";
SET search_path = :"schema";
SET client_min_messages = NOTICE;
CREATE EXTENSION count_nulls;
\endif

-- Remember that JSON only accepts 'null'
SELECT null_count('{"a": null}'::jsonb);
SELECT null_count(1,NULL);

\echo TRANSACTION INTENTIONALLY LEFT OPEN
