/*
 * Switches the session to a non-superuser role, so everything that follows
 * (installing count_nulls, and the pgTAP suite itself) only passes if it
 * genuinely works without superuser rights. count_nulls is pure SQL
 * functions - nothing in it needs superuser - so a suite that silently ran
 * as one could never notice count_nulls.control regressing back to the
 * default superuser = true.
 *
 * Included from every entry point that starts a session the suite runs in:
 * test/deps.sql (each test/sql/ session, via pgxntool's setup.sql),
 * test/install/load.sql (the install session) and
 * test/helpers/create_test_schema.sql (bin/test_existing's prepare-old).
 * Each of them creates the schema its session works in first, as the
 * connecting role, and names it in :count_nulls_grant_schema - the test user
 * ends up with rights on that schema and nothing else.
 *
 * RESET ROLE first, so what this file does depends only on how the session
 * connected and not on anything an earlier \i of it already did - it needs
 * the connecting role's privileges back before it can grant anything.
 */
RESET ROLE;

/*
 * The one and only definition of the test user's name. Deliberately
 * sentence-like: unlikely to collide with a real role on a cluster someone
 * points the suite at, and (like the generated schema name) it can't be
 * spelled without SQL identifier quoting, so every run exercises that.
 */
\set test_user 'Test user for count_nulls'

/*
 * Every decision is made server-side, by a function taking the role name and
 * returning the role this session should actually run as, because psql has
 * no way to branch before 10: \if is psql 10, and CI covers back to 9.4,
 * where psql reports it as an invalid command and then carries straight on
 * into the branch it should have skipped. (\gset, below, is fine - 9.3.)
 *
 * p_load_mode must come from the caller, not from reading
 * count_nulls.test_load_mode in here: the Makefile only exports that GUC via
 * PGOPTIONS for pg_regress sessions, and bin/test_existing's prepare-old
 * invokes psql directly without it. Every includer sets the psql variables
 * count_nulls_load_mode and count_nulls_grant_schema before \i-ing this
 * file.
 *
 * TODO: collapse this into a \gset + \if once 10 is the oldest version
 * supported - the plpgsql is only here to work around \if's absence.
 */
CREATE OR REPLACE FUNCTION pg_temp.count_nulls_prepare_test_user(
  p_test_user name
  , p_load_mode text
  , p_grant_schema name
) RETURNS name LANGUAGE plpgsql AS $body$
DECLARE
  /*
   * The managed-cloud analogues of superuser: AWS RDS and Aurora's
   * rds_superuser, Cloud SQL's cloudsqlsuperuser, Azure Flexible Server's
   * azure_pg_admin. None carries the rolsuper attribute - that's the whole
   * point of them - so rolsuper and is_superuser can't see them and they
   * have to be named. Both checks below treat them as equivalent to
   * superuser: enough to set the test user up, and disqualifying for the
   * test user itself.
   */
  c_managed_superuser_roles CONSTANT name[] :=
    '{rds_superuser,cloudsqlsuperuser,azure_pg_admin}'
  ;

  /*
   * Joining pg_roles rather than naming the roles to pg_has_role() keeps the
   * ones that don't exist on this cluster out of it entirely - it errors on
   * a role that isn't there. MEMBER, not USAGE, is deliberately over-strict:
   * it counts a role that merely *could* SET ROLE without having done so.
   */
  c_admin CONSTANT boolean := current_setting('is_superuser') = 'on' OR EXISTS(
    SELECT 1 FROM pg_roles
     WHERE rolname = ANY(c_managed_superuser_roles)
       AND pg_has_role(current_user, oid, 'MEMBER')
  );

  c_extension_owner CONSTANT name := (
    SELECT pg_get_userbyid(extowner) FROM pg_extension WHERE extname = 'count_nulls'
  );
  v_disqualifying name;
BEGIN
  /*
   * In existing mode, an extension owned by someone else is tolerated - the
   * test user can't manage it, so stay as the connecting role. Any other
   * mode treats this as an error: silently staying would run the suite
   * with the connecting role's (often superuser) privileges, proving
   * nothing.
   *
   * PostgreSQL has no ALTER EXTENSION ... OWNER TO, so pg_upgrade can't
   * preserve extension ownership (BUG #18625) - which is why existing mode
   * can meet a foreign owner at all. Member functions keep their owner;
   * only the extension object doesn't.
   */
  IF c_extension_owner IS NOT NULL AND c_extension_owner <> p_test_user THEN
    IF p_load_mode = 'existing' THEN
      RETURN current_user;
    END IF;

    RAISE EXCEPTION
      'count_nulls is owned by "%", not test user "%", and load mode "%" expects no pre-existing installation'
      , c_extension_owner, p_test_user, p_load_mode
    ;
  END IF;

  IF c_admin THEN
    /*
     * Check-then-create, not atomic - safe only because test/install/load.sql
     * finishes before pg_regress starts the concurrent test/sql/ sessions.
     */
    IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = p_test_user) THEN
      EXECUTE format('CREATE ROLE %I', p_test_user);
    END IF;

    /*
     * A real superuser can already SET ROLE to anything. A managed-cloud
     * admin can't, even to a role it just created: from PG16 a CREATEROLE
     * creator gets ADMIN on that role, which is not the same as SET.
     */
    IF current_setting('is_superuser') = 'off' THEN
      EXECUTE format('GRANT %I TO %I', p_test_user, current_user);
    END IF;

    /*
     * The test user's entire footprint: rights on the one schema its caller
     * already created for it, and nothing on the database. USAGE as well as
     * CREATE because search_path skips a schema the role can't use at all.
     *
     * These two grants are all the suite gets. Anything else turning out to
     * be necessary is a finding about count_nulls, not something to grant.
     */
    EXECUTE format(
      'GRANT USAGE, CREATE ON SCHEMA %I TO %I', p_grant_schema, p_test_user
    );

    /*
     * setup.sql creates schema tap as the connecting role, which grants
     * nobody else USAGE - without this, runtests() is invisible.
     */
    IF EXISTS(SELECT 1 FROM pg_namespace WHERE nspname = 'tap') THEN
      EXECUTE format('GRANT USAGE ON SCHEMA tap TO %I', p_test_user);
    END IF;
  END IF;

  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = p_test_user) THEN
    RAISE EXCEPTION
      'role "%" does not exist, and this session cannot create it'
      , p_test_user
    ;
  END IF;

  IF (SELECT rolsuper FROM pg_roles WHERE rolname = p_test_user) THEN
    RAISE EXCEPTION 'test user "%" must not be a superuser', p_test_user;
  END IF;

  SELECT rolname INTO v_disqualifying
    FROM pg_roles
   WHERE rolname = ANY(c_managed_superuser_roles)
     AND pg_has_role(p_test_user, oid, 'MEMBER')
  ;

  IF v_disqualifying IS NOT NULL THEN
    RAISE EXCEPTION
      'test user "%" must not be granted %', p_test_user, v_disqualifying;
  END IF;

  RETURN p_test_user;
END
$body$;

SELECT pg_temp.count_nulls_prepare_test_user(
    :'test_user'
    , :'count_nulls_load_mode'
    , :'count_nulls_grant_schema'
  ) AS count_nulls_run_as
\gset

SET ROLE :"count_nulls_run_as";

-- vi: expandtab sw=2 ts=2
