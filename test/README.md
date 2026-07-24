# count_nulls test suite

## Layout

- `deps.sql` — loaded by every test file (via `load.sql` ->
  `pgxntool/setup.sql` -> `deps.sql`). Installs the extension according to
  two independent GUC-driven switches (below), or asserts it's already
  installed.
- `core/functions.sql` — a shared helper, `\i`'d by `sql/extension_tests.sql`.
  Defines `ncs()` (discovers, live, which schema the extension is actually
  installed in - never trusts a hardcoded/passed-in value) plus a battery of
  `test__*` functions (pgTAP's `runtests()` naming convention) covering
  function definitions, immutability/strictness, and behavior across
  `anyarray`/`json`/`jsonb` and both trigger functions.
- `sql/extension_tests.sql` — `\i`'s `core/functions.sql`, adds two more
  `test__*` functions of its own (`test__check_ncs`, asserting the extension
  landed where expected; `test__shutdown__drop_all`, asserting it can be
  cleanly dropped), then runs everything via `runtests()`.
- `sql/sanity.sql` — deliberately does NOT go through `deps.sql`/
  `core/functions.sql`. A minimal, independent smoke test: `CREATE EXTENSION`
  (or assert-only, in `existing` mode) plus two direct `null_count()` calls,
  left in an open transaction. Exists specifically so a failure here is
  trivially localized (nothing shared to go wrong) - if this fails, the
  extension itself is broken, not the shared test harness.
- `build/upgrade.sql` — pgxntool's `test-build` feature: a fast, cheap smoke
  check (install 0.9.6, `ALTER EXTENSION UPDATE`, rolled back) that runs
  automatically before the main suite on every `make test`. Catches a broken
  update script immediately, before the heavier CI jobs even start.
- `expected/*.out` — pg_regress's expected output per test file. See
  "Why multiple expected-output files per test" below before touching these.

## The two independent mode switches

Both are make vars, propagated the same way: `make var` -> `PGOPTIONS -c
<guc>=<value>` -> `current_setting()` in `deps.sql` (`pg_regress` doesn't
forward make vars, but the `psql` it spawns inherits the environment).

**`TEST_LOAD_SOURCE`** (`count_nulls.test_load_mode`) — *how* the extension
got there:
- `fresh` (default): `CREATE EXTENSION count_nulls` at current.
- `update`: installs `0.9.6`, then `ALTER EXTENSION UPDATE`. `make
  test-update` wraps this.
- `existing`: extension already installed (a real `pg_upgrade`, or an
  out-of-band update via `bin/test_existing`) - asserts present/current,
  touches nothing.

**`TEST_SCHEMA`** (`count_nulls.test_schema`) — *where* it lands:
- empty (default): no `CREATE SCHEMA`/`SET search_path` at all - lands
  wherever the session's own ambient search_path resolves.
- non-empty: explicitly targets that schema. `TEST_SCHEMA=Quoted` locally
  exercises a name requiring SQL identifier quoting.

These are independent axes; the CI matrix (`.github/workflows/ci.yml`, see
its top-of-file summary comment) crosses both with the PostgreSQL version.

## Why multiple expected-output files per test

`extension_tests.sql`'s assertions build SQL text through `%I`-qualified
`format()` calls using `ncs()`'s result (`core/functions.sql`) - e.g. a
`CREATE TRIGGER ... EXECUTE PROCEDURE tap.null_count_trigger(...)` line's
exact text depends on which schema `ncs()` found. `pg_regress` requires an
EXACT text match against `expected/<test>.out`, so a run that lands the
extension somewhere else produces a *correct but textually different*
result - not a failure to paper over, a second valid baseline to capture.
`pg_regress` natively supports this: it tries `expected/<test>.out`, then
`expected/<test>_1.out`, `_2.out`, ... in turn, and passes if ANY one
matches (see `PGXNTOOL_ENABLE_TEST_BUILD`/pg_regress docs for the general
mechanism - this isn't pgxntool-specific).

Concretely, three real scenarios currently produce different (each
individually correct) text for `extension_tests`, so there are three files:

| File | Scenario | Where the extension lands, and why |
|---|---|---|
| `extension_tests.out` (default) | `TEST_SCHEMA` empty, run in-suite (`make test`) | `tap` - this suite's own pgTAP setup (`pgxntool/test/pgxntool/tap_setup.sql`) already puts its own schema first on `search_path` *before* `deps.sql` runs, so an untargeted `CREATE EXTENSION` lands there. |
| `extension_tests_1.out` | `TEST_SCHEMA=Quoted` (any entry point) | `Quoted` - explicitly targeted, so it's wherever it was told to go, regardless of entry point. |
| `extension_tests_2.out` | `TEST_SCHEMA` empty, run via `bin/test_existing` (the `extension-update-test`/`pg-upgrade-test` CI jobs) | `public` - `bin/test_existing` connects with a bare, standalone `psql` session that never runs `tap_setup.sql`, so an untargeted `CREATE EXTENSION` lands in Postgres's own real default instead. |

If you add a new scenario that changes this text again (a new TEST_SCHEMA
value, a new entry point), capture its actual `test/results/<test>.out` (a
real run, zero raw `^not ok` lines) as the next `_N.out`, don't hand-author
one. `sanity.out` doesn't vary by scenario (its calls are all unqualified,
no schema name ever appears in its output), so it has no alternates.

## Regenerating expected output

Never hand-edit files under `expected/`. Regenerate via `make results`
(guarded by `make verify-results`, which refuses to copy while
`regression.diffs` shows real failures - use `PGXNTOOL_ENABLE_VERIFY_RESULTS=no`
to bypass that guard for a run you've already reviewed and know is a
legitimate, intentional change, not a way to skip reviewing the diff).
`make results` only ever writes the unsuffixed default; alternates
(`_1.out`, `_2.out`, ...) have to be copied by hand from a real
`test/results/<test>.out` for that scenario.
