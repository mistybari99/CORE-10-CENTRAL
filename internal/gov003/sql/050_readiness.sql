-- 05 readiness-states: typed readiness derived from PROOF rows, never from a manually set boolean.
-- DEMO / NOT LIVE. Isolated contract/test bed; final adoption must be reconciled to the canonical CORE10
-- audit service and owner approval.
--
-- Ladder (in order): proposed < code_built < isolated_test_pass < signed_stage_verified
--                    < integrated_verified < deployed_verified < released.
-- Rules (mirrored byte-for-byte by internal/gov003/server/readiness.mjs):
--   * state = highest level reachable CONTIGUOUSLY from `proposed`; a level is satisfied only by a proof that
--     (a) binds the CURRENT head sha of the feature (stale-head validator), (b) is the LATEST proof for that
--     (level, sha) and (c) has outcome = pass. An old SHA pass is never reused for a new SHA.
--   * simulated proofs can satisfy ONLY code_built / isolated_test_pass. Real levels (signed GoTrue,
--     integration, runtime deploy) fail CLOSED: they need a registered real-evidence gate that is DISABLED in
--     this bed. Synthetic green therefore can never produce signed / production / release green.
--   * deployed_verified is written only by 070 certify_deployment; released only by approve_release (owner).
-- Error codes: G3A01 forged actor, G3A02 scope denied, G3A03 validation, G3A05 unauthenticated,
--              G3C01 conflict/stale/replay-mismatch, G3C02 precondition failed, G3E01 real evidence unavailable.
\set ON_ERROR_STOP on
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

-- ------------------------------------------------------------------------------------------ reference data
create table c10_gov003_demo.readiness_levels (
  level          text primary key,
  rank           int  not null unique,
  allowed_envs   text[] not null,
  allows_simulated boolean not null,
  gate           text,
  dedicated_path boolean not null default false
);
insert into c10_gov003_demo.readiness_levels (level, rank, allowed_envs, allows_simulated, gate, dedicated_path) values
  ('proposed',              1, '{}',                                   true,  null,             true),
  ('code_built',            2, '{local,isolated_pg,ci_isolated}',      true,  null,             false),
  ('isolated_test_pass',    3, '{isolated_pg,ci_isolated}',            true,  null,             false),
  ('signed_stage_verified', 4, '{staging_signed}',                     false, 'signed_gotrue',  false),
  ('integrated_verified',   5, '{integration}',                        false, 'integration_env',false),
  ('deployed_verified',     6, '{staging,production}',                 false, 'runtime_probe',  true),
  ('released',              7, '{production}',                         false, null,             true);
alter table c10_gov003_demo.readiness_levels enable row level security;
revoke all on c10_gov003_demo.readiness_levels from public;

-- Real-evidence gates. ALL DISABLED: this bed has no real signed GoTrue, integration environment, runtime
-- probe or remote GitHub verifier. Enabling a gate is an owner-only, out-of-band decision (future adapter).
create table c10_gov003_demo.real_evidence_gates (
  gate    text primary key,
  enabled boolean not null default false,
  note    text not null
);
insert into c10_gov003_demo.real_evidence_gates (gate, enabled, note) values
  ('signed_gotrue',   false, 'Authentic signed GoTrue session adapter: future blocker (A034 parity pending).'),
  ('integration_env', false, 'Integrated environment verifier: not available in the isolated bed.'),
  ('runtime_probe',   false, 'Real runtime probe of a real deployment: not available in the isolated bed.'),
  ('github_remote',   false, 'Remote GitHub Actions verifier adapter: not available in the isolated bed.');
alter table c10_gov003_demo.real_evidence_gates enable row level security;
revoke all on c10_gov003_demo.real_evidence_gates from public;

-- ------------------------------------------------------------------------------------------ tenant data
create table c10_gov003_demo.readiness_features (
  tenant_id       uuid not null,
  business_id     uuid not null,
  feature_id      text not null check (feature_id ~ '^[A-Za-z0-9_.:/#-]{1,128}$'),
  title           text not null check (length(title) between 1 and 200),
  registered_by   uuid not null references c10_gov003_demo.identities,
  registered_at   timestamptz not null default clock_timestamp(),
  idempotency_key text not null,
  audit_receipt_id uuid not null references c10_gov003_demo.audit_receipts,
  primary key (tenant_id, business_id, feature_id),
  unique (tenant_id, business_id, idempotency_key),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);

