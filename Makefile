include pgxntool/base.mk

# Temporary hack
testdeps: $(wildcard test/*/*.sql) $(wildcard test/*.sql) # Be careful not to include directories in this

# sql/count_nulls.sql is the hand-written source the versioned sql/count_nulls--*.sql
# files are generated/derived from; those aren't relinted (see linter's DESIGN.md).
LINT_TARGETS = sql/count_nulls.sql test/
include lint.mk
