-- 07 deployment-provenance: typed deployment record + runtime probe contract. DEMO / NOT LIVE.
--
--   * Deployed proof is SEPARATE from built/tested proof: only certify_deployment can write a
--     deployed_verified readiness proof, and only from a PASSING runtime probe of a DEPLOYED, REAL
--     staging/production deployment whose source commit is the feature's CURRENT head.
--   * A preview deployment, a queued/building/failed deployment, or queued CI can never certify.
--   * mode real|simulated is explicit. This isolated bed has no real runtime: mode = 'real' is gated by
--     real_evidence_gates.runtime_probe (DISABLED => fail closed). Simulated records never improve readiness.
--   * Probe contract: the deployment record carries the EXPECTED source commit, artifact sha256, version and
--     health. The probe result is computed server-side from the observation (never caller-supplied):
--       probe_before_deploy, source_commit_mismatch, artifact_hash_mismatch, version_mismatch,
--       health_not_ok, http_status_not_200  -> result 'fail', else 'pass'. Mirrored by deploy-record.mjs.
--   * Deployment/probe rows are immutable. A state change (queued -> deployed) is a NEW deployment record.
\set ON_ERROR_STOP on
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

create table c10_gov003_demo.deployments (
  deployment_id   uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null,
  business_id     uuid not null,
  feature_id      text not null,
  environment     text not null check (environment in ('preview','staging','production')),
  mode            text not null check (mode in ('real','simulated')),
  deploy_status   text not null check (deploy_status in ('queued','building','deployed','failed')),
  source_commit   text not null check (source_commit ~ '^[0-9a-f]{40}$'),
  artifact_sha256 text not null check (artifact_sha256 ~ '^[0-9a-f]{64}$'),
  build_ref       text not null check (build_ref ~ '^[A-Za-z0-9_.:/#-]{1,128}$'),
  branch_ref      text check (branch_ref ~ '^[A-Za-z0-9_.:/#-]{1,128}$'),
  deployed_at     timestamptz,
  expected_version text not null check (expected_version ~ '^[A-Za-z0-9_.:+-]{1,64}$'),
  expected_health text not null default 'ok' check (expected_health = 'ok'),
  check ((deploy_status = 'deployed') = (deployed_at is not null)),
  recorded_by     uuid not null references c10_gov003_demo.identities,
  recorded_at     timestamptz not null default clock_timestamp(),
  idempotency_key text not null,
  audit_receipt_id uuid not null references c10_gov003_demo.audit_receipts,
  audit_seq       bigint not null,
  unique (tenant_id, business_id, deployment_id),
  unique (tenant_id, business_id, idempotency_key),
  foreign key (tenant_id, business_id, feature_id) references c10_gov003_demo.readiness_features
);

create table c10_gov003_demo.deployment_probes (
  probe_id        uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null,
  business_id     uuid not null,
  deployment_id   uuid not null,
  mode            text not null check (mode in ('real','simulated')),
  observed_at     timestamptz not null,
  observed_source_commit text not null check (observed_source_commit ~ '^[0-9a-f]{40}$'),
  observed_artifact_sha256 text not null check (observed_artifact_sha256 ~ '^[0-9a-f]{64}$'),
  observed_version text not null check (observed_version ~ '^[A-Za-z0-9_.:+-]{1,64}$'),
  observed_health text not null check (observed_health in ('ok','degraded','down')),
  http_status     int  not null check (http_status between 100 and 599),
  result          text not null check (result in ('pass','fail')),
  mismatch_codes  text[] not null default '{}',
  check ((result = 'pass') = (cardinality(mismatch_codes) = 0)),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  recorded_by     uuid not null references c10_gov003_demo.identities,
  recorded_at     timestamptz not null default clock_timestamp(),
  idempotency_key text not null,
  audit_receipt_id uuid not null references c10_gov003_demo.audit_receipts,
  unique (tenant_id, business_id, probe_id),
  unique (tenant_id, business_id, idempotency_key),
  foreign key (tenant_id, business_id, deployment_id)
    references c10_gov003_demo.deployments (tenant_id, business_id, deployment_id)
);
create index deployment_probes_dep_idx on c10_gov003_demo.deployment_probes (tenant_id, business_id, deployment_id);

