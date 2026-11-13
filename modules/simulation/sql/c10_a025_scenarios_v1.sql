-- C10-A025 scenario persistence — ADDITIVE, ISOLATED schema c10_sim. DRAFT. DISPOSABLE PG17 ONLY.
-- NO production DDL. No writes to any operational table. Synthetic jwt-claim actor (NOT signed GoTrue auth).
-- Apply order: c10_a025_fixture_v1.sql (test only) -> this file -> c10_a025_rollback_v1.sql to undo.
create schema if not exists c10_sim;
revoke all on schema c10_sim from public;
grant usage on schema c10_sim to sim_authenticated, sim_gateway;

-- ---- scope sources (REPLACE with canonical A018/A021/A034 views in staging) ----
create or replace view c10_sim.business_source as select id as business_id, tenant_id from c10_sim_fixture.businesses;
create or replace view c10_sim.site_source as select id as site_id, business_id from c10_sim_fixture.sites;
create or replace view c10_sim.grant_source as select user_id, tenant_id, business_id, site_id, cap from c10_sim_fixture.grants where not revoked;
revoke all on c10_sim.business_source, c10_sim.site_source, c10_sim.grant_source from public;

-- ---- actor + permission (read-only definer helpers, pinned search_path) ----
create or replace function c10_sim.actor() returns text language sql stable
as $$ select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '') $$;

create or replace function c10_sim.can(p_cap text, p_business text, p_site text) returns boolean
language plpgsql stable security definer set search_path = pg_catalog, c10_sim as $$
declare v_actor text := c10_sim.actor(); v_tenant text;
begin
  if v_actor is null then return false; end if;
  select tenant_id into v_tenant from c10_sim.business_source where business_id = p_business;
  if v_tenant is null then return false; end if;
  if p_site is not null and not exists (select 1 from c10_sim.site_source where site_id = p_site and business_id = p_business) then return false; end if;
  return exists (select 1 from c10_sim.grant_source g where g.user_id = v_actor and g.cap = p_cap
                 and (g.tenant_id is null or g.tenant_id = v_tenant)
                 and (g.business_id is null or g.business_id = p_business)
                 and (g.site_id is null or g.site_id = p_site));
end $$;

-- ---- tables ----
create table c10_sim.model_registry (
  model_id text not null, version text not null, status text not null check (status in ('implemented_tested','partial','research_only','not_implemented')),
  formula_hash text check (formula_hash ~ '^[0-9a-f]{64}$'), spec jsonb not null default '{}', published_at timestamptz not null default now(), retired_at timestamptz,
  primary key (model_id, version));
create table c10_sim.scenario_drafts (
  id uuid primary key default gen_random_uuid(), tenant_id text not null, business_id text not null, site_id text,
  owner_user text not null, name text not null check (char_length(name) between 1 and 120),
  kind text not null check (kind in ('baseline','conservative','optimistic','custom')),
  status text not null default 'draft' check (status in ('draft','simulated','reviewed','approved','rejected','proposal','monitored','closed')),
  revision integer not null default 1 check (revision >= 1), request_key text not null,
  model_id text not null, model_version text not null, inputs jsonb not null default '{}', currency text not null default 'BDT',
  archived boolean not null default false, shared_with text[] not null default '{}', created_at timestamptz not null default now(),
  unique (tenant_id, business_id, request_key),
  foreign key (model_id, model_version) references c10_sim.model_registry(model_id, version));
create table c10_sim.scenario_runs (
  id uuid primary key default gen_random_uuid(), scenario_id uuid not null references c10_sim.scenario_drafts(id), tenant_id text not null,
  revision_at_run integer not null, model_id text not null, model_version text not null,
  formula_hash text not null check (formula_hash ~ '^[0-9a-f]{64}$'), input_hash text not null check (input_hash ~ '^[0-9a-f]{64}$'), source_hash text not null,
  inputs jsonb not null, result jsonb not null, side_effects jsonb not null default '[]' check (side_effects = '[]'::jsonb),
  ran_by text not null, computed_at timestamptz not null default now());
create table c10_sim.scenario_decision_events (
  id bigint generated always as identity primary key, scenario_id uuid not null references c10_sim.scenario_drafts(id), tenant_id text not null,
  to_status text not null, by_user text not null, note text, at timestamptz not null default now());
