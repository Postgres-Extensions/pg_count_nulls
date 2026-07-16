-- Note: pgTap is loaded by setup.sql

-- Add any test dependency statements here
-- IF NOT EXISTS will emit NOTICEs, which is annoying
SET client_min_messages = WARNING;
CREATE SCHEMA IF NOT EXISTS :schema;
SET search_path = :schema;
SET client_min_messages = NOTICE;

CREATE EXTENSION count_nulls;
