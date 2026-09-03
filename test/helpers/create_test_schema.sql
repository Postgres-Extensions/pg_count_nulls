/*
 * Installs count_nulls at :version into a fresh, randomly named schema.
 * Exists as a file only because bin/test_existing's prepare-old runs it
 * standalone (psql -v version=<VERSION> -f); the work itself lives in
 * test/helpers/extension_installer.sql.
 *
 * The install itself runs as a non-superuser (see
 * test/helpers/use_test_user.sql), which is what proves count_nulls doesn't
 * need superuser to install. Cleanup happens before that switch: a leftover
 * schema can belong to any role, and only the connecting one is sure to be
 * able to drop it.
 */
\i test/helpers/extension_installer.sql

/*
 * Always a fresh install here, never 'existing' - see the mode's no-op note
 * on count_nulls_cleanup_test_schemas() itself.
 */
SELECT pg_temp.count_nulls_cleanup_test_schemas('fresh');

/*
 * :count_nulls_load_mode must already be set by the caller
 * (bin/test_existing's -v on the command line - see the file header) -
 * this file only installs, so it can't know on its own whether that's
 * genuinely a fresh run rather than 'existing'.
 */
\i test/helpers/use_test_user.sql

SELECT pg_temp.count_nulls_install_extension(:'version') AS count_nulls_test_schema
\gset

-- vi: expandtab sw=2 ts=2
