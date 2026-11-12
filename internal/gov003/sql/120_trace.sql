-- 12 decision-and-change-trace: requirement -> feature -> source file -> tests -> release graph validator.
-- Works on a SAFE LOCAL SOURCE SNAPSHOT supplied as JSON. It never reads or rewrites Drive history.
\set ON_ERROR_STOP on
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

-- Pure validator. Mirrors internal/gov003/server/trace-graph.mjs (parity-tested).
create function c10_gov003_demo.validate_trace(p jsonb)
returns table (code text, subject text, detail text)
language plpgsql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
begin
  return query
  with
  reqs as (select r->>'id' as id, r->>'status' as status,
                  coalesce((r->>'hard')::boolean, false) as hard,
                  coalesce(r->>'deferral_reason', '') as dr,
                  coalesce(r->>'deferral_approval_ref', '') as dar
             from jsonb_array_elements(coalesce(p->'requirements', '[]'::jsonb)) r),
  feats as (select f->>'id' as id, f->>'head_sha' as head_sha, coalesce(f->'requirement_ids', '[]'::jsonb) as rids
              from jsonb_array_elements(coalesce(p->'features', '[]'::jsonb)) f),
  frefs as (select f.id as fid, x as rid
              from feats f, jsonb_array_elements_text(f.rids) x),
  srcs as (select s->>'path' as id, s->>'feature_id' as fid
             from jsonb_array_elements(coalesce(p->'source_files', '[]'::jsonb)) s),
  tsts as (select t->>'id' as id, t->>'feature_id' as fid,
                  coalesce((t->>'passed')::boolean, false) as passed, t->>'commit_sha' as sha
             from jsonb_array_elements(coalesce(p->'tests', '[]'::jsonb)) t),
  rels as (select e->>'id' as id, e->'feature_ids' as fids
             from jsonb_array_elements(coalesce(p->'releases', '[]'::jsonb)) e),
  decl as (select x as id from jsonb_array_elements_text(coalesce(p->'declared_requirement_ids', '[]'::jsonb)) x),
  good_tests as (select t.* from tsts t
                  where t.passed and t.sha ~ '^[0-9a-f]{40}$'
                    and not exists (select 1 from feats f where f.id = t.fid and f.head_sha is not null and f.head_sha <> t.sha)),
  v as (
    select 'duplicate_id'::text as code, k || ':' || id as subject, 'id appears ' || count(*) || ' times' as detail
      from (select 'requirement' k, id from reqs union all select 'feature', id from feats
            union all select 'source_file', id from srcs union all select 'test', id from tsts
            union all select 'release', id from rels) d
     group by k, id having count(*) > 1
    union all
    select 'invalid_status', id, 'status must be built|deferred|missing|proposed'
      from reqs where status is null or status not in ('built','deferred','missing','proposed')
    union all
    select 'dangling_requirement_ref', fr.fid, 'references unknown requirement ' || fr.rid
      from frefs fr where not exists (select 1 from reqs r where r.id = fr.rid)
    union all
    select 'orphan_feature', f.id, 'feature maps to no requirement'
      from feats f where jsonb_array_length(f.rids) = 0
    union all
    select 'orphan_requirement', r.id, 'built requirement has no feature'
      from reqs r where r.status = 'built' and not exists (select 1 from frefs fr where fr.rid = r.id)
    union all
    select 'deferral_without_reason', r.id, 'deferred requirement carries no explicit reason'
      from reqs r where r.status = 'deferred' and r.dr = ''
    union all
    select 'hard_requirement_deferred', r.id, 'hard requirement deferred without owner approval reference'
      from reqs r where r.status = 'deferred' and r.hard and r.dar = ''
    union all
    select 'requirement_removed_from_denominator', d.id, 'declared requirement is absent from the requirement list'
      from decl d where not exists (select 1 from reqs r where r.id = d.id)
    union all
    select 'undeclared_requirement', r.id, 'requirement is not in the declared denominator'
      from reqs r where p ? 'declared_requirement_ids' and not exists (select 1 from decl d where d.id = r.id)
    union all
    select 'denominator_count_mismatch', 'denominator',
           'expected ' || (p->>'expected_requirement_count') || ' requirements, found ' || (select count(*) from reqs)
      where p ? 'expected_requirement_count'
        and (p->>'expected_requirement_count')::int <> (select count(*) from reqs)
    union all
    select 'orphan_source_file', s.id, 'source file references unknown feature'
      from srcs s where not exists (select 1 from feats f where f.id = s.fid)
    union all
    select 'orphan_test', t.id, 'test references unknown feature'
      from tsts t where not exists (select 1 from feats f where f.id = t.fid)
    union all
    select 'passing_test_without_exact_sha', t.id, 'passing test lacks an exact 40-hex commit sha'
      from tsts t where t.passed and (t.sha is null or t.sha !~ '^[0-9a-f]{40}$')
    union all
    select 'stale_test_sha', t.id, 'test sha differs from the feature head sha'
      from tsts t join feats f on f.id = t.fid
     where t.passed and t.sha ~ '^[0-9a-f]{40}$' and f.head_sha is not null and f.head_sha <> t.sha
    union all
    select 'built_without_proof', r.id, 'built requirement has no passing exact-sha test'
      from reqs r
     where r.status = 'built'
       and exists (select 1 from frefs fr where fr.rid = r.id)
       and not exists (select 1 from frefs fr join good_tests g on g.fid = fr.fid where fr.rid = r.id)
    union all
    select 'orphan_release', e.id, 'release references unknown feature ' || x
      from rels e, jsonb_array_elements_text(coalesce(e.fids, '[]'::jsonb)) x
     where not exists (select 1 from feats f where f.id = x)
  )
  select v.code, v.subject, v.detail from v order by v.code, v.subject, v.detail;
