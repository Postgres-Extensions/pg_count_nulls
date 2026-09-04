/*
 * Defines, but does not call, the functions that find-and-drop leftover test
 * schemas, produce the schema count_nulls goes into, and install it there.
 * Split from calling them, and from each other, so test/install/load.sql can
 * decide server-side whether to install at all, and so every caller can run
 * the first two as the connecting role and only the install as the test user
 * (test/helpers/use_test_user.sql). Cleanup has to be the connecting role's
 * because a leftover schema can belong to any role; the schema creation has
 * to be, because the whole point is that the test user holds nothing but
 * what it was granted on that one schema.
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
   * count_nulls_prepare_test_schema()'s c_prefix below) and drop whatever's
   * there.
   */
  FOR r IN SELECT nspname FROM pg_namespace WHERE nspname LIKE 'count_nulls test schema %' LOOP
    EXECUTE format('DROP SCHEMA %I CASCADE', r.nspname);
  END LOOP;
END
$body$;

/*
 * Names the schema count_nulls is about to be installed into, creating it as
 * the connecting role. 'existing' instead finds the schema a prior, separate
 * prepare-old run installed into: that installation is the thing the mode
 * exists to test, so creating a second schema here would both destroy the
 * one-schema invariant test/helpers/find_test_schema.sql relies on and leave
 * the real one untested.
 */
CREATE OR REPLACE FUNCTION pg_temp.count_nulls_prepare_test_schema(
  p_mode text
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
  IF p_mode = 'existing' THEN
    SELECT nspname INTO v_schema
      FROM pg_namespace n JOIN pg_extension x ON n.oid = x.extnamespace
     WHERE extname = 'count_nulls'
    ;

    IF v_schema IS NULL THEN
      RAISE EXCEPTION
        'count_nulls is not installed, so mode ''%'' has no test schema to find'
        , p_mode
      ;
    END IF;

    RETURN v_schema;
  END IF;

  v_schema := c_prefix || substr(md5(random()::text), 1, 12);
  EXECUTE format('CREATE SCHEMA %I', v_schema);

  RETURN v_schema;
END
$body$;

/*
 * Runs as the test user, on a schema the connecting role made and granted it
 * rights on (test/helpers/use_test_user.sql) - which is what makes a
 * successful install prove count_nulls needs no privilege on the database
 * itself, only on its target schema.
 */
CREATE OR REPLACE FUNCTION pg_temp.count_nulls_install_extension(
  p_schema name
  , p_version text
) RETURNS void LANGUAGE plpgsql AS $body$
BEGIN
  /*
   * 'current' means whatever the control file's default_version is, matching
   * the sentinel bin/test_existing already uses. Empty is a hard error, so an
   * unpropagated :version can't silently install 'current' instead.
   */
  IF p_version = '' THEN
    RAISE EXCEPTION $$p_version must be set explicitly, or 'current'$$;
  END IF;

  /*
   * WITH SCHEMA rather than arranging search_path first: this way a
   * successful install proves the install script doesn't depend on
   * unqualified name resolution, instead of hiding it behind a search_path
   * that happened to suit.
   */
  EXECUTE format(
    'CREATE EXTENSION count_nulls WITH SCHEMA %I%s'
    , p_schema
    , CASE WHEN p_version = 'current' THEN '' ELSE format(' VERSION %L', p_version) END
  );

  /*
   * CREATE EXTENSION runs the install script with search_path set to
   * "<target>, pg_temp", and search_path silently drops a schema the role
   * lacks USAGE on - so a role holding only CREATE builds the entire
   * extension in pg_temp, where it disappears at disconnect, and CREATE
   * EXTENSION still reports success. pg_extension.extnamespace says the
   * target either way, so the only way to tell is to look for the objects.
   */
  IF NOT EXISTS(
    SELECT 1
      FROM pg_depend d
      JOIN pg_proc p ON p.oid = d.objid AND d.classid = 'pg_proc'::regclass
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE d.deptype = 'e'
       AND d.refobjid = (SELECT oid FROM pg_extension WHERE extname = 'count_nulls')
       AND n.nspname = p_schema
  ) THEN
    RAISE EXCEPTION 'count_nulls installed no functions into schema %', p_schema;
  END IF;
END
$body$;

-- vi: expandtab sw=2 ts=2
