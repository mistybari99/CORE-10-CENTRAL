-- CORE 10 / Owner Approval Inbox : READ-ONLY PREFLIGHT
-- Run in the *real* deployed Supabase project's SQL editor. No mutation.
-- NOT a migration. Do not activate additional business staff solely from this report.
-- A. Discover actual queues and location/business mapping columns.
select table_schema,table_name,column_name,data_type
from information_schema.columns
where table_schema='public'
  and table_name in (
    'entries','release_requests','emergency_requests','exceptions',
    'item_changes','user_org_scopes','org_units','locations',
    'purchase_bills','payment_requests','approval_requests',
    'stock_adjustments','business_profiles'
  )
  and column_name in (
    'id','business_id','org_unit_id','location_id','project_id',
    'status','requester_id','requested_by','approved_by','created_at','request_type'
  )
order by table_name,ordinal_position;

-- B. Review real approval functions and server-side security qualifiers.
select p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as arguments,
       p.prosecdef as security_definer,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as auth_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and
      (p.proname like '%approv%' or p.proname like '%queue%'
       or p.proname like '%request%' or p.proname like '%needs_you%'
       or p.proname like '%scope%' or p.proname like '%business%')
order by p.proname, arguments;

-- C. Check row security and policies of approval source tables.
select c.relname, c.relrowsecurity, c.relforcerowsecurity,
       count(pol.policyname) as policy_count
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
left join pg_policies pol on pol.schemaname=n.nspname and pol.tablename=c.relname
where n.nspname='public' and c.relkind in ('r','p')
and (c.relname like '%approv%' or c.relname like '%request%'
or c.relname in ('entries','exceptions','item_changes','locations','org_units'))
group by c.relname,c.relrowsecurity,c.relforcerowsecurity
order by c.relname;

-- D. Verify existence, but NOT correctness, of future read-only inbox API.
select to_regprocedure('public.core10_owner_inbox_v1(bigint,integer)') as inbox_contract_installed;

-- Run authenticated owner and isolated staff negative tests after code review.
-- Do not copy/supply private SQL results publicly; keep schema and data private.
