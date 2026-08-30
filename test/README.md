# count_nulls test suite

Unusually for a pgTAP suite, assertions aren't written per test file:
`core/functions.sql` defines a shared library of `test__*` functions that
`sql/extension_tests.sql` `\i`s and then runs via `runtests()`.

## Layout

- `install/load.sql` — installs count_nulls once, committed, before the
  `test/sql/` schedule. Its output isn't tracked; it fails loudly instead.
- `deps.sql` — per-test-session setup; drops the session to the test user.
- `core/functions.sql` — `ncs()`, plus the shared `test__*` library.
- `sql/extension_tests.sql` — adds `test__check_ncs` and
  `test__shutdown__drop_all`, then calls `runtests()`.
- `helpers/test_user.sql` — switches the session to the non-superuser role.
- `helpers/create_test_schema.sql` — installs count_nulls at `:version` into
  a fresh, randomly named schema.
- `helpers/find_test_schema.sql` — finds that schema again, from a session
  that didn't create it.
- `../bin/compare_fresh_vs_update` — not part of this suite: diffs a fresh
  install against an updated one (definitions, comments, ACLs).

## Two things to know before changing anything

**The suite runs as an ordinary role, not a superuser** (`Test user for
count_nulls`). That's what makes `superuser = false` in
`count_nulls.control` a tested property rather than a claim. See
`helpers/test_user.sql`, including why it deliberately does *not* switch
when a real `pg_upgrade` has left the extension owned by someone else.

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

## Regenerating expected output

Never hand-edit `expected/`. Use `make results`, guarded by `make
verify-results` (which refuses while `regression.diffs` shows real failures;
`PGXNTOOL_ENABLE_VERIFY_RESULTS=no` bypasses it for a diff you've already
reviewed). It only writes the unsuffixed default — alternates (`_1.out`, …)
must be copied by hand from `test/results/<test>.out`.
