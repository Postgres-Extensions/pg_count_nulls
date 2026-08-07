/*
 * Creates a fresh, randomly named schema and installs count_nulls into it.
 * Shared by test/install/load.sql (fresh/update modes - same psql session,
 * `\set version` then `\i` this file) AND bin/test_existing's prepare-old
 * (a SEPARATE invocation - `-v version=<INSTALL_VERSION>` on the command
 * line). Unusual for a test/ file to also be invoked from bin/, but the
 * creation logic is identical in both cases, so it lives here once instead
 * of being duplicated.
 *
 * :version empty means "no VERSION clause" (installs whatever the current
 * default is); non-empty targets that specific version.
 *
 * The generated name's constant prefix (a literal trailing space included)
 * already guarantees SQL identifier quoting is required before the random
 * suffix is even appended - unlike a mixed-case-only name, which would
 * only force quoting by coincidence of which characters the randomness
 * happened to produce.
 *
 * Cleanup-before-create: a prior run that crashed before reaching its own
 * teardown would otherwise leave its randomly-named schema behind forever,
 * since nothing else knows that name to find and drop it later. Matching
 * on the constant prefix finds and drops any such leftovers before
 * generating this run's own name. See test/helpers/find_test_schema.sql
 * for how later, separate sessions rediscover the name this creates.
 */
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

/*
 * WITH SCHEMA targets the schema directly without touching search_path at
 * all, so a successful install actually proves the install script itself
 * doesn't need search_path arranged any particular way - the same
 * qualification-correctness principle behind randomizing the schema name
 * in the first place. Mutating search_path before CREATE EXTENSION
 * instead would let the install succeed via a coincidentally arranged
 * search_path, masking the extension's own install script secretly
 * depending on unqualified name resolution during install.
 */
SELECT CASE WHEN :'version' <> '' THEN format(' VERSION %L', :'version') ELSE '' END AS version_clause
\gset

CREATE EXTENSION count_nulls WITH SCHEMA :"schema":version_clause;