create table c10_gov003_demo.readiness_heads (
  head_id         uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null,
  business_id     uuid not null,
  feature_id      text not null,
  head_seq        int  not null check (head_seq >= 1),
  head_sha        text not null check (head_sha ~ '^[0-9a-f]{40}$'),
  recorded_by     uuid not null references c10_gov003_demo.identities,
  recorded_at     timestamptz not null default clock_timestamp(),
  idempotency_key text not null,
  audit_receipt_id uuid not null references c10_gov003_demo.audit_receipts,
  unique (tenant_id, business_id, feature_id, head_seq),
  unique (tenant_id, business_id, idempotency_key),
  foreign key (tenant_id, business_id, feature_id) references c10_gov003_demo.readiness_features
);

create table c10_gov003_demo.readiness_proofs (
  proof_id        uuid primary key default gen_random_uuid(),
  proof_seq       bigint generated always as identity,
  tenant_id       uuid not null,
  business_id     uuid not null,
  feature_id      text not null,
  level           text not null references c10_gov003_demo.readiness_levels check (level <> 'proposed'),
  commit_sha      text not null check (commit_sha ~ '^[0-9a-f]{40}$'),
  environment     text not null check (environment in
                    ('local','isolated_pg','ci_isolated','staging_signed','integration','staging','production')),
  run_ref         text not null check (run_ref ~ '^[A-Za-z0-9_.:/#-]{1,128}$'),
  simulated       boolean not null,
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  outcome         text not null check (outcome in ('pass','fail')),
  source_kind     text check (source_kind in ('ci_receipt','deployment_probe','owner_release')),
  source_id       uuid,
  check ((source_kind is null) = (source_id is null)),
  recorded_by     uuid not null references c10_gov003_demo.identities,
  recorded_at     timestamptz not null default clock_timestamp(),
  idempotency_key text not null,
  audit_receipt_id uuid not null references c10_gov003_demo.audit_receipts,
  audit_seq       bigint not null,
  unique (tenant_id, business_id, idempotency_key, level),
  foreign key (tenant_id, business_id, feature_id) references c10_gov003_demo.readiness_features
);
create index readiness_proofs_lookup_idx on c10_gov003_demo.readiness_proofs
  (tenant_id, business_id, feature_id, level, commit_sha);
-- A receipt/probe can bind a given level exactly once.
create unique index readiness_proofs_source_once on c10_gov003_demo.readiness_proofs
  (tenant_id, business_id, source_kind, source_id, level) where source_id is not null;

-- Defense-in-depth on EVERY insert path (generic, CI-bind, deployment, release).
create function c10_gov003_demo._f57_proof_guard() returns trigger
language plpgsql
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare lv record;
begin
  select l.level as lvl, l.allowed_envs as envs, l.allows_simulated as sim_ok
    into lv from c10_gov003_demo.readiness_levels l where l.level = new.level;
  if not (new.environment = any (lv.envs)) then
    raise exception 'proof_environment_invalid: level % does not accept environment %', new.level, new.environment
      using errcode = 'G3A03';
  end if;
  if new.simulated and not lv.sim_ok then
    raise exception 'simulated_proof_cannot_satisfy: simulated evidence can never satisfy level %', new.level
      using errcode = 'G3C02';
  end if;
  return new;
end $$;
create trigger g3_proof_guard before insert on c10_gov003_demo.readiness_proofs
  for each row execute function c10_gov003_demo._f57_proof_guard();

select c10_gov003_demo.protect_table('c10_gov003_demo.readiness_features');
select c10_gov003_demo.protect_table('c10_gov003_demo.readiness_heads');
select c10_gov003_demo.protect_table('c10_gov003_demo.readiness_proofs');

alter table c10_gov003_demo.readiness_features enable row level security;
alter table c10_gov003_demo.readiness_heads enable row level security;
alter table c10_gov003_demo.readiness_proofs enable row level security;
create policy readiness_features_read on c10_gov003_demo.readiness_features for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
create policy readiness_heads_read on c10_gov003_demo.readiness_heads for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
create policy readiness_proofs_read on c10_gov003_demo.readiness_proofs for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
revoke all on c10_gov003_demo.readiness_features, c10_gov003_demo.readiness_heads,
              c10_gov003_demo.readiness_proofs from public;
