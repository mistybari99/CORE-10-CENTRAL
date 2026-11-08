-- CORE 10 | LIVE DATABASE READ-ONLY SECURITY PREFLIGHT
-- Run ONLY in the actual production Supabase SQL editor connected to the published app.
-- Every statement below is SELECT. Do not turn on org_scope_on until failures are resolved.
-- This is a release gate, not a migration. Run sections in order.
-- SECTION 1. Installed schema/function checks. 'missing' blocks deployment.
SELECT k.expected_object, CASE WHEN to_regprocedure(k.signature) IS NULL THEN 'MISSING' ELSE 'installed' END AS status
FROM (VALUES
 ('phase 122 organization tree','public.org_tree()'),
 ('phase 122 location membership','public.org_unit_scope(integer)'),
 ('phase 123 scope preflight','public.org_scope_preflight()'),
 ('phase 123 scoped access','public.can_loc(integer)'),
 ('phase 123 location business','public.business_of_location(integer)'),
 ('phase 134 visible businesses','public._vis_biz134()'),
 ('phase 134 business profiles','public.business_profile_list134()'),
 ('phase 135 business places','public.business_places_list135(bigint)')
) AS k(expected_object,signature)
ORDER BY k.expected_object;
-- SECTION 2. Read-only scope switch. Multi-business is NOT ready when OFF.
-- Requires rules table (base ERP schema).
SELECT key,
  coalesce((coalesce(value, default_value) #>> '{}')::boolean, false) AS org_scope_enabled,
  CASE WHEN coalesce((coalesce(value, default_value) #>> '{}')::boolean, false)
    THEN 'ON: still requires full isolation tests'
    ELSE 'OFF: DO NOT ENABLE A SECOND BUSINESS FOR STAFF' END AS release_gate
FROM public.rules WHERE key='org_scope_on';
-- SECTION 3. Real mapping: all operational locations must belong to exactly one business.
-- Requires phase123 helpers, and should be run only after section 1 reports installed.
SELECT l.id AS location_id,l.code AS location_code,l.kind AS location_kind,
       l.org_unit_id, public._business_of_unit123(l.org_unit_id) AS business_id,
       CASE
         WHEN l.org_unit_id IS NULL THEN 'BLOCKER: location unmapped'
         WHEN public._business_of_unit123(l.org_unit_id) IS NULL THEN 'BLOCKER: outside business'
         ELSE 'mapped' END AS mapping_status
FROM public.locations l ORDER BY l.id;
-- SECTION 4. Summary. Any unmatched row BLOCKS a multi-business rollout.
SELECT
 (SELECT count(*) FROM public.org_units WHERE kind='business' AND status<>'inactive') AS active_businesses,
 (SELECT count(*) FROM public.locations WHERE org_unit_id IS NULL) AS unmapped_locations,
 (SELECT count(*) FROM public.locations l WHERE l.org_unit_id IS NOT NULL
          AND public._business_of_unit123(l.org_unit_id) IS NULL) AS locations_outside_business,
 (SELECT count(*) FROM public.profiles p WHERE p.status='active'
          AND NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=p.id AND ur.role_code='owner')
          AND NOT EXISTS (SELECT 1 FROM public._user_biz123(p.id))) AS active_nonowners_without_business,
 (SELECT count(*) FROM public.user_roles ur WHERE ur.role_code='management'
          AND NOT EXISTS (SELECT 1 FROM public._scopes123(ur.user_id) sc
                          WHERE sc.role_code='management')) AS management_without_scope;
-- SECTION 5. RLS enabled on critical tables? Missing RLS requires review.
SELECT c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_rls,
       count(pol.policyname) AS policy_count
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
LEFT JOIN pg_policies pol ON pol.schemaname=n.nspname AND pol.tablename=c.relname
WHERE n.nspname='public' AND c.relkind IN ('r','p')
AND c.relname IN ('locations','user_locations','org_units','user_org_scopes',
  'business_profiles','sales','stock_ledger','entries','employees',
  'customers','purchase_bills','settings_sheets','report_brand_map')
GROUP BY c.relname,c.relrowsecurity,c.relforcerowsecurity ORDER BY c.relname;
-- SECTION 6. Dangerous API surface: security-definer functions executable by anon.
-- A row is not automatically a vulnerability, but every row is a mandatory manual review.
SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS arguments,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anon_can_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_can_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND has_function_privilege('anon',p.oid,'EXECUTE')
ORDER BY p.proname LIMIT 150;
-- SECTION 7. Scope policies (inspect both permissive AND restrictive policies).
SELECT tablename,policyname,permissive,cmd,roles,qual,with_check
FROM pg_policies WHERE schemaname='public' AND tablename IN
 ('locations','user_locations','org_units','user_org_scopes',
 'business_profiles','sales','stock_ledger','entries',
 'customers','purchase_bills','settings_sheets','report_brand_map')
ORDER BY tablename,policyname;
-- RESULTS REQUIRE REVIEW BEFORE PERMISSIONS CHANGE.