select c10_gov003_demo.protect_table('c10_gov003_demo.deployments');
select c10_gov003_demo.protect_table('c10_gov003_demo.deployment_probes');
alter table c10_gov003_demo.deployments enable row level security;
alter table c10_gov003_demo.deployment_probes enable row level security;
create policy deployments_read on c10_gov003_demo.deployments for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
create policy deployment_probes_read on c10_gov003_demo.deployment_probes for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
revoke all on c10_gov003_demo.deployments, c10_gov003_demo.deployment_probes from public;
grant select on c10_gov003_demo.deployments, c10_gov003_demo.deployment_probes to c10g3_reader, c10g3_backend;

-- ------------------------------------------------------------------------------------------ writers
create function c10_gov003_demo.record_deployment(
  p_tenant uuid, p_business uuid, p_feature_id text, p_environment text, p_mode text, p_deploy_status text,
  p_source_commit text, p_artifact_sha256 text, p_build_ref text, p_branch_ref text, p_deployed_at timestamptz,
  p_expected_version text, p_expected_health text, p_idem text, p_claimed_actor uuid default null)
returns table (result text, deployment_id uuid, audit_receipt_id uuid, replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare a uuid; rc record; ex record; v_cmd text; v_id uuid := gen_random_uuid(); v_payload jsonb; v_health text := coalesce(p_expected_health, 'ok');
begin
  a := c10_gov003_demo._f57_actor(p_claimed_actor, p_tenant, p_business, false);
  perform c10_gov003_demo._f57_check_idem(p_idem);
  perform c10_gov003_demo._f57_check_ref(p_feature_id, 'feature_id');
  perform c10_gov003_demo._f57_check_ref(p_build_ref, 'build_ref');
  if p_branch_ref is not null then perform c10_gov003_demo._f57_check_ref(p_branch_ref, 'branch_ref'); end if;
  if p_environment is null or p_environment not in ('preview','staging','production')
     or p_mode is null or p_mode not in ('real','simulated')
     or p_deploy_status is null or p_deploy_status not in ('queued','building','deployed','failed') then
    raise exception 'validation_failed: environment, mode and deploy status' using errcode = 'G3A03';
  end if;
  if not c10_gov003_demo._f57_is_sha40(p_source_commit) or not c10_gov003_demo._f57_is_sha256(p_artifact_sha256) then
    raise exception 'validation_failed: source commit (40 hex) and artifact sha256 (64 hex) required' using errcode = 'G3A03';
  end if;
  if p_expected_version is null or p_expected_version !~ '^[A-Za-z0-9_.:+-]{1,64}$' or v_health <> 'ok' then
    raise exception 'validation_failed: expected version / health' using errcode = 'G3A03';
  end if;
  if (p_deploy_status = 'deployed') <> (p_deployed_at is not null)
     or (p_deployed_at is not null and p_deployed_at > clock_timestamp() + interval '5 minutes') then
    raise exception 'validation_failed: deployed_at is required exactly when status is deployed (and not in the future)'
      using errcode = 'G3A03';
  end if;
  if p_mode = 'real' and not c10_gov003_demo._f57_gate_enabled('runtime_probe') then
    raise exception 'real_evidence_unavailable: no real runtime in this isolated bed (fail closed)' using errcode = 'G3E01';
  end if;
  perform c10_gov003_demo._f57_require_feature(p_tenant, p_business, p_feature_id);
  v_cmd := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(jsonb_build_object(
    'op', 'record_deployment', 'feature_id', p_feature_id, 'environment', p_environment, 'mode', p_mode,
    'deploy_status', p_deploy_status, 'source_commit', p_source_commit, 'artifact_sha256', p_artifact_sha256,
    'build_ref', p_build_ref, 'branch_ref', p_branch_ref,
    'deployed_at', c10_gov003_demo.utc_iso(p_deployed_at), 'expected_version', p_expected_version,
    'expected_health', v_health)));
  v_payload := jsonb_build_object('feature_id', p_feature_id, 'commit_sha', p_source_commit,
    'artifact_sha256', p_artifact_sha256, 'detail_code', p_environment, 'method', p_mode,
    'status', p_deploy_status, 'source_ref', p_build_ref, 'doc_ref', 'cmd:' || v_cmd);
  if p_branch_ref is not null then v_payload := v_payload || jsonb_build_object('entity_ref', p_branch_ref); end if;
  begin
    select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
      'gov003.deploy', p_feature_id, 'v1', 'deploy.recorded', clock_timestamp(), p_idem, p_idem,
      v_payload, null, 'readiness', 1, null, null);
    if rc.replayed then
      select d.deployment_id as did into ex from c10_gov003_demo.deployments d
       where d.tenant_id = p_tenant and d.business_id = p_business and d.idempotency_key = p_idem;
      return query select 'replayed'::text, ex.did, rc.receipt_id, true;
      return;
    end if;
    perform set_config('c10_gov003.writer', 'append_path', true);
    insert into c10_gov003_demo.deployments
      (deployment_id, tenant_id, business_id, feature_id, environment, mode, deploy_status, source_commit,
       artifact_sha256, build_ref, branch_ref, deployed_at, expected_version, expected_health, recorded_by,
       idempotency_key, audit_receipt_id, audit_seq)
    values (v_id, p_tenant, p_business, p_feature_id, p_environment, p_mode, p_deploy_status, p_source_commit,
       p_artifact_sha256, p_build_ref, p_branch_ref, p_deployed_at, p_expected_version, v_health, a,
       p_idem, rc.receipt_id, rc.stream_seq);
    perform set_config('c10_gov003.writer', '', true);
    return query select 'created'::text, v_id, rc.receipt_id, false;
  exception when unique_violation then
    raise exception 'conflict: deployment already recorded' using errcode = 'G3C01';
  end;