end $$;

create function c10_gov003_demo.trace_summary(p jsonb) returns jsonb
language sql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  with
  reqs as (select r->>'id' as id, r->>'status' as status
             from jsonb_array_elements(coalesce(p->'requirements', '[]'::jsonb)) r),
  feats as (select f->>'id' as id, f->>'head_sha' as head_sha, coalesce(f->'requirement_ids', '[]'::jsonb) as rids
              from jsonb_array_elements(coalesce(p->'features', '[]'::jsonb)) f),
  frefs as (select f.id as fid, x as rid from feats f, jsonb_array_elements_text(f.rids) x),
  srcs as (select s->>'feature_id' as fid from jsonb_array_elements(coalesce(p->'source_files', '[]'::jsonb)) s),
  tsts as (select t->>'feature_id' as fid, coalesce((t->>'passed')::boolean, false) as passed, t->>'commit_sha' as sha
             from jsonb_array_elements(coalesce(p->'tests', '[]'::jsonb)) t),
  good_tests as (select t.* from tsts t
                  where t.passed and t.sha ~ '^[0-9a-f]{40}$'
                    and not exists (select 1 from feats f where f.id = t.fid and f.head_sha is not null and f.head_sha <> t.sha)),
  rel_feats as (select x as fid from jsonb_array_elements(coalesce(p->'releases', '[]'::jsonb)) e,
                  jsonb_array_elements_text(coalesce(e->'feature_ids', '[]'::jsonb)) x)
  select jsonb_build_object(
    'requirements', (select count(*) from reqs),
    'declared', (select count(*) from jsonb_array_elements_text(coalesce(p->'declared_requirement_ids', '[]'::jsonb))),
    'built', (select count(*) from reqs where status = 'built'),
    'deferred', (select count(*) from reqs where status = 'deferred'),
    'missing', (select count(*) from reqs where status = 'missing'),
    'proposed', (select count(*) from reqs where status = 'proposed'),
    'complete_chains', (select count(*) from reqs r where r.status = 'built' and exists (
        select 1 from frefs fr where fr.rid = r.id
           and exists (select 1 from srcs s where s.fid = fr.fid)
           and exists (select 1 from good_tests g where g.fid = fr.fid))),
    'released', (select count(*) from reqs r where r.status = 'built' and exists (
        select 1 from frefs fr join rel_feats rf on rf.fid = fr.fid where fr.rid = r.id))
  );
$$;

