\set ECHO none

\i test/load.sql

\i test/core/functions.sql

/*
 * count_nulls is installed by test/install/load.sql with no schema
 * targeting - it lands wherever the session's own search_path resolves at
 * CREATE EXTENSION time (in-suite, that's pgTap's own schema, put on
 * search_path first by test/pgxntool/tap_setup.sql). This just proves
 * ncs() actually resolves to something real; a future TEST_SCHEMA switch
 * (see pgxntool/README.asc's U&U section) would let this assert an exact,
 * known location instead.
 */
CREATE FUNCTION _null_count_test.test__check_ncs
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
BEGIN
    RETURN NEXT isnt(
        ncs()
        , NULL
        , 'ncs() resolves to the schema count_nulls actually installed in'
    );
END
$body$;

CREATE FUNCTION _null_count_test.test__shutdown__drop_all
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
BEGIN
    RETURN NEXT lives_ok(
        $$DROP EXTENSION count_nulls$$
    );
END
$body$;

--SET client_min_messages = debug;

SELECT * FROM runtests( '_null_count_test'::name );
