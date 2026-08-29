/*
 * Per-test-session setup, run by pgxntool/test/pgxntool/setup.sql (vendored,
 * never hand-edited) for every file under test/sql/. It does NOT install
 * count_nulls - test/install/load.sql does that once, committed, before
 * test/sql/ runs (see its header comment).
 *
 * The one thing it does do is drop the session's privileges, so the suite
 * proper runs as a non-superuser too and not just the install does. This is
 * the last hook that runs before the test file's own SQL, and it runs after
 * setup.sql has already created the tap schema and pgtap as the connecting
 * (superuser) role - pgTAP is test harness, not something count_nulls'
 * privileges have anything to say about.
 *
 * Also can't be deleted regardless: setup.sql unconditionally `\i`s it, and
 * it's one of only two files (.gitignore, test/deps.sql) that pgxntool's
 * subtree-sync reconciliation tracks and 3-way-merges on every
 * `git subtree pull`.
 */
\i test/helpers/test_user.sql