grant select on c10_gov003_demo.readiness_features, c10_gov003_demo.readiness_heads,
                c10_gov003_demo.readiness_proofs to c10g3_reader, c10g3_backend;

-- ------------------------------------------------------------------------------------------ helpers
create function c10_gov003_demo._f57_is_sha40(p text) returns boolean
language sql immutable set search_path = pg_catalog
as $$ select p ~ '^[0-9a-f]{40}$' $$;

create function c10_gov003_demo._f57_is_sha256(p text) returns boolean
language sql immutable set search_path = pg_catalog
as $$ select p ~ '^[0-9a-f]{64}$' $$;

create function c10_gov003_demo._f57_gate_enabled(p_gate text) returns boolean
language sql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$ select coalesce((select g.enabled from c10_gov003_demo.real_evidence_gates g where g.gate = p_gate), false) $$;

create function c10_gov003_demo._f57_check_idem(p text) returns void
language plpgsql immutable set search_path = pg_catalog
as $$
begin
  if p is null or p !~ '^[A-Za-z0-9_.:-]{8,128}$' then
    raise exception 'validation_failed: idempotency key must be 8-128 chars of [A-Za-z0-9_.:-]' using errcode = 'G3A03';
  end if;
end $$;

create function c10_gov003_demo._f57_check_ref(p text, p_name text) returns void
language plpgsql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
begin
  if p is null or p !~ '^[A-Za-z0-9_.:/#-]{1,128}$' or c10_gov003_demo.looks_secret(p) then
    raise exception 'validation_failed: % is not an opaque reference', p_name using errcode = 'G3A03';
  end if;
end $$;

-- Actor is ALWAYS server-derived. A caller-supplied claim is only compared, never trusted.
create function c10_gov003_demo._f57_actor(p_claimed uuid, p_tenant uuid, p_business uuid, p_owner_only boolean)
returns uuid
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare a uuid := c10_gov003_demo.actor_id();
begin
  if a is null then
    raise exception 'actor_unauthenticated' using errcode = 'G3A05';
  end if;
  if p_claimed is not null and p_claimed <> a then
    raise exception 'forged_actor: caller-supplied actor does not match the server-derived actor'
      using errcode = 'G3A01';
  end if;
  if p_tenant is null or p_business is null
     or not c10_gov003_demo.scope_exists(p_tenant, p_business, null, null) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  if p_owner_only then
    if not c10_gov003_demo.can_read_business(p_tenant, p_business) then
      raise exception 'scope_denied: owner approval required' using errcode = 'G3A02';
    end if;
  elsif not c10_gov003_demo.can_write_scope(p_tenant, p_business, null) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  return a;
end $$;

create function c10_gov003_demo._f57_require_feature(p_tenant uuid, p_business uuid, p_feature text) returns void
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
begin
  if not exists (select 1 from c10_gov003_demo.readiness_features f
                  where f.tenant_id = p_tenant and f.business_id = p_business and f.feature_id = p_feature) then
    raise exception 'feature_not_registered' using errcode = 'G3C02';
  end if;
end $$;

create function c10_gov003_demo._f57_current_head(p_tenant uuid, p_business uuid, p_feature text) returns text
language sql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select h.head_sha from c10_gov003_demo.readiness_heads h
   where h.tenant_id = p_tenant and h.business_id = p_business and h.feature_id = p_feature
   order by h.head_seq desc limit 1
$$;

-- Raw proof insert shared by every path. Real-evidence gates are enforced here (fail closed).
create function c10_gov003_demo._f57_insert_proof(
  p_tenant uuid, p_business uuid, p_feature text, p_level text, p_sha text, p_env text, p_run_ref text,
  p_simulated boolean, p_evidence text, p_outcome text, p_idem text, p_actor uuid,
  p_audit_receipt uuid, p_audit_seq bigint, p_source_kind text, p_source_id uuid)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare v_gate text; v_id uuid := gen_random_uuid();
