/*
 * Switches the session to a non-superuser role, so everything that follows
 * (installing count_nulls, and the pgTAP suite itself) only passes if it
 * genuinely works without superuser rights. count_nulls is pure SQL
 * functions - nothing in it needs superuser - so a suite that silently ran
 * as one could never notice count_nulls.control regressing back to the
 * default superuser = true.
 *
 * Included from every entry point that starts a session the suite runs in:
 * test/deps.sql (each test/sql/ session, via pgxntool's setup.sql) and
 * test/helpers/create_test_schema.sql (the install session, and
 * bin/test_existing's prepare-old).
 *
 * The RESET ROLE below is what makes a second \i of this file in one
 * session behave exactly like the first: it hands the privileges back
 * before anything that needs them. That isn't hypothetical - psql older
 * than 10 has no \if, so test/install/load.sql's mode branches all run and
 * create_test_schema.sql gets included twice.
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
 * TODO: collapse this into a \gset + \if once 10 is the oldest version
 * supported - the plpgsql is only here to work around \if's absence.
 */
CREATE OR REPLACE FUNCTION pg_temp.count_nulls_prepare_test_user(
  p_test_user name
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
   * An already-installed count_nulls belonging to somebody else is one a
   * real pg_upgrade restored, and it can only be managed by its owner - so
   * stay as we are rather than switching to a role that can't drop it.
   *
   * PostgreSQL has no ALTER EXTENSION ... OWNER TO, so pg_dump has no way
   * to carry an extension's ownership across: --binary-upgrade emits
   * binary_upgrade_create_empty_extension(), which takes no owner, and the
   * extension ends up belonging to whoever ran the restore. Its member
   * functions DO keep their owner, so only the extension object itself is
   * out of reach - which is exactly what test__shutdown__drop_all needs.
   *
   * Don't expect a newer PostgreSQL to retire this branch. extowner has had
   * no matching ALTER EXTENSION ... OWNER TO since it was added in 2011,
   * because what that should do to the contained objects was never settled
   * (handing a non-superuser a C-language handler function is the awkward
   * case). Reported as BUG #18625 and acknowledged as a known shortcoming,
   * still unfixed. pg_dump's --use-set-session-authorization does dodge it,
   * but pg_upgrade offers no way to ask for that.
   *
   * Nothing is lost by not switching here: existing mode installs nothing,
   * so it was never the leg proving the install works unprivileged.
   */
  IF c_extension_owner IS NOT NULL AND c_extension_owner <> p_test_user THEN
    RETURN current_user;
  END IF;

  IF c_admin THEN
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
     * Can't fold into the CREATE ROLE above: the role is cluster-wide and
     * outlives any one run, but this grant lives in the current database's
     * ACL, so a run against a new database still has to issue it.
     *
     * These two grants are all the suite gets. Anything else turning out to
     * be necessary is a finding about count_nulls, not something to grant.
     */
    EXECUTE format(
      'GRANT CREATE ON DATABASE %I TO %I', current_database(), p_test_user
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

SELECT pg_temp.count_nulls_prepare_test_user(:'test_user') AS count_nulls_run_as
\gset

SET ROLE :"count_nulls_run_as";

-- vi: expandtab sw=2 ts=2
