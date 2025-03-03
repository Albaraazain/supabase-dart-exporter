-- Drop existing functions
DROP FUNCTION IF EXISTS exec_sql(text);
DROP FUNCTION IF EXISTS get_table_constraints(text);
DROP FUNCTION IF EXISTS get_column_definitions(text);
DROP FUNCTION IF EXISTS get_types();
DROP FUNCTION IF EXISTS get_functions();
DROP FUNCTION IF EXISTS get_triggers();

-- Function to execute SQL queries safely
CREATE OR REPLACE FUNCTION exec_sql(sql_query text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  IF sql_query IS NULL OR sql_query = '' THEN
    RETURN '[]'::json;
  END IF;
  
  EXECUTE format('SELECT json_agg(t) FROM (%s) AS t', sql_query) INTO result;
  RETURN COALESCE(result, '[]'::json);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Error in exec_sql: %', SQLERRM;
  RETURN json_build_object('error', SQLERRM);
END;
$$;

-- Function to get table constraints
CREATE OR REPLACE FUNCTION get_table_constraints(p_table_name text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  IF p_table_name IS NULL OR p_table_name = '' THEN
    RETURN '[]'::json;
  END IF;

  SELECT json_agg(t) INTO result
  FROM (
    SELECT 
      tc.constraint_name,
      tc.constraint_type,
      tc.table_name,
      kcu.column_name,
      ccu.table_name AS foreign_table_name,
      ccu.column_name AS foreign_column_name,
      cc.check_clause,
      pgc.confupdtype,
      pgc.confdeltype
    FROM information_schema.table_constraints tc
    LEFT JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    LEFT JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name = tc.constraint_name
      AND ccu.table_schema = tc.table_schema
    LEFT JOIN information_schema.check_constraints cc
      ON cc.constraint_name = tc.constraint_name
      AND cc.constraint_schema = tc.table_schema
    LEFT JOIN pg_constraint pgc
      ON pgc.conname = tc.constraint_name
    WHERE tc.table_schema = 'public'
      AND tc.table_name = p_table_name
    ORDER BY tc.constraint_name
  ) t;
  RETURN COALESCE(result, '[]'::json);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Error in get_table_constraints: %', SQLERRM;
  RETURN '[]'::json;
END;
$$;

-- Function to get column definitions
CREATE OR REPLACE FUNCTION get_column_definitions(p_table_name text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  IF p_table_name IS NULL OR p_table_name = '' THEN
    RETURN '[]'::json;
  END IF;

  SELECT json_agg(t) INTO result
  FROM (
    SELECT 
      c.column_name,
      c.column_default,
      c.data_type,
      c.character_maximum_length,
      c.is_nullable,
      c.numeric_precision,
      c.numeric_scale
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.table_name = p_table_name
    ORDER BY c.ordinal_position
  ) AS t;
  RETURN COALESCE(result, '[]'::json);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Error in get_column_definitions: %', SQLERRM;
  RETURN '[]'::json;
END;
$$;

-- Function to get custom types
CREATE OR REPLACE FUNCTION get_types()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  SELECT json_agg(t) INTO result
  FROM (
    SELECT 
      t.typname AS name,
      array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
    FROM pg_type t
    JOIN pg_enum e ON t.oid = e.enumtypid
    WHERE t.typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    GROUP BY t.typname
  ) AS t;
  RETURN COALESCE(result, '[]'::json);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Error in get_types: %', SQLERRM;
  RETURN '[]'::json;
END;
$$;

-- Function to get functions
CREATE OR REPLACE FUNCTION get_functions()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  SELECT json_agg(t) INTO result
  FROM (
    SELECT 
      p.proname AS name,
      pg_get_functiondef(p.oid) AS definition
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
  ) AS t;
  RETURN COALESCE(result, '[]'::json);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Error in get_functions: %', SQLERRM;
  RETURN '[]'::json;
END;
$$;

-- Function to get triggers
CREATE OR REPLACE FUNCTION get_triggers()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  SELECT json_agg(t) INTO result
  FROM (
    SELECT 
      t.tgname AS name,
      c.relname AS table,
      pg_get_triggerdef(t.oid) AS definition
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public'
    AND t.tgisinternal = false
  ) AS t;
  RETURN COALESCE(result, '[]'::json);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Error in get_triggers: %', SQLERRM;
  RETURN '[]'::json;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION exec_sql(text) TO postgres;
GRANT EXECUTE ON FUNCTION get_table_constraints(text) TO postgres;
GRANT EXECUTE ON FUNCTION get_column_definitions(text) TO postgres;
GRANT EXECUTE ON FUNCTION get_types() TO postgres;
GRANT EXECUTE ON FUNCTION get_functions() TO postgres;
GRANT EXECUTE ON FUNCTION get_triggers() TO postgres;