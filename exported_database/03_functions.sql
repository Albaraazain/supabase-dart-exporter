-- Functions

CREATE OR REPLACE FUNCTION public.get_nearby_broadcasts_for_professional(p_professional_id text, p_max_distance integer DEFAULT NULL::integer)
 RETURNS TABLE(broadcast_id text, title text, description text, service_name text, service_category text, location_address text, distance_km numeric, budget_min numeric, budget_max numeric, created_at timestamp with time zone, expiry_time timestamp with time zone, homeowner_name text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  pro_lat NUMERIC;
  pro_lng NUMERIC;
  pro_radius INTEGER;
  service_ids TEXT[];
BEGIN
  -- Get professional location and service radius
  SELECT
    pp.current_location_lat,
    pp.current_location_lng,
    pp.service_radius
  INTO
    pro_lat,
    pro_lng,
    pro_radius
  FROM professional_profiles pp
  WHERE pp.professional_id = p_professional_id;
  
  -- Get services offered by the professional
  SELECT array_agg(service_id)
  INTO service_ids
  FROM professional_services
  WHERE professional_id = p_professional_id
  AND is_available = TRUE;
  
  -- Use the professional's service radius if no max_distance is provided
  IF p_max_distance IS NULL THEN
    p_max_distance := pro_radius;
  END IF;
  
  RETURN QUERY
  SELECT
    jb.broadcast_id,
    jb.title,
    jb.description,
    s.name AS service_name,
    sc.name AS service_category,
    jb.location_address,
    -- Calculate distance using the Haversine formula (approximate) and cast to NUMERIC
    (6371 * acos(cos(radians(pro_lat)) * cos(radians(jb.location_lat)) * 
    cos(radians(jb.location_lng) - radians(pro_lng)) + 
    sin(radians(pro_lat)) * sin(radians(jb.location_lat))))::NUMERIC AS distance_km,
    jb.budget_range_min,
    jb.budget_range_max,
    jb.created_at,
    jb.expiry_time,
    u.full_name AS homeowner_name
  FROM
    job_broadcasts jb
  JOIN
    services s ON jb.service_id = s.service_id
  JOIN
    service_categories sc ON s.category_id = sc.category_id
  JOIN
    users u ON jb.homeowner_id = u.user_id
  WHERE
    jb.status = 'active'
    AND jb.service_id = ANY(service_ids)
    AND jb.expiry_time > NOW()
    AND (
      -- Skip distance calculation if location is not available
      pro_lat IS NULL
      OR pro_lng IS NULL
      OR jb.location_lat IS NULL
      OR jb.location_lng IS NULL
      OR (
        -- Calculate distance using the Haversine formula (approximate)
        (6371 * acos(cos(radians(pro_lat)) * cos(radians(jb.location_lat)) * 
        cos(radians(jb.location_lng) - radians(pro_lng)) + 
        sin(radians(pro_lat)) * sin(radians(jb.location_lat))))::NUMERIC <= p_max_distance
      )
    )
    -- Exclude broadcasts that the professional has already responded to
    AND NOT EXISTS (
      SELECT 1 FROM professional_responses pr
      WHERE pr.broadcast_id = jb.broadcast_id
      AND pr.professional_id = p_professional_id
    )
  ORDER BY
    -- Sort by distance if location is available, otherwise by creation date
    CASE WHEN pro_lat IS NOT NULL AND pro_lng IS NOT NULL
      AND jb.location_lat IS NOT NULL AND jb.location_lng IS NOT NULL
      THEN (6371 * acos(cos(radians(pro_lat)) * cos(radians(jb.location_lat)) * 
           cos(radians(jb.location_lng) - radians(pro_lng)) + 
           sin(radians(pro_lat)) * sin(radians(jb.location_lat))))::NUMERIC
      ELSE NULL
    END ASC NULLS LAST,
    jb.created_at DESC;
END;
$function$


CREATE OR REPLACE FUNCTION public.auto_match_professionals(p_broadcast_id text, p_max_matches integer DEFAULT 5)
 RETURNS TABLE(professional_id text, professional_name text, business_name text, distance_km numeric, rating numeric, total_jobs_completed integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_service_id TEXT;
  v_location_lat NUMERIC;
  v_location_lng NUMERIC;
  v_broadcast_radius INTEGER;
BEGIN
  -- Get broadcast information
  SELECT
    jb.service_id,
    jb.location_lat,
    jb.location_lng,
    jb.broadcast_radius
  INTO
    v_service_id,
    v_location_lat,
    v_location_lng,
    v_broadcast_radius
  FROM job_broadcasts jb
  WHERE jb.broadcast_id = p_broadcast_id;
  
  -- Return matching professionals
  RETURN QUERY
  SELECT
    pp.professional_id,
    u.full_name AS professional_name,
    pp.business_name,
    -- Calculate distance using the Haversine formula (approximate) and cast to NUMERIC
    CASE WHEN pp.current_location_lat IS NOT NULL AND pp.current_location_lng IS NOT NULL
      AND v_location_lat IS NOT NULL AND v_location_lng IS NOT NULL 
      THEN (6371 * acos(cos(radians(v_location_lat)) * cos(radians(pp.current_location_lat)) * 
           cos(radians(pp.current_location_lng) - radians(v_location_lng)) + 
           sin(radians(v_location_lat)) * sin(radians(pp.current_location_lat))))::NUMERIC
      ELSE NULL
    END AS distance_km,
    pp.rating,
    pp.total_jobs_completed
  FROM
    professional_profiles pp
  JOIN
    users u ON pp.user_id = u.user_id
  JOIN
    professional_services ps ON pp.professional_id = ps.professional_id
  WHERE
    ps.service_id = v_service_id
    AND ps.is_available = TRUE
    AND pp.availability_status = 'Available'
    AND u.status = 'active'
    -- Professional is within broadcast radius or has no location set
    AND (
      pp.current_location_lat IS NULL
      OR pp.current_location_lng IS NULL
      OR v_location_lat IS NULL
      OR v_location_lng IS NULL
      OR (
        -- Calculate distance using the Haversine formula
        (6371 * acos(cos(radians(v_location_lat)) * cos(radians(pp.current_location_lat)) * 
        cos(radians(pp.current_location_lng) - radians(v_location_lng)) + 
        sin(radians(v_location_lat)) * sin(radians(pp.current_location_lat))))::NUMERIC <= v_broadcast_radius
      )
    )
    -- Exclude professionals who have already responded
    AND NOT EXISTS (
      SELECT 1 FROM professional_responses pr
      WHERE pr.broadcast_id = p_broadcast_id
      AND pr.professional_id = pp.professional_id
    )
  ORDER BY
    -- Sort by a combination of distance, rating, and experience
    CASE WHEN pp.current_location_lat IS NOT NULL AND pp.current_location_lng IS NOT NULL
      AND v_location_lat IS NOT NULL AND v_location_lng IS NOT NULL
      THEN (6371 * acos(cos(radians(v_location_lat)) * cos(radians(pp.current_location_lat)) * 
           cos(radians(pp.current_location_lng) - radians(v_location_lng)) + 
           sin(radians(v_location_lat)) * sin(radians(pp.current_location_lat))))::NUMERIC
      ELSE 999999
    END ASC,
    pp.rating DESC,
    pp.total_jobs_completed DESC
  LIMIT p_max_matches;
END;
$function$


CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$function$


CREATE OR REPLACE FUNCTION public.update_professional_stats()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Only run when job is marked as completed
  IF NEW.current_stage = 'Completed' AND OLD.current_stage != 'Completed' THEN
    -- Update jobs completed count
    UPDATE professional_profiles
    SET total_jobs_completed = total_jobs_completed + 1
    WHERE professional_id = NEW.professional_id;
    
    -- Could also update other stats here (rating, etc.)
  END IF;
  RETURN NEW;
END;
$function$


CREATE OR REPLACE FUNCTION public.record_professional_earnings()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_quote_amount NUMERIC;
  v_service_category TEXT;
BEGIN
  -- Get the quote amount and service category
  SELECT sq.total_amount, s.category_id INTO v_quote_amount, v_service_category
  FROM service_quotes sq
  JOIN jobs j ON sq.job_id = j.job_id
  JOIN services s ON j.service_id = s.service_id
  WHERE j.job_id = NEW.job_id;
  
  -- Record the earnings
  INSERT INTO professional_earnings (
    professional_id, job_id, amount, service_category_id
  ) VALUES (
    NEW.professional_id, NEW.job_id, v_quote_amount, v_service_category
  );
  
  RETURN NEW;
END;
$function$


CREATE OR REPLACE FUNCTION public.validate_professional(professional_id_param text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
  is_valid BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 
    FROM professional_profiles pp
    JOIN users u ON pp.user_id = u.user_id
    WHERE pp.professional_id = professional_id_param
    AND u.status = 'active'
  ) INTO is_valid;
  
  RETURN is_valid;
END;
$function$


CREATE OR REPLACE FUNCTION public.validate_job_stage_transition(current_stage job_stage, new_stage job_stage)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Define valid transitions
  RETURN CASE
    WHEN current_stage = 'En Route' AND new_stage IN ('At Location', 'Cancelled') THEN true
    WHEN current_stage = 'At Location' AND new_stage IN ('Diagnosing', 'Cancelled') THEN true
    WHEN current_stage = 'Diagnosing' AND new_stage IN ('Quote Pending', 'Cancelled') THEN true
    WHEN current_stage = 'Quote Pending' AND new_stage IN ('Quote Accepted', 'Cancelled') THEN true
    WHEN current_stage = 'Quote Accepted' AND new_stage IN ('In Progress', 'Cancelled') THEN true
    WHEN current_stage = 'In Progress' AND new_stage IN ('Completed', 'Cancelled') THEN true
    ELSE false
  END;
END;
$function$


CREATE OR REPLACE FUNCTION public.calculate_service_fee(materials_cost numeric, labor_cost numeric)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
  total_cost DECIMAL;
  fee_rate DECIMAL;
BEGIN
  total_cost := materials_cost + labor_cost;
  
  -- Define fee rate based on total cost
  IF total_cost < 100 THEN
    fee_rate := 0.10; -- 10% for small jobs
  ELSIF total_cost < 500 THEN
    fee_rate := 0.08; -- 8% for medium jobs
  ELSIF total_cost < 1000 THEN
    fee_rate := 0.06; -- 6% for larger jobs
  ELSE
    fee_rate := 0.05; -- 5% for very large jobs
  END IF;
  
  -- Return the calculated fee (rounded to 2 decimal places)
  RETURN ROUND(total_cost * fee_rate, 2);
END;
$function$


CREATE OR REPLACE FUNCTION public.record_job_stage_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Only insert a record if the stage has actually changed
  IF OLD.current_stage IS DISTINCT FROM NEW.current_stage THEN
    INSERT INTO job_stage_history (
      history_id,
      job_id,
      stage,
      notes,
      created_by,
      timestamp
    ) VALUES (
      gen_random_uuid()::text, -- Use UUID for guaranteed uniqueness
      NEW.job_id,
      NEW.current_stage,
      'Automatic stage transition',
      NEW.last_updated_by,
      NOW()
    );
  END IF;
  RETURN NEW;
END;
$function$


CREATE OR REPLACE FUNCTION public.update_location_timestamp_function()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Update the timestamp whenever location is updated
  IF OLD.current_location_lat IS DISTINCT FROM NEW.current_location_lat OR
     OLD.current_location_lng IS DISTINCT FROM NEW.current_location_lng THEN
    NEW.updated_at := NOW();
  END IF;
  
  RETURN NEW;
END;
$function$


CREATE OR REPLACE FUNCTION public.validate_broadcast_response_function()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_broadcast_status TEXT;
  v_service_id TEXT;
  v_pro_service_exists BOOLEAN;
BEGIN
  -- Get broadcast status and service ID
  SELECT jb.status, jb.service_id
  INTO v_broadcast_status, v_service_id
  FROM job_broadcasts jb
  WHERE jb.broadcast_id = NEW.broadcast_id;
  
  -- Check if the broadcast is still active
  IF v_broadcast_status != 'active' THEN
    RAISE EXCEPTION 'Cannot respond to a non-active broadcast';
  END IF;
  
  -- Check if the professional offers this service
  SELECT EXISTS (
    SELECT 1 FROM professional_services ps
    WHERE ps.professional_id = NEW.professional_id
      AND ps.service_id = v_service_id
      AND ps.is_available = TRUE
  ) INTO v_pro_service_exists;
  
  IF NOT v_pro_service_exists THEN
    RAISE EXCEPTION 'Professional does not offer this service or service is not available';
  END IF;
  
  RETURN NEW;
END;
$function$


CREATE OR REPLACE FUNCTION public.update_broadcast_status()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Mark expired broadcasts as inactive
  UPDATE job_broadcasts
  SET status = 'expired'
  WHERE status = 'active'
    AND expiry_time < NOW();
  
  -- Mark broadcasts with accepted responses as completed
  UPDATE job_broadcasts
  SET status = 'completed'
  WHERE status = 'active'
    AND EXISTS (
      SELECT 1 FROM professional_responses pr
      WHERE pr.broadcast_id = job_broadcasts.broadcast_id
      AND pr.status = 'accepted'
    );
END;
$function$


CREATE OR REPLACE FUNCTION public.expire_broadcasts_function()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Mark expired broadcasts as inactive
  NEW.status := CASE
    WHEN NEW.expiry_time < NOW() THEN 'expired'
    ELSE NEW.status
  END;
  
  RETURN NEW;
END;
$function$


CREATE OR REPLACE FUNCTION public.exec_sql(sql_query text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.get_table_constraints(table_name text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  result json;
BEGIN
  IF table_name IS NULL OR table_name = '' THEN
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
      AND tc.table_name = table_name
    ORDER BY tc.constraint_name
  ) t;
  RETURN COALESCE(result, '[]'::json);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Error in get_table_constraints: %', SQLERRM;
  RETURN '[]'::json;
END;
$function$


CREATE OR REPLACE FUNCTION public.get_column_definitions(table_name text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  result json;
BEGIN
  IF table_name IS NULL OR table_name = '' THEN
    RETURN '[]'::json;
  END IF;

  SELECT json_agg(t) INTO result
  FROM (
    SELECT 
      column_name,
      column_default,
      data_type,
      character_maximum_length,
      is_nullable,
      numeric_precision,
      numeric_scale
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = table_name
    ORDER BY ordinal_position
  ) AS t;
  RETURN COALESCE(result, '[]'::json);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Error in get_column_definitions: %', SQLERRM;
  RETURN '[]'::json;
END;
$function$


CREATE OR REPLACE FUNCTION public.get_types()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.get_functions()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.get_triggers()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Insert a new record into public.users
  INSERT INTO public.users (
    user_id, 
    email, 
    full_name, 
    phone, 
    user_type, 
    status
  ) VALUES (
    NEW.id, 
    NEW.email, 
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'User ' || NEW.id), -- Default name if null
    NEW.raw_user_meta_data->>'phone', 
    COALESCE(NEW.raw_user_meta_data->>'user_type', 'professional'), 
    'active'
  )
  -- Do nothing if the user already exists
  ON CONFLICT (user_id) DO NOTHING;
  
  RETURN NEW;
END;
$function$


CREATE OR REPLACE FUNCTION public.handle_new_professional()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- Only create a professional profile if the user_type is 'professional'
  IF NEW.user_type = 'professional' THEN
    -- Check if a profile already exists for this user_id
    IF NOT EXISTS (SELECT 1 FROM public.professional_profiles WHERE user_id = NEW.user_id) THEN
      -- Insert a new record into public.professional_profiles
      INSERT INTO public.professional_profiles (
        professional_id,
        user_id,
        service_radius,
        experience_years,
        availability_status
      ) VALUES (
        gen_random_uuid()::text,
        NEW.user_id,
        25, -- Default service radius
        0,  -- Default experience years
        'Available'
      );
    END IF;
  END IF;
  
  RETURN NEW;
END;
$function$


CREATE OR REPLACE FUNCTION public.calculate_weekly_revenue(p_professional_id text, p_start_date text)
 RETURNS double precision
 LANGUAGE plpgsql
AS $function$ DECLARE total_revenue FLOAT; BEGIN SELECT COALESCE(SUM(sq.total_amount), 0) INTO total_revenue FROM jobs j JOIN service_quotes sq ON j.job_id = sq.job_id WHERE j.professional_id = p_professional_id AND j.current_stage = 'Completed' AND j.updated_at >= p_start_date::DATE; RETURN total_revenue; END; $function$


CREATE OR REPLACE FUNCTION public.get_enum_types()
 RETURNS TABLE(type_name text, definition text)
 LANGUAGE plpgsql
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.get_table_indexes()
 RETURNS TABLE(table_name text, index_name text, index_definition text, is_primary boolean, is_unique boolean)
 LANGUAGE plpgsql
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.calculate_completion_rate(p_professional_id text)
 RETURNS double precision
 LANGUAGE plpgsql
AS $function$ DECLARE total_jobs INT; completed_jobs INT; completion_rate FLOAT; BEGIN SELECT COUNT(*) INTO total_jobs FROM jobs WHERE professional_id = p_professional_id; SELECT COUNT(*) INTO completed_jobs FROM jobs WHERE professional_id = p_professional_id AND current_stage = 'Completed'; IF total_jobs > 0 THEN completion_rate := (completed_jobs::FLOAT / total_jobs::FLOAT) * 100; ELSE completion_rate := 0; END IF; RETURN completion_rate; END; $function$


CREATE OR REPLACE FUNCTION public.get_table_info(table_name_param text)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.get_professional_schedule(p_professional_id text)
 RETURNS TABLE(job_id text, homeowner_name text, service_name text, scheduled_time timestamp with time zone, current_stage text, location_address text)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT j.job_id, u.full_name, s.name, j.scheduled_time, j.current_stage, jb.location_address
  FROM jobs j
  JOIN users u ON j.homeowner_id = u.user_id
  JOIN services s ON j.service_id = s.service_id
  LEFT JOIN job_broadcasts jb ON j.broadcast_id = jb.broadcast_id
  WHERE j.professional_id = p_professional_id
  AND j.current_stage NOT IN ('Completed', 'Cancelled')
  ORDER BY j.scheduled_time ASC;
END;
$function$


CREATE OR REPLACE FUNCTION public.get_homeowner_service_history(p_homeowner_id text, p_category_id text DEFAULT NULL::text)
 RETURNS TABLE(job_id text, service_name text, service_category text, professional_name text, professional_business text, professional_rating numeric, completion_date timestamp with time zone, total_amount numeric)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT 
        j.job_id,
        s.name AS service_name,
        sc.name AS service_category,
        u.full_name AS professional_name,
        pp.business_name AS professional_business,
        pp.rating AS professional_rating,
        j.updated_at AS completion_date,
        sq.total_amount
    FROM jobs j
    JOIN services s ON j.service_id = s.service_id
    JOIN service_categories sc ON s.category_id = sc.category_id
    JOIN professional_profiles pp ON j.professional_id = pp.professional_id
    JOIN users u ON pp.user_id = u.user_id
    LEFT JOIN service_quotes sq ON j.job_id = sq.job_id
    WHERE j.homeowner_id = p_homeowner_id
    AND j.current_stage = 'Completed'
    AND (p_category_id IS NULL OR sc.category_id = p_category_id)
    ORDER BY j.updated_at DESC;
END;
$function$


CREATE OR REPLACE FUNCTION public.get_professional_jobs_paginated(p_professional_id text, p_page_num integer, p_page_size integer, p_status text DEFAULT NULL::text)
 RETURNS TABLE(job_id text, homeowner_name text, service_name text, scheduled_time timestamp with time zone, current_stage text, location_address text, quoted_amount numeric, total_count bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
    status_filter TEXT;
BEGIN
    -- Set status filter
    IF p_status = 'active' THEN
        status_filter := 'j.current_stage NOT IN (''Completed'', ''Cancelled'')';
    ELSIF p_status = 'completed' THEN
        status_filter := 'j.current_stage = ''Completed''';
    ELSE
        status_filter := 'TRUE';
    END IF;

    RETURN QUERY EXECUTE
    'WITH job_count AS (
        SELECT COUNT(*) AS total
        FROM jobs j
        WHERE j.professional_id = $1
        AND ' || status_filter || '
    )
    SELECT 
        j.job_id, 
        u.full_name, 
        s.name, 
        j.scheduled_time, 
        j.current_stage, 
        jb.location_address,
        COALESCE(sq.total_amount, 0) as quoted_amount,
        (SELECT total FROM job_count)
    FROM jobs j
    JOIN users u ON j.homeowner_id = u.user_id
    JOIN services s ON j.service_id = s.service_id
    LEFT JOIN job_broadcasts jb ON j.broadcast_id = jb.broadcast_id
    LEFT JOIN service_quotes sq ON j.job_id = sq.job_id
    WHERE j.professional_id = $1
    AND ' || status_filter || '
    ORDER BY 
        CASE WHEN j.current_stage IN (''In Progress'', ''Quote Accepted'') THEN 1
             WHEN j.current_stage IN (''Quote Pending'', ''Diagnosing'') THEN 2
             WHEN j.current_stage IN (''At Location'', ''En Route'') THEN 3
             WHEN j.current_stage = ''Completed'' THEN 4
             ELSE 5
        END,
        j.scheduled_time DESC NULLS LAST
    LIMIT $3
    OFFSET ($2 - 1) * $3'
    USING p_professional_id, p_page_num, p_page_size;
END;
$function$


CREATE OR REPLACE FUNCTION public.get_homeowner_jobs_paginated(p_homeowner_id text, p_page_num integer, p_page_size integer, p_status text DEFAULT NULL::text)
 RETURNS TABLE(job_id text, professional_name text, professional_business text, service_name text, service_category text, scheduled_time timestamp with time zone, current_stage text, quoted_amount numeric, total_count bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
    status_filter TEXT;
BEGIN
    -- Set status filter
    IF p_status = 'active' THEN
        status_filter := 'j.current_stage NOT IN (''Completed'', ''Cancelled'')';
    ELSIF p_status = 'completed' THEN
        status_filter := 'j.current_stage = ''Completed''';
    ELSE
        status_filter := 'TRUE';
    END IF;

    RETURN QUERY EXECUTE
    'WITH job_count AS (
        SELECT COUNT(*) AS total
        FROM jobs j
        WHERE j.homeowner_id = $1
        AND ' || status_filter || '
    )
    SELECT 
        j.job_id, 
        u.full_name,
        pp.business_name,
        s.name, 
        sc.name,
        j.scheduled_time, 
        j.current_stage,
        COALESCE(sq.total_amount, 0),
        (SELECT total FROM job_count)
    FROM jobs j
    JOIN professional_profiles pp ON j.professional_id = pp.professional_id
    JOIN users u ON pp.user_id = u.user_id
    JOIN services s ON j.service_id = s.service_id
    JOIN service_categories sc ON s.category_id = sc.category_id
    LEFT JOIN service_quotes sq ON j.job_id = sq.job_id
    WHERE j.homeowner_id = $1
    AND ' || status_filter || '
    ORDER BY 
        CASE WHEN j.current_stage = ''Quote Pending'' THEN 1
             WHEN j.current_stage IN (''In Progress'', ''Quote Accepted'', ''Diagnosing'') THEN 2
             WHEN j.current_stage IN (''At Location'', ''En Route'') THEN 3
             WHEN j.current_stage = ''Completed'' THEN 4
             ELSE 5
        END,
        j.scheduled_time DESC NULLS LAST
    LIMIT $3
    OFFSET ($2 - 1) * $3'
    USING p_homeowner_id, p_page_num, p_page_size;
END;
$function$


CREATE OR REPLACE FUNCTION public.get_job_details(p_job_id text, p_user_id text, p_user_type text)
 RETURNS TABLE(job_id text, current_stage text, scheduled_time timestamp with time zone, homeowner_name text, homeowner_phone text, professional_name text, professional_phone text, professional_business text, service_name text, service_description text, service_category text, quote_id text, quote_status text, quote_total numeric, location_address text, location_lat numeric, location_lng numeric, stage_history json, finding_count integer, is_authorized boolean)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_is_authorized BOOLEAN;
BEGIN
    -- Check authorization first
    v_is_authorized := (
        CASE
            WHEN p_user_type = 'professional' AND EXISTS (
                SELECT 1 FROM jobs j
                JOIN professional_profiles pp ON j.professional_id = pp.professional_id
                WHERE j.job_id = p_job_id AND pp.user_id = p_user_id
            ) THEN true
            WHEN p_user_type = 'homeowner' AND EXISTS (
                SELECT 1 FROM jobs j
                WHERE j.job_id = p_job_id AND j.homeowner_id = p_user_id
            ) THEN true
            ELSE false
        END
    );

    -- Only return data if authorized
    IF v_is_authorized THEN
        RETURN QUERY
        WITH stage_history_json AS (
            SELECT json_agg(
                json_build_object(
                    'stage', jsh.stage,
                    'timestamp', jsh.timestamp,
                    'notes', jsh.notes,
                    'created_by_name', u.full_name
                ) ORDER BY jsh.timestamp DESC
            ) AS history
            FROM job_stage_history jsh
            JOIN users u ON jsh.created_by = u.user_id
            WHERE jsh.job_id = p_job_id
        )
        SELECT
            j.job_id,
            j.current_stage,
            j.scheduled_time,
            u_h.full_name AS homeowner_name,
            u_h.phone AS homeowner_phone,
            u_p.full_name AS professional_name,
            u_p.phone AS professional_phone,
            pp.business_name AS professional_business,
            s.name AS service_name,
            s.description AS service_description,
            sc.name AS service_category,
            sq.quote_id,
            sq.status AS quote_status,
            sq.total_amount AS quote_total,
            jb.location_address,
            jb.location_lat,
            jb.location_lng,
            COALESCE((SELECT history FROM stage_history_json), '[]'::json) AS stage_history,
            (SELECT COUNT(*)::INTEGER FROM diagnosis_findings df WHERE df.job_id = j.job_id) AS finding_count,
            v_is_authorized
        FROM jobs j
        JOIN users u_h ON j.homeowner_id = u_h.user_id
        JOIN professional_profiles pp ON j.professional_id = pp.professional_id
        JOIN users u_p ON pp.user_id = u_p.user_id
        JOIN services s ON j.service_id = s.service_id
        JOIN service_categories sc ON s.category_id = sc.category_id
        LEFT JOIN job_broadcasts jb ON j.broadcast_id = jb.broadcast_id
        LEFT JOIN service_quotes sq ON j.job_id = sq.job_id
        WHERE j.job_id = p_job_id;
    END IF;
END;
$function$


CREATE OR REPLACE FUNCTION public.create_active_job(professional_email text, service_id_param text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_professional_id TEXT;
    v_broadcast_id TEXT;
    v_job_id TEXT;
    v_homeowner_id TEXT;
    v_user_id TEXT;
    v_service_exists BOOLEAN;
BEGIN
    -- Get professional_id from email
    SELECT pp.professional_id INTO v_professional_id
    FROM professional_profiles pp
    JOIN users u ON pp.user_id = u.user_id
    WHERE u.email = professional_email AND u.status = 'active';

    IF v_professional_id IS NULL THEN
        RAISE EXCEPTION 'Professional not found or not active with email %', professional_email;
    END IF;

    -- Verify professional offers this service
    SELECT EXISTS (
        SELECT 1 FROM professional_services
        WHERE professional_id = v_professional_id
        AND service_id = service_id_param
        AND is_available = true
    ) INTO v_service_exists;

    IF NOT v_service_exists THEN
        RAISE EXCEPTION 'Professional does not offer this service or service is not available';
    END IF;

    -- Get random active homeowner's user_id
    SELECT u.user_id INTO v_user_id
    FROM users u
    JOIN homeowner_profiles hp ON u.user_id = hp.user_id
    WHERE u.status = 'active'
    AND u.user_type = 'homeowner'
    ORDER BY RANDOM()
    LIMIT 1;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No active homeowners found in the system';
    END IF;

    -- Create job broadcast
    v_broadcast_id := gen_random_uuid()::TEXT;
    INSERT INTO job_broadcasts (
        broadcast_id,
        homeowner_id,  -- This references users.user_id
        service_id,
        status,
        title,
        description
    ) VALUES (
        v_broadcast_id,
        v_user_id,     -- Using user_id
        service_id_param,
        'active',
        'Auto-matched Service Request',
        'Automatically created service request for professional matching'
    );

    -- Create job
    v_job_id := gen_random_uuid()::TEXT;
    INSERT INTO jobs (
        job_id,
        broadcast_id,
        homeowner_id,  -- This references users.user_id
        professional_id,
        service_id,
        current_stage,
        stage_updated_at,
        scheduled_time,
        last_updated_by
    ) VALUES (
        v_job_id,
        v_broadcast_id,
        v_user_id,     -- Using user_id
        v_professional_id,
        service_id_param,
        'En Route',    -- Starting with En Route stage as the professional is immediately matched
        NOW(),
        NOW(),        -- Scheduled for immediate service
        v_user_id     -- System initiated
    );

    -- Create initial job stage history
    INSERT INTO job_stage_history (
        history_id,
        job_id,
        stage,
        created_by,
        timestamp
    ) VALUES (
        gen_random_uuid()::TEXT,
        v_job_id,
        'En Route',
        v_user_id,
        NOW()
    );

    RETURN v_job_id;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error and re-raise
        INSERT INTO error_logs (
            error_code,
            error_message,
            function_name,
            parameters,
            operation
        ) VALUES (
            SQLSTATE,
            SQLERRM,
            'create_active_job',
            jsonb_build_object(
                'professional_email', professional_email,
                'service_id', service_id_param,
                'professional_id', v_professional_id,
                'user_id', v_user_id
            ),
            'create_job'
        );
        RAISE;
END;
$function$


CREATE OR REPLACE FUNCTION public.get_professional_earnings(p_professional_id text, p_start_date timestamp with time zone, p_end_date timestamp with time zone)
 RETURNS TABLE(period text, job_count integer, total_earnings numeric, service_category text, avg_job_value numeric)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT 
        TO_CHAR(j.created_at, 'YYYY-MM') as period,
        COUNT(DISTINCT j.job_id)::INTEGER as job_count,
        SUM(sq.total_amount) as total_earnings,
        sc.name as service_category,
        CASE WHEN COUNT(DISTINCT j.job_id) > 0 
             THEN SUM(sq.total_amount)/COUNT(DISTINCT j.job_id)
             ELSE 0 END as avg_job_value
    FROM jobs j
    JOIN service_quotes sq ON j.job_id = sq.job_id
    JOIN services s ON j.service_id = s.service_id
    JOIN service_categories sc ON s.category_id = sc.category_id
    WHERE j.professional_id = p_professional_id
    AND j.current_stage = 'Completed'
    AND j.created_at BETWEEN p_start_date AND p_end_date
    GROUP BY period, sc.name
    ORDER BY period DESC, total_earnings DESC;
END;
$function$


CREATE OR REPLACE FUNCTION public.get_homeowner_quotes(p_homeowner_id text)
 RETURNS TABLE(job_id text, quote_id text, service_name text, professional_name text, professional_business text, professional_rating numeric, total_amount numeric, expiry_time timestamp with time zone, materials_cost numeric, labor_cost numeric, quote_status text, line_item_count integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT 
        j.job_id,
        sq.quote_id,
        s.name AS service_name,
        u.full_name AS professional_name,
        pp.business_name AS professional_business,
        pp.rating AS professional_rating,
        sq.total_amount,
        sq.expiry_time,
        sq.materials_cost,
        sq.labor_cost,
        sq.status AS quote_status,
        (SELECT COUNT(*)::INTEGER FROM quote_line_items qli WHERE qli.quote_id = sq.quote_id) as line_item_count
    FROM jobs j
    JOIN service_quotes sq ON j.job_id = sq.job_id
    JOIN services s ON j.service_id = s.service_id
    JOIN professional_profiles pp ON j.professional_id = pp.professional_id
    JOIN users u ON pp.user_id = u.user_id
    WHERE j.homeowner_id = p_homeowner_id
    AND j.current_stage IN ('Quote Pending', 'Quote Accepted')
    AND sq.status IN ('pending', 'accepted')
    ORDER BY sq.expiry_time ASC;
END;
$function$


CREATE OR REPLACE FUNCTION public.get_tables_base()
 RETURNS TABLE(table_name text, table_type text)
 LANGUAGE plpgsql
AS $function$
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
        t.table_type,
        t.table_name;
END;
$function$


CREATE OR REPLACE FUNCTION public.get_db_functions_base()
 RETURNS TABLE(routine_name text, routine_definition text, data_type text, routine_body text, external_language text)
 LANGUAGE plpgsql
AS $function$
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
        AND r.routine_type = 'FUNCTION'
        AND r.routine_name NOT IN (
            'get_tables',
            'get_table_info',
            'get_table_indexes',
            'get_enum_types'
        )
    ORDER BY
        r.routine_name;
END;
$function$


CREATE OR REPLACE FUNCTION public.get_db_triggers_base()
 RETURNS TABLE(trigger_name text, event_object_table text, action_timing text, event_manipulation text, trigger_definition text)
 LANGUAGE plpgsql
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.get_view_definitions_base()
 RETURNS TABLE(view_name text, view_definition text)
 LANGUAGE plpgsql
AS $function$
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
$function$


CREATE OR REPLACE FUNCTION public.get_tables()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN (SELECT jsonb_agg(t) FROM (SELECT * FROM get_tables_base()) t);
END;
$function$


CREATE OR REPLACE FUNCTION public.get_db_functions()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN (SELECT jsonb_agg(f) FROM (SELECT * FROM get_db_functions_base()) f);
END;
$function$


CREATE OR REPLACE FUNCTION public.get_db_triggers()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN (SELECT jsonb_agg(t) FROM (SELECT * FROM get_db_triggers_base()) t);
END;
$function$


CREATE OR REPLACE FUNCTION public.get_view_definitions()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN (SELECT jsonb_agg(v) FROM (SELECT * FROM get_view_definitions_base()) v);
END;
$function$


CREATE OR REPLACE FUNCTION public.get_professional_detailed_earnings(p_professional_id text, p_start_date timestamp with time zone, p_end_date timestamp with time zone)
 RETURNS TABLE(period text, job_count integer, total_earnings numeric, diagnosis_fees numeric, materials_cost numeric, labor_cost numeric, other_fees numeric, service_category text)
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY WITH job_data AS ( SELECT TO_CHAR(j.created_at, 'YYYY-MM') AS period, j.job_id, sq.total_amount, sc.name AS service_category FROM jobs j JOIN service_quotes sq ON j.job_id = sq.job_id JOIN services s ON j.service_id = s.service_id JOIN service_categories sc ON s.category_id = sc.category_id WHERE j.professional_id = p_professional_id AND j.current_stage = 'Completed' AND j.created_at BETWEEN p_start_date AND p_end_date ), line_item_data AS ( SELECT sq.job_id, SUM(CASE WHEN qli.item_type = 'labor' AND qli.description ILIKE '%diagnosis%' THEN qli.total_price ELSE 0 END) AS diagnosis_fees, SUM(CASE WHEN qli.item_type = 'material' THEN qli.total_price ELSE 0 END) AS materials_cost, SUM(CASE WHEN qli.item_type = 'labor' AND qli.description NOT ILIKE '%diagnosis%' THEN qli.total_price ELSE 0 END) AS labor_cost, SUM(CASE WHEN qli.item_type = 'fee' THEN qli.total_price ELSE 0 END) AS other_fees FROM service_quotes sq JOIN quote_line_items qli ON sq.quote_id = qli.quote_id GROUP BY sq.job_id ) SELECT jd.period, COUNT(DISTINCT jd.job_id)::INTEGER AS job_count, SUM(jd.total_amount) AS total_earnings, COALESCE(SUM(lid.diagnosis_fees), 0) AS diagnosis_fees, COALESCE(SUM(lid.materials_cost), 0) AS materials_cost, COALESCE(SUM(lid.labor_cost), 0) AS labor_cost, COALESCE(SUM(lid.other_fees), 0) AS other_fees, jd.service_category FROM job_data jd LEFT JOIN line_item_data lid ON jd.job_id = lid.job_id GROUP BY jd.period, jd.service_category ORDER BY jd.period DESC, total_earnings DESC; END; $function$


