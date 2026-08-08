/*
 * Dependency guard: plants an object with a hard pg_depend dependency on a
 * stable, never-dropped/redefined extension member (null_count(anyarray),
 * unchanged since 0.9.0), so that a non-CASCADE DROP EXTENSION count_nulls
 * is blocked. Used by the pg_upgrade CI job to prove a real pg_upgrade/
 * update run didn't silently destroy the extension it's meant to be
 * testing (a stray CASCADE drop, a logic bug, a bad CI step would
 * otherwise fall through to a silent fresh reinstall and the job would
 * still report green).
 *
 * count_nulls always installs into its own randomly generated schema (see
 * test/helpers/create_test_schema.sql) - this session didn't create it, so
 * it has no other way to know its name; test/helpers/find_test_schema.sql
 * discovers it live via pg_namespace.
 *
 * Usage: psql -v ON_ERROR_STOP=1 -f plant_guard.sql
 */
\set ON_ERROR_STOP on

\i test/helpers/find_test_schema.sql

CREATE SCHEMA IF NOT EXISTS count_nulls_drop_guard;
CREATE OR REPLACE VIEW count_nulls_drop_guard.guard AS
  SELECT :"test_schema".null_count(NULL::int, NULL::int) AS guarded_member;
