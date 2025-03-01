-- DB Export Tool - Function Installation Script
-- This script installs all the required functions for the database export tool

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

-- Function to get detailed table information
CREATE OR REPLACE FUNCTION get_table_info(table_name_param text)
RETURNS json AS $$
DECLARE
    columns_json json;
    constraints_json json;
    indexes_json json;
    result json;
BEGIN
    -- Get columns
    SELECT json_agg(col ORDER BY col.ordinal_position)
    INTO columns_json
    FROM (
        SELECT 
            c.column_name,
            c.data_type,
            c.character_maximum_length,
            c.column_default,
            c.is_nullable,
            c.ordinal_position
        FROM information_schema.columns c
        WHERE c.table_schema = 'public'
        AND c.table_name = table_name_param
    ) col;

    -- Get all constraints in a unified format
    WITH constraint_info AS (
        -- Primary Key constraints
        SELECT
            tc.constraint_name,
            tc.constraint_type,
            array_agg(kcu.column_name ORDER BY kcu.ordinal_position) as columns,
            NULL::text as check_clause,
            json_build_object(
                'referenced_table', NULL,
                'referenced_column', NULL,
                'update_rule', NULL,
                'delete_rule', NULL
            ) as foreign_key_info
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_schema = 'public'
        AND tc.table_name = table_name_param
        AND tc.constraint_type = 'PRIMARY KEY'
        GROUP BY tc.constraint_name, tc.constraint_type

        UNION ALL

        -- Foreign Key constraints
        SELECT
            tc.constraint_name,
            tc.constraint_type,
            array_agg(kcu.column_name ORDER BY kcu.ordinal_position) as columns,
            NULL::text as check_clause,
            (
                SELECT row_to_json(fk_info)
                FROM (
                    SELECT pg_get_constraintdef(c.oid) as definition
                    FROM pg_constraint c
                    JOIN pg_namespace n ON n.oid = c.connamespace
                    WHERE c.conname = tc.constraint_name
                    AND n.nspname = 'public'
                    LIMIT 1
                ) as fk_info
            ) as foreign_key_info
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
        WHERE tc.table_schema = 'public'
        AND tc.table_name = table_name_param
        AND tc.constraint_type = 'FOREIGN KEY'
        GROUP BY tc.constraint_name, tc.constraint_type

        UNION ALL

        -- Check constraints
        SELECT
            tc.constraint_name,
            tc.constraint_type,
            NULL::text[] as columns,
            cc.check_clause,
            json_build_object(
                'referenced_table', NULL,
                'referenced_column', NULL,
                'update_rule', NULL,
                'delete_rule', NULL
            ) as foreign_key_info
        FROM information_schema.table_constraints tc
        JOIN information_schema.check_constraints cc
            ON tc.constraint_name = cc.constraint_name
        WHERE tc.table_schema = 'public'
        AND tc.table_name = table_name_param
        AND tc.constraint_type = 'CHECK'
    )
    SELECT json_agg(
        json_build_object(
            'name', constraint_name,
            'type', constraint_type,
            'columns', columns,
            'check_clause', check_clause,
            'foreign_key_info', foreign_key_info
        )
        ORDER BY
            CASE constraint_type
                WHEN 'CHECK' THEN 1
                WHEN 'PRIMARY KEY' THEN 2
                WHEN 'FOREIGN KEY' THEN 3
                ELSE 4
            END
    )
    INTO constraints_json
    FROM constraint_info;

    -- Get indexes (excluding those for primary keys)
    SELECT json_agg(idx)
    INTO indexes_json
    FROM (
        SELECT 
            index_name,
            index_definition,
            is_primary,
            is_unique
        FROM get_table_indexes()
        WHERE table_name = table_name_param
        AND NOT is_primary
    ) idx;

    -- Combine all information
    SELECT json_build_object(
        'columns', COALESCE(columns_json, '[]'::json),
        'constraints', COALESCE(constraints_json, '[]'::json),
        'indexes', COALESCE(indexes_json, '[]'::json)
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to get all tables in the database
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
        AND t.table_type = 'BASE TABLE'
        AND t.table_name NOT LIKE 'pg_%'
        AND t.table_name NOT LIKE 'get_%'
    ORDER BY
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
        AND r.routine_name NOT LIKE 'get_%'
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

-- Notify completion
DO $$
BEGIN
    RAISE NOTICE 'Database export functions installed successfully.';
END $$; 