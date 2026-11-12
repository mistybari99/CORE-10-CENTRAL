-- 06 exact-commit-ci-receipts: receipt schema, SHA / CI-run validation, stale-head validator, immutable
-- evidence reference. DEMO / NOT LIVE.
--
-- TRUST MODEL (stated on purpose):
--   * A receipt is recorded as origin = 'offline_fixture' and reads `offline_fixture/unverified`.
--   * A caller-supplied GitHub URL is NEVER certification: the URL is only pattern-validated.
--   * A receipt becomes `offline_fixture/simulated_verified` only when a verification record from the
--     SIMULATED adapter matches it; `remote_verified` needs the github_api adapter, whose gate
--     (real_evidence_gates.github_remote) is DISABLED here, so remote verification is fail-closed.
--   * Observation authenticity for a future real adapter rests on the trusted c10g3_backend boundary; SQL
--     compares a supplied observation to the receipt, it cannot itself call GitHub.
--   * A CI receipt can only ever back code_built / isolated_test_pass (never signed, integrated, deployed,
--     released), and only the receipt's own head sha: an old SHA pass is recorded but stays stale.
-- Evidence reference = sha256(canonical_json(receipt)); byte-identical to ci-receipt.mjs buildReceipt().
\set ON_ERROR_STOP on
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

create table c10_gov003_demo.ci_trusted_repos (
  repo_full text primary key check (repo_full = lower(repo_full) and repo_full ~ '^[a-z0-9][a-z0-9-]{0,38}/[a-z0-9._-]{1,100}$')
);
insert into c10_gov003_demo.ci_trusted_repos (repo_full) values ('mistybari99/core-10-central');
alter table c10_gov003_demo.ci_trusted_repos enable row level security;
revoke all on c10_gov003_demo.ci_trusted_repos from public;

create table c10_gov003_demo.ci_receipts (
  receipt_id      uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null,
  business_id     uuid not null,
  feature_id      text not null,
  repo_full       text not null check (repo_full = lower(repo_full)),
  workflow        text not null check (workflow ~ '^[A-Za-z0-9][A-Za-z0-9 _.()/-]{0,99}$'),
  run_id          text not null check (run_id ~ '^[0-9]{1,18}$'),
  run_attempt     int  not null check (run_attempt between 1 and 999),
  run_url         text not null check (run_url ~ '^https://github\.com/[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}/actions/runs/[0-9]{1,18}$'),
  head_sha        text not null check (head_sha ~ '^[0-9a-f]{40}$'),
  run_status      text not null check (run_status in ('queued','in_progress','completed')),
  conclusion      text check (conclusion in ('success','failure','cancelled','skipped','neutral','timed_out','action_required')),
  environment     text not null check (environment in
                    ('local','isolated_pg','ci_isolated','staging_signed','integration','staging','production')),
  origin          text not null default 'offline_fixture' check (origin = 'offline_fixture'),
  receipt_json    jsonb not null,
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  recorded_by     uuid not null references c10_gov003_demo.identities,
  recorded_at     timestamptz not null default clock_timestamp(),
  idempotency_key text not null,
  audit_receipt_id uuid not null references c10_gov003_demo.audit_receipts,
  audit_seq       bigint not null,
  check ((run_status = 'completed') = (conclusion is not null)),
  unique (tenant_id, business_id, receipt_id),
  unique (tenant_id, business_id, idempotency_key),
  unique nulls not distinct (tenant_id, business_id, repo_full, run_id, run_attempt, head_sha, run_status, conclusion),
  foreign key (tenant_id, business_id, feature_id) references c10_gov003_demo.readiness_features
);

create table c10_gov003_demo.ci_receipt_verifications (
  verification_id uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null,
  business_id     uuid not null,
  receipt_id      uuid not null,
  verifier_kind   text not null check (verifier_kind in ('simulated_fixture','github_api')),
  observation     jsonb not null,
  remote_payload_sha256 text not null check (remote_payload_sha256 ~ '^[0-9a-f]{64}$'),
  observed_at     timestamptz not null,
  recorded_by     uuid not null references c10_gov003_demo.identities,
  recorded_at     timestamptz not null default clock_timestamp(),
  idempotency_key text not null,
  audit_receipt_id uuid not null references c10_gov003_demo.audit_receipts,
  unique (tenant_id, business_id, idempotency_key),
  foreign key (tenant_id, business_id, receipt_id) references c10_gov003_demo.ci_receipts (tenant_id, business_id, receipt_id)
);
create index ci_receipt_verifications_receipt_idx on c10_gov003_demo.ci_receipt_verifications (tenant_id, business_id, receipt_id);

