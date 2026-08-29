/*
 * Creates a fresh, randomly named schema and installs count_nulls into it.
 * Shared by test/install/load.sql (fresh/update modes - same psql session,
 * `\set version` then `\i` this file) AND bin/test_existing's prepare-old
 * (a SEPARATE invocation - `-v version=<INSTALL_VERSION>` on the command
 * line). Unusual for a test/ file to also be invoked from bin/, but the
 * creation logic is identical in both cases, so it lives here once instead
 * of being duplicated.
 *
 * :version must always be set explicitly to either the literal string
 * 'current' (no VERSION clause - installs whatever the current default is)
 * or a real version string (targets that specific version) - matching the
 * same 'current' sentinel bin/test_existing's assert_version()/
 * current_version() already use, for the same reason: an empty string is a
 * HARD ERROR rather than a valid signal, so an accidentally-unpropagated
 * :version fails loudly instead of silently installing 'current' when
 * something else was actually intended.
 *
 * The guard below bridges :version into the DO block via a SET + a real
 * GUC (like test/install/load.sql's count_nulls.test_load_mode) rather than
 * referencing :'version' directly inside the DO $$ ... $$ body: psql does
 * NOT interpolate variables inside dollar-quoted strings (confirmed
 * directly - a bare :'version' inside a $$ ... $$ block reaches the server
 * un-substituted and is a syntax error), only in plain top-level SQL text
 * such as the version_clause SELECT below.
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
 *
 * Everything below runs as a non-superuser (see test/helpers/test_user.sql),
 * so a successful install here is itself the proof that count_nulls doesn't
 * need superuser to install. The switch has to come before the cleanup loop,
 * not just before CREATE EXTENSION: a leftover schema is one this same role
 * created on a previous run, so it's the role that must be able to drop it.
 */
\i test/helpers/test_user.sql

SET count_nulls.test_schema_version = :'version';

DO $$
BEGIN
  IF current_setting('count_nulls.test_schema_version') = '' THEN
    RAISE EXCEPTION ':version must be set explicitly - use ''current'' to install whatever the current default is, never an empty string, so an accidentally-unpropagated value fails loudly instead of silently installing ''current'' when something else was actually intended';
  END IF;
END
$$;

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
SELECT CASE WHEN :'version' = 'current' THEN '' ELSE format(' VERSION %L', :'version') END AS version_clause
\gset

CREATE EXTENSION count_nulls WITH SCHEMA :"schema":version_clause;
