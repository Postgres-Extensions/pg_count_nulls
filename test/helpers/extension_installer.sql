/*
 * Defines, but does not call, the functions that find-and-drop leftover test
 * schemas and install count_nulls into a fresh one. Split from calling them,
 * and from each other, so test/install/load.sql can decide server-side
 * whether to install at all, and so every caller can run cleanup before
 * switching to the test user (test/helpers/use_test_user.sql) while
 * installing after - a leftover schema can belong to any role, and only the
 * connecting one is sure to be able to drop it.
 */
CREATE OR REPLACE FUNCTION pg_temp.count_nulls_cleanup_test_schemas(
  p_mode text
) RETURNS void LANGUAGE plpgsql AS $body$
DECLARE
  r record;
BEGIN
  /*
   * 'existing' asserts against a schema a prior, separate prepare-old run
   * left behind on purpose - dropping it here would destroy the very thing
   * pg_upgrade is being tested against, so this mode must be a no-op.
   */
  IF p_mode = 'existing' THEN
    RETURN;
  END IF;

  /*
   * A run that died before its own teardown leaves a schema nothing else
   * knows the name of, so match the prefix (see
   * count_nulls_install_extension()'s c_prefix below) and drop whatever's
   * there.
   */
  FOR r IN SELECT nspname FROM pg_namespace WHERE nspname LIKE 'count_nulls test schema %' LOOP
    EXECUTE format('DROP SCHEMA %I CASCADE', r.nspname);
  END LOOP;
END
$body$;

CREATE OR REPLACE FUNCTION pg_temp.count_nulls_install_extension(
  p_version text
) RETURNS name LANGUAGE plpgsql AS $body$
DECLARE
  /*
   * The trailing space alone forces SQL identifier quoting, so every run
   * exercises the suite's %I-qualification rather than passing by luck of
   * which characters the random suffix drew. Must match the literal
   * count_nulls_cleanup_test_schemas() matches on above.
   */
  c_prefix CONSTANT text := 'count_nulls test schema ';
  v_schema name;
BEGIN
  /*
   * 'current' means whatever the control file's default_version is, matching
   * the sentinel bin/test_existing already uses. Empty is a hard error, so an
   * unpropagated :version can't silently install 'current' instead.
   */
  IF p_version = '' THEN
    RAISE EXCEPTION $$p_version must be set explicitly, or 'current'$$;
  END IF;

  v_schema := c_prefix || substr(md5(random()::text), 1, 12);
  EXECUTE format('CREATE SCHEMA %I', v_schema);

  /*
   * WITH SCHEMA rather than arranging search_path first: this way a
   * successful install proves the install script doesn't depend on
   * unqualified name resolution, instead of hiding it behind a search_path
   * that happened to suit.
   */
  EXECUTE format(
    'CREATE EXTENSION count_nulls WITH SCHEMA %I%s'
    , v_schema
    , CASE WHEN p_version = 'current' THEN '' ELSE format(' VERSION %L', p_version) END
  );

  RETURN v_schema;
END
$body$;

-- vi: expandtab sw=2 ts=2