begin
  select l.gate into v_gate from c10_gov003_demo.readiness_levels l where l.level = p_level;
  if v_gate is not null and not p_simulated and not c10_gov003_demo._f57_gate_enabled(v_gate) then
    raise exception 'real_evidence_unavailable: gate % is disabled in this isolated bed (fail closed)', v_gate
      using errcode = 'G3E01';
  end if;
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.readiness_proofs
    (proof_id, tenant_id, business_id, feature_id, level, commit_sha, environment, run_ref, simulated,
     evidence_sha256, outcome, source_kind, source_id, recorded_by, idempotency_key, audit_receipt_id, audit_seq)
  values (v_id, p_tenant, p_business, p_feature, p_level, p_sha, p_env, p_run_ref, p_simulated,
     p_evidence, p_outcome, p_source_kind, p_source_id, p_actor, p_idem, p_audit_receipt, p_audit_seq);
  perform set_config('c10_gov003.writer', '', true);
  return v_id;
end $$;

-- ------------------------------------------------------------------------------------------ derivation
-- Pure derivation from proof rows. INTERNAL (no scope check): callers must authorize.
create function c10_gov003_demo._f57_derive(p_tenant uuid, p_business uuid, p_feature text) returns jsonb
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  v_head text; v_head_seq int;
  lv record; st record; v_outc text; v_simu boolean;
  sat text[] := '{}'; sim text[] := '{}'; mis text[] := '{}';
  stale jsonb := '[]'::jsonb;
  v_state text := 'proposed'; v_rank int := 1; contig boolean := true;
  txt text[] := '{}';
  stale_ci boolean := false; stale_other boolean := false; l text;
begin
  select h.head_sha, h.head_seq into v_head, v_head_seq
    from c10_gov003_demo.readiness_heads h
   where h.tenant_id = p_tenant and h.business_id = p_business and h.feature_id = p_feature
   order by h.head_seq desc limit 1;

  for lv in select rl.level as lvl, rl.rank as rnk from c10_gov003_demo.readiness_levels rl
             where rl.rank >= 2 order by rl.rank loop
    v_outc := null; v_simu := null;
    if v_head is not null then
      select p.outcome, p.simulated into v_outc, v_simu
        from c10_gov003_demo.readiness_proofs p
       where p.tenant_id = p_tenant and p.business_id = p_business and p.feature_id = p_feature
         and p.level = lv.lvl and p.commit_sha = v_head
       order by p.audit_seq desc, p.proof_seq desc limit 1;
    end if;
    if v_outc = 'pass' then
      sat := array_append(sat, lv.lvl);
      if v_simu then sim := array_append(sim, lv.lvl); end if;
      if contig then v_state := lv.lvl; v_rank := lv.rnk; end if;
    else
      mis := array_append(mis, lv.lvl);
      contig := false;
      if v_head is not null then
        for st in
          select x.commit_sha as csha, x.outcome as outc from (
            select distinct on (p.commit_sha) p.commit_sha, p.outcome
              from c10_gov003_demo.readiness_proofs p
             where p.tenant_id = p_tenant and p.business_id = p_business and p.feature_id = p_feature
               and p.level = lv.lvl and p.commit_sha <> v_head
             order by p.commit_sha, p.audit_seq desc, p.proof_seq desc) x
          order by x.commit_sha collate "C"
        loop
          if st.outc = 'pass' then
            stale := stale || jsonb_build_array(jsonb_build_object('level', lv.lvl, 'commit_sha', st.csha));
            if lv.lvl in ('code_built', 'isolated_test_pass') then stale_ci := true; else stale_other := true; end if;
          end if;
        end loop;
      end if;
    end if;
  end loop;

  if v_state <> 'released' then txt := array_append(txt, 'not certified'::text); end if;
  if v_head is null then txt := array_append(txt, 'head not registered'::text); end if;
  if stale_ci then txt := array_append(txt, 'stale CI'::text); end if;
  if stale_other then txt := array_append(txt, 'stale evidence'::text); end if;
  if not ('isolated_test_pass' = any (sat)) and not stale_ci then txt := array_append(txt, 'isolated tests missing'::text); end if;
  if not ('signed_stage_verified' = any (sat)) then txt := array_append(txt, 'staging missing'::text); end if;
  if not ('integrated_verified' = any (sat)) then txt := array_append(txt, 'integration missing'::text); end if;
  if not ('deployed_verified' = any (sat)) then txt := array_append(txt, 'deployment unverified'::text); end if;
  if not ('released' = any (sat)) then txt := array_append(txt, 'release not approved'::text); end if;
  if coalesce(array_length(sat, 1), 0) > 0 and sat <@ sim then txt := array_append(txt, 'simulation only'::text); end if;

  return jsonb_build_object(
    'feature_id', p_feature,
    'current_head_sha', v_head,
    'head_seq', v_head_seq,
    'state', v_state,
    'state_rank', v_rank,
    'satisfied_levels', to_jsonb(sat),
    'missing_proofs', to_jsonb(mis),
    'stale', stale,
    'simulated_levels', to_jsonb(sim),
    'certified', v_state = 'released',
    'text', to_jsonb(txt),
    'summary', array_to_string(txt, ' / '));