select c10_gov003_demo.protect_table('c10_gov003_demo.ci_receipts');
select c10_gov003_demo.protect_table('c10_gov003_demo.ci_receipt_verifications');
alter table c10_gov003_demo.ci_receipts enable row level security;
alter table c10_gov003_demo.ci_receipt_verifications enable row level security;
create policy ci_receipts_read on c10_gov003_demo.ci_receipts for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
create policy ci_receipt_verifications_read on c10_gov003_demo.ci_receipt_verifications for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
revoke all on c10_gov003_demo.ci_receipts, c10_gov003_demo.ci_receipt_verifications from public;
grant select on c10_gov003_demo.ci_receipts, c10_gov003_demo.ci_receipt_verifications to c10g3_reader, c10g3_backend;

-- Receipt trust: unverified | simulated_verified | verified (never inferred from the caller's URL).
create function c10_gov003_demo._f57_ci_trust(p_tenant uuid, p_business uuid, p_receipt uuid) returns text
language sql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select case
    when exists (select 1 from c10_gov003_demo.ci_receipt_verifications v
                  where v.tenant_id = p_tenant and v.business_id = p_business and v.receipt_id = p_receipt
                    and v.verifier_kind = 'github_api') then 'verified'
    when exists (select 1 from c10_gov003_demo.ci_receipt_verifications v
                  where v.tenant_id = p_tenant and v.business_id = p_business and v.receipt_id = p_receipt
                    and v.verifier_kind = 'simulated_fixture') then 'simulated_verified'
    else 'unverified' end
$$;

create function c10_gov003_demo._f57_trust_label(p_trust text) returns text
language sql immutable set search_path = pg_catalog
as $$ select case p_trust when 'verified' then 'remote_verified'
                          when 'simulated_verified' then 'offline_fixture/simulated_verified'
                          else 'offline_fixture/unverified' end $$;

-- ------------------------------------------------------------------------------------------ writers
create function c10_gov003_demo.record_ci_receipt(
  p_tenant uuid, p_business uuid, p_feature_id text, p_workflow text, p_run_id text, p_run_url text,
  p_head_sha text, p_run_status text, p_conclusion text, p_environment text, p_run_attempt int,
  p_idem text, p_claimed_actor uuid default null)
returns table (result text, receipt_id uuid, evidence_sha256 text, audit_receipt_id uuid, replayed boolean,
               trust_label text, head_is_current boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  a uuid; rc record; ex record; m text[]; v_repo text; v_json jsonb; v_ev text; v_cmd text; v_id uuid := gen_random_uuid();
  v_attempt int := coalesce(p_run_attempt, 1); v_cur text; v_payload jsonb;
begin
  a := c10_gov003_demo._f57_actor(p_claimed_actor, p_tenant, p_business, false);
  perform c10_gov003_demo._f57_check_idem(p_idem);
  perform c10_gov003_demo._f57_check_ref(p_feature_id, 'feature_id');
  if not c10_gov003_demo._f57_is_sha40(p_head_sha) then
    raise exception 'validation_failed: head sha must be 40 lowercase hex' using errcode = 'G3A03';
  end if;
  if p_run_id is null or p_run_id !~ '^[0-9]{1,18}$' then
    raise exception 'validation_failed: run id must be numeric' using errcode = 'G3A03';
  end if;
  if p_workflow is null or p_workflow !~ '^[A-Za-z0-9][A-Za-z0-9 _.()/-]{0,99}$' then
    raise exception 'validation_failed: workflow name' using errcode = 'G3A03';
  end if;
  if p_run_status is null or p_run_status not in ('queued','in_progress','completed')
     or (p_run_status = 'completed') <> (p_conclusion is not null)
     or (p_conclusion is not null and p_conclusion not in
         ('success','failure','cancelled','skipped','neutral','timed_out','action_required')) then
    raise exception 'validation_failed: run status/conclusion' using errcode = 'G3A03';
  end if;
  if p_environment is null or p_environment not in
       ('local','isolated_pg','ci_isolated','staging_signed','integration','staging','production') then
    raise exception 'validation_failed: environment' using errcode = 'G3A03';
  end if;
  if v_attempt not between 1 and 999 then
    raise exception 'validation_failed: run attempt' using errcode = 'G3A03';
  end if;
  -- CI run URL contract: https://github.com/<owner>/<repo>/actions/runs/<id>, nothing else.
  m := regexp_match(coalesce(p_run_url, ''),
         '^https://github\.com/([A-Za-z0-9][A-Za-z0-9-]{0,38})/([A-Za-z0-9._-]{1,100})/actions/runs/([0-9]{1,18})$');
  if m is null then
    raise exception 'validation_failed: run url does not match the GitHub Actions run pattern' using errcode = 'G3A03';
  end if;
  if m[3] <> p_run_id then
    raise exception 'validation_failed: run url id does not match run id' using errcode = 'G3A03';
  end if;
  v_repo := lower(m[1] || '/' || m[2]);
  if not exists (select 1 from c10_gov003_demo.ci_trusted_repos t where t.repo_full = v_repo) then
    raise exception 'validation_failed: repository is not a trusted source for this module' using errcode = 'G3A03';
  end if;
  perform c10_gov003_demo._f57_require_feature(p_tenant, p_business, p_feature_id);

  v_json := jsonb_build_object('conclusion', p_conclusion, 'environment', p_environment,
    'feature_id', p_feature_id, 'head_sha', p_head_sha, 'repo', v_repo, 'run_attempt', v_attempt::text,
    'run_id', p_run_id, 'run_status', p_run_status, 'run_url', p_run_url, 'workflow', p_workflow);
  v_ev := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(v_json));
  v_cmd := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(
             jsonb_build_object('op', 'record_ci_receipt', 'receipt', v_json)));
  v_payload := jsonb_build_object('feature_id', p_feature_id, 'commit_sha', p_head_sha, 'evidence_ref', v_ev,
    'source_ref', 'gh-run-' || p_run_id, 'detail_code', p_environment, 'method', 'offline_fixture',
    'status', p_run_status, 'doc_ref', 'cmd:' || v_cmd);
  if p_conclusion is not null then v_payload := v_payload || jsonb_build_object('new_status', p_conclusion); end if;
  begin
    select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
      'gov003.ci', 'gh-run-' || p_run_id, 'v1', 'ci.receipt_recorded', clock_timestamp(), p_idem, p_idem,
      v_payload, null, 'readiness', 1, null, null);
    v_cur := c10_gov003_demo._f57_current_head(p_tenant, p_business, p_feature_id);
    if rc.replayed then
      select c.receipt_id as rid, c.evidence_sha256 as ev into ex from c10_gov003_demo.ci_receipts c
       where c.tenant_id = p_tenant and c.business_id = p_business and c.idempotency_key = p_idem;
      return query select 'replayed'::text, ex.rid, ex.ev, rc.receipt_id, true,
        c10_gov003_demo._f57_trust_label(c10_gov003_demo._f57_ci_trust(p_tenant, p_business, ex.rid)),
        (v_cur = p_head_sha);
      return;
    end if;
    perform set_config('c10_gov003.writer', 'append_path', true);
    insert into c10_gov003_demo.ci_receipts
      (receipt_id, tenant_id, business_id, feature_id, repo_full, workflow, run_id, run_attempt, run_url,
       head_sha, run_status, conclusion, environment, receipt_json, evidence_sha256, recorded_by,
       idempotency_key, audit_receipt_id, audit_seq)
    values (v_id, p_tenant, p_business, p_feature_id, v_repo, p_workflow, p_run_id, v_attempt, p_run_url,
       p_head_sha, p_run_status, p_conclusion, p_environment, v_json, v_ev, a, p_idem, rc.receipt_id, rc.stream_seq);
    perform set_config('c10_gov003.writer', '', true);
    return query select 'created'::text, v_id, v_ev, rc.receipt_id, false,
      'offline_fixture/unverified'::text, (v_cur = p_head_sha);
  exception when unique_violation then
    raise exception 'conflict: this CI run/sha receipt is already recorded' using errcode = 'G3C01';
  end;