create table c10_sim.scenario_annotations (
  id bigint generated always as identity primary key, scenario_id uuid not null references c10_sim.scenario_drafts(id), tenant_id text not null,
  by_user text not null, body text not null check (char_length(body) between 1 and 1000), at timestamptz not null default now());
create table c10_sim.decision_proposals (
  id uuid primary key default gen_random_uuid(), scenario_id uuid not null references c10_sim.scenario_drafts(id), run_id uuid not null references c10_sim.scenario_runs(id), tenant_id text not null,
  advisory_only boolean not null default true check (advisory_only), apply_state text not null default 'DISABLED' check (apply_state = 'DISABLED'),
  summary text not null, created_by text not null, created_at timestamptz not null default now());
create table c10_sim.scenario_audit (
  n bigint generated always as identity primary key, at timestamptz not null default now(), actor text, action text not null, scenario_id uuid, tenant_id text, detail jsonb, prev_hash text, hash text);

-- ---- immutability / append-only ----
create or replace function c10_sim.block_mutation() returns trigger language plpgsql as $$ begin raise exception 'IMMUTABLE: % on % is not allowed', tg_op, tg_table_name using errcode = '55000'; end $$;
create trigger runs_immutable before update or delete on c10_sim.scenario_runs for each row execute function c10_sim.block_mutation();
create trigger events_append_only before update or delete on c10_sim.scenario_decision_events for each row execute function c10_sim.block_mutation();
create trigger annotations_append_only before update or delete on c10_sim.scenario_annotations for each row execute function c10_sim.block_mutation();
create trigger proposals_immutable before update or delete on c10_sim.decision_proposals for each row execute function c10_sim.block_mutation();
create trigger audit_append_only before update or delete on c10_sim.scenario_audit for each row execute function c10_sim.block_mutation();
create or replace function c10_sim.registry_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'IMMUTABLE: registry versions cannot be deleted' using errcode = '55000'; end if;
  if (new.model_id, new.version, new.status, new.formula_hash, new.spec, new.published_at) is distinct from (old.model_id, old.version, old.status, old.formula_hash, old.spec, old.published_at)
  then raise exception 'IMMUTABLE: only retired_at may change on a published model version' using errcode = '55000'; end if; return new;
end $$;
create trigger registry_guard before update or delete on c10_sim.model_registry for each row execute function c10_sim.registry_guard();
create or replace function c10_sim.audit_chain() returns trigger language plpgsql as $$
declare v_prev text;
begin
  perform pg_advisory_xact_lock(70250001);
  select hash into v_prev from c10_sim.scenario_audit order by n desc limit 1;
  new.prev_hash := coalesce(v_prev, 'GENESIS');
  new.hash := encode(sha256(convert_to(coalesce(new.prev_hash,'') || '|' || coalesce(new.actor,'') || '|' || new.action || '|' || coalesce(new.scenario_id::text,'') || '|' || coalesce(new.detail::text,''), 'UTF8')), 'hex');
  return new;
end $$;
create trigger audit_chain before insert on c10_sim.scenario_audit for each row execute function c10_sim.audit_chain();

-- ---- RLS: authenticated may only SELECT rows it is entitled to; no DML grants at all ----
alter table c10_sim.scenario_drafts enable row level security; alter table c10_sim.scenario_runs enable row level security; alter table c10_sim.scenario_decision_events enable row level security;
alter table c10_sim.scenario_annotations enable row level security; alter table c10_sim.decision_proposals enable row level security; alter table c10_sim.scenario_audit enable row level security; alter table c10_sim.model_registry enable row level security;
create or replace function c10_sim.can_see(p_scenario uuid) returns boolean language plpgsql stable security definer set search_path = pg_catalog, c10_sim as $$
declare s c10_sim.scenario_drafts%rowtype;
begin
  select * into s from c10_sim.scenario_drafts where id = p_scenario; if not found then return false; end if;
  if c10_sim.can('sim.read', s.business_id, s.site_id) then return true; end if;
  return c10_sim.actor() = any (s.shared_with) and c10_sim.can('sim.read_shared', s.business_id, null);
