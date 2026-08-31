/*
 * Per-test-session setup: pgxntool's setup.sql `\i`s this for every file
 * under test/sql/. See pgxntool/README.asc's "test/install" section for why
 * installing count_nulls is not done here.
 */
\i test/helpers/use_test_user.sql