end $$;

-- Remote verification record. `p_observation` is what a remote verifier adapter observed. It is compared with
-- the receipt: ANY mismatch is rejected (nothing is stored). github_api needs the github_remote gate (closed).
create function c10_gov003_demo.verify_ci_receipt(
  p_tenant uuid, p_business uuid, p_receipt_id uuid, p_verifier_kind text, p_observation jsonb,
  p_idem text, p_claimed_actor uuid default null)
returns table (result text, verification_id uuid, trust_label text, audit_receipt_id uuid, replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  a uuid; rc record; ex record; r record; o jsonb; v_sha text; v_cmd text; v_id uuid := gen_random_uuid();
  mism text[] := '{}'; v_obs_at timestamptz; k text;
begin
  a := c10_gov003_demo._f57_actor(p_claimed_actor, p_tenant, p_business, false);
  perform c10_gov003_demo._f57_check_idem(p_idem);
  if p_verifier_kind is null or p_verifier_kind not in ('simulated_fixture','github_api') then
    raise exception 'validation_failed: verifier kind' using errcode = 'G3A03';
  end if;
  if p_verifier_kind = 'github_api' and not c10_gov003_demo._f57_gate_enabled('github_remote') then
    raise exception 'real_evidence_unavailable: remote GitHub verifier adapter is not available (fail closed)'
      using errcode = 'G3E01';
  end if;
  if p_observation is null or jsonb_typeof(p_observation) <> 'object' or length(p_observation::text) > 4000 then
    raise exception 'validation_failed: observation must be a bounded object' using errcode = 'G3A03';
  end if;
  for k in select jsonb_object_keys(p_observation) loop
    if k not in ('repo','run_id','run_url','head_sha','workflow','run_status','conclusion','observed_at') then
      raise exception 'validation_failed: unexpected observation field' using errcode = 'G3A03';
    end if;
  end loop;
  o := p_observation;
  if coalesce(o ->> 'head_sha', '') !~ '^[0-9a-f]{40}$' or coalesce(o ->> 'run_id', '') !~ '^[0-9]{1,18}$'
     or coalesce(o ->> 'observed_at', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$'
     or coalesce(o ->> 'run_status', '') not in ('queued','in_progress','completed') then
    raise exception 'validation_failed: observation shape' using errcode = 'G3A03';
  end if;
  v_obs_at := (o ->> 'observed_at')::timestamptz;
  select c.* into r from c10_gov003_demo.ci_receipts c
   where c.tenant_id = p_tenant and c.business_id = p_business and c.receipt_id = p_receipt_id;
  if not found then
    raise exception 'receipt_not_found' using errcode = 'G3C02';
  end if;
  v_sha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(o));
  v_cmd := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(jsonb_build_object(
    'op', 'verify_ci_receipt', 'receipt_id', p_receipt_id::text, 'kind', p_verifier_kind, 'observation', o)));
  begin
    select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
      'gov003.ci', 'gh-run-' || r.run_id, 'v1', 'ci.receipt_verified', clock_timestamp(), p_idem, p_idem,
      jsonb_build_object('feature_id', r.feature_id, 'commit_sha', r.head_sha, 'receipt_ref', p_receipt_id::text,
        'evidence_ref', v_sha, 'method', p_verifier_kind, 'status', 'verified', 'doc_ref', 'cmd:' || v_cmd),
      null, 'readiness', 1, null, null);
    if rc.replayed then
      select v.verification_id as vid into ex from c10_gov003_demo.ci_receipt_verifications v
       where v.tenant_id = p_tenant and v.business_id = p_business and v.idempotency_key = p_idem;
      return query select 'replayed'::text, ex.vid,
        c10_gov003_demo._f57_trust_label(c10_gov003_demo._f57_ci_trust(p_tenant, p_business, p_receipt_id)),
        rc.receipt_id, true;
      return;
    end if;
    if lower(coalesce(o ->> 'repo', '')) <> r.repo_full then mism := array_append(mism, 'repo_mismatch'); end if;
    if o ->> 'run_id' <> r.run_id then mism := array_append(mism, 'run_id_mismatch'); end if;
    if o ->> 'run_url' is distinct from r.run_url then mism := array_append(mism, 'run_url_mismatch'); end if;
    if o ->> 'head_sha' <> r.head_sha then mism := array_append(mism, 'head_sha_mismatch'); end if;
    if o ->> 'workflow' is distinct from r.workflow then mism := array_append(mism, 'workflow_mismatch'); end if;
    if o ->> 'run_status' <> r.run_status then mism := array_append(mism, 'run_status_mismatch'); end if;
    if o ->> 'conclusion' is distinct from r.conclusion then mism := array_append(mism, 'conclusion_mismatch'); end if;
    if array_length(mism, 1) > 0 then
      raise exception 'remote_mismatch: %', array_to_string(mism, ',') using errcode = 'G3C02';
    end if;
    perform set_config('c10_gov003.writer', 'append_path', true);
    insert into c10_gov003_demo.ci_receipt_verifications
      (verification_id, tenant_id, business_id, receipt_id, verifier_kind, observation, remote_payload_sha256,
       observed_at, recorded_by, idempotency_key, audit_receipt_id)
    values (v_id, p_tenant, p_business, p_receipt_id, p_verifier_kind, o, v_sha, v_obs_at, a, p_idem, rc.receipt_id);
    perform set_config('c10_gov003.writer', '', true);
    return query select 'created'::text, v_id,
      c10_gov003_demo._f57_trust_label(c10_gov003_demo._f57_ci_trust(p_tenant, p_business, p_receipt_id)),
      rc.receipt_id, false;
  exception when unique_violation then
    raise exception 'conflict: verification already recorded' using errcode = 'G3C01';
  end;