end $$;
create policy sd_select on c10_sim.scenario_drafts for select to sim_authenticated using (c10_sim.can_see(id));
create policy sr_select on c10_sim.scenario_runs for select to sim_authenticated using (c10_sim.can_see(scenario_id));
create policy se_select on c10_sim.scenario_decision_events for select to sim_authenticated using (c10_sim.can_see(scenario_id));
create policy sa_select on c10_sim.scenario_annotations for select to sim_authenticated using (c10_sim.can_see(scenario_id));
create policy dp_select on c10_sim.decision_proposals for select to sim_authenticated using (c10_sim.can_see(scenario_id));
create policy au_select on c10_sim.scenario_audit for select to sim_authenticated using (scenario_id is not null and c10_sim.can('sim.export_full', (select business_id from c10_sim.scenario_drafts d where d.id = scenario_id), null));
create policy mr_select on c10_sim.model_registry for select to sim_authenticated using (true);
grant select on c10_sim.scenario_drafts, c10_sim.scenario_runs, c10_sim.scenario_decision_events, c10_sim.scenario_annotations, c10_sim.decision_proposals, c10_sim.scenario_audit, c10_sim.model_registry to sim_authenticated;
-- NOTE: no privileges for sim_anon anywhere; no privileges for anyone on operational tables.

-- ---- lifecycle contract (mirrors lib/decisions.js) ----
create or replace function c10_sim.transition_allowed(p_from text, p_to text) returns boolean language sql immutable as $$
  select (p_from, p_to) in (('draft','simulated'),('simulated','simulated'),('simulated','reviewed'),('simulated','draft'),('reviewed','approved'),('reviewed','rejected'),('reviewed','simulated'),
    ('approved','proposal'),('approved','closed'),('rejected','closed'),('rejected','draft'),('proposal','monitored'),('proposal','closed'),('monitored','closed')) $$;
create or replace function c10_sim._audit(p_action text, p_scenario uuid, p_tenant text, p_detail jsonb) returns void language sql as $$
  insert into c10_sim.scenario_audit(actor, action, scenario_id, tenant_id, detail) values (c10_sim.actor(), p_action, p_scenario, p_tenant, p_detail) $$;
create or replace function c10_sim._need_actor() returns text language plpgsql stable as $$ declare a text := c10_sim.actor(); begin if a is null then raise exception 'UNAUTHENTICATED' using errcode = '28000'; end if; return a; end $$;
create or replace function c10_sim._lock_scenario(p_id uuid, p_cap text) returns c10_sim.scenario_drafts language plpgsql security definer set search_path = pg_catalog, c10_sim as $$
declare s c10_sim.scenario_drafts;
begin
  perform c10_sim._need_actor();
  select * into s from c10_sim.scenario_drafts where id = p_id for update;
  if not found or not c10_sim.can_see(p_id) then raise exception 'NOT_FOUND' using errcode = 'P0002'; end if;   -- no existence leak
  if p_cap is not null and not c10_sim.can(p_cap, s.business_id, s.site_id) then raise exception 'FORBIDDEN: %', p_cap using errcode = '42501'; end if;
  return s;
end $$;

-- ---- RPCs (SECURITY DEFINER, pinned search_path, explicit checks, EXECUTE only for sim_authenticated) ----
create or replace function c10_sim.create_scenario(p_business text, p_site text, p_name text, p_kind text, p_request_key text, p_model_id text, p_model_version text, p_inputs jsonb, p_currency text default 'BDT', p_client_tenant text default null)
returns uuid language plpgsql security definer set search_path = pg_catalog, c10_sim as $$
declare v_actor text := c10_sim._need_actor(); v_tenant text; v_id uuid; v_status text;
begin
  select tenant_id into v_tenant from c10_sim.business_source where business_id = p_business;
  if v_tenant is null then raise exception 'FORBIDDEN: unknown business' using errcode = '42501'; end if;
  if p_client_tenant is not null and p_client_tenant <> v_tenant then raise exception 'SCOPE_OVERRIDE_REJECTED' using errcode = '42501'; end if;
  if not c10_sim.can('sim.write', p_business, p_site) then raise exception 'FORBIDDEN: sim.write' using errcode = '42501'; end if;
  if p_request_key is null or p_request_key = '' then raise exception 'REQUEST_KEY_REQUIRED' using errcode = '22023'; end if;
  select status into v_status from c10_sim.model_registry where model_id = p_model_id and version = p_model_version and retired_at is null;
  if v_status is null or v_status in ('research_only','not_implemented') then raise exception 'MODEL_NOT_IMPLEMENTED' using errcode = '22023'; end if;
  insert into c10_sim.scenario_drafts(tenant_id, business_id, site_id, owner_user, name, kind, request_key, model_id, model_version, inputs, currency)
  values (v_tenant, p_business, p_site, v_actor, p_name, p_kind, p_request_key, p_model_id, p_model_version, coalesce(p_inputs,'{}'), p_currency)
  on conflict (tenant_id, business_id, request_key) do nothing returning id into v_id;
  if v_id is null then select id into v_id from c10_sim.scenario_drafts where tenant_id = v_tenant and business_id = p_business and request_key = p_request_key; -- idempotent retry
  else perform c10_sim._audit('scenario.create', v_id, v_tenant, jsonb_build_object('model', p_model_id || '@' || p_model_version)); end if;
  return v_id;