end $$;

-- Public read: owner-scoped. Raises scope_denied (uniform) for foreign / unauthorized callers.
create function c10_gov003_demo.derive_readiness(p_tenant uuid, p_business uuid, p_feature text) returns jsonb
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
begin
  if not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  perform c10_gov003_demo._f57_require_feature(p_tenant, p_business, p_feature);
  return c10_gov003_demo._f57_derive(p_tenant, p_business, p_feature);
end $$;

-- Stale-head validator: is this sha the CURRENT head of the feature?
create function c10_gov003_demo.readiness_head_is_current(p_tenant uuid, p_business uuid, p_feature text, p_sha text)
returns boolean
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
begin
  if not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  if not c10_gov003_demo._f57_is_sha40(p_sha) then
    raise exception 'validation_failed: sha must be 40 lowercase hex' using errcode = 'G3A03';
  end if;
  return c10_gov003_demo._f57_current_head(p_tenant, p_business, p_feature) = p_sha;
end $$;

-- ------------------------------------------------------------------------------------------ writers
create function c10_gov003_demo.register_readiness_feature(
  p_tenant uuid, p_business uuid, p_feature_id text, p_title text, p_idem text, p_claimed_actor uuid default null)
returns table (result text, audit_receipt_id uuid, replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare a uuid; rc record; v_cmd text;
begin
  a := c10_gov003_demo._f57_actor(p_claimed_actor, p_tenant, p_business, false);
  perform c10_gov003_demo._f57_check_idem(p_idem);
  perform c10_gov003_demo._f57_check_ref(p_feature_id, 'feature_id');
  if p_title is null or length(p_title) not between 1 and 200 or c10_gov003_demo.looks_secret(p_title) then
    raise exception 'validation_failed: title' using errcode = 'G3A03';
  end if;
  v_cmd := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(jsonb_build_object(
    'op', 'register_feature', 'feature_id', p_feature_id, 'title', p_title)));
  begin
    select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
      'gov003.readiness', p_feature_id, 'v1', 'readiness.feature_registered', clock_timestamp(), p_idem, p_idem,
      jsonb_build_object('feature_id', p_feature_id, 'note_code', 'feature_registered', 'doc_ref', 'cmd:' || v_cmd),
      null, 'readiness', 1, null, null);
    if rc.replayed then
      return query select 'replayed'::text, rc.receipt_id, true;
      return;
    end if;
    perform set_config('c10_gov003.writer', 'append_path', true);
    insert into c10_gov003_demo.readiness_features
      (tenant_id, business_id, feature_id, title, registered_by, idempotency_key, audit_receipt_id)
    values (p_tenant, p_business, p_feature_id, p_title, a, p_idem, rc.receipt_id);
    perform set_config('c10_gov003.writer', '', true);
    return query select 'created'::text, rc.receipt_id, false;
  exception when unique_violation then
    raise exception 'conflict: feature already registered' using errcode = 'G3C01';
  end;
end $$;

-- Register the feature's CURRENT head sha (source HEAD). Older proofs become stale the moment it moves.
create function c10_gov003_demo.record_readiness_head(
  p_tenant uuid, p_business uuid, p_feature_id text, p_head_sha text, p_idem text, p_claimed_actor uuid default null)
