/*
 * Per-test-session setup: pgxntool's setup.sql `\i`s this for every file
 * under test/sql/. See pgxntool/README.asc's "test/install" section for why
 * installing count_nulls is not done here.
 *
 * Read without missing_ok: a genuinely unpropagated GUC must fail loudly,
 * not be indistinguishable from a deliberately empty one. (current_setting's
 * missing_ok argument is 9.6 anyway, and CI covers 9.4.) These are real
 * pg_regress sessions, so the Makefile has exported it via PGOPTIONS.
 */
SELECT current_setting('count_nulls.test_load_mode') AS count_nulls_load_mode
\gset

/*
 * Where the test__* functions and their fixtures live (test/core/functions.sql
 * puts it on search_path). Created here, by the connecting role, so that the
 * test user needs no privilege on the database - only what use_test_user.sql
 * grants it below on this one schema. Rolled back with the rest of the
 * session, like every other object a test/sql/ session makes.
 */
CREATE SCHEMA _null_count_test;
\set count_nulls_grant_schema _null_count_test

\i test/helpers/use_test_user.sql