end $$;
create or replace function c10_sim.save_inputs(p_id uuid, p_expected_revision integer, p_inputs jsonb) returns integer language plpgsql security definer set search_path = pg_catalog, c10_sim as $$
declare s c10_sim.scenario_drafts;
begin
  s := c10_sim._lock_scenario(p_id, 'sim.write');
  if s.archived then raise exception 'ARCHIVED' using errcode = '55000'; end if;
  if s.status in ('reviewed','approved','rejected','proposal','monitored','closed') then raise exception 'LOCKED: clone to change inputs' using errcode = '55000'; end if;
  if s.revision <> p_expected_revision then raise exception 'REVISION_CONFLICT: have %, got %', s.revision, p_expected_revision using errcode = '40001'; end if;
  update c10_sim.scenario_drafts set inputs = p_inputs, revision = revision + 1, status = case when status = 'simulated' then 'draft' else status end where id = p_id;
  perform c10_sim._audit('scenario.inputs', p_id, s.tenant_id, jsonb_build_object('revision', s.revision + 1)); return s.revision + 1;
end $$;
create or replace function c10_sim.record_run(p_id uuid, p_formula_hash text, p_input_hash text, p_source_hash text, p_inputs jsonb, p_result jsonb) returns uuid language plpgsql security definer set search_path = pg_catalog, c10_sim as $$
declare s c10_sim.scenario_drafts; v_hash text; v_run uuid;
begin
  s := c10_sim._lock_scenario(p_id, 'sim.run');
  if s.archived then raise exception 'ARCHIVED' using errcode = '55000'; end if;
  select formula_hash into v_hash from c10_sim.model_registry where model_id = s.model_id and version = s.model_version;
  if v_hash is distinct from p_formula_hash then raise exception 'FORMULA_HASH_MISMATCH: run does not match the pinned model version' using errcode = '22023'; end if;
  if p_inputs is distinct from s.inputs then raise exception 'INPUT_SNAPSHOT_MISMATCH: run inputs differ from the saved scenario revision' using errcode = '22023'; end if;
  if coalesce(p_result -> 'sideEffects', '[]'::jsonb) <> '[]'::jsonb then raise exception 'SIDE_EFFECTS_FORBIDDEN' using errcode = '22023'; end if;
  insert into c10_sim.scenario_runs(scenario_id, tenant_id, revision_at_run, model_id, model_version, formula_hash, input_hash, source_hash, inputs, result, ran_by)
  values (p_id, s.tenant_id, s.revision, s.model_id, s.model_version, p_formula_hash, p_input_hash, p_source_hash, p_inputs, p_result, c10_sim.actor()) returning id into v_run;
  if s.status = 'draft' and p_result -> 'outputs' is not null and jsonb_typeof(p_result -> 'outputs') = 'object' then update c10_sim.scenario_drafts set status = 'simulated' where id = p_id; end if;
  perform c10_sim._audit('scenario.run', p_id, s.tenant_id, jsonb_build_object('run', v_run, 'input_hash', p_input_hash)); return v_run;