end $$;

-- Runtime smoke probe. The pass/fail verdict and mismatch codes are computed HERE from the observation.
create function c10_gov003_demo.record_runtime_probe(
  p_tenant uuid, p_business uuid, p_deployment_id uuid, p_mode text, p_observed_at timestamptz,
  p_observed_source_commit text, p_observed_artifact_sha256 text, p_observed_version text,
  p_observed_health text, p_http_status int, p_idem text, p_claimed_actor uuid default null)
returns table (result text, probe_id uuid, probe_result text, mismatch_codes text[], audit_receipt_id uuid,
               replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  a uuid; rc record; ex record; d record; v_cmd text; v_ev text; v_id uuid := gen_random_uuid();
  codes text[] := '{}'; v_res text;
begin
  a := c10_gov003_demo._f57_actor(p_claimed_actor, p_tenant, p_business, false);
  perform c10_gov003_demo._f57_check_idem(p_idem);
  if p_mode is null or p_mode not in ('real','simulated') or p_observed_at is null
     or not c10_gov003_demo._f57_is_sha40(p_observed_source_commit)
     or not c10_gov003_demo._f57_is_sha256(p_observed_artifact_sha256)
     or p_observed_version is null or p_observed_version !~ '^[A-Za-z0-9_.:+-]{1,64}$'
     or p_observed_health is null or p_observed_health not in ('ok','degraded','down')
     or p_http_status is null or p_http_status not between 100 and 599 then
    raise exception 'validation_failed: probe observation' using errcode = 'G3A03';
  end if;
  if p_observed_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'validation_failed: probe observed_at is in the future' using errcode = 'G3A03';
  end if;
  select dp.* into d from c10_gov003_demo.deployments dp
   where dp.tenant_id = p_tenant and dp.business_id = p_business and dp.deployment_id = p_deployment_id;
  if not found then
    raise exception 'deployment_not_found' using errcode = 'G3C02';
  end if;
  v_ev := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(jsonb_build_object(
    'deployment_id', p_deployment_id::text, 'http_status', p_http_status::text, 'mode', p_mode,
    'observed_artifact_sha256', p_observed_artifact_sha256, 'observed_at', c10_gov003_demo.utc_iso(p_observed_at),
    'observed_health', p_observed_health, 'observed_source_commit', p_observed_source_commit,
    'observed_version', p_observed_version)));
  v_cmd := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(jsonb_build_object(
    'op', 'record_probe', 'evidence', v_ev)));
  begin
    select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
      'gov003.deploy', d.feature_id, 'v1', 'deploy.probe_recorded', clock_timestamp(), p_idem, p_idem,
      jsonb_build_object('feature_id', d.feature_id, 'commit_sha', p_observed_source_commit,
        'artifact_sha256', p_observed_artifact_sha256, 'evidence_ref', v_ev, 'method', p_mode,
        'detail_code', d.environment, 'receipt_ref', p_deployment_id::text, 'status', 'recorded',
        'doc_ref', 'cmd:' || v_cmd),
      null, 'readiness', 1, null, null);
    if rc.replayed then
      select pb.probe_id as pid, pb.result as res, pb.mismatch_codes as mc into ex
        from c10_gov003_demo.deployment_probes pb
       where pb.tenant_id = p_tenant and pb.business_id = p_business and pb.idempotency_key = p_idem;
      return query select 'replayed'::text, ex.pid, ex.res, ex.mc, rc.receipt_id, true;
      return;
    end if;
    if d.deploy_status <> 'deployed' then
      raise exception 'deployment_not_deployed: a % deployment cannot be smoke-probed as deployed', d.deploy_status
        using errcode = 'G3C02';
    end if;
    if p_mode <> d.mode then
      raise exception 'probe_mode_mismatch: probe mode must equal the deployment mode' using errcode = 'G3C02';
    end if;
    if p_mode = 'real' and not c10_gov003_demo._f57_gate_enabled('runtime_probe') then
      raise exception 'real_evidence_unavailable: no real runtime probe in this isolated bed (fail closed)'
        using errcode = 'G3E01';
    end if;
    if p_observed_at < d.deployed_at then codes := array_append(codes, 'probe_before_deploy'); end if;
    if p_observed_source_commit <> d.source_commit then codes := array_append(codes, 'source_commit_mismatch'); end if;
    if p_observed_artifact_sha256 <> d.artifact_sha256 then codes := array_append(codes, 'artifact_hash_mismatch'); end if;
    if p_observed_version <> d.expected_version then codes := array_append(codes, 'version_mismatch'); end if;
    if p_observed_health <> d.expected_health then codes := array_append(codes, 'health_not_ok'); end if;
    if p_http_status <> 200 then codes := array_append(codes, 'http_status_not_200'); end if;
    v_res := case when cardinality(codes) = 0 then 'pass' else 'fail' end;
    perform set_config('c10_gov003.writer', 'append_path', true);
    insert into c10_gov003_demo.deployment_probes
      (probe_id, tenant_id, business_id, deployment_id, mode, observed_at, observed_source_commit,
       observed_artifact_sha256, observed_version, observed_health, http_status, result, mismatch_codes,
       evidence_sha256, recorded_by, idempotency_key, audit_receipt_id)
    values (v_id, p_tenant, p_business, p_deployment_id, p_mode, p_observed_at, p_observed_source_commit,
       p_observed_artifact_sha256, p_observed_version, p_observed_health, p_http_status, v_res, codes,
       v_ev, a, p_idem, rc.receipt_id);
    perform set_config('c10_gov003.writer', '', true);
    return query select 'created'::text, v_id, v_res, codes, rc.receipt_id, false;
  exception when unique_violation then
    raise exception 'conflict: probe already recorded' using errcode = 'G3C01';
  end;
