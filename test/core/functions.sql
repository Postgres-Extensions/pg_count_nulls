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

/* EXCLUDED CODE — unused boilerplate template for new test functions, not meant to be enabled
CREATE FUNCTION test__
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
BEGIN
END
$body$;
*/

/*
 * search_path guard: not a correctness assertion about count_nulls itself,
 * but a guard against some OTHER test in this suite accidentally mutating
 * search_path (e.g. via a stray SET) and leaking that mutation into every
 * test that runs afterward. At this phase there's no TEST_SCHEMA concept
 * yet, so the expected search_path for this test session is already a
 * static, hardcoded literal - it's set two lines above (SET SEARCH_PATH =
 * _null_count_test, tap) - so there's nothing to capture at runtime; just
 * compare current_setting('search_path') against that known literal. A
 * plain exception is enough here - pgTAP's runner reports any exception
 * raised by a teardown__ function as "Test died: ..." against the test it
 * ran after, no ok()/is() needed.
 *
 * SEE ALSO: test__check_ncs in test/sql/extension_tests.sql, which checks
 * WHERE count_nulls actually landed (a different risk than this check).
 */
CREATE FUNCTION _null_count_test.teardown__search_path_unchanged
() RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
    v_current text := current_setting('search_path');
BEGIN
    IF v_current IS DISTINCT FROM '_null_count_test, tap' THEN
        RAISE EXCEPTION
            'search_path was left dirty by the preceding test: expected %, got %'
            , '_null_count_test, tap', v_current;
    END IF;
    RETURN;
END
$body$;

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

      /*
       * Explicit descriptions below (not pgTAP's auto-generated default,
       * which schema-qualifies via ncs()): this suite may run against
       * count_nulls installed in ANY schema (see TEST_SCHEMA in the
       * Makefile), and the description text is exact-matched by pg_regress
       * against a single committed expected-output file - it must stay
       * IDENTICAL no matter which schema the extension actually landed in.
       * ncs() itself is still used to locate and call the real function;
       * only the visible description text drops it.
       */
      RETURN NEXT function_returns(
        ncs(), f_name, f_args
        , 'int'::regtype::text -- Sanitize type name
        , format('Function %s(%s) should return int', f_name, array_to_string(f_args, ','))
      );

      -- TODO: isnt_definer
      RETURN NEXT isnt_strict(
        ncs(), f_name, f_args
        , format('Function %s(%s) should not be strict', f_name, array_to_string(f_args, ','))
      );

      RETURN NEXT volatility_is(
        ncs(), f_name, f_args
        , 'immutable'
        , format('Function %s(%s) should be IMMUTABLE', f_name, array_to_string(f_args, ','))
      );
    END LOOP;
  END LOOP;

  FOREACH f_name IN ARRAY '{null_count_trigger,not_null_count_trigger}'::name[] LOOP
    f_args := '{}';
    RETURN NEXT function_returns(
      ncs(), f_name, f_args
      , 'trigger'
      , format('Function %s() should return trigger', f_name)
    );

    -- TODO: isnt_definer
    RETURN NEXT isnt_strict(
      ncs(), f_name, f_args
      , format('Function %s() should not be strict', f_name)
    );

    RETURN NEXT volatility_is(
      ncs(), f_name, f_args
      , 'immutable'
      , format('Function %s() should be IMMUTABLE', f_name)
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
  /*
   * Schema-free stand-in for exec, used ONLY in the visible description
   * below - exec itself (schema-qualified via ncs(), by callers) is what
   * actually runs. Keeps this suite's output identical no matter which
   * schema count_nulls is installed in (see TEST_SCHEMA).
   */
  , exec_desc text

) RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
  c_command CONSTANT text :=
    format( $$CREATE TRIGGER %s %s INSERT ON test_data FOR EACH ROW EXECUTE PROCEDURE %s$$
      , trigger_name
      , ba
      , exec
    )
  ;
  c_command_desc CONSTANT text :=
    format( $$CREATE TRIGGER %s %s INSERT ON test_data FOR EACH ROW EXECUTE PROCEDURE %s$$
      , trigger_name
      , ba
      , exec_desc
    )
  ;
BEGIN
  RETURN NEXT lives_ok( c_command, c_command_desc );
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
      , exec_desc := format(
          $$%s_count_trigger(1, %L)$$
          , nn
          , err
        )
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
    , 'Test null_count(a, b, c)'
  );

  -- Test JSON versions
  -- These could be combined...
  RETURN NEXT bag_eq(
    format($$SELECT a, b, c, %1$I.null_count( row_to_json( row(a, b, c) ) ), %1$I.not_null_count( row_to_json( row(a, b, c) ) ) FROM test_data$$, ncs())
    , $$SELECT *, 3-null_count AS not_null_count FROM test_data$$
    , 'Test null_count(json)'
  );
  RETURN NEXT bag_eq(
    format($$SELECT a, b, c, %1$I.null_count( row_to_json( row(a, b, c) )::jsonb ), %1$I.not_null_count( row_to_json( row(a, b, c) )::jsonb ) FROM test_data$$, ncs())
    , $$SELECT *, 3-null_count AS not_null_count FROM test_data$$
    , 'Test null_count(jsonb)'
  );

  -- Doesn't work for array types
  /* EXCLUDED CODE — doesn't work for array types
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
          , 'Test ' || trig_desc
          , trig_desc
        )
      FROM (
        SELECT *
          , format( '%I.%snull_count_trigger( %s )', ncs(), not_, args ) AS trig
          , format( '%snull_count_trigger( %s )', not_, args ) AS trig_desc
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
 * No explicit target schema to restore in phase 1 (count_nulls installs
 * with no schema targeting at all - see test/install/load.sql), so this
 * just re-states the same search_path already set at the top of this file.
 * A later schema-targeting phase may need this to do more.
 */
SET SEARCH_PATH = _null_count_test, tap;

-- vi: expandtab sw=2 ts=2
