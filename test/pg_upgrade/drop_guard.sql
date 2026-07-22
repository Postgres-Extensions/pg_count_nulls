-- Removes the guard (plant_guard.sql) once its job is done - proving the
-- install/pg_upgrade/update steps didn't corrupt the real extension - so it
-- doesn't then block the pgTap suite's own DROP EXTENSION test
-- (test__shutdown__drop_all, run in a transaction that's rolled back
-- regardless, so re-dropping the real extension there is harmless).
--
-- Usage: psql -v ON_ERROR_STOP=1 -f drop_guard.sql
\set ON_ERROR_STOP on
DROP SCHEMA count_nulls_drop_guard CASCADE;
