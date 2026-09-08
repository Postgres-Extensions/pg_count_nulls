/*
 * Installs count_nulls at :version into a fresh, randomly named schema.
 * Exists as a file only because bin/test_existing's prepare-old runs it
 * standalone (psql -v version=<VERSION> -f); the work itself lives in
 * test/helpers/extension_installer.sql.
 *
 * The install itself runs as a non-superuser holding nothing but a grant on
 * the target schema (see test/helpers/use_test_user.sql), which is what
 * proves count_nulls needs neither superuser nor any database-level
 * privilege. Cleanup and the schema creation happen before that switch, as
 * the connecting role: a leftover schema can belong to any role, and only
 * the connecting one is sure to be able to drop it.
 */
\i test/helpers/extension_installer.sql

/*
 * Always a fresh install here, never 'existing' - see the mode's no-op note
 * on count_nulls_cleanup_test_schemas() itself.
 */
SELECT pg_temp.count_nulls_cleanup_test_schemas('fresh');

SELECT pg_temp.count_nulls_prepare_test_schema('fresh') AS count_nulls_grant_schema
\gset

/*
 * :count_nulls_load_mode must already be set by the caller
 * (bin/test_existing's -v on the command line - see the file header) -
 * this file only installs, so it can't know on its own whether that's
 * genuinely a fresh run rather than 'existing'.
 */
\i test/helpers/use_test_user.sql

SELECT pg_temp.count_nulls_install_extension(
    :'count_nulls_grant_schema', :'version'
  ) AS count_nulls_installed
\gset

-- vi: expandtab sw=2 ts=2
