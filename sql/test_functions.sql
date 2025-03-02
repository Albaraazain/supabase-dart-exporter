-- Test get_tables function
SELECT 'Testing get_tables()' as test;
SELECT * FROM get_tables_base() LIMIT 5;
SELECT * FROM public.get_tables();

-- Test get_view_definitions function
SELECT 'Testing get_view_definitions()' as test;
SELECT * FROM get_view_definitions_base();
SELECT * FROM public.get_view_definitions();

-- Test get_db_functions function
SELECT 'Testing get_db_functions()' as test;
SELECT routine_name, data_type, external_language 
FROM get_db_functions_base() 
WHERE routine_name NOT LIKE 'get_%_base'
LIMIT 5;
SELECT * FROM public.get_db_functions();

-- Test get_db_triggers function
SELECT 'Testing get_db_triggers()' as test;
SELECT trigger_name, event_object_table, action_timing 
FROM get_db_triggers_base() 
LIMIT 5;
SELECT * FROM public.get_db_triggers();