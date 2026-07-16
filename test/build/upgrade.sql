\set ECHO none
\i test/pgxntool/psql.sql
\t

-- Sanity check: install the oldest available version and upgrade to current.
-- sql/count_nulls--0.9.6.sql is the oldest full install script we still ship
-- (0.9.0/0.9.2/0.9.5 only exist as upgrade diffs, not standalone installs).
BEGIN;
CREATE EXTENSION count_nulls VERSION '0.9.6';
ALTER EXTENSION count_nulls UPDATE;
ROLLBACK;
