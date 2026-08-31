/*
 * Creates a fresh, randomly named schema and installs count_nulls into it.
 * Shared by test/install/load.sql (fresh/update modes, same psql session)
 * and bin/test_existing's prepare-old (a separate invocation) - the
 * creation logic is identical in both, so it lives here once.
 */
SET count_nulls.test_schema_version = :'version';

/*
 * Bridged through a GUC instead of referencing :'version' directly inside
 * the DO block: psql doesn't interpolate variables inside dollar-quoted
 * strings.
 *
 * 'current' means install whatever the current default is, matching the
 * sentinel bin/test_existing already uses; empty is a hard error so an
 * unpropagated :version can't silently install 'current' instead.
 */
DO $$
BEGIN
  IF current_setting('count_nulls.test_schema_version') = '' THEN
    RAISE EXCEPTION $msg$:version must be set explicitly, or 'current'$msg$;
  END IF;
END
$$;

/*
 * A run that crashed before its own teardown leaves a schema nothing else
 * knows the name of, so match the prefix (see the name generation below)
 * and drop it here - before the test-user switch, since a leftover schema
 * can belong to any role and only the connecting one is sure to be able to
 * drop it. See find_test_schema.sql for how later sessions rediscover the
 * name this creates.
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

/*
 * :count_nulls_load_mode must already be set by the caller (test/install/
 * load.sql, or bin/test_existing's -v on the command line) - this file
 * installs count_nulls, so it can't know on its own whether that's
 * genuinely a fresh/update run rather than 'existing'.
 */
\i test/helpers/use_test_user.sql

/*
 * Trailing space alone forces identifier quoting, so every run exercises
 * %I-qualification rather than passing by luck of the random suffix. Must
 * match the prefix cleanup matches on above.
 */
SELECT 'count_nulls test schema ' || substr(md5(random()::text), 1, 12) AS schema
\gset

CREATE SCHEMA :"schema";

SELECT CASE WHEN :'version' = 'current' THEN '' ELSE format(' VERSION %L', :'version') END AS version_clause
\gset

/*
 * WITH SCHEMA rather than arranging search_path first: this way a
 * successful install proves the install script doesn't depend on
 * unqualified name resolution, instead of hiding it behind a search_path
 * that happened to suit.
 */
CREATE EXTENSION count_nulls WITH SCHEMA :"schema":version_clause;
