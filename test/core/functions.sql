CREATE SCHEMA _null_count_test;

-- See bottom as well!
SET SEARCH_PATH = _null_count_test, tap;

CREATE FUNCTION ncs() RETURNS name IMMUTABLE LANGUAGE sql AS $$
SELECT nspname FROM pg_namespace n JOIN pg_extension x ON n.oid = x.extnamespace WHERE extname = 'count_nulls'
$$;
/*
 * NOTE! Do not use create or replace function in here. If you do that and
 * accidentally try to define the same function twice you'll never detect that
 * mistake!
 */

/*
CREATE FUNCTION test__
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
BEGIN
END
$body$;
*/

/*
 * function definition
 */
CREATE FUNCTION test__definition
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
  f_name name;
  t text;
  f_args text[];
BEGIN
  FOREACH f_name IN ARRAY '{null_count,not_null_count}'::name[] LOOP
    FOREACH t IN ARRAY '{anyarray,json,jsonb}'::text[] LOOP
      f_args := array[t];

      -- If the installed schema isn't in our search path
      IF NOT current_schemas(true)@>array[ncs()] THEN
        RETURN NEXT hasnt_function(
          f_name, f_args
          , format('ensure %s(%s) is not in search_path', f_name, f_args)
        );
      END IF;

      RETURN NEXT function_returns(
        ncs(), f_name, f_args
        , 'int'::regtype::text -- Sanitize type name
      );

      -- TODO: isnt_definer
      RETURN NEXT isnt_strict(
        ncs(), f_name, f_args
      );

      RETURN NEXT volatility_is(
        ncs(), f_name, f_args
        , 'immutable'
      );
    END LOOP;
  END LOOP;

  FOREACH f_name IN ARRAY '{null_count_trigger,not_null_count_trigger}'::name[] LOOP
    f_args := '{}';
    RETURN NEXT function_returns(
      ncs(), f_name, f_args
      , 'trigger'
    );

    -- TODO: isnt_definer
    RETURN NEXT isnt_strict(
      ncs(), f_name, f_args
    );

    RETURN NEXT volatility_is(
      ncs(), f_name, f_args
      , 'immutable'
    );
  END LOOP;
END
$body$;

/*
 * Operation
 */

CREATE FUNCTION pg_temp.test_trigger_raw(
  trigger_name name
  , ba text
  , exec text
  , errmsg text
  , errdesc text

) RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
  c_command CONSTANT text :=
    format( $$CREATE TRIGGER %s %s INSERT ON test_data FOR EACH ROW EXECUTE PROCEDURE %s$$
      , trigger_name
      , ba
      , exec
    )
  ;
BEGIN
  RETURN NEXT lives_ok( c_command, c_command );
  RETURN NEXT throws_ok(
    $$INSERT INTO test_data VALUES (1,1,NULL)$$
    , 'P0001'
    , errmsg
    , errdesc
  );

  RETURN NEXT lives_ok(
    format( 'DROP TRIGGER %s ON test_data', trigger_name )
    , format( 'DROP TRIGGER %s', trigger_name )
  );
END
$body$;

CREATE FUNCTION pg_temp.test_trigger(
  ba text
  , nn text
  , err text
) RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
  c_trigger_name CONSTANT text := quote_ident(format('%s_%s_%s', nn, ba, err));
BEGIN
  RETURN QUERY
    SELECT pg_temp.test_trigger_raw(
      c_trigger_name
      , ba
      , exec := format(
          $$%I.%s_count_trigger(1, %L)$$
          , ncs()
          , nn
          , err
        )
      , errmsg := coalesce( err, format( 'test_data must contain 1 %s fields', upper( replace( nn, '_', ' ' ) ) ) )
      , errdesc := 'Test ' || c_trigger_name
    )
  ;
END
$body$;

CREATE FUNCTION test__functionality
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
BEGIN
  CREATE TEMP TABLE test_data AS
    SELECT * FROM (
    VALUES
      -- Can't make first argument bigint without variant
        ( 1::int, 2::int, 3::int, 0 )
      , ( 1,    2,    NULL, 1 )
      , ( 1,    NULL, 3,    1 )
      , ( 1,    NULL, NULL, 2 )
      , ( NULL, 2,    3,    1 )
      , ( NULL, 2,    NULL, 2 )
      , ( NULL, NULL, 3,    2 )
      , ( NULL, NULL, NULL, 3 )
    ) AS a( a, b, c, null_count )
  ;

  RETURN NEXT bag_eq(
    format($$SELECT a, b, c, %1$I.null_count( a, b, c ), %1$I.not_null_count( a, b, c ) FROM test_data$$, ncs())
    , $$SELECT *, 3-null_count AS not_null_count FROM test_data$$
    , format('Test %I.null_count(a, b, c)', ncs())
  );

  -- Test JSON versions
  -- These could be combined...
  RETURN NEXT bag_eq(
    format($$SELECT a, b, c, %1$I.null_count( row_to_json( row(a, b, c) ) ), %1$I.not_null_count( row_to_json( row(a, b, c) ) ) FROM test_data$$, ncs())
    , $$SELECT *, 3-null_count AS not_null_count FROM test_data$$
    , format('Test %I.null_count(json)', ncs())
  );
  RETURN NEXT bag_eq(
    format($$SELECT a, b, c, %1$I.null_count( row_to_json( row(a, b, c) )::jsonb ), %1$I.not_null_count( row_to_json( row(a, b, c) )::jsonb ) FROM test_data$$, ncs())
    , $$SELECT *, 3-null_count AS not_null_count FROM test_data$$
    , format('Test %I.null_count(jsonb)', ncs())
  );

  -- Doesn't work for array types
  /*
  RETURN NEXT bag_eq(
    $$SELECT a, b, c, null_count( array[a], array[b], array[c] ) FROM test_data$$
    , $$SELECT * FROM test_data$$
    , 'Test null_count(array[a], array[b], array[c])'
  );
  */

  RETURN QUERY
    SELECT pg_temp.test_trigger_raw(
          '"test trigger"'
          , 'BEFORE'
          , trig
          , CASE
              WHEN args = '' AND not_ = 'not_'  THEN $$test trigger usage: number of NOT NULL columns[, error message]$$
              WHEN args = '' AND not_ = ''      THEN $$test trigger usage: number of NULL columns[, error message]$$
              ELSE 'test trigger: first argument must not be null'
            END
          , 'Test ' || trig
        )
      FROM (
        SELECT *, format( '%I.%snull_count_trigger( %s )', ncs(), not_, args ) AS trig
          FROM
            unnest( array['not_', ''] ) not_
            , unnest( array['NULL', ''] ) args
        ) a
  ;

  RETURN QUERY
    SELECT pg_temp.test_trigger( ba, nn, err )
      FROM
        unnest( '{"null",not_null}'::text[] ) AS nn(nn)
        , unnest( '{BEFORE,AFTER}'::text[] ) AS ba(ba)
        , unnest( '{"error_message",NULL}'::text[] ) AS err(err)
  ;

END
$body$;

/*
 * Deliberately does NOT restore :"schema" (the schema count_nulls is
 * installed into) onto search_path here - whether the caller wants it there
 * (testing unqualified/on-search-path use) or not (testing fully-qualified/
 * off-search-path use) differs per test file, so each caller sets its own
 * search_path explicitly after \i'ing this file.
 */

-- vi: expandtab sw=2 ts=2