end $$;

-- The ONLY writer of a deployed_verified proof.
create function c10_gov003_demo.certify_deployment(
  p_tenant uuid, p_business uuid, p_deployment_id uuid, p_probe_id uuid, p_idem text,
  p_claimed_actor uuid default null)
returns table (result text, proof_id uuid, audit_receipt_id uuid, replayed boolean, readiness jsonb)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare a uuid; rc record; ex record; d record; pb record; v_cmd text; v_id uuid; v_head text;
begin
  a := c10_gov003_demo._f57_actor(p_claimed_actor, p_tenant, p_business, false);
  perform c10_gov003_demo._f57_check_idem(p_idem);
  select dp.* into d from c10_gov003_demo.deployments dp
   where dp.tenant_id = p_tenant and dp.business_id = p_business and dp.deployment_id = p_deployment_id;
  if not found then raise exception 'deployment_not_found' using errcode = 'G3C02'; end if;
  select x.* into pb from c10_gov003_demo.deployment_probes x
   where x.tenant_id = p_tenant and x.business_id = p_business and x.probe_id = p_probe_id
     and x.deployment_id = p_deployment_id;
  if not found then raise exception 'probe_not_found: a runtime smoke probe record is required' using errcode = 'G3C02'; end if;
  v_cmd := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(jsonb_build_object(
    'op', 'certify_deployment', 'deployment_id', p_deployment_id::text, 'probe_id', p_probe_id::text)));
  begin
    select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
      'gov003.deploy', d.feature_id, 'v1', 'deploy.certified', clock_timestamp(), p_idem, p_idem,
      jsonb_build_object('feature_id', d.feature_id, 'commit_sha', d.source_commit,
        'artifact_sha256', d.artifact_sha256, 'evidence_ref', pb.evidence_sha256, 'new_status', 'deployed_verified',
        'detail_code', d.environment, 'method', d.mode, 'receipt_ref', p_deployment_id::text,
        'status', 'pass', 'doc_ref', 'cmd:' || v_cmd),
      null, 'readiness', 1, null, null);
    if rc.replayed then
      select p.proof_id as pid into ex from c10_gov003_demo.readiness_proofs p
       where p.tenant_id = p_tenant and p.business_id = p_business and p.idempotency_key = p_idem
         and p.level = 'deployed_verified';
      return query select 'replayed'::text, ex.pid, rc.receipt_id, true,
        c10_gov003_demo._f57_derive(p_tenant, p_business, d.feature_id);
      return;
    end if;
    if d.environment = 'preview' then
      raise exception 'preview_cannot_certify: a preview deployment is not deployed/healthy proof' using errcode = 'G3C02';
    end if;
    if d.deploy_status <> 'deployed' then
      raise exception 'deployment_not_deployed: % is not deployed', d.deploy_status using errcode = 'G3C02';
    end if;
    if d.mode <> 'real' or pb.mode <> 'real' then
      raise exception 'simulated_cannot_certify: simulated deployment evidence never certifies' using errcode = 'G3C02';
    end if;
    if not c10_gov003_demo._f57_gate_enabled('runtime_probe') then
      raise exception 'real_evidence_unavailable: runtime probe gate is disabled (fail closed)' using errcode = 'G3E01';
    end if;
    if pb.result <> 'pass' then
      raise exception 'probe_not_passing: %', array_to_string(pb.mismatch_codes, ',') using errcode = 'G3C02';
    end if;
    v_head := c10_gov003_demo._f57_current_head(p_tenant, p_business, d.feature_id);
    if v_head is distinct from d.source_commit then
      raise exception 'stale_head: deployed source commit is not the current head' using errcode = 'G3C01';
    end if;
    v_id := c10_gov003_demo._f57_insert_proof(p_tenant, p_business, d.feature_id, 'deployed_verified',
      d.source_commit, d.environment, d.build_ref, false, pb.evidence_sha256, 'pass', p_idem, a,
      rc.receipt_id, rc.stream_seq, 'deployment_probe', p_probe_id);
    return query select 'created'::text, v_id, rc.receipt_id, false,
      c10_gov003_demo._f57_derive(p_tenant, p_business, d.feature_id);
  exception when unique_violation then
    raise exception 'conflict: probe already certified' using errcode = 'G3C01';
  end;
