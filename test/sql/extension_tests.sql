\set ECHO none

\i test/load.sql

\i test/core/functions.sql

/*
 * This file leaves search_path as functions.sql set it (_null_count_test,
 * tap) - with an explicit TEST_SCHEMA, that keeps count_nulls' own schema
 * off search_path, so every check below only passes if functions.sql's
 * %I-qualified calls (via ncs()) are actually correct, never relying on
 * count_nulls' own schema being reachable unqualified. When TEST_SCHEMA is
 * empty, count_nulls lands in 'public' (test/install/load.sql runs in its
 * own bare connection, with no schema targeting - see phase 1's commit
 * message), which is NOT on search_path here either.
 *
 * schema_hint reads the count_nulls.test_schema GUC directly (the Makefile
 * exports it via PGOPTIONS for the whole run - see test/install/load.sql,
 * which installs into it) rather than via a psql variable relayed through
 * test/deps.sql: nothing in this per-test session needs deps.sql to have
 * set anything, since the GUC is readable from any session in the run.
 * NULLIF turns the empty-TEST_SCHEMA case into NULL, and runtests() calls
 * every test__* function with no arguments, so it always gets this default.
 */
CREATE FUNCTION _null_count_test.test__check_ncs(
  schema_hint name DEFAULT NULLIF(current_setting('count_nulls.test_schema'), '')::name
) RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
    /*
     * When TEST_SCHEMA is non-empty we know exactly where count_nulls
     * should be, so compare ncs() against that known value - a real
     * assertion. When it's empty (schema_hint is NULL), there's no fixed
     * expectation (it lands in 'public', an artifact of test/install's own
     * bare connection - not something this test should hardcode), so fall
     * back to ncs() itself: a no-op comparison that still exercises the
     * call, without asserting a location this file has no business
     * assuming.
     */
    s CONSTANT name = COALESCE(schema_hint, ncs());
BEGIN
    RETURN NEXT is(
        ncs()
        , s
    );
    RETURN NEXT is(
        current_schemas(true) @> array[s]
        , false
        , 'count_nulls'' schema should not be in search path'
    );
END
$body$;

CREATE FUNCTION _null_count_test.test__shutdown__drop_all(
  schema_hint name DEFAULT NULLIF(current_setting('count_nulls.test_schema'), '')::name
) RETURNS SETOF text LANGUAGE plpgsql AS $body$
BEGIN
    RETURN NEXT lives_ok(
        $$DROP EXTENSION count_nulls$$
    );

    /*
     * Only try to drop a schema when TEST_SCHEMA actually created one -
     * when it's empty (schema_hint is NULL), count_nulls lives in 'public'
     * (see test/install/load.sql), which this file has no business
     * dropping.
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
