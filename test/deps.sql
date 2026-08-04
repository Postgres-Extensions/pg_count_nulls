/*
 * Add any test dependency statements here
 *
 * count_nulls itself is no longer installed here: test/install/load.sql
 * installs it once, committed, before any file under test/sql/ runs (see
 * pgxntool/README.asc's "test/install" section) - so it's already present
 * by the time this per-test (rolled-back) file loads.
 */
