-- C10-A007 isolated integration assertions: 2 active + 1 inactive business.
-- Validates JSON shape, canonical IDs, business scoping and 4 role classes.
\set ON_ERROR_STOP on
DO $test$
BEGIN
  IF has_function_privilege('anon','public.core10_owner_inbox_v1(bigint,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon has execute privilege';
  END IF;
  IF NOT has_function_privilege('authenticated','public.core10_owner_inbox_v1(bigint,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: authenticated lacks execute privilege';
  END IF;
END $test$;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
DO $test$
DECLARE v_master jsonb; v_ten jsonb; v_twenty jsonb;
BEGIN
  v_master := public.core10_owner_inbox_v1(NULL,40);
  v_ten := public.core10_owner_inbox_v1(10,40);
  v_twenty := public.core10_owner_inbox_v1(20,40);
  IF v_master->>'scope'<>'owner' OR v_master->'business_id'<>'null'::jsonb
     OR v_master->'certified'<>'true'::jsonb THEN
    RAISE EXCEPTION 'FAIL: master contract';
  END IF;
  IF (v_ten->'business_id')::text<>'10' OR (v_twenty->'business_id')::text<>'20' THEN
    RAISE EXCEPTION 'FAIL: scoped business response';
  END IF;
  IF jsonb_array_length(v_master->'items')<>9
     OR jsonb_array_length(v_ten->'items')<>6
     OR jsonb_array_length(v_twenty->'items')<>3 THEN
    RAISE EXCEPTION 'FAIL: counts master/Islamia/Paint: % % %',
      jsonb_array_length(v_master->'items'),
      jsonb_array_length(v_ten->'items'),
      jsonb_array_length(v_twenty->'items');
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_ten->'items') AS item
      WHERE (item->>'business_id')::bigint<>10
         OR item->>'status'<>'pending'
         OR item->>'created_at' !~ '^\d{4}-\d{2}-\d{2}T'
  ) THEN
    RAISE EXCEPTION 'FAIL: foreign/non-pending/malformed business 10 row';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_master->'items') AS item
      WHERE (item->>'business_id')::bigint NOT IN (10,20)
         OR item->>'id' IN ('release:2','release:3','exception:1',
                           'emergency:2','pay:2','item_change:2','item_change:3',
                           'entry:eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')
  ) THEN
    RAISE EXCEPTION 'FAIL: unmapped, conflicting, approved or inactive leak';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_master->'items') AS item
      WHERE item->>'id'='release:1'
  ) OR NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_ten->'items') AS item
      WHERE item->>'id'='release:1'
  ) THEN
    RAISE EXCEPTION 'FAIL: canonical ID mismatch in master/business views';
  END IF;
  RAISE NOTICE 'PASS owner scope master=9 business10=6 business20=3, no leaks';
END $test$;

-- Invalid business, inactive business, and oversized limit must fail closed.
DO $test$
BEGIN
  BEGIN
    PERFORM public.core10_owner_inbox_v1(999,40);
    RAISE EXCEPTION 'FAIL nonexistent business granted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.core10_owner_inbox_v1(30,40);
    RAISE EXCEPTION 'FAIL inactive business granted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.core10_owner_inbox_v1(10,41);
    RAISE EXCEPTION 'FAIL invalid limit granted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  RAISE NOTICE 'PASS invalid/inactive scope + oversized limit denied';
END $test$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
DO $test$
BEGIN
  BEGIN
    PERFORM public.core10_owner_inbox_v1(10,40);
    RAISE EXCEPTION 'FAIL staff permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.core10_owner_inbox_v1(NULL,40);
    RAISE EXCEPTION 'FAIL staff master permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS active staff denied for both scopes';
END $test$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',false);
DO $test$
BEGIN
  BEGIN
    PERFORM public.core10_owner_inbox_v1(10,40);
    RAISE EXCEPTION 'FAIL revoked owner permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS inactive/revoked owner denied';
END $test$;
SELECT set_config('request.jwt.claim.sub','',false);
DO $test$
BEGIN
  BEGIN
    PERFORM public.core10_owner_inbox_v1(10,40);
    RAISE EXCEPTION 'FAIL missing identity permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS missing auth UID denied';
END $test$;
RESET ROLE;

-- Even with owner-like session claims, anon cannot execute RPC.
SET ROLE anon;
DO $test$
BEGIN
  BEGIN
    PERFORM public.core10_owner_inbox_v1(NULL,40);
    RAISE EXCEPTION 'FAIL anon permitted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS anon direct RPC denied by EXECUTE ACL';
END $test$;
RESET ROLE;
