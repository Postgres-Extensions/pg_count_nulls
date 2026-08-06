/*
 * Intentionally empty. test/install/load.sql now installs count_nulls once,
 * committed, before test/sql/ runs (see its header comment), so this
 * per-test file no longer has anything to do.
 *
 * Can't be deleted: pgxntool/test/pgxntool/setup.sql (vendored, never
 * hand-edited) unconditionally does `\i test/deps.sql`, so every test
 * session's setup would fail without it. It's also one of only two files
 * (.gitignore, test/deps.sql) that pgxntool's subtree-sync reconciliation
 * tracks and 3-way-merges on every `git subtree pull`.
 *
 * Kept for future use: add per-test dependency statements here again if a
 * genuine need arises - e.g. relaying a value into the per-test session via
 * a psql variable - same role this file played before test/install took
 * over installing count_nulls.
 */
