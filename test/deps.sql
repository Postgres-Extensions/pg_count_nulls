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

\i test/helpers/use_test_user.sql
