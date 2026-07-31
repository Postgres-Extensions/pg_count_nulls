# Explicit, not auto-detected: fail loudly if test/install/ ever ends up
# empty by accident, rather than silently falling back to per-test install.
PGXNTOOL_ENABLE_TEST_INSTALL = yes

include pgxntool/base.mk

# Temporary hack
testdeps: $(wildcard test/*/*.sql) $(wildcard test/*.sql) # Be careful not to include directories in this

# TEST_SCHEMA selects which schema test/install/load.sql installs count_nulls
# into, for the WHOLE test run (every test file sees the SAME schema in a
# given run).
#
# Empty (the default): don't target any schema at all - count_nulls installs
# wherever the session's own default search_path already resolves. Non-empty:
# explicitly CREATE SCHEMA/SET search_path to that name first - including a
# name that requires SQL identifier quoting (mixed case - unquoted would fold
# to lowercase), to exercise the suite's %I schema-qualification rather than
# just its literal test data. Locally: `make test TEST_SCHEMA=Quoted`.
#
# Propagated as a GUC (count_nulls.test_schema), exported unconditionally via
# PGOPTIONS - pg_regress doesn't forward make variables, but the psql
# processes it spawns inherit the environment. Empty is a valid, deliberate
# value (not an error) - read without missing_ok, so a truly unpropagated GUC
# still fails loudly instead of looking identical to a deliberately empty one.
TEST_SCHEMA ?=
export PGOPTIONS := $(PGOPTIONS) -c count_nulls.test_schema=$(TEST_SCHEMA)

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
# Propagated the same way as TEST_SCHEMA: via the count_nulls.test_load_mode
# GUC, exported unconditionally through PGOPTIONS, read without missing_ok.
TEST_LOAD_SOURCE ?= fresh
ifeq ($(filter $(TEST_LOAD_SOURCE),fresh update existing),)
$(error TEST_LOAD_SOURCE must be 'fresh', 'update' or 'existing', got '$(TEST_LOAD_SOURCE)')
endif
export PGOPTIONS := $(PGOPTIONS) -c count_nulls.test_load_mode=$(TEST_LOAD_SOURCE)

# Convenience wrapper: `make test-update` == `make test TEST_LOAD_SOURCE=update`.
# Must recurse (a fresh $(MAKE)) rather than depend on `test`, so the
# parse-time TEST_LOAD_SOURCE conditional above re-evaluates with update set.
.PHONY: test-update
test-update:
	$(MAKE) test TEST_LOAD_SOURCE=update
