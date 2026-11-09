-- CORE-10-CENTRAL | Owner Inbox release preflight | READ ONLY
-- Compatible with live IMG-ERP-SG and isolated PostgreSQL CI.
-- This query inspects metadata; it DOES NOT simulate real JWT sessions and
-- cannot approve a release or change a production database.
WITH
required(table_name,column_name) AS (
 VALUES
 ('org_units','id'),('org_units','kind'),('org_units','status'),
 ('entries','id'),('entries','location_id'),('entries','status'),('entries','created_at'),
 ('release_requests','id'),('release_requests','entry_id'),('release_requests','status'),('release_requests','requested_at'),
 ('entry_change_requests','id'),('entry_change_requests','entry_id'),('entry_change_requests','status'),('entry_change_requests','created_at'),
 ('exceptions','id'),('exceptions','entry_id'),('exceptions','location_id'),('exceptions','status'),('exceptions','created_at'),
 ('emergency_requests','id'),('emergency_requests','location_id'),('emergency_requests','status'),('emergency_requests','created_at'),
 ('pay_requests','id'),('pay_requests','location_id'),('pay_requests','status'),('pay_requests','created_at'),
 ('wastage_requests','id'),('wastage_requests','location_id'),('wastage_requests','status'),('wastage_requests','requested_at'),
 ('item_changes','id'),('item_changes','org_unit_id'),('item_changes','status'),('item_changes','requested_at')
),
sources(table_name) AS (
 VALUES ('org_units'),('profiles'),('user_roles'),('locations'),('entries'),
        ('release_requests'),('entry_change_requests'),('exceptions'),
        ('emergency_requests'),('pay_requests'),('wastage_requests'),('item_changes')
),
required_helpers(signature,needs_authenticated_execute) AS (
 VALUES ('public.is_owner()',true),
        ('public._business_of_loc123(integer)',false),
        ('public._business_of_unit123(bigint)',false)
),
inspection AS (
 SELECT
  (SELECT COUNT(*) FROM required r
   LEFT JOIN information_schema.columns c
    ON c.table_schema='public' AND c.table_name=r.table_name AND c.column_name=r.column_name
   WHERE c.column_name IS NULL) missing_columns,
  (SELECT COUNT(*) FROM sources s
   LEFT JOIN pg_catalog.pg_class c ON c.relname=s.table_name
      AND c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p')
   WHERE c.oid IS NULL OR NOT c.relrowsecurity) unprotected_tables,
  (SELECT COUNT(*) FROM required_helpers h
   LEFT JOIN pg_catalog.pg_proc p ON p.oid=to_regprocedure(h.signature)
   WHERE p.oid IS NOT NULL AND p.prosecdef
     AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
     AND (NOT h.needs_authenticated_execute OR has_function_privilege('authenticated',p.oid,'EXECUTE'))
     AND (h.needs_authenticated_execute OR NOT has_function_privilege('authenticated',p.oid,'EXECUTE'))
  ) secured_helpers,
  (SELECT COUNT(*) FROM public.org_units WHERE kind='business' AND status='active') active_businesses,
  COALESCE(public._org_on123(),false) org_mode_on,
  to_regprocedure('public.core10_owner_inbox_v1(bigint,integer)') rpc_oid
), checks AS (
 SELECT '01_required_schema' name, CASE WHEN missing_columns=0 THEN 'PASS' ELSE 'BLOCK' END result FROM inspection
 UNION ALL SELECT '02_rls_enabled',CASE WHEN unprotected_tables=0 THEN 'PASS' ELSE 'BLOCK' END FROM inspection
 UNION ALL SELECT '03_owner_helpers',CASE WHEN secured_helpers=3 AND to_regprocedure('auth.uid()') IS NOT NULL THEN 'PASS' ELSE 'BLOCK' END FROM inspection
 UNION ALL SELECT '04_org_mode',CASE WHEN org_mode_on THEN 'PASS' ELSE 'BLOCK' END FROM inspection
 UNION ALL SELECT '05_two_active_businesses',CASE WHEN active_businesses>=2 THEN 'PASS' ELSE 'BLOCK' END FROM inspection
 UNION ALL SELECT '06_rpc_security_definer',CASE WHEN rpc_oid IS NOT NULL AND EXISTS
  (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.oid=rpc_oid AND p.prosecdef
   AND (p.proconfig @> ARRAY['search_path=']::text[]
        OR p.proconfig @> ARRAY['search_path=""']::text[]))
  THEN 'PASS' ELSE 'BLOCK' END FROM inspection
 UNION ALL SELECT '07_rpc_execute_grants',
  CASE WHEN rpc_oid IS NOT NULL
     AND has_function_privilege('authenticated',rpc_oid,'EXECUTE')
     AND NOT has_function_privilege('anon',rpc_oid,'EXECUTE')
  THEN 'PASS' ELSE 'BLOCK' END FROM inspection
 UNION ALL SELECT '08_real_signed_sessions','MANUAL_REQUIRED' FROM inspection
 UNION ALL SELECT '09_release_decision','STOP_UNTIL_OWNER_APPROVAL' FROM inspection
)
SELECT name,result FROM checks ORDER BY name;
