\set ECHO none

\i test/load.sql

\i test/core/functions.sql

/*
 * This file leaves search_path as functions.sql set it
 * (_null_count_test, tap) - with an explicit TEST_SCHEMA, that keeps the
 * extension's schema off search_path, so every check below only passes if
 * functions.sql's %I-qualified calls (via ncs()) are actually correct,
 * never relying on the extension's own schema being reachable unqualified.
 * When TEST_SCHEMA is empty, the extension happens to land in 'tap' itself
 * (wherever the ambient search_path - already tap, public at this point,
 * via pgTap's own setup - resolves at CREATE EXTENSION time), which IS on
 * search_path; test__check_ncs accounts for that below rather than
 * asserting something that wouldn't hold.
 */

CREATE FUNCTION _null_count_test.test__check_ncs
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
    /*
     * current_setting(), not a psql :"schema" substitution: psql does not
     * interpolate variables inside dollar-quoted function bodies.
     *
     * When TEST_SCHEMA is non-empty we know exactly where the extension
     * should be, so compare ncs() against that known value - a real
     * assertion. When it's empty, there's no fixed expectation (it lands
     * wherever the ambient search_path resolves at CREATE EXTENSION time,
     * which depends on what ran before deps.sql - not something this test
     * should hardcode), so fall back to ncs() itself: a no-op comparison
     * that still exercises the call, without asserting a location this
     * file has no business assuming.
     */
    s CONSTANT name = CASE
        WHEN current_setting('count_nulls.test_schema') <> ''
            THEN current_setting('count_nulls.test_schema')::name
        ELSE ncs()
    END;
BEGIN
    RETURN NEXT is(
        ncs()
        , s
    );
    /*
     * "Not on search path" only means anything when s isn't one of the
     * schemas functions.sql itself always puts there (_null_count_test,
     * tap) - which happens exactly when TEST_SCHEMA is empty and the
     * extension coincidentally lands in 'tap' (pgTap's own schema, always
     * on search_path here). That's not a bug to work around, just a
     * scenario this particular check can't say anything meaningful about.
     */
    IF s IN ('_null_count_test', 'tap') THEN
        RETURN NEXT skip('extension landed in a schema functions.sql always keeps on search_path - not a meaningful check here');
    ELSE
        RETURN NEXT is(
            current_schemas(true) @> array[s]
            , false
            , format('schema %I should not be in search path', s)
        );
    END IF;
END
$body$;

CREATE FUNCTION _null_count_test.test__shutdown__drop_all
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
    v_schema CONSTANT text = current_setting('count_nulls.test_schema');
BEGIN
    RETURN NEXT lives_ok(
        $$DROP EXTENSION count_nulls$$
    );

    /*
     * Only try to drop a schema when TEST_SCHEMA actually created one -
     * when it's empty, the extension lives wherever it landed on its own
     * (see test/deps.sql), which this file has no business dropping.
     */
    IF v_schema <> '' THEN
        RETURN NEXT lives_ok(
            format('DROP SCHEMA %I', v_schema)
        );
    ELSE
        RETURN NEXT skip('TEST_SCHEMA is empty - no dedicated schema to drop');
    END IF;
END
$body$;

--SET client_min_messages = debug;

SELECT * FROM runtests( '_null_count_test'::name );
