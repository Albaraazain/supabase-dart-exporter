-- Get table constraints
CREATE OR REPLACE FUNCTION get_table_constraints(p_table_name text)
RETURNS json AS $$
BEGIN
  RETURN (
    SELECT json_agg(json_build_object(
      'constraint_name', tc.constraint_name,
      'constraint_type', tc.constraint_type,
      'table_name', tc.table_name,
      'column_name', kcu.column_name,
      'foreign_table_name', ccu.table_name,
      'foreign_column_name', ccu.column_name,
      'check_clause', cc.check_clause
    ))
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
    WHERE tc.table_schema = 'public'
      AND tc.table_name = p_table_name
  );
END;
$$ LANGUAGE plpgsql;

-- Get column definitions
CREATE OR REPLACE FUNCTION get_column_definitions(p_table_name text)
RETURNS json AS $$
BEGIN
  RETURN (
    WITH ordered_columns AS (
      SELECT 
        column_name,
        data_type,
        character_maximum_length,
        is_nullable,
        column_default,
        numeric_precision,
        numeric_scale,
        ordinal_position
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = p_table_name
    )
    SELECT json_agg(
      json_build_object(
        'column_name', column_name,
        'data_type', data_type,
        'character_maximum_length', character_maximum_length,
        'is_nullable', is_nullable,
        'column_default', column_default,
        'numeric_precision', numeric_precision,
        'numeric_scale', numeric_scale
      ) ORDER BY ordinal_position
    )
    FROM ordered_columns
  );
END;
$$ LANGUAGE plpgsql;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_table_constraints(text) TO postgres;
GRANT EXECUTE ON FUNCTION get_column_definitions(text) TO postgres;