end $$;

create view c10_gov003_demo.v_deployments with (security_invoker = true) as
  select d.deployment_id, d.tenant_id, d.business_id, d.feature_id, d.environment, d.mode, d.deploy_status,
         d.source_commit, d.artifact_sha256, d.build_ref, d.branch_ref, d.deployed_at, d.expected_version,
         d.expected_health, d.recorded_by, d.recorded_at, d.audit_receipt_id,
         exists (select 1 from c10_gov003_demo.deployment_probes p
                  where p.tenant_id = d.tenant_id and p.business_id = d.business_id
                    and p.deployment_id = d.deployment_id and p.result = 'pass') as has_passing_probe,
         (d.environment <> 'preview' and d.deploy_status = 'deployed' and d.mode = 'real'
          and exists (select 1 from c10_gov003_demo.deployment_probes p
                       where p.tenant_id = d.tenant_id and p.business_id = d.business_id
                         and p.deployment_id = d.deployment_id and p.result = 'pass' and p.mode = 'real')) as runtime_verified,
         (d.source_commit = (select h.head_sha from c10_gov003_demo.readiness_heads h
                              where h.tenant_id = d.tenant_id and h.business_id = d.business_id
                                and h.feature_id = d.feature_id order by h.head_seq desc limit 1)) as is_current_head
    from c10_gov003_demo.deployments d;
create view c10_gov003_demo.v_deployment_probes with (security_invoker = true) as
  select p.probe_id, p.tenant_id, p.business_id, p.deployment_id, p.mode, p.observed_at,
         p.observed_source_commit, p.observed_artifact_sha256, p.observed_version, p.observed_health,
         p.http_status, p.result, p.mismatch_codes, p.evidence_sha256, p.recorded_by, p.recorded_at,
         p.audit_receipt_id
    from c10_gov003_demo.deployment_probes p;
revoke all on c10_gov003_demo.v_deployments, c10_gov003_demo.v_deployment_probes from public;
grant select on c10_gov003_demo.v_deployments, c10_gov003_demo.v_deployment_probes to c10g3_reader, c10g3_backend;

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.proname as nm
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'c10_gov003_demo'
       and p.proname = any (array['record_deployment','record_runtime_probe','certify_deployment'])
  loop
    execute format('revoke all on function %s from public', r.sig);
    execute format('grant execute on function %s to c10g3_backend', r.sig);
  end loop;
end $$;
