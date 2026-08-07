/*
 * Discovers the schema count_nulls was installed into for this test run -
 * for scripts/sessions that didn't create it themselves and have no other
 * way to know its (randomly generated) name. See test/install/load.sql for
 * how/why the name is randomized.
 *
 * Exactly one schema matching the prefix is expected. Finding zero or more
 * than one means something is broken (e.g. a previous run's schema was
 * never cleaned up, or this ran before installation happened) - abort
 * immediately rather than silently guessing. This is a hard failure, not a
 * pgTAP-style assertion.
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
