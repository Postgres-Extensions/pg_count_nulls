include pgxntool/base.mk

# Temporary hack
testdeps: $(wildcard test/*/*.sql) $(wildcard test/*.sql) # Be careful not to include directories in this

# Install the outgoing "current" version's full install script now that
# default_version is 'stable' (see count_nulls.control and RELEASE.md), so
# CREATE EXTENSION count_nulls VERSION '1.0.0' keeps working. Not covered by
# base.mk's DATA wildcard, which only picks up upgrade scripts
# (sql/*--*--*.sql) and the CURRENT version file (now
# sql/count_nulls--stable.sql) - a pgxntool bug, filed as
# Postgres-Extensions/pgxntool#48.
DATA += sql/count_nulls--1.0.0.sql

# Same gap, for the oldest version we still ship a full install script for
# (0.9.6): test/deps.sql's 'update' load mode and bin/test_existing both
# need `CREATE EXTENSION count_nulls VERSION '0.9.6'` to work, and it's
# neither the CURRENT version file nor an upgrade script, so base.mk's DATA
# wildcard misses it too.
DATA += sql/count_nulls--0.9.6.sql

# TEST_LOAD_SOURCE selects how test/deps.sql installs the extension for the
# WHOLE test suite:
#   - fresh (default): CREATE EXTENSION count_nulls (current version).
#   - update: CREATE EXTENSION at the oldest version we still ship a full
#     install script for (0.9.6), then ALTER EXTENSION UPDATE to current.
#   - existing: the extension is already installed (a real `pg_upgrade` run,
#     or an out-of-band update) - deps.sql only asserts it's present and
#     current, it does not drop/create/update anything. Meant to be run with
#     CONTRIB_TESTDB=<db> EXTRA_REGRESS_OPTS=--use-existing
#     PGXNTOOL_ENABLE_TEST_BUILD=no against a real database, not via a make
#     wrapper here (see bin/test_existing and the pg_upgrade CI job).
# Running the SAME suite with the SAME expected output against the updated/
# upgraded database proves it behaves identically to a fresh install.
#
# "update" (this) is extension-level (ALTER EXTENSION UPDATE); "upgrade" is
# cluster-level (pg_upgrade) - 'existing' is how that axis is exercised.
# Don't conflate the two in variable names or comments.
#
# The mode is signalled to test/deps.sql via the count_nulls.test_load_mode
# placeholder GUC. pg_regress does not forward make variables, but the psql
# processes it spawns inherit the environment, so PGOPTIONS reaches deps.sql.
# It's exported unconditionally so deps.sql can read it without missing_ok
# and fail loudly if it didn't propagate, instead of silently defaulting to
# fresh and running the wrong suite.
TEST_LOAD_SOURCE ?= fresh
ifeq ($(filter $(TEST_LOAD_SOURCE),fresh update existing),)
$(error TEST_LOAD_SOURCE must be 'fresh', 'update' or 'existing', got '$(TEST_LOAD_SOURCE)')
endif
export PGOPTIONS := $(PGOPTIONS) -c count_nulls.test_load_mode=$(TEST_LOAD_SOURCE)

# TEST_SCHEMA selects which schema test/deps.sql installs count_nulls into,
# for the WHOLE test run (every test file uses the SAME schema in a given
# run - previously each test file hardcoded its own literal schema name as a
# stand-in for real schema-qualification coverage, which only ever tested
# two fixed, always-lowercase names).
#
# Empty (the default): don't target any schema at all. The extension
# installs wherever the session's own default search_path already resolves
# (ordinarily 'public'), exercising the plain, untouched default-install
# code path - the "without a schema" leg.
#
# Non-empty: explicitly CREATE SCHEMA/SET search_path to that name before
# installing - the "with a schema" leg. In particular, a schema whose name
# requires SQL identifier quoting (mixed case - unquoted would silently fold
# to lowercase) exercises the suite's %I schema-qualification, not just its
# literal test data. Locally: `make test TEST_SCHEMA=Quoted`.
#
# Both legs matter and both run in CI - "without" and "with" are genuinely
# different code paths (one never touches search_path, the other explicitly
# targets a schema), not one being a redundant special case of the other.
#
# Propagated the same way as TEST_LOAD_SOURCE: via the count_nulls.test_schema
# GUC, exported unconditionally through PGOPTIONS. Empty is a valid,
# deliberate value here (not an error) - deps.sql reads it without
# missing_ok, so a truly unset GUC (the pipeline failing to propagate at all)
# still fails loudly, while an explicitly empty one means "no schema".
TEST_SCHEMA ?=
export PGOPTIONS := $(PGOPTIONS) -c count_nulls.test_schema=$(TEST_SCHEMA)

# TEST_EXISTING_DEPLOY: in 'existing' mode (TEST_LOAD_SOURCE=existing), how
# was the extension actually deployed onto the cluster before this run
# started? Unlike TEST_LOAD_SOURCE/TEST_SCHEMA above, this does not select or
# change any install behavior - it only tells test/deps.sql's existing-mode
# assertion where to cross-check "what does the cluster consider count_nulls's
# current version" against the actually-installed extversion:
#   - filesystem (default): a real .control file is on disk (a real `make
#     install`, or a pg_upgrade'd cluster carrying one over) - cross-check
#     against pg_available_extensions.default_version, which reads .control
#     files directly off disk.
#   - pgtle: count_nulls was registered purely through pg_tle's
#     database-backed catalog (see the pg-tle-test CI job), never touching
#     the filesystem. pg_available_extensions does NOT see pg_tle
#     registrations at all - it only ever reads .control files off disk - so
#     its default_version comes back NULL for a pg_tle-only extension even
#     though a version-less CREATE EXTENSION resolves correctly through
#     pg_tle. pg_tle ships its own separate, non-integrated analog instead:
#     pgtle.available_extensions(), a C function whose own doc comment in
#     pg_tle's tleextension.c says "The system view pg_available_extensions
#     provides a user interface to this SRF" - i.e. pg_tle's SRF is modeled
#     on pg_available_extensions, but pg_tle never hooks or populates the
#     real view itself. In this mode, cross-check against pg_tle's SRF
#     instead.
#
# Deliberately the SAME env var name bin/test_existing already reads (to
# decide between `make test`/`verify-results` and `make testdeps`/
# `installcheck`), not a second variable: it's already exported to any `make`
# invocation bin/test_existing spawns as a child process, so no extra
# plumbing is needed to get it here.
TEST_EXISTING_DEPLOY ?= filesystem
ifeq ($(filter $(TEST_EXISTING_DEPLOY),filesystem pgtle),)
$(error TEST_EXISTING_DEPLOY must be 'filesystem' or 'pgtle', got '$(TEST_EXISTING_DEPLOY)')
endif
export PGOPTIONS := $(PGOPTIONS) -c count_nulls.test_existing_deploy=$(TEST_EXISTING_DEPLOY)

# Convenience wrapper: `make test-update` == `make test TEST_LOAD_SOURCE=update`.
# Must recurse (a fresh $(MAKE)) rather than depend on `test`, so the
# parse-time TEST_LOAD_SOURCE conditional above re-evaluates with update set.
.PHONY: test-update
test-update:
	$(MAKE) test TEST_LOAD_SOURCE=update
