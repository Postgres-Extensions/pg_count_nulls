-- Proves the guard planted by plant_guard.sql actually blocks a
-- non-CASCADE DROP EXTENSION - "prove it, don't assume it"
-- (advanced-extension-testing.md #4). Re-run after every step (install,
-- pg_upgrade, post-upgrade ALTER EXTENSION UPDATE): the guard disappearing
-- at any point means a CASCADE drop happened somewhere upstream, i.e. the
-- "existing" run downstream would actually be a silent fresh install.
--
-- Usage: psql -v ON_ERROR_STOP=1 -f assert_guard.sql
\set ON_ERROR_STOP on

DO $$
BEGIN
  DROP EXTENSION count_nulls;
  -- Only reached if the drop above unexpectedly succeeded.
  RAISE EXCEPTION 'GUARD FAILURE: non-CASCADE DROP EXTENSION count_nulls unexpectedly succeeded';
EXCEPTION WHEN dependent_objects_still_exist THEN
  RAISE NOTICE 'guard held: DROP EXTENSION count_nulls correctly blocked';
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'count_nulls') THEN
    RAISE EXCEPTION 'GUARD FAILURE: count_nulls extension missing after guard check';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relname = 'guard' AND n.nspname = 'count_nulls_drop_guard'
  ) THEN
    RAISE EXCEPTION 'GUARD FAILURE: count_nulls_drop_guard.guard view missing';
  END IF;
END
$$;
