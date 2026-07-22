\set ECHO none

\i test/load.sql

\i test/core/functions.sql

-- Unlike extension_tests.sql, this file tests count_nulls used unqualified
-- (i.e. installed schema IS on search_path), regardless of which schema
-- TEST_SCHEMA (test/deps.sql's :"schema") actually names.
SET SEARCH_PATH = _null_count_test, tap, :"schema";

--SET client_min_messages = debug;

SELECT * FROM runtests( '_null_count_test'::name );