returns table (result text, head_seq int, audit_receipt_id uuid, replayed boolean, readiness jsonb)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare a uuid; rc record; v_cmd text; v_seq int; v_cur text; ex record;
begin
  a := c10_gov003_demo._f57_actor(p_claimed_actor, p_tenant, p_business, false);
  perform c10_gov003_demo._f57_check_idem(p_idem);
  perform c10_gov003_demo._f57_check_ref(p_feature_id, 'feature_id');
  if not c10_gov003_demo._f57_is_sha40(p_head_sha) then
    raise exception 'validation_failed: head sha must be 40 lowercase hex' using errcode = 'G3A03';
  end if;
  perform c10_gov003_demo._f57_require_feature(p_tenant, p_business, p_feature_id);
  v_cmd := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(jsonb_build_object(
    'op', 'record_head', 'feature_id', p_feature_id, 'head_sha', p_head_sha)));
  begin
    select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
      'gov003.readiness', p_feature_id, 'v1', 'readiness.head_recorded', clock_timestamp(), p_idem, p_idem,
      jsonb_build_object('feature_id', p_feature_id, 'commit_sha', p_head_sha, 'doc_ref', 'cmd:' || v_cmd),
      null, 'readiness', 1, null, null);
    if rc.replayed then
      select h.head_seq as hs into ex from c10_gov003_demo.readiness_heads h
       where h.tenant_id = p_tenant and h.business_id = p_business and h.idempotency_key = p_idem;
      return query select 'replayed'::text, ex.hs, rc.receipt_id, true,
        c10_gov003_demo._f57_derive(p_tenant, p_business, p_feature_id);
      return;
    end if;
    v_cur := c10_gov003_demo._f57_current_head(p_tenant, p_business, p_feature_id);
    if v_cur = p_head_sha then
      raise exception 'conflict: head unchanged' using errcode = 'G3C01';
    end if;
    select coalesce(max(h.head_seq), 0) + 1 into v_seq from c10_gov003_demo.readiness_heads h
     where h.tenant_id = p_tenant and h.business_id = p_business and h.feature_id = p_feature_id;
    perform set_config('c10_gov003.writer', 'append_path', true);
    insert into c10_gov003_demo.readiness_heads
      (tenant_id, business_id, feature_id, head_seq, head_sha, recorded_by, idempotency_key, audit_receipt_id)
    values (p_tenant, p_business, p_feature_id, v_seq, p_head_sha, a, p_idem, rc.receipt_id);
    perform set_config('c10_gov003.writer', '', true);
    return query select 'created'::text, v_seq, rc.receipt_id, false,
      c10_gov003_demo._f57_derive(p_tenant, p_business, p_feature_id);
  exception when unique_violation then
    raise exception 'conflict: head already recorded' using errcode = 'G3C01';
  end;
end $$;

-- Generic proof writer for code_built / isolated_test_pass / signed_stage_verified / integrated_verified.
-- deployed_verified and released have dedicated, stricter paths (070 certify_deployment / approve_release).
create function c10_gov003_demo.record_readiness_proof(
  p_tenant uuid, p_business uuid, p_feature_id text, p_level text, p_commit_sha text, p_environment text,
  p_run_ref text, p_simulated boolean, p_evidence_sha256 text, p_outcome text, p_idem text,
  p_claimed_actor uuid default null)
returns table (result text, proof_id uuid, audit_receipt_id uuid, replayed boolean, readiness jsonb)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare a uuid; rc record; v_cmd text; v_id uuid; ex record;
begin
  a := c10_gov003_demo._f57_actor(p_claimed_actor, p_tenant, p_business, false);
  perform c10_gov003_demo._f57_check_idem(p_idem);
  perform c10_gov003_demo._f57_check_ref(p_feature_id, 'feature_id');
  perform c10_gov003_demo._f57_check_ref(p_run_ref, 'run_ref');
  if p_level is null or p_level not in ('code_built','isolated_test_pass','signed_stage_verified','integrated_verified') then
    raise exception 'validation_failed: level requires a dedicated path or is unknown' using errcode = 'G3A03';
  end if;
  if not c10_gov003_demo._f57_is_sha40(p_commit_sha) or not c10_gov003_demo._f57_is_sha256(p_evidence_sha256) then
    raise exception 'validation_failed: commit sha (40 hex) and evidence sha256 (64 hex) required' using errcode = 'G3A03';
  end if;
  if p_environment is null or p_simulated is null or p_outcome is null or p_outcome not in ('pass','fail') then
    raise exception 'validation_failed: environment, simulated flag and outcome required' using errcode = 'G3A03';
  end if;
  perform c10_gov003_demo._f57_require_feature(p_tenant, p_business, p_feature_id);
  v_cmd := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(jsonb_build_object(
    'op', 'record_proof', 'feature_id', p_feature_id, 'level', p_level, 'commit_sha', p_commit_sha,
    'environment', p_environment, 'run_ref', p_run_ref, 'simulated', p_simulated,
    'evidence_sha256', p_evidence_sha256, 'outcome', p_outcome)));
  begin
    select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
      'gov003.readiness', p_feature_id, 'v1', 'readiness.proof_recorded', clock_timestamp(), p_idem, p_idem,
      jsonb_build_object('feature_id', p_feature_id, 'commit_sha', p_commit_sha, 'new_status', p_level,
        'detail_code', p_environment, 'method', case when p_simulated then 'simulated' else 'real' end,
        'status', p_outcome, 'source_ref', p_run_ref, 'evidence_ref', p_evidence_sha256, 'doc_ref', 'cmd:' || v_cmd),
      null, 'readiness', 1, null, null);
    if rc.replayed then
      select p.proof_id as pid into ex from c10_gov003_demo.readiness_proofs p
       where p.tenant_id = p_tenant and p.business_id = p_business and p.idempotency_key = p_idem
         and p.level = p_level;
      return query select 'replayed'::text, ex.pid, rc.receipt_id, true,
        c10_gov003_demo._f57_derive(p_tenant, p_business, p_feature_id);
      return;
    end if;
    v_id := c10_gov003_demo._f57_insert_proof(p_tenant, p_business, p_feature_id, p_level, p_commit_sha,
      p_environment, p_run_ref, p_simulated, p_evidence_sha256, p_outcome, p_idem, a,
      rc.receipt_id, rc.stream_seq, null, null);
    return query select 'created'::text, v_id, rc.receipt_id, false,
      c10_gov003_demo._f57_derive(p_tenant, p_business, p_feature_id);
  exception when unique_violation then
    raise exception 'conflict: proof already recorded' using errcode = 'G3C01';
  end;
