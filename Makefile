include pgxntool/base.mk

# Temporary hack
testdeps: $(wildcard test/*/*.sql) $(wildcard test/*.sql) # Be careful not to include directories in this

# Install the oldest historical version's full install script so the update
# test in test/build/upgrade.sql and test/deps.sql's update mode can
# CREATE EXTENSION count_nulls VERSION '0.9.6'.
# Not covered by base.mk's DATA wildcard, which only picks up upgrade scripts
# (sql/*--*--*.sql) and the current version file - a pgxntool bug, filed as
# Postgres-Extensions/pgxntool#48.
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
#     wrapper here (see the pg_upgrade CI job).
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

# Convenience wrapper: `make test-update` == `make test TEST_LOAD_SOURCE=update`.
# Must recurse (a fresh $(MAKE)) rather than depend on `test`, so the
# parse-time TEST_LOAD_SOURCE conditional above re-evaluates with update set.
.PHONY: test-update
test-update:
	$(MAKE) test TEST_LOAD_SOURCE=update
