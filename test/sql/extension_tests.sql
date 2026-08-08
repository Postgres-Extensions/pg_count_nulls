\set ECHO none

\i test/load.sql

\i test/core/functions.sql

/*
 * This file leaves search_path as functions.sql set it (_null_count_test,
 * tap), and count_nulls always installs into its own freshly, randomly
 * generated schema (see test/install/load.sql) - which is never on that
 * search_path. So every check below only passes if functions.sql's
 * %I-qualified calls (via ncs()) are actually correct, never relying on
 * count_nulls' own schema being reachable unqualified.
 *
 * This also means test/expected/extension_tests.out stays identical run to
 * run regardless of which random name the schema gets: none of the pgTAP
 * assertion descriptions below embed the actual schema name (see
 * test/README.md's "Assertion descriptions deliberately never embed the
 * schema name" section for the full rationale), so no numbered pg_regress
 * alternate is ever needed for it.
 */
CREATE FUNCTION _null_count_test.test__check_ncs(
) RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
    /*
     * We never expect count_nulls' own schema to be in search_path in this
     * file: functions.sql unconditionally sets search_path to exclude it
     * (see the header comment above). s is still real, independently
     * determined content (via ncs()), so the membership check below
     * genuinely exercises functions.sql's %I-qualification and load.sql's
     * schema targeting - it isn't a tautology.
     *
     * SEE ALSO: teardown__search_path_unchanged in test/core/functions.sql,
     * which guards against some OTHER test mutating search_path mid-suite (a
     * different risk than this check).
     */
    s CONSTANT name = ncs();
BEGIN
    RETURN NEXT is(
        current_schemas(true) @> array[s]
        , false
        , $$count_nulls' schema should not be in search path$$
    );
END
$body$;

CREATE FUNCTION _null_count_test.test__shutdown__drop_all(
) RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
    /*
     * Captured before DROP EXTENSION: ncs() looks the schema up live via
     * pg_extension, which can't resolve anything once the extension is
     * gone.
     */
    s CONSTANT name = ncs();
BEGIN
    RETURN NEXT lives_ok(
        $$DROP EXTENSION count_nulls$$
    );

    /*
     * Plain cleanup, not a TAP assertion - dropping the schema count_nulls
     * was installed into isn't something this suite is testing, just
     * tearing down what test/install/load.sql created. Every run always
     * has a schema to drop (there's no longer an "installed with no
     * schema targeting" case). If the DROP SCHEMA itself ever failed, the
     * unhandled exception aborts the run loudly on its own - no lives_ok()
     * needed for that.
     */
    EXECUTE format('DROP SCHEMA %I', s);
END
$body$;

--SET client_min_messages = debug;

SELECT * FROM runtests( '_null_count_test'::name );
