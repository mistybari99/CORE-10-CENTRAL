-- C10-A019 | SG CANONICAL SCOPE AND RLS PREFLIGHT v1
-- SELECT ONLY. Safe to run read-only on IMG-ERP-SG. No DDL/DML/grants/RPC calls.
-- Output omits client UUIDs, names, staff identities, balances and policy SQL bodies.
-- This inspection cannot certify effective RLS or Supabase Auth behavior.
WITH
 nodes AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',id::text,'parent_id',parent_id::text,'kind',kind,'template_code',template_code
  ) ORDER BY id),'[]'::jsonb) AS rows FROM public.org_units
 ),
 stock_locations AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'org_unit_id',org_unit_id::text,'kind',kind,
    'code_present', (code IS NOT NULL AND btrim(code) <> '')
  ) ORDER BY id),'[]'::jsonb) AS rows FROM public.locations
 ),
 rls_flags AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'table',c.relname,'enabled',c.relrowsecurity,'forced',c.relforcerowsecurity
  ) ORDER BY c.relname),'[]'::jsonb) AS rows
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','p')
    AND c.relname IN ('org_units','locations','items','business_profiles','business_templates','user_locations')
 ),
 policy_flags AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'table',tablename,'name',policyname,'cmd',cmd,'permissive',permissive,
    'roles',roles::text,
    'active_only',(btrim(coalesce(qual,''))='is_active()'),
    'loc_scope_helper',(qual LIKE '%_loc_vis123(%'),
    'org_disabled_bypass',(position('_org_on123()' in coalesce(qual,'')) > 0 AND position('NOT' in upper(coalesce(qual,''))) > 0)
  ) ORDER BY tablename,policyname),'[]'::jsonb) AS rows
  FROM pg_policies WHERE schemaname='public'
    AND tablename IN ('org_units','locations','items','business_profiles','business_templates','user_locations')
 ),
 func_flags AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),
    'security_definer',p.prosecdef,
    'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE')
  ) ORDER BY p.proname),'[]'::jsonb) AS rows
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname IN ('_org_on123','_loc_vis123','_vis_biz134','_my_biz125','business_place_create135')
 ),
 fk_counts AS (
  SELECT jsonb_build_object(
    'locations',count(*) FILTER(WHERE confrelid='public.locations'::regclass),
    'org_units',count(*) FILTER(WHERE confrelid='public.org_units'::regclass)
  ) AS value FROM pg_constraint WHERE contype='f'
 ),
 column_flags AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'table',table_name,'column',column_name,'type',udt_name
  ) ORDER BY table_name,column_name),'[]'::jsonb) AS rows
  FROM information_schema.columns WHERE table_schema='public'
   AND ((table_name='org_units' AND column_name IN('id','parent_id','kind','template_code','client_id'))
      OR (table_name='locations' AND column_name IN('id','org_unit_id','kind','code')))
 )
SELECT jsonb_build_object(
  'source','IMG-ERP-SG',
  'schema_version',1,
  'captured_at_utc',to_char(current_timestamp AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'read_only',true,
  'contains_personal_data',false,
  'org_units',(SELECT rows FROM nodes),
  'locations',(SELECT rows FROM stock_locations),
  'rls',(SELECT rows FROM rls_flags),
  'policies',(SELECT rows FROM policy_flags),
  'functions',(SELECT rows FROM func_flags),
  'foreign_key_refs',(SELECT value FROM fk_counts),
  'columns',(SELECT rows FROM column_flags)
)::text AS c10_a019_scope_preflight;
