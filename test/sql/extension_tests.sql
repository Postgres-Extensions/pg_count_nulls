\set ECHO none

\set schema schema_to_load_count_nulls
\i test/load.sql

\set schema public
\i test/core/functions.sql

--CREATE OR REPLACE FUNCTION ncs() RETURNS name LANGUAGE sql IMMUTABLE AS $$SELECT 'schema_to_load_count_nulls'::name$$;

CREATE FUNCTION _null_count_test.test__check_ncs
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
    s CONSTANT name = 'schema_to_load_count_nulls';
BEGIN
    RETURN NEXT is(
        ncs()
        , s
    );
    RETURN NEXT is(
        current_schemas(true) @> array[s]
        , false
        --, format('schema %I should not be in search path (%s)', s, current_schemas(true))
        , format('schema %I should not be in search path', s) --, current_schemas(true))
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
        $$DROP SCHEMA schema_to_load_count_nulls$$
    );
END
$body$;

--SET client_min_messages = debug;

SELECT * FROM runtests( '_null_count_test'::name );