end $$;

-- Owner approval. Only reachable when every lower level is satisfied for the CURRENT head and the deployed
-- proof is a PRODUCTION runtime proof. Fail-closed in this bed (real gates disabled), by design.
create function c10_gov003_demo.approve_release(
  p_tenant uuid, p_business uuid, p_feature_id text, p_commit_sha text, p_run_ref text,
  p_evidence_sha256 text, p_idem text, p_claimed_actor uuid default null)
returns table (result text, proof_id uuid, audit_receipt_id uuid, replayed boolean, readiness jsonb)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare a uuid; rc record; v_cmd text; v_id uuid; ex record; d jsonb; v_head text; v_env text; v_missing text[];
begin
  a := c10_gov003_demo._f57_actor(p_claimed_actor, p_tenant, p_business, true);
  perform c10_gov003_demo._f57_check_idem(p_idem);
  perform c10_gov003_demo._f57_check_ref(p_feature_id, 'feature_id');
  perform c10_gov003_demo._f57_check_ref(p_run_ref, 'run_ref');
  if not c10_gov003_demo._f57_is_sha40(p_commit_sha) or not c10_gov003_demo._f57_is_sha256(p_evidence_sha256) then
    raise exception 'validation_failed: commit sha (40 hex) and evidence sha256 (64 hex) required' using errcode = 'G3A03';
  end if;
  perform c10_gov003_demo._f57_require_feature(p_tenant, p_business, p_feature_id);
  v_cmd := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(jsonb_build_object(
    'op', 'approve_release', 'feature_id', p_feature_id, 'commit_sha', p_commit_sha,
    'run_ref', p_run_ref, 'evidence_sha256', p_evidence_sha256)));
  begin
    select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
      'gov003.readiness', p_feature_id, 'v1', 'readiness.release_approved', clock_timestamp(), p_idem, p_idem,
      jsonb_build_object('feature_id', p_feature_id, 'commit_sha', p_commit_sha, 'new_status', 'released',
        'detail_code', 'production', 'method', 'owner_approval', 'status', 'pass',
        'source_ref', p_run_ref, 'evidence_ref', p_evidence_sha256, 'doc_ref', 'cmd:' || v_cmd),
      null, 'readiness', 1, null, null);
    if rc.replayed then
      select p.proof_id as pid into ex from c10_gov003_demo.readiness_proofs p
       where p.tenant_id = p_tenant and p.business_id = p_business and p.idempotency_key = p_idem
         and p.level = 'released';
      return query select 'replayed'::text, ex.pid, rc.receipt_id, true,
        c10_gov003_demo._f57_derive(p_tenant, p_business, p_feature_id);
      return;
    end if;
    v_head := c10_gov003_demo._f57_current_head(p_tenant, p_business, p_feature_id);
    if v_head is distinct from p_commit_sha then
      raise exception 'stale_head: release must bind the CURRENT head sha' using errcode = 'G3C01';
    end if;
    d := c10_gov003_demo._f57_derive(p_tenant, p_business, p_feature_id);
    select array_agg(m) into v_missing from jsonb_array_elements_text(d -> 'missing_proofs') m where m <> 'released';
    if v_missing is not null then
      raise exception 'release_prerequisites_missing: %', array_to_string(v_missing, ',') using errcode = 'G3C02';
    end if;
    select p.environment as env into v_env from c10_gov003_demo.readiness_proofs p
     where p.tenant_id = p_tenant and p.business_id = p_business and p.feature_id = p_feature_id
       and p.level = 'deployed_verified' and p.commit_sha = v_head
     order by p.audit_seq desc, p.proof_seq desc limit 1;
    if v_env is distinct from 'production' then
      raise exception 'release_prerequisites_missing: a production runtime proof is required' using errcode = 'G3C02';
    end if;
    v_id := c10_gov003_demo._f57_insert_proof(p_tenant, p_business, p_feature_id, 'released', p_commit_sha,
      'production', p_run_ref, false, p_evidence_sha256, 'pass', p_idem, a, rc.receipt_id, rc.stream_seq,
      'owner_release', gen_random_uuid());
    return query select 'created'::text, v_id, rc.receipt_id, false,
      c10_gov003_demo._f57_derive(p_tenant, p_business, p_feature_id);
  exception when unique_violation then
    raise exception 'conflict: release already recorded' using errcode = 'G3C01';
  end;
