\i test/pgxntool/setup.sql

SET search_path = tap, public;

-- Don't use IF NOT EXISTS here; we want to ensure we always have the latest code
SET client_min_messages = WARNING; -- Squelch notices about dependent extensions

CREATE SCHEMA IF NOT EXISTS :schema;
SET search_path = :schema;

CREATE EXTENSION object_reference CASCADE;

CREATE EXTENSION count_nulls;

--SET client_min_messages = NOTICE;
