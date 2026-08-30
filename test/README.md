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
  `pgxntool/setup.sql` -> `deps.sql`). Doesn't install count_nulls (that's
  `install/load.sql`'s job); its only job is `\i`ing `helpers/test_user.sql`
  so each test session runs unprivileged (see "Running as a non-superuser"
  below).
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
- `helpers/test_user.sql` — drops the session to a non-superuser role (see
  "Running as a non-superuser" below). `\i`'d by `deps.sql` and
  `helpers/create_test_schema.sql`.

## Running as a non-superuser

Every session the suite runs in - the install session and each test session
- runs as an ordinary role, `Test user for count_nulls`. That's what makes
`superuser = false` in `count_nulls.control` a tested property rather than a
claim: count_nulls is pure SQL functions with nothing privileged in it, and
a suite running as a superuser could never notice that line going missing.

`helpers/test_user.sql` owns the whole arrangement, and is `\i`'d from both
entry points that start such a session: `deps.sql` (every `test/sql/` file,
via pgxntool's `setup.sql`) and `helpers/create_test_schema.sql` (the
install session, and `bin/test_existing`'s `prepare-old`).

The role's name is spelled exactly once, as a psql variable at the top of
that file. Like the generated schema name it can't be written without SQL
identifier quoting, and it's deliberately sentence-like so it won't collide
with a real role on whatever cluster someone points the suite at.

**Every decision is server-side**, in a `pg_temp` function taking the role
name and *returning the role this session should run as*, because psql can't
branch before 10: `\if` is psql 10, and CI covers back to 9.4, where psql
reports it as an invalid command and then runs the branch it should have
skipped. (`\gset`, which feeds the returned name into the `SET ROLE`, is fine
- 9.3.) The function creates the role if it's missing, grants it what it
needs, and raises if the role is a superuser or a member of any managed-cloud
equivalent - `rds_superuser` (RDS/Aurora), `cloudsqlsuperuser` (Cloud SQL) or
`azure_pg_admin` (Azure Flexible Server), none of which carry `rolsuper`, so
they have to be named. The `SET ROLE` itself is a plain statement after that
call, not something the function does.

**One case deliberately doesn't switch**: a count_nulls that's already
installed and owned by somebody else, which is what a real `pg_upgrade`
leaves behind (existing mode). PostgreSQL has no `ALTER EXTENSION ... OWNER
TO`, so pg_dump can't carry an extension's ownership across - `--binary-
upgrade` emits `binary_upgrade_create_empty_extension()`, which takes no
owner, and the extension ends up belonging to whoever ran the restore. Its
member functions keep their owner; only the extension object itself is out of
reach, which is precisely what `test__shutdown__drop_all` needs. Switching
there would just hand the suite a role that can't drop the extension, and
nothing is lost by staying put: existing mode installs nothing, so it was
never the leg proving the install works unprivileged.

Don't expect a newer PostgreSQL to retire that branch. `extowner` has had no
matching `ALTER EXTENSION ... OWNER TO` since it was added in 2011, because
what that should do to the contained objects was never settled (handing a
non-superuser a C-language handler function is the awkward case). Reported as
BUG #18625 and acknowledged as a known shortcoming, still unfixed.
`pg_dump --use-set-session-authorization` does dodge it, but `pg_upgrade`
offers no way to ask for that.

The file opens with `RESET ROLE` so a second `\i` in one session behaves
exactly like the first - which is not hypothetical, since on psql older than
10 `install/load.sql`'s mode branches all run and this file gets reached
twice.

Only two privileges are granted: `CREATE` on the database (count_nulls' own
schema, and `_null_count_test`) and `USAGE` on schema `tap` (pgTAP is
harness, and `setup.sql` creates that schema as the connecting role, which
grants nobody else access). Anything beyond those turning out to be
necessary is a finding about count_nulls, not something to grant here.

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
