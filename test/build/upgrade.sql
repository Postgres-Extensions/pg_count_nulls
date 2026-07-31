\set ECHO none
\i test/pgxntool/psql.sql
\t

/*
 * Fast, cheap smoke check: install the oldest version we still ship a full
 * script for and ALTER EXTENSION UPDATE to current, rolled back so it has
 * no side effects. sql/count_nulls--0.9.6.sql is that oldest full install
 * script (0.9.0/0.9.2/0.9.5 only exist as upgrade diffs, not standalone
 * installs).
 *
 * pgxntool's test-build feature runs this automatically as part of every
 * plain `make test` - i.e. on every PG major in the fresh-install CI
 * matrix, before the pgTAP suite even starts. It only proves the update
 * SQL runs without erroring, nothing about behavior, so it's not a
 * substitute for test/deps.sql's 'update' load mode (which reruns the
 * whole suite against the updated database - see the extension-update-test
 * CI job) or the real binary-pg_upgrade coverage (pg-upgrade-test). Its
 * value is failing fast and cheaply on a broken update script, across
 * every supported PostgreSQL major, before those heavier jobs run at all.
 */
BEGIN;
CREATE EXTENSION count_nulls VERSION '0.9.6';
ALTER EXTENSION count_nulls UPDATE;
ROLLBACK;
