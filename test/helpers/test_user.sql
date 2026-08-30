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
   * The managed-cloud analogues of superuser. None of them carry the
   * rolsuper attribute - that's the whole point of them - so the rolsuper
   * check below can't see them and they have to be named explicitly. AWS
   * RDS and Aurora call it rds_superuser, Cloud SQL cloudsqlsuperuser,
   * Azure Flexible Server azure_pg_admin.
   */
  c_managed_superuser_roles CONSTANT name[] :=
    '{rds_superuser,cloudsqlsuperuser,azure_pg_admin}'
  ;
  v_role name;
  c_extension_owner CONSTANT name := (
    SELECT pg_get_userbyid(extowner) FROM pg_extension WHERE extname = 'count_nulls'
  );
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

  IF current_setting('is_superuser') = 'on' THEN
    IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = p_test_user) THEN
      EXECUTE format('CREATE ROLE %I', p_test_user);
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
      'role "%" does not exist, and this session is not a superuser so it cannot be created'
      , p_test_user
    ;
  END IF;

  IF (SELECT rolsuper FROM pg_roles WHERE rolname = p_test_user) THEN
    RAISE EXCEPTION 'test user "%" must not be a superuser', p_test_user;
  END IF;

  FOREACH v_role IN ARRAY c_managed_superuser_roles LOOP
    /*
     * Whether the role exists has to be settled in its own statement:
     * pg_has_role() errors outright on one that doesn't, and SQL promises
     * no evaluation order between the two halves of an AND.
     *
     * MEMBER, not USAGE, is deliberately over-strict: it also rejects a
     * role that merely *could* SET ROLE to one of these without ever having
     * done so, which isn't the same as holding the privileges. Simpler than
     * reasoning about when it would actually matter, and nothing needs the
     * looser check yet.
     */
    IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
      IF pg_has_role(p_test_user, v_role, 'MEMBER') THEN
        RAISE EXCEPTION
          'test user "%" must not be granted %', p_test_user, v_role;
      END IF;
    END IF;
  END LOOP;

  RETURN p_test_user;
END
$body$;

/*
 * \gset, not \if, is what keeps the SET ROLE below both unconditional and
 * correct: the function returns whichever role this session should run as,
 * so the decision stays server-side while the switch itself stays an
 * ordinary statement. It also keeps the function's result out of every
 * test's expected output.
 */
SELECT pg_temp.count_nulls_prepare_test_user(:'test_user') AS count_nulls_run_as
\gset

SET ROLE :"count_nulls_run_as";

-- vi: expandtab sw=2 ts=2
