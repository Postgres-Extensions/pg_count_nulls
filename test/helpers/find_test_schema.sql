/*
 * Discovers the schema count_nulls was installed into for this test run -
 * for scripts/sessions that didn't create it themselves and have no other
 * way to know its (randomly generated) name. See
 * test/helpers/create_test_schema.sql for how/why the name is randomized.
 *
 * If an anonymous DO block could return/populate a value back to the
 * calling psql session, `SELECT ... INTO STRICT` would be the more natural
 * way to write this check - Postgres's own built-in "expect exactly one
 * row" enforcement, instead of manually counting rows and raising a custom
 * exception. It can't (confirmed directly: a `\gset` following a DO block
 * just silently re-executes the block's query text and captures nothing),
 * so validation and the actual :test_schema capture below have to be two
 * separate statements regardless, and the DO block falls back to a
 * hand-counted check. That check is a hard failure, not a pgTAP-style
 * assertion -
 * finding zero or more than one match means something is broken (a
 * previous run's schema was never cleaned up, or this ran before
 * installation happened) and must abort immediately rather than silently
 * guessing.
 */
DO $$
DECLARE
  v_count int := (SELECT count(*) FROM pg_namespace WHERE nspname LIKE 'count_nulls test schema %');
BEGIN
  IF v_count <> 1 THEN
    RAISE EXCEPTION
      'expected exactly one schema matching ''count_nulls test schema %%'', found %'
      , v_count;
  END IF;
END
$$;

SELECT nspname AS test_schema FROM pg_namespace WHERE nspname LIKE 'count_nulls test schema %'
\gset
