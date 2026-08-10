# Explicit, not auto-detected: fail loudly if test/install/ ever ends up
# empty by accident, rather than silently falling back to per-test install.
PGXNTOOL_ENABLE_TEST_INSTALL = yes

include pgxntool/base.mk

# Temporary hack
testdeps: $(wildcard test/*/*.sql) $(wildcard test/*.sql) # Be careful not to include directories in this

# sql/count_nulls.sql is the hand-written source the versioned sql/count_nulls--*.sql
# files are generated/derived from; those aren't relinted (see linter's DESIGN.md).
LINT_TARGETS = sql/count_nulls.sql test/
include lint.mk

# TEST_LOAD_SOURCE selects how test/install/load.sql installs count_nulls
# for the WHOLE test run:
#   - fresh (default): CREATE EXTENSION count_nulls (current version).
#   - update: CREATE EXTENSION at the oldest version we still ship a full
#     install script for (0.9.6), then ALTER EXTENSION UPDATE to current -
#     committed, since test/install runs outside any per-test rolled-back
#     transaction (see pgxntool/README.asc's Update & Upgrade (U&U) Testing
#     section for why the commit matters).
#   - existing: count_nulls is already installed (a real `pg_upgrade` run,
#     external to this invocation) - test/install only asserts it's present
#     and current, it does not drop/create/update anything. Meant to be run
#     with CONTRIB_TESTDB=<db> EXTRA_REGRESS_OPTS=--use-existing against a
#     real database, not via a make wrapper here.
#
# "update" (this) is extension-level (ALTER EXTENSION UPDATE); "upgrade" is
# cluster-level (pg_upgrade) - 'existing' is how that axis is exercised.
#
# Propagated as a GUC (count_nulls.test_load_mode), exported unconditionally
# through PGOPTIONS - pg_regress doesn't forward make variables, but the
# psql processes it spawns inherit the environment. Read without missing_ok:
# a genuinely unpropagated GUC must fail loudly, not look like a valid value.
TEST_LOAD_SOURCE ?= fresh
ifeq ($(filter $(TEST_LOAD_SOURCE),fresh update existing),)
$(error TEST_LOAD_SOURCE must be 'fresh', 'update' or 'existing', got '$(TEST_LOAD_SOURCE)')
endif
export PGOPTIONS := $(PGOPTIONS) -c count_nulls.test_load_mode=$(TEST_LOAD_SOURCE)

# TEST_EXISTING_DEPLOY: in 'existing' mode (TEST_LOAD_SOURCE=existing), how
# was the extension actually deployed onto the cluster before this run
# started? Unlike TEST_LOAD_SOURCE/TEST_SCHEMA above, this does not select or
# change any install behavior - it only tells test/install/load.sql's
# existing-mode assertion where to cross-check "what does the cluster
# consider count_nulls's current version" against the actually-installed
# extversion:
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
# decide whether to sandbox `make test`'s install step via a scratch
# DESTDIR) - it's already exported to any `make` invocation bin/test_existing
# spawns as a child process (and explicitly passed through on run_suite's
# `make test` command line too), so no extra plumbing is needed to get it
# here.
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
