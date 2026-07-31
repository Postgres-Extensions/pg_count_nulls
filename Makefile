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
