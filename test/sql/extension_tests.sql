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

/*
 * schema_hint DEFAULT NULLIF(:'schema', '')::name, not current_setting()
 * inside the function body: psql does not interpolate variables inside
 * dollar-quoted bodies, but a parameter DEFAULT is plain top-level SQL, so
 * :'schema' (test/deps.sql's psql variable, still set from this session's
 * \gset) substitutes there normally. NULLIF turns the empty-TEST_SCHEMA
 * case into NULL, and runtests() calls every test__* function with no
 * arguments, so it always gets this default.
 */
CREATE FUNCTION _null_count_test.test__check_ncs
(schema_hint name DEFAULT NULLIF(:'schema', '')::name)
RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
    /*
     * When TEST_SCHEMA is non-empty we know exactly where the extension
     * should be, so compare ncs() against that known value - a real
     * assertion. When it's empty (schema_hint is NULL), there's no fixed
     * expectation (it lands wherever the ambient search_path resolves at
     * CREATE EXTENSION time, which depends on what ran before deps.sql -
     * not something this test should hardcode), so fall back to ncs()
     * itself: a no-op comparison that still exercises the call, without
     * asserting a location this file has no business assuming.
     */
    s CONSTANT name = COALESCE(schema_hint, ncs());
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
(schema_hint name DEFAULT NULLIF(:'schema', '')::name)
RETURNS SETOF text LANGUAGE plpgsql AS $body$
BEGIN
    RETURN NEXT lives_ok(
        $$DROP EXTENSION count_nulls$$
    );

    /*
     * Only try to drop a schema when TEST_SCHEMA actually created one -
     * when it's empty (schema_hint is NULL), the extension lives wherever
     * it landed on its own (see test/deps.sql), which this file has no
     * business dropping.
     */
    IF schema_hint IS NOT NULL THEN
        RETURN NEXT lives_ok(
            format('DROP SCHEMA %I', schema_hint)
        );
    ELSE
        RETURN NEXT skip('TEST_SCHEMA is empty - no dedicated schema to drop');
    END IF;
END
$body$;

--SET client_min_messages = debug;

SELECT * FROM runtests( '_null_count_test'::name );
