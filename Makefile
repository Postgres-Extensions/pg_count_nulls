include pgxntool/base.mk

# Temporary hack
testdeps: $(wildcard test/*/*.sql) $(wildcard test/*.sql) # Be careful not to include directories in this

# Install the oldest historical version's full install script so the upgrade
# test in test/build/upgrade.sql and test/deps.sql's upgrade mode can
# CREATE EXTENSION count_nulls VERSION '0.9.6'.
# Not covered by base.mk's DATA wildcard, which only picks up upgrade scripts
# (sql/*--*--*.sql) and the current version file.
DATA += sql/count_nulls--0.9.6.sql

# TEST_LOAD_SOURCE selects how test/deps.sql installs the extension for the
# WHOLE test suite:
#   - fresh (default): CREATE EXTENSION count_nulls (current version).
#   - upgrade: CREATE EXTENSION at the oldest version we still ship a full
#     install script for (0.9.6), then ALTER EXTENSION UPDATE to current.
# Running the SAME suite with the SAME expected output against the upgraded
# database proves it behaves identically to a fresh install.
#
# The mode is signalled to test/deps.sql via the count_nulls.test_load_mode
# placeholder GUC. pg_regress does not forward make variables, but the psql
# processes it spawns inherit the environment, so PGOPTIONS reaches deps.sql.
# It's exported unconditionally so deps.sql can read it without missing_ok
# and fail loudly if it didn't propagate, instead of silently defaulting to
# fresh and running the wrong suite.
TEST_LOAD_SOURCE ?= fresh
ifeq ($(filter $(TEST_LOAD_SOURCE),fresh upgrade),)
$(error TEST_LOAD_SOURCE must be 'fresh' or 'upgrade', got '$(TEST_LOAD_SOURCE)')
endif
export PGOPTIONS := $(PGOPTIONS) -c count_nulls.test_load_mode=$(TEST_LOAD_SOURCE)

# Convenience wrapper: `make test-update` == `make test TEST_LOAD_SOURCE=upgrade`.
# Must recurse (a fresh $(MAKE)) rather than depend on `test`, so the
# parse-time TEST_LOAD_SOURCE conditional above re-evaluates with upgrade set.
.PHONY: test-update
test-update:
	$(MAKE) test TEST_LOAD_SOURCE=upgrade
