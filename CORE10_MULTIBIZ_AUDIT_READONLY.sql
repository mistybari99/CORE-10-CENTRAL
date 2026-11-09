-- CORE 10 multi-business Read-Only audit v2 (NO modifications)
-- Execute in actual LIVE Supabase project SQL editor, one section at a time.
-- Never share user rows, secrets, JWTs or internal function bodies outside the owner team.

-- 01. Source registry. Detect actual approval-related columns, not guessed schema.
select c.table_name, c.column_name, c.data_type
from information_schema.columns c
where c.table_schema='public'
 and (c.table_name in ('entries','release_requests','emergency_requests','exceptions',
   'profiles','item_changes','entry_changes','payment_requests','pay_requests',
   'settings_drafts','user_org_scopes','user_roles','locations','org_units')
   or c.table_name like '%approv%' or c.table_name like '%request%')
 and c.column_name in ('id','business_id','org_unit_id','location_id','requester_id',
   'approved_by','status','created_at','parent_id','kind','role_code','user_id','source_id')
order by c.table_name,c.ordinal_position;

-- 02. Approval RPC and authorization surface. Flag functions callable anonymously.
select p.proname,pg_get_function_identity_arguments(p.oid) as args,
       p.prosecdef as security_definer,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and (p.proname like '%approv%' or p.proname like '%request%'
       or p.proname like '%scope%' or p.proname like '%queue%'
       or p.proname like '%needs_you%' or p.proname like '%counts%'
       or p.proname like 'core10_%')
order by p.proname,args;

-- 03. RLS status for every public table. A table without RLS is a release blocker
-- if exposed and accessible to authenticated/anon roles.
select c.relname as table_name,c.relrowsecurity as rls_enabled,
       c.relforcerowsecurity as force_rls,
       has_table_privilege('anon',c.oid,'SELECT') as anon_can_select,
       has_table_privilege('authenticated',c.oid,'SELECT') as authenticated_can_select
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind in ('r','p')
order by c.relname;

-- 04. Per-table policies including USING and WITH CHECK for review.
select schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
from pg_policies
where schemaname='public'
order by tablename,policyname;

-- 05. Views that may bypass underlying RLS.
select c.relname as view_name,c.reloptions as view_options,
       has_table_privilege('anon',c.oid,'SELECT') as anon_select,
       has_table_privilege('authenticated',c.oid,'SELECT') as authenticated_select
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind in ('v','m')
order by c.relname;

-- 06. Confirm legacy mapping and new RPC availability. Existence != security.
select to_regprocedure('public.org_tree()') as org_tree,
 to_regprocedure('public.org_unit_scope(integer)') as location_scope,
 to_regprocedure('public.core10_owner_inbox_v1(bigint,integer)') as inbox_api;

-- 07. Rule if present. Change NOTHING here; switch must stay OFF until release gates pass.
select key,value,default_value
from public.rules
where key='org_scope_on';

-- 08. Run existing CORE10_SECURITY_PREFLIGHT.sql for mapping anomalies;
-- follow with authenticated owner, Islamia staff, Paint staff, revoked staff,
-- and anonymous negative tests using direct REST/RPC calls.