end $$;

-- ------------------------------------------------------------------------------------------ read views
create view c10_gov003_demo.v_readiness_heads with (security_invoker = true) as
  select h.tenant_id, h.business_id, h.feature_id, h.head_seq, h.head_sha, h.recorded_by, h.recorded_at,
         h.audit_receipt_id
    from c10_gov003_demo.readiness_heads h;

create view c10_gov003_demo.v_readiness_proofs with (security_invoker = true) as
  select p.proof_id, p.proof_seq, p.tenant_id, p.business_id, p.feature_id, p.level, p.commit_sha,
         p.environment, p.run_ref, p.simulated, p.evidence_sha256, p.outcome, p.source_kind, p.source_id,
         p.recorded_by, p.recorded_at, p.audit_receipt_id, p.audit_seq,
         (p.commit_sha = (select h.head_sha from c10_gov003_demo.readiness_heads h
                           where h.tenant_id = p.tenant_id and h.business_id = p.business_id
                             and h.feature_id = p.feature_id
                           order by h.head_seq desc limit 1)) as is_current_head
    from c10_gov003_demo.readiness_proofs p;

create view c10_gov003_demo.v_readiness_features with (security_invoker = true) as
  select f.tenant_id, f.business_id, f.feature_id, f.title, f.registered_at,
         c10_gov003_demo.derive_readiness(f.tenant_id, f.business_id, f.feature_id) as readiness
    from c10_gov003_demo.readiness_features f;

revoke all on c10_gov003_demo.v_readiness_heads, c10_gov003_demo.v_readiness_proofs,
              c10_gov003_demo.v_readiness_features from public;
grant select on c10_gov003_demo.v_readiness_heads, c10_gov003_demo.v_readiness_proofs,
                c10_gov003_demo.v_readiness_features to c10g3_reader, c10g3_backend;

-- ------------------------------------------------------------------------------------------ grants
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname as nm
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'c10_gov003_demo'
       and p.proname = any (array[
         '_f57_proof_guard','_f57_is_sha40','_f57_is_sha256','_f57_gate_enabled','_f57_check_idem',
         '_f57_check_ref','_f57_actor','_f57_require_feature','_f57_current_head','_f57_insert_proof',
         '_f57_derive','derive_readiness','readiness_head_is_current','register_readiness_feature',
         'record_readiness_head','record_readiness_proof','approve_release'])
  loop
    execute format('revoke all on function %s from public', r.sig);
    if r.nm in ('register_readiness_feature','record_readiness_head','record_readiness_proof','approve_release') then
      execute format('grant execute on function %s to c10g3_backend', r.sig);
    elsif r.nm in ('derive_readiness','readiness_head_is_current') then
      execute format('grant execute on function %s to c10g3_backend, c10g3_reader', r.sig);
    end if;
  end loop;
end $$;