create table c10_gov003_demo.trace_snapshots (
  snapshot_id     uuid primary key,
  tenant_id       uuid not null,
  business_id     uuid not null,
  idempotency_key text not null,
  source_label    text not null check (source_label ~ '^[A-Za-z0-9_.:/ -]{1,128}$'),
  imported_by     uuid not null references c10_gov003_demo.identities,
  imported_at     timestamptz not null default clock_timestamp(),
  snapshot        jsonb not null,
  snapshot_sha256 text not null check (snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  verdict         text not null check (verdict in ('valid','invalid')),
  violations      jsonb not null,
  summary         jsonb not null,
  receipt_id      uuid,
  unique (tenant_id, business_id, idempotency_key),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);
select c10_gov003_demo.protect_table('c10_gov003_demo.trace_snapshots');
alter table c10_gov003_demo.trace_snapshots enable row level security;
create policy trace_snapshots_read on c10_gov003_demo.trace_snapshots for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
revoke all on c10_gov003_demo.trace_snapshots from public;
grant select on c10_gov003_demo.trace_snapshots to c10g3_reader, c10g3_backend;
create view c10_gov003_demo.v_trace_snapshots with (security_invoker = true) as
  select snapshot_id, tenant_id, business_id, source_label, imported_by, imported_at, snapshot_sha256,
         verdict, violations, summary, receipt_id from c10_gov003_demo.trace_snapshots;
revoke all on c10_gov003_demo.v_trace_snapshots from public;
grant select on c10_gov003_demo.v_trace_snapshots to c10g3_reader, c10g3_backend;

-- Importer: validates, stores the snapshot append-only, audits with a receipt. An INVALID snapshot is stored
-- with verdict 'invalid' (evidence of what was supplied); it is never silently fixed or dropped.
create function c10_gov003_demo.import_trace_snapshot(
  p_tenant uuid, p_business uuid, p_snapshot jsonb, p_label text, p_idem text)
returns table (snapshot_id uuid, verdict text, violation_count int, receipt_id uuid, replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  a uuid := c10_gov003_demo.actor_id();
  v_id uuid := gen_random_uuid();
  viol jsonb; summ jsonb; sha text; verd text; rc record; ex record;
begin
  if a is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if not c10_gov003_demo.scope_exists(p_tenant, p_business, null, null)
     or not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' or octet_length(p_snapshot::text) > 1000000 then
    raise exception 'snapshot_rejected: must be a JSON object up to 1 MB' using errcode = 'G3A03';
  end if;
  sha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(p_snapshot));
  select coalesce(jsonb_agg(jsonb_build_object('code', t.code, 'subject', t.subject, 'detail', t.detail)), '[]'::jsonb)
    into viol from c10_gov003_demo.validate_trace(p_snapshot) t;
  summ := c10_gov003_demo.trace_summary(p_snapshot);
  verd := case when jsonb_array_length(viol) = 0 then 'valid' else 'invalid' end;

  select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null, 'gov003.trace',
    'trace-' || left(sha, 16), 'v1', 'trace.import', clock_timestamp(), 'trace-' || left(sha, 16), p_idem,
    jsonb_build_object('artifact_sha256', sha, 'count', jsonb_array_length(viol)::text, 'status', verd),
    null, 'readiness', 1, null, null);
  if rc.replayed then
    select s.snapshot_id as sid, s.verdict as vd, jsonb_array_length(s.violations) as vc, s.receipt_id as rid into ex
      from c10_gov003_demo.trace_snapshots s
     where s.tenant_id = p_tenant and s.business_id = p_business and s.idempotency_key = p_idem;
    return query select ex.sid, ex.vd, ex.vc, ex.rid, true;
    return;
  end if;
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.trace_snapshots (snapshot_id, tenant_id, business_id, idempotency_key, source_label,
    imported_by, snapshot, snapshot_sha256, verdict, violations, summary, receipt_id)
  values (v_id, p_tenant, p_business, p_idem, p_label, a, p_snapshot, sha, verd, viol, summ, rc.receipt_id);
  perform set_config('c10_gov003.writer', '', true);
  return query select v_id, verd, jsonb_array_length(viol), rc.receipt_id, false;
end $$;

revoke all on function c10_gov003_demo.validate_trace(jsonb), c10_gov003_demo.trace_summary(jsonb),
  c10_gov003_demo.import_trace_snapshot(uuid,uuid,jsonb,text,text) from public;
grant execute on function c10_gov003_demo.validate_trace(jsonb), c10_gov003_demo.trace_summary(jsonb)
  to c10g3_backend, c10g3_reader;
grant execute on function c10_gov003_demo.import_trace_snapshot(uuid,uuid,jsonb,text,text) to c10g3_backend;
