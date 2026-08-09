# count_nulls test suite

This suite is structured differently from most pgTAP-based extension tests:
rather than each `test/sql/*.sql` file writing its own independent
assertions, `core/functions.sql` defines a shared library of `test__*`
functions (pgTAP's `runtests()` naming convention) that test files `\i` and
then invoke via `runtests()`.

## Layout

- `install/load.sql` — installs count_nulls once, committed, before the main
  `test/sql/` schedule (see pgxntool/README.asc's `test/install` section).
  Its own output isn't tracked (see `install/.gitignore`) - correctness
  comes from this file failing loudly if something's wrong, not from a
  textual comparison.
- `deps.sql` — loaded by every test file (via `load.sql` ->
  `pgxntool/setup.sql` -> `deps.sql`). No longer installs count_nulls
  itself (that's `install/load.sql`'s job); only for genuine per-test
  dependency statements. Currently empty - see its own header comment for
  why it's kept that way rather than deleted.
- `core/functions.sql` — a shared helper, `\i`'d by `sql/extension_tests.sql`.
  Defines `ncs()` (discovers, live, which schema count_nulls is actually
  installed in - never trusts a hardcoded/passed-in value) plus a battery of
  `test__*` functions covering function definitions, immutability/
  strictness, and behavior across `anyarray`/`json`/`jsonb` and both
  trigger functions.
- `../bin/compare_fresh_vs_update` — not part of the pgTAP suite itself: a
  standalone script the `test` CI job's update leg runs after
  `TEST_LOAD_SOURCE=update`, which installs a fresh copy and a
  0.9.6-then-updated copy of the extension into their own scratch
  databases - each an unqualified `CREATE EXTENSION`, so both land in the
  same default schema by construction, which is all the diff needs to
  isolate real update-vs-fresh divergence rather than a spurious
  schema-name difference - and diffs `pg_get_functiondef`/comments/ACLs for
  every object the extension owns. Catches an update script leaving some
  definition subtly different from a fresh install, even when the fixed
  pgTAP suite above still passes (it only asserts the specific behaviors it
  happens to check). The `pg-upgrade-test` CI job also reuses it (via its
  optional `EXISTING_DB` argument) to compare a fresh install against the
  real, already-populated databases a binary `pg_upgrade` just produced,
  discovering and matching that database's own randomly generated schema
  (from `helpers/create_test_schema.sql`, via `bin/test_existing
  prepare-old`) instead of generating a new one.
- `sql/extension_tests.sql` — `\i`'s `core/functions.sql`, adds two more
  `test__*` functions of its own (`test__check_ncs`, asserting count_nulls
  landed where expected; `test__shutdown__drop_all`, asserting it can be
  cleanly dropped), then runs everything via `runtests()`.
- `helpers/create_test_schema.sql` — creates the freshly, randomly generated
  schema and installs count_nulls into it (see "Schema targeting" below).
  Shared by `install/load.sql`'s fresh/update modes and `bin/test_existing`'s
  `prepare-old` - two separate call sites, one shared implementation.
- `helpers/find_test_schema.sql` — rediscovers the randomly generated schema
  count_nulls was installed into (see "Schema targeting" below), for
  sessions that didn't create it themselves.

## Schema targeting

`helpers/create_test_schema.sql` always installs count_nulls into its own
freshly, randomly generated schema - never a fixed name, and never no
schema at all. It's shared by `install/load.sql`'s fresh/update modes (`\i`'d
in the same psql session) and `bin/test_existing`'s `prepare-old` (a
separate, `-f`'d invocation) - the schema-targeting behavior described here
applies to both. The generated name
(`'count_nulls test schema ' || substr(md5(random()::text), 1, 12)`) has two
deliberate properties:

- A constant prefix (`count_nulls test schema `, with a trailing space)
  that by itself already requires SQL identifier quoting - so every single
  run exercises the suite's `%I`-qualification, not just a dedicated
  "quoting" leg that could bitrot independently of a "plain" one.
- The same prefix doubles as a marker for stale-schema cleanup: before
  generating a new name, `helpers/create_test_schema.sql` finds and drops
  any already-existing schema matching the prefix (`nspname LIKE
  'count_nulls test schema %'`), so a schema left behind by a run that
  crashed before reaching its own teardown doesn't accumulate run over run.

`helpers/create_test_schema.sql` targets the generated schema via `CREATE
EXTENSION ... WITH SCHEMA`, never by mutating its own search_path first.

**Cross-session discovery.** Some scripts/sessions (e.g. `bin/test_existing`'s
steps, each a fresh `psql -f ...` invocation with no memory of another
invocation's `\gset` variables) need the generated name without having
created it themselves. `helpers/find_test_schema.sql` looks it up live via
`pg_namespace`, hard-failing (not a pgTAP assertion - a genuinely broken
condition, like zero or more than one matching schema) if it can't find
exactly one, and sets `:"test_schema"` via `\gset` for the including script
to use.

**Why this proves anything.** Because count_nulls' own schema is randomly
named, it can never coincidentally end up on the test session's
search_path - so `core/functions.sql`'s `%I`-qualified calls (via `ncs()`)
only pass if they're genuinely correct, never because count_nulls' schema
happened to be reachable unqualified. `test__check_ncs` in
`sql/extension_tests.sql` is what actually checks this, via the fixed `SET
SEARCH_PATH` in `core/functions.sql`.

**Assertion descriptions deliberately never embed the schema name.**
`core/functions.sql`'s assertions build the SQL they *execute* via `%I`
qualification (through `ncs()`, so they're always correct no matter which
real schema count_nulls landed in) but pass an *explicit*, schema-free
description to every pgTAP call - overriding pgTAP's own auto-generated
descriptions, which otherwise embed the schema. This is what keeps
`test/expected/extension_tests.out` a single file that passes no matter
which randomly generated name count_nulls actually landed in.

**`test__shutdown__drop_all` only asserts the extension can be dropped -
it doesn't clean up the schema itself.** Dropping the schema count_nulls
was installed into isn't something this suite is testing, and
`helpers/create_test_schema.sql` already unconditionally drops any
leftover schema before the next run creates its own, so a second, per-run
drop here would only ever be redundant. Its output is identical on every
run (one `ok` row), so `test/expected/extension_tests.out` needs no
numbered pg_regress alternate for this function.

## Regenerating expected output

Never hand-edit files under `expected/`. Regenerate via `make results`
(guarded by `make verify-results`, which refuses to copy while
`regression.diffs` shows real failures - use
`PGXNTOOL_ENABLE_VERIFY_RESULTS=no` to bypass that guard for a run you've
already reviewed and know is a legitimate, intentional change, not a way to
skip reviewing the diff). `make results` only ever writes the unsuffixed
default; alternates (`_1.out`, ...) have to be copied by hand from a real
`test/results/<test>.out` for that scenario.
