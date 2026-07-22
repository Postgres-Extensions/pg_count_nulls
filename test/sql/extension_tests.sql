\set ECHO none

\i test/load.sql

\i test/core/functions.sql

-- Unlike simple.sql, this file deliberately leaves search_path as
-- functions.sql set it (_null_count_test, tap) - the schema count_nulls is
-- installed into (TEST_SCHEMA / test/deps.sql's :"schema") stays off
-- search_path, so every check below only passes if functions.sql's
-- %I-qualified calls (via ncs()) are actually correct, regardless of which
-- schema TEST_SCHEMA names.

CREATE FUNCTION _null_count_test.test__check_ncs
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
    -- current_setting(), not a psql :"schema" substitution: psql does not
    -- interpolate variables inside dollar-quoted function bodies.
    s CONSTANT name = current_setting('count_nulls.test_schema')::name;
BEGIN
    RETURN NEXT is(
        ncs()
        , s
    );
    RETURN NEXT is(
        current_schemas(true) @> array[s]
        , false
        , format('schema %I should not be in search path', s)
    );
END
$body$;

CREATE FUNCTION _null_count_test.test__shutdown__drop_all
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
BEGIN
    RETURN NEXT lives_ok(
        $$DROP EXTENSION count_nulls$$
    );

    RETURN NEXT lives_ok(
        format('DROP SCHEMA %I', current_setting('count_nulls.test_schema'))
    );
END
$body$;

--SET client_min_messages = debug;

SELECT * FROM runtests( '_null_count_test'::name );
