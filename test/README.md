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
- `sql/extension_tests.sql` — `\i`'s `core/functions.sql`, adds two more
  `test__*` functions of its own (`test__check_ncs`, asserting count_nulls
  landed where expected; `test__shutdown__drop_all`, asserting it can be
  cleanly dropped), then runs everything via `runtests()`.

## TEST_SCHEMA

A make var/GUC (`count_nulls.test_schema`, propagated the same way as any
other placeholder GUC: `make var` -> `PGOPTIONS -c ...` -> `current_setting()`
- pg_regress doesn't forward make variables, but the psql processes it
spawns inherit the environment) selecting which schema `install/load.sql`
installs count_nulls into:

- Empty (default): no schema targeting at all - count_nulls lands wherever
  the session's own default search_path resolves. Since `install/load.sql`
  runs in its own bare connection (not the in-suite session pgTAP's own
  `tap_setup.sql` runs in), that's `public`.
- Non-empty: explicitly `CREATE SCHEMA`, then `CREATE EXTENSION ... WITH
  SCHEMA` that name - `install/load.sql` never mutates its own
  search_path to do this. `TEST_SCHEMA=Quoted` locally exercises a name
  requiring SQL identifier quoting (mixed case - unquoted would fold to
  lowercase).

Both legs run in CI - genuinely different code paths, not one a redundant
special case of the other.

**Why two legs prove anything.** Installing into two different schemas by
itself doesn't test whether count_nulls' own SQL correctly schema-qualifies
its internal references - if BOTH schemas happened to stay on the test
session's search_path (e.g. because the empty leg's `public` and the
`TEST_SCHEMA` leg's target were both reachable), an extension full of
unqualified, resolve-by-accident references would pass every leg too. What
actually matters is that at least ONE leg's install schema is verifiably
absent from search_path, so that leg's assertions only pass if `%I`-qualified
references are genuinely correct - checked by `test__check_ncs` in
`sql/extension_tests.sql`. This suite goes further and excludes the schema
from search_path in *every* leg, via the fixed `SET SEARCH_PATH` in
`core/functions.sql` - a stronger, deliberate choice, not the minimum
required.

**Assertion descriptions deliberately never embed the schema name.**
`core/functions.sql`'s assertions build the SQL they *execute* via `%I`
qualification (through `ncs()`, so they're always correct no matter which
real schema count_nulls landed in) but pass an *explicit*, schema-free
description to every pgTAP call - overriding pgTAP's own auto-generated
descriptions, which otherwise embed the schema. This is what keeps
`test/expected/extension_tests.out` a single file that both TEST_SCHEMA
legs pass against, instead of needing one file per schema value.

**`test__shutdown__drop_all`'s schema drop is plain cleanup, not a TAP
assertion.** Dropping the schema TEST_SCHEMA created is a real, correct
behavioral difference between "there's a schema to clean up" (non-empty)
and "there isn't" (empty, nothing to drop) - but it's teardown, not
something this suite is testing, so it's plain `EXECUTE`'d SQL with no
`lives_ok()`/`skip()` branch. That keeps its TAP output identical in every
TEST_SCHEMA leg (one `ok` row either way), so `test/expected/extension_tests.out`
needs no numbered pg_regress alternate for this function.

## Regenerating expected output

Never hand-edit files under `expected/`. Regenerate via `make results`
(guarded by `make verify-results`, which refuses to copy while
`regression.diffs` shows real failures - use
`PGXNTOOL_ENABLE_VERIFY_RESULTS=no` to bypass that guard for a run you've
already reviewed and know is a legitimate, intentional change, not a way to
skip reviewing the diff). `make results` only ever writes the unsuffixed
default; alternates (`_1.out`, ...) have to be copied by hand from a real
`test/results/<test>.out` for that scenario.