end $$;

-- Update delivery truth: bind a COMPLETED, remote/simulated-VERIFIED isolated-CI receipt to readiness proofs.
-- The proofs bind the receipt's OWN head sha, so an old-SHA pass is recorded but stays stale (never reused).
create function c10_gov003_demo.bind_ci_receipt_to_readiness(
  p_tenant uuid, p_business uuid, p_receipt_id uuid, p_idem text, p_claimed_actor uuid default null)
returns table (result text, proof_ids uuid[], audit_receipt_id uuid, replayed boolean,
               head_is_current boolean, readiness jsonb)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  a uuid; rc record; r record; v_trust text; v_sim boolean; v_cmd text; v_ids uuid[] := '{}'; v_out text;
  v_cur text; ex uuid[];
begin
  a := c10_gov003_demo._f57_actor(p_claimed_actor, p_tenant, p_business, false);
  perform c10_gov003_demo._f57_check_idem(p_idem);
  select c.* into r from c10_gov003_demo.ci_receipts c
   where c.tenant_id = p_tenant and c.business_id = p_business and c.receipt_id = p_receipt_id;
  if not found then
    raise exception 'receipt_not_found' using errcode = 'G3C02';
  end if;
  v_trust := c10_gov003_demo._f57_ci_trust(p_tenant, p_business, p_receipt_id);
  v_cmd := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(jsonb_build_object(
    'op', 'bind_ci_receipt', 'receipt_id', p_receipt_id::text)));
  begin
    select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
      'gov003.ci', 'gh-run-' || r.run_id, 'v1', 'ci.receipt_bound', clock_timestamp(), p_idem, p_idem,
      jsonb_build_object('feature_id', r.feature_id, 'commit_sha', r.head_sha, 'receipt_ref', p_receipt_id::text,
        'evidence_ref', r.evidence_sha256, 'status', 'bound', 'doc_ref', 'cmd:' || v_cmd),
      null, 'readiness', 1, null, null);
    v_cur := c10_gov003_demo._f57_current_head(p_tenant, p_business, r.feature_id);
    if rc.replayed then
      select array_agg(p.proof_id order by p.level) into ex from c10_gov003_demo.readiness_proofs p
       where p.tenant_id = p_tenant and p.business_id = p_business and p.idempotency_key = p_idem;
      return query select 'replayed'::text, ex, rc.receipt_id, true, (v_cur = r.head_sha),
        c10_gov003_demo._f57_derive(p_tenant, p_business, r.feature_id);
      return;
    end if;
    if r.run_status <> 'completed' then
      raise exception 'ci_not_completed: queued or in-progress CI is not evidence' using errcode = 'G3C02';
    end if;
    if r.environment not in ('ci_isolated','isolated_pg') then
      raise exception 'ci_receipt_cannot_certify: a CI receipt can only back isolated levels' using errcode = 'G3C02';
    end if;
    if v_trust = 'unverified' then
      raise exception 'receipt_unverified: an offline_fixture/unverified receipt (e.g. a caller-supplied URL) is not certification'
        using errcode = 'G3C02';
    end if;
    v_sim := v_trust <> 'verified';
    v_out := case when r.conclusion = 'success' then 'pass' else 'fail' end;
    if v_out = 'pass' then
      v_ids := array_append(v_ids, c10_gov003_demo._f57_insert_proof(p_tenant, p_business, r.feature_id,
        'code_built', r.head_sha, r.environment, 'gh-run-' || r.run_id, v_sim, r.evidence_sha256, 'pass', p_idem, a,
        rc.receipt_id, rc.stream_seq, 'ci_receipt', p_receipt_id));
    end if;
    v_ids := array_append(v_ids, c10_gov003_demo._f57_insert_proof(p_tenant, p_business, r.feature_id,
      'isolated_test_pass', r.head_sha, r.environment, 'gh-run-' || r.run_id, v_sim, r.evidence_sha256, v_out,
      p_idem, a, rc.receipt_id, rc.stream_seq, 'ci_receipt', p_receipt_id));
    return query select 'created'::text, v_ids, rc.receipt_id, false, (v_cur = r.head_sha),
      c10_gov003_demo._f57_derive(p_tenant, p_business, r.feature_id);
  exception when unique_violation then
    raise exception 'conflict: receipt already bound' using errcode = 'G3C01';
  end;
