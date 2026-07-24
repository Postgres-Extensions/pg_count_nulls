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
