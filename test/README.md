# count_nulls test suite

Unusually for a pgTAP suite, assertions aren't written per test file:
`core/functions.sql` defines a shared library of `test__*` functions that
`sql/extension_tests.sql` `\i`s and then runs via `runtests()`.

## Layout

A helper named for an action performs it when `\i`'d; one named for a thing
just defines it, leaving the caller to decide when to use it.

- `install/load.sql` — installs count_nulls once, committed, before the
  `test/sql/` schedule, per `TEST_LOAD_SOURCE`. Its output isn't tracked; it
  fails loudly instead.
- `deps.sql` — per-test-session setup; creates `_null_count_test` for the
  `test__*` library to live in, then drops the session to the test user.
- `core/functions.sql` — `ncs()`, plus the shared `test__*` library.
- `sql/extension_tests.sql` — adds `test__check_ncs` and
  `test__shutdown__drop_all`, then calls `runtests()`.
- `helpers/use_test_user.sql` — switches the session to the non-superuser
  role, granting it its rights on `:count_nulls_grant_schema` first.
- `helpers/extension_installer.sql` — defines the functions that clean up
  leftover test schemas, produce a fresh, randomly named one, and install
  count_nulls at a given version into it.
- `helpers/create_test_schema.sql` — calls all three, with `:version`; a file
  only because `bin/test_existing`'s `prepare-old` runs it standalone.
- `helpers/find_test_schema.sql` — finds that schema again, from a session
  that didn't create it.
- `../bin/compare_fresh_vs_update` — not part of this suite: diffs a fresh
  install against an updated one (definitions, comments, ACLs).

## Two things to know before changing anything

**The suite runs as an ordinary role, not a superuser** (`Test user for
count_nulls`). That's what makes `superuser = false` in
`count_nulls.control` a tested property rather than a claim. See
`helpers/use_test_user.sql`, including why it deliberately does *not* switch
when a real `pg_upgrade` has left the extension owned by someone else.

That role holds **no privilege on the database** — every schema it works in is
created by the connecting role, which grants it `USAGE` and `CREATE` on that
one schema and nothing else. So a regression that made installing count_nulls
depend on database-level rights fails the suite instead of passing on a
privilege the test role happened to have.

**count_nulls is installed into a randomly named schema**, never a fixed one
and never the default. That's what gives `core/functions.sql`'s
`%I`-qualified calls their meaning: the extension's schema can never
coincidentally land on `search_path`, so those calls only pass if they're
genuinely correct. `test__check_ncs` asserts it. Two consequences:

- Nothing may assume the name — use `ncs()` from SQL, or
  `helpers/find_test_schema.sql` from a separate session.
- Assertions pass an explicit, schema-free description to every pgTAP call,
  overriding pgTAP's own (which embeds the schema). That's what keeps
  `expected/extension_tests.out` a single file valid for every run.

Neither `install/load.sql` nor `helpers/use_test_user.sql` may use `\if`:
it's psql 10, CI covers back to 9.4, and under `ON_ERROR_STOP` psql aborts on
it. Both branch server-side instead.

## Regenerating expected output

Never hand-edit `expected/`. Use `make results`, guarded by `make
verify-results` (which refuses while `regression.diffs` shows real failures;
`PGXNTOOL_ENABLE_VERIFY_RESULTS=no` bypasses it for a diff you've already
reviewed). It only writes the unsuffixed default — alternates (`_1.out`, …)
must be copied by hand from `test/results/<test>.out`.