end $$;

-- Stale-head validator for a receipt (read-only, owner scoped).
create function c10_gov003_demo.validate_ci_receipt_head(p_tenant uuid, p_business uuid, p_receipt_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare r record; v_cur text; v_trust text;
begin
  if not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  select c.head_sha, c.feature_id into r from c10_gov003_demo.ci_receipts c
   where c.tenant_id = p_tenant and c.business_id = p_business and c.receipt_id = p_receipt_id;
  if not found then raise exception 'receipt_not_found' using errcode = 'G3C02'; end if;
  v_cur := c10_gov003_demo._f57_current_head(p_tenant, p_business, r.feature_id);
  v_trust := c10_gov003_demo._f57_ci_trust(p_tenant, p_business, p_receipt_id);
  return jsonb_build_object('receipt_head_sha', r.head_sha, 'current_head_sha', v_cur,
    'stale', v_cur is distinct from r.head_sha, 'trust', v_trust,
    'trust_label', c10_gov003_demo._f57_trust_label(v_trust));
end $$;

create view c10_gov003_demo.v_ci_receipts with (security_invoker = true) as
  select c.receipt_id, c.tenant_id, c.business_id, c.feature_id, c.repo_full, c.workflow, c.run_id,
         c.run_attempt, c.run_url, c.head_sha, c.run_status, c.conclusion, c.environment, c.origin,
         c.evidence_sha256, c.recorded_by, c.recorded_at, c.audit_receipt_id,
         (case when exists (select 1 from c10_gov003_demo.ci_receipt_verifications v
                             where v.tenant_id = c.tenant_id and v.business_id = c.business_id
                               and v.receipt_id = c.receipt_id and v.verifier_kind = 'github_api') then 'remote_verified'
               when exists (select 1 from c10_gov003_demo.ci_receipt_verifications v
                             where v.tenant_id = c.tenant_id and v.business_id = c.business_id
                               and v.receipt_id = c.receipt_id and v.verifier_kind = 'simulated_fixture')
                    then 'offline_fixture/simulated_verified'
               else 'offline_fixture/unverified' end) as trust_label,
         (c.head_sha = (select h.head_sha from c10_gov003_demo.readiness_heads h
                         where h.tenant_id = c.tenant_id and h.business_id = c.business_id
                           and h.feature_id = c.feature_id order by h.head_seq desc limit 1)) as is_current_head
    from c10_gov003_demo.ci_receipts c;
create view c10_gov003_demo.v_ci_receipt_verifications with (security_invoker = true) as
  select v.verification_id, v.tenant_id, v.business_id, v.receipt_id, v.verifier_kind,
         v.remote_payload_sha256, v.observed_at, v.recorded_by, v.recorded_at, v.audit_receipt_id
    from c10_gov003_demo.ci_receipt_verifications v;
revoke all on c10_gov003_demo.v_ci_receipts, c10_gov003_demo.v_ci_receipt_verifications from public;
grant select on c10_gov003_demo.v_ci_receipts, c10_gov003_demo.v_ci_receipt_verifications to c10g3_reader, c10g3_backend;

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname as nm
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'c10_gov003_demo'
       and p.proname = any (array['_f57_ci_trust','_f57_trust_label','record_ci_receipt','verify_ci_receipt',
                                  'bind_ci_receipt_to_readiness','validate_ci_receipt_head'])
  loop
    execute format('revoke all on function %s from public', r.sig);
    if r.nm in ('record_ci_receipt','verify_ci_receipt','bind_ci_receipt_to_readiness') then
      execute format('grant execute on function %s to c10g3_backend', r.sig);
    elsif r.nm = 'validate_ci_receipt_head' then
      execute format('grant execute on function %s to c10g3_backend, c10g3_reader', r.sig);
    end if;
  end loop;
end $$;
