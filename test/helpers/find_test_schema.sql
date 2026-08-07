/*
 * Discovers the schema count_nulls was installed into for this test run -
 * for scripts/sessions that didn't create it themselves and have no other
 * way to know its (randomly generated) name. See
 * test/helpers/create_test_schema.sql for how/why the name is randomized.
 *
 * SELECT ... INTO STRICT raises Postgres's own no_data_found/too_many_rows
 * if this doesn't resolve to exactly one schema, instead of hand-counting
 * rows and raising a custom exception for the same thing - a DO block
 * can't populate a psql variable itself (confirmed directly: a `\gset`
 * following one just silently re-executes it and sets nothing), so the
 * actual :test_schema capture below still has to be a separate plain
 * SELECT. This is a hard failure either way, not a pgTAP-style assertion -
 * finding zero or more than one match means something is broken (a
 * previous run's schema was never cleaned up, or this ran before
 * installation happened) and must abort immediately rather than silently
 * guessing.
 */
DO $$
DECLARE
  v_schema name;
BEGIN
  SELECT nspname INTO STRICT v_schema FROM pg_namespace WHERE nspname LIKE 'count_nulls test schema %';
END
$$;

SELECT nspname AS test_schema FROM pg_namespace WHERE nspname LIKE 'count_nulls test schema %'
\gset
