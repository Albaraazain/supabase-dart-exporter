-- Function to get enum types and their definitions
CREATE OR REPLACE FUNCTION get_enum_types()
RETURNS TABLE (
    type_name text,
    definition text
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.typname::text,
        format(
            'CREATE TYPE %I AS ENUM (%s);',
            t.typname,
            string_agg(quote_literal(e.enumlabel), ', ' ORDER BY e.enumsortorder)
        )::text AS definition
    FROM pg_type t
    JOIN pg_enum e ON t.oid = e.enumtypid
    JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
    GROUP BY t.typname;
END;
$$ LANGUAGE plpgsql;