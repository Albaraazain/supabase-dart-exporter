-- Function to get detailed table information
CREATE OR REPLACE FUNCTION get_table_info(table_name_param text)
RETURNS json AS $$
DECLARE
    result json;
BEGIN
    -- Get columns
    WITH columns AS (
        SELECT
            c.column_name,
            c.data_type,
            c.character_maximum_length,
            c.is_nullable,
            c.column_default
        FROM
            information_schema.columns c
        WHERE
            c.table_schema = 'public'
            AND c.table_name = table_name_param
        ORDER BY
            c.ordinal_position
    ),
    -- Get constraints
    constraints AS (
        SELECT
            tc.constraint_name AS name,
            tc.constraint_type AS type,
            array_agg(kcu.column_name ORDER BY kcu.ordinal_position) AS columns,
            CASE
                WHEN tc.constraint_type = 'FOREIGN KEY' THEN
                    json_build_object(
                        'referenced_table', ccu.table_name,
                        'referenced_columns', array_agg(ccu.column_name ORDER BY kcu.position_in_unique_constraint),
                        'definition', format(
                            'FOREIGN KEY (%s) REFERENCES %I(%s)',
                            string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position),
                            ccu.table_name,
                            string_agg(ccu.column_name, ', ' ORDER BY kcu.position_in_unique_constraint)
                        )
                    )
                ELSE NULL
            END AS foreign_key_info,
            CASE
                WHEN tc.constraint_type = 'CHECK' THEN
                    (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = tc.constraint_name)
                ELSE NULL
            END AS check_clause
        FROM
            information_schema.table_constraints tc
        JOIN
            information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
        LEFT JOIN
            information_schema.constraint_column_usage ccu
            ON ccu.constraint_name = tc.constraint_name
            AND ccu.table_schema = tc.table_schema
        WHERE
            tc.table_schema = 'public'
            AND tc.table_name = table_name_param
        GROUP BY
            tc.constraint_name, tc.constraint_type, ccu.table_name
    )
    SELECT
        json_build_object(
            'columns', (SELECT json_agg(columns) FROM columns),
            'constraints', (SELECT json_agg(constraints) FROM constraints)
        ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql; 