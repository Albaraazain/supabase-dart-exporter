-- Function to get table indexes and their definitions
CREATE OR REPLACE FUNCTION get_table_indexes()
RETURNS TABLE (
    table_name text,
    index_name text,
    index_definition text,
    is_primary boolean,
    is_unique boolean
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.relname::text AS table_name,
        i.relname::text AS index_name,
        pg_get_indexdef(i.oid)::text AS index_definition,
        ix.indisprimary AS is_primary,
        ix.indisunique AS is_unique
    FROM pg_index ix
    JOIN pg_class i ON i.oid = ix.indexrelid
    JOIN pg_class t ON t.oid = ix.indrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
    ORDER BY t.relname, i.relname;
END;
$$ LANGUAGE plpgsql; 