end $$;
create or replace function c10_sim.transition_scenario(p_id uuid, p_to text, p_note text default null) returns text language plpgsql security definer set search_path = pg_catalog, c10_sim as $$
declare s c10_sim.scenario_drafts; v_cap text; v_actor text;
begin
  s := c10_sim._lock_scenario(p_id, null); v_actor := c10_sim.actor();
  if not c10_sim.transition_allowed(s.status, p_to) then raise exception 'BAD_TRANSITION: % -> %', s.status, p_to using errcode = '22023'; end if;
  v_cap := case when p_to in ('reviewed','approved','rejected') then 'sim.review' when p_to = 'proposal' then 'sim.propose' else 'sim.write' end;
  if not c10_sim.can(v_cap, s.business_id, s.site_id) then raise exception 'FORBIDDEN: %', v_cap using errcode = '42501'; end if;
  if p_to in ('approved','rejected') and s.owner_user = v_actor then raise exception 'SEPARATION_OF_DUTIES' using errcode = '42501'; end if;
  if p_to in ('reviewed','approved') and not exists (select 1 from c10_sim.scenario_runs where scenario_id = p_id) then raise exception 'NO_RUN' using errcode = '22023'; end if;
  if p_to = 'proposal' then raise exception 'USE propose_scenario' using errcode = '22023'; end if;
  update c10_sim.scenario_drafts set status = p_to where id = p_id;
  insert into c10_sim.scenario_decision_events(scenario_id, tenant_id, to_status, by_user, note) values (p_id, s.tenant_id, p_to, v_actor, p_note);
  perform c10_sim._audit('decision.' || p_to, p_id, s.tenant_id, jsonb_build_object('note', p_note)); return p_to;
end $$;
create or replace function c10_sim.propose_scenario(p_id uuid) returns uuid language plpgsql security definer set search_path = pg_catalog, c10_sim as $$
declare s c10_sim.scenario_drafts; v_run c10_sim.scenario_runs; v_id uuid;
begin
  s := c10_sim._lock_scenario(p_id, 'sim.propose');
  if s.status <> 'approved' then raise exception 'NOT_APPROVED' using errcode = '22023'; end if;
  select * into v_run from c10_sim.scenario_runs where scenario_id = p_id order by computed_at desc, id desc limit 1;
  insert into c10_sim.decision_proposals(scenario_id, run_id, tenant_id, summary, created_by) values (p_id, v_run.id, s.tenant_id, 'ADVISORY ONLY. Nothing is applied to live records.', c10_sim.actor()) returning id into v_id;
  update c10_sim.scenario_drafts set status = 'proposal' where id = p_id;
  insert into c10_sim.scenario_decision_events(scenario_id, tenant_id, to_status, by_user, note) values (p_id, s.tenant_id, 'proposal', c10_sim.actor(), 'advisory proposal');
  perform c10_sim._audit('decision.proposal', p_id, s.tenant_id, jsonb_build_object('proposal', v_id)); return v_id;
end $$;
create or replace function c10_sim.apply_to_live(p_id uuid) returns jsonb language plpgsql security definer set search_path = pg_catalog, c10_sim as $$
declare s c10_sim.scenario_drafts;
begin s := c10_sim._lock_scenario(p_id, 'sim.propose'); perform c10_sim._audit('apply.refused', p_id, s.tenant_id, '{}');
  return jsonb_build_object('applied', false, 'reason', 'DISABLED_ADVISORY_ONLY'); end $$;
create or replace function c10_sim.share_scenario(p_id uuid, p_user text) returns void language plpgsql security definer set search_path = pg_catalog, c10_sim as $$
declare s c10_sim.scenario_drafts;
begin
  s := c10_sim._lock_scenario(p_id, 'sim.share');
  if not exists (select 1 from c10_sim.grant_source g where g.user_id = p_user and g.tenant_id = s.tenant_id) then raise exception 'SHARE_TARGET_OUT_OF_TENANT' using errcode = '42501'; end if;
  update c10_sim.scenario_drafts set shared_with = array(select distinct unnest(shared_with || p_user)) where id = p_id;
  perform c10_sim._audit('scenario.share', p_id, s.tenant_id, jsonb_build_object('to', p_user));
