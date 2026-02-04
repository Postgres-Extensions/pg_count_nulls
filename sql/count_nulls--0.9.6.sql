SET client_min_messages = WARNING;

CREATE OR REPLACE FUNCTION null_count(
  VARIADIC argument anyarray
) RETURNS int LANGUAGE sql IMMUTABLE AS $body$
  SELECT sum( CASE WHEN a IS NULL THEN 1 ELSE 0 END )::int
    FROM unnest( $1 ) a
$body$;

CREATE OR REPLACE FUNCTION null_count(
  argument jsonb
) RETURNS int LANGUAGE sql IMMUTABLE AS $body$
SELECT count(*)::int
  FROM jsonb_each_text( $1 ) a
  WHERE value IS NULL
$body$;
CREATE OR REPLACE FUNCTION null_count(
  argument json
) RETURNS int LANGUAGE sql IMMUTABLE AS 'SELECT @extschema@.null_count($1::jsonb)';

CREATE OR REPLACE FUNCTION null_count_trigger(
) RETURNS trigger LANGUAGE plpgsql IMMUTABLE AS $body$
DECLARE
  c_msg CONSTANT text := coalesce(
    nullif( TG_ARGV[1], 'null' )
    , format( '%s must contain %s NULL fields', TG_RELID::regclass, TG_ARGV[0] )
  );
BEGIN
  IF TG_NARGS NOT BETWEEN 1 AND 2 THEN
    RAISE '% usage: number of NULL columns[, error message]', TG_NAME;
  END IF;
  -- Casing intentional for cut/paste/replace/
  IF nullif(TG_ARGV[0], 'null') IS null THEN
    RAISE '%: first argument must not be null', TG_NAME;
  END IF;

  IF @extschema@.null_count( row_to_json(NEW) ) <> TG_ARGV[0]::int THEN
    RAISE '%', c_msg;
  END IF;

  RETURN NEW;
END
$body$;


CREATE OR REPLACE FUNCTION not_null_count(
  VARIADIC argument anyarray
) RETURNS int LANGUAGE sql IMMUTABLE AS $body$
  SELECT sum( CASE WHEN a IS NOT NULL THEN 1 ELSE 0 END )::int
    FROM unnest( $1 ) a
$body$;

CREATE OR REPLACE FUNCTION not_null_count(
  argument jsonb
) RETURNS int LANGUAGE sql IMMUTABLE AS $body$
SELECT count(*)::int
  FROM jsonb_each_text( $1 ) a
  WHERE value IS NOT NULL
$body$;
CREATE OR REPLACE FUNCTION not_null_count(
  argument json
) RETURNS int LANGUAGE sql IMMUTABLE AS 'SELECT @extschema@.not_null_count($1::jsonb)';

CREATE OR REPLACE FUNCTION not_null_count_trigger(
) RETURNS trigger LANGUAGE plpgsql IMMUTABLE AS $body$
DECLARE
  c_msg CONSTANT text := coalesce(
    nullif( TG_ARGV[1], 'null' )
    , format( '%s must contain %s NOT NULL fields', TG_RELID::regclass, TG_ARGV[0] )
  );
BEGIN
  IF TG_NARGS NOT BETWEEN 1 AND 2 THEN
    RAISE '% usage: number of NOT NULL columns[, error message]', TG_NAME;
  END IF;
  -- Casing intentional for cut/paste/replace/
  IF nullif(TG_ARGV[0], 'null') IS null THEN
    RAISE '%: first argument must not be null', TG_NAME;
  END IF;

  IF @extschema@.not_null_count( row_to_json(NEW) ) <> TG_ARGV[0]::int THEN
    RAISE '%', c_msg;
  END IF;

  RETURN NEW;
END
$body$;

-- vi: expandtab sw=2 ts=2
