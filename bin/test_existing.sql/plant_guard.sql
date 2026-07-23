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
 * Usage: psql -v ON_ERROR_STOP=1 -v schema=<schema-or-empty> -f plant_guard.sql
 * (empty schema means "wherever null_count already resolves unqualified" -
 * i.e. the extension was installed without targeting a schema).
 */
\set ON_ERROR_STOP on
SELECT :'schema' <> '' AS count_nulls_has_schema
\gset

CREATE SCHEMA IF NOT EXISTS count_nulls_drop_guard;
\if :count_nulls_has_schema
CREATE OR REPLACE VIEW count_nulls_drop_guard.guard AS
  SELECT :"schema".null_count(NULL::int, NULL::int) AS guarded_member;
\else
CREATE OR REPLACE VIEW count_nulls_drop_guard.guard AS
  SELECT null_count(NULL::int, NULL::int) AS guarded_member;
\endif
