DO $$ 
DECLARE
    func record;
BEGIN
    -- Drop RPC functions first
    FOR func IN 
        SELECT n.nspname as schema_name, p.proname as func_name,
               pg_get_function_arguments(p.oid) as func_args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
        AND p.proname IN ('get_tables', 'get_db_functions', 'get_db_triggers', 'get_view_definitions')
    LOOP
        -- Construct and execute DROP statement with full signature
        EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s) CASCADE',
                      func.schema_name,
                      func.func_name,
                      func.func_args);
        RAISE NOTICE 'Dropped function: %.%(%s)',
                    func.schema_name,
                    func.func_name,
                    func.func_args;
    END LOOP;

    -- Clear any lingering functions
    EXECUTE 'DROP FUNCTION IF EXISTS get_tables() CASCADE';
    EXECUTE 'DROP FUNCTION IF EXISTS get_db_functions() CASCADE';
    EXECUTE 'DROP FUNCTION IF EXISTS get_db_triggers() CASCADE';
    EXECUTE 'DROP FUNCTION IF EXISTS get_view_definitions() CASCADE';
END $$;