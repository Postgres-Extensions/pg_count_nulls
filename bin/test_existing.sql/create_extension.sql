/*
 * Generates a fresh, randomly-named schema and installs count_nulls at
 * :version into it, for prepare_old()'s old-cluster install - the same
 * cleanup-before-create + random-name pattern test/install/load.sql uses
 * for its own installs (see that file for the full rationale). Later,
 * separate invocations (e.g. bin/test_existing's other steps, each a
 * fresh psql session with no memory of this one's \gset variables)
 * rediscover the name this creates via test/helpers/find_test_schema.sql.
 *
 * Usage: psql -v ON_ERROR_STOP=1 -v version=<version> -f create_extension.sql
 */
\set ON_ERROR_STOP on

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT nspname FROM pg_namespace WHERE nspname LIKE 'count_nulls test schema %' LOOP
    EXECUTE format('DROP SCHEMA %I CASCADE', r.nspname);
  END LOOP;
END
$$;

SELECT 'count_nulls test schema ' || substr(md5(random()::text), 1, 12) AS schema
\gset

CREATE SCHEMA :"schema";
CREATE EXTENSION count_nulls WITH SCHEMA :"schema" VERSION :'version';