end $$;
create or replace function c10_sim.add_annotation(p_id uuid, p_body text) returns bigint language plpgsql security definer set search_path = pg_catalog, c10_sim as $$
declare s c10_sim.scenario_drafts; v bigint;
begin s := c10_sim._lock_scenario(p_id, 'sim.comment'); insert into c10_sim.scenario_annotations(scenario_id, tenant_id, by_user, body) values (p_id, s.tenant_id, c10_sim.actor(), p_body) returning id into v;
  perform c10_sim._audit('scenario.comment', p_id, s.tenant_id, '{}'); return v; end $$;
create or replace function c10_sim.archive_scenario(p_id uuid) returns void language plpgsql security definer set search_path = pg_catalog, c10_sim as $$
declare s c10_sim.scenario_drafts;
begin s := c10_sim._lock_scenario(p_id, 'sim.write'); update c10_sim.scenario_drafts set archived = true where id = p_id; perform c10_sim._audit('scenario.archive', p_id, s.tenant_id, '{}'); end $$;
create or replace function c10_sim.export_scenario(p_id uuid) returns jsonb language plpgsql security definer set search_path = pg_catalog, c10_sim as $$
declare s c10_sim.scenario_drafts; r c10_sim.scenario_runs; v_full boolean; v_out jsonb;
begin
  s := c10_sim._lock_scenario(p_id, null);
  v_full := c10_sim.can('sim.export_full', s.business_id, s.site_id);
  if not v_full and not c10_sim.can('sim.export', s.business_id, s.site_id) then raise exception 'FORBIDDEN: sim.export' using errcode = '42501'; end if;
  select * into r from c10_sim.scenario_runs where scenario_id = p_id order by computed_at desc, id desc limit 1;
  if r.id is null then raise exception 'NO_RUN' using errcode = '22023'; end if;
  v_out := jsonb_build_object('label','SIMULATION — HYPOTHETICAL, ADVISORY ONLY','scope', jsonb_build_object('tenantId', s.tenant_id,'businessId', s.business_id,'siteId', s.site_id),
    'scenario', jsonb_build_object('id', s.id,'name', s.name,'kind', s.kind,'status', s.status), 'model', jsonb_build_object('id', r.model_id,'version', r.model_version,'formulaHash', r.formula_hash),
    'outputs', r.result -> 'outputs', 'feasibility', r.result -> 'feasibility', 'hashes', jsonb_build_object('inputHash', r.input_hash,'sourceHash', r.source_hash), 'sideEffects','[]'::jsonb, 'redacted', not v_full);
  if v_full then v_out := v_out || jsonb_build_object('inputs', r.inputs, 'formulaBreakdown', r.result -> 'breakdown'); end if;
  perform c10_sim._audit('scenario.export', p_id, s.tenant_id, jsonb_build_object('redacted', not v_full)); return v_out;
end $$;

-- ---- privileges: functions callable ONLY by sim_authenticated; helpers not callable ----
revoke all on all functions in schema c10_sim from public;
grant execute on function c10_sim.create_scenario(text,text,text,text,text,text,text,jsonb,text,text), c10_sim.save_inputs(uuid,integer,jsonb),
  c10_sim.transition_scenario(uuid,text,text), c10_sim.propose_scenario(uuid), c10_sim.apply_to_live(uuid), c10_sim.share_scenario(uuid,text), c10_sim.add_annotation(uuid,text), c10_sim.archive_scenario(uuid), c10_sim.export_scenario(uuid) to sim_authenticated;
grant execute on function c10_sim.actor(), c10_sim.can(text,text,text), c10_sim.can_see(uuid) to sim_authenticated;  -- RLS policies run as the caller and call these

-- ---- TRUSTED RESULT WRITER (closes IMPL-009) ----
-- record_run is callable ONLY by sim_gateway: the trusted service that authenticates the user, re-computes the result with the pinned
-- model version and then writes it. Browser/PostgREST users (sim_authenticated) can no longer submit a result of their own.
grant execute on function c10_sim.record_run(uuid,text,text,text,jsonb,jsonb) to sim_gateway;
grant execute on function c10_sim.actor(), c10_sim.can(text,text,text), c10_sim.can_see(uuid) to sim_gateway;
create policy sd_select_gw on c10_sim.scenario_drafts for select to sim_gateway using (c10_sim.can_see(id));
grant select on c10_sim.scenario_drafts, c10_sim.model_registry to sim_gateway;
create policy mr_select_gw on c10_sim.model_registry for select to sim_gateway using (true);
