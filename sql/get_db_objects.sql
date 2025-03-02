-- Function to get all tables and views in the database
CREATE OR REPLACE FUNCTION get_tables()
RETURNS TABLE (
    table_name text,
    table_type text
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.table_name::text,
        t.table_type::text
    FROM
        information_schema.tables t
    WHERE
        t.table_schema = 'public'
        AND (
            t.table_type = 'BASE TABLE'
            OR t.table_type = 'VIEW'
        )
        AND t.table_name NOT LIKE 'pg_%'
        AND t.table_name NOT LIKE 'get_%'
    ORDER BY
        t.table_type,  -- List tables before views
        t.table_name;
END;
$$ LANGUAGE plpgsql;

-- Function to get all functions in the database
CREATE OR REPLACE FUNCTION get_db_functions()
RETURNS TABLE (
    routine_name text,
    routine_definition text,
    data_type text,
    routine_body text,
    external_language text
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        r.routine_name::text,
        pg_get_functiondef(p.oid)::text AS routine_definition,
        r.data_type::text,
        r.routine_body::text,
        r.external_language::text
    FROM
        information_schema.routines r
    JOIN
        pg_proc p ON p.proname = r.routine_name
    JOIN
        pg_namespace n ON n.oid = p.pronamespace AND n.nspname = r.routine_schema
    WHERE
        r.routine_schema = 'public'
        AND r.routine_type = 'FUNCTION'  -- Only include functions, not procedures
        AND r.routine_name NOT IN (      -- Exclude system functions but keep user functions
            'get_tables',
            'get_table_info',
            'get_table_indexes',
            'get_enum_types'
        )
    ORDER BY
        r.routine_name;
END;
$$ LANGUAGE plpgsql;

-- Function to get all triggers in the database
CREATE OR REPLACE FUNCTION get_db_triggers()
RETURNS TABLE (
    trigger_name text,
    event_object_table text,
    action_timing text,
    event_manipulation text,
    trigger_definition text
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.trigger_name::text,
        t.event_object_table::text,
        t.action_timing::text,
        t.event_manipulation::text,
        pg_get_triggerdef(p.oid)::text AS trigger_definition
    FROM
        information_schema.triggers t
    JOIN
        pg_trigger p ON p.tgname = t.trigger_name
    JOIN
        pg_class c ON c.oid = p.tgrelid AND c.relname = t.event_object_table
    JOIN
        pg_namespace n ON n.oid = c.relnamespace AND n.nspname = t.trigger_schema
    WHERE
        t.trigger_schema = 'public'
    ORDER BY
        t.trigger_name;
END;
$$ LANGUAGE plpgsql;

-- Function to get view definitions
CREATE OR REPLACE FUNCTION get_view_definitions()
RETURNS TABLE (
    view_name text,
    view_definition text
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.table_name::text,
        pg_get_viewdef(c.oid, true)::text
    FROM 
        information_schema.views v
    JOIN 
        pg_class c ON c.relname = v.table_name
    JOIN 
        pg_namespace n ON n.oid = c.relnamespace AND n.nspname = v.table_schema
    WHERE 
        v.table_schema = 'public'
    ORDER BY 
        v.table_name;
END;
$$ LANGUAGE plpgsql;