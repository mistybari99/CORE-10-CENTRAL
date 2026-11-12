-- GOV-003 feature 11 incident-evidence-preservation. DEMO / NOT LIVE. Disposable test bed.
-- Scoped incident cases, immutable evidence manifest, hold/retention fields, independent Owner review, and a
-- purge service that must refuse while a hold or a future retention-until covers the evidence.
--
-- NO LEGAL CLAIM IS MADE HERE. A hold flag in a mutable PostgreSQL database is an ENGINEERING CONTROL (it stops
-- ordinary principals and this schema's own purge path from deleting evidence). It is NOT a legal-hold
-- certification and NOT WORM storage: a privileged DBA/superuser can still disable triggers or rewrite storage
-- (verify_manifest and the audit chain only make such edits detectable). Whether, when and for how long data
-- must be retained, and when a hold may be lifted, is an Owner / legal counsel decision gate outside this code.
-- Evidence items here are opaque references + SHA-256 + byte length; the evidence bytes are NOT stored here.
--
-- Roles: investigation rights = owner of the exact business (tenant_owner / business_owner), via can_read_business.
-- Site-only staff, investors, revoked memberships, support operators and foreign tenants are denied (G3A02).
-- Error codes: forged actor G3A01, scope denied G3A02, bad input G3A03, hash mismatch G3A04, conflict G3C01,
-- append-only G3H01, preservation/hold violation G3H02.
\set ON_ERROR_STOP on
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

-- ---------------------------------------------------------------------------------------------------------
-- Tables (all append-only; state changes are new rows: reviews, releases, tombstones)
-- ---------------------------------------------------------------------------------------------------------
create table c10_gov003_demo.incident_cases (
  case_id          uuid primary key,
  tenant_id        uuid not null,
  business_id      uuid not null,
  site_id          uuid,
  case_ref         text not null check (case_ref ~ '^[A-Za-z0-9_.:/#-]{1,128}$'),
  severity         text not null check (severity in ('low','medium','high','critical')),
  category         text not null check (category in ('operational','security','fraud_review','access','data_integrity','other')),
  opened_by        uuid not null references c10_gov003_demo.identities,
  opened_at        timestamptz not null,
  audit_event_id   uuid not null unique references c10_gov003_demo.audit_events,
  audit_receipt_id uuid not null unique references c10_gov003_demo.audit_receipts,
  unique (tenant_id, business_id, case_ref),
  unique (case_id, tenant_id, business_id),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses,
  foreign key (tenant_id, business_id, site_id) references c10_gov003_demo.sites
);

create table c10_gov003_demo.incident_evidence_items (
  evidence_id      uuid primary key,
  case_id          uuid not null,
  tenant_id        uuid not null,
  business_id      uuid not null,
  item_seq         int  not null check (item_seq > 0),
  evidence_ref     text not null check (evidence_ref ~ '^[A-Za-z0-9_.:/#-]{1,128}$'),
  kind             text not null check (kind in ('log_extract','document','image','export_csv','db_snapshot_ref','other')),
  sha256           text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  byte_length      bigint not null check (byte_length >= 0 and byte_length <= 1000000000000),
  source_ref       text not null check (source_ref ~ '^[A-Za-z0-9_.:/#-]{1,128}$'),
  retain_until     timestamptz,
  added_by         uuid not null references c10_gov003_demo.identities,
  added_at         timestamptz not null,
  prior_digest     text not null check (prior_digest ~ '^[0-9a-f]{64}$'),
  item_digest      text not null check (item_digest ~ '^[0-9a-f]{64}$'),
  audit_event_id   uuid not null unique references c10_gov003_demo.audit_events,
  audit_receipt_id uuid not null unique references c10_gov003_demo.audit_receipts,
  unique (case_id, item_seq),
  unique (case_id, evidence_ref),
  unique (evidence_id, case_id),
  foreign key (case_id, tenant_id, business_id)
    references c10_gov003_demo.incident_cases (case_id, tenant_id, business_id)
);

create table c10_gov003_demo.incident_holds (
  hold_id          uuid primary key,
  case_id          uuid not null,
  tenant_id        uuid not null,
  business_id      uuid not null,
  evidence_id      uuid,                       -- null = the whole case (also covers evidence added later)
  hold_ref         text not null check (hold_ref ~ '^[A-Za-z0-9_.:/#-]{1,128}$'),
  reason_category  text not null check (reason_category in
                     ('security_incident','fraud_review','owner_directive','counsel_request','regulatory_inquiry','other')),
  retention_until  timestamptz not null,
  placed_by        uuid not null references c10_gov003_demo.identities,   -- always the server-derived actor
  placed_at        timestamptz not null,
  audit_event_id   uuid not null unique references c10_gov003_demo.audit_events,
  audit_receipt_id uuid not null unique references c10_gov003_demo.audit_receipts,
  check (retention_until > placed_at),
  unique (case_id, hold_ref),
  foreign key (case_id, tenant_id, business_id)
    references c10_gov003_demo.incident_cases (case_id, tenant_id, business_id),
  foreign key (evidence_id, case_id) references c10_gov003_demo.incident_evidence_items (evidence_id, case_id)
);

create table c10_gov003_demo.incident_hold_reviews (        -- Owner-review status: no row = pending
  hold_id          uuid primary key references c10_gov003_demo.incident_holds,
  tenant_id        uuid not null,
  business_id      uuid not null,
  reviewer_id      uuid not null references c10_gov003_demo.identities,
  decision         text not null check (decision in ('approved','rejected')),
  note_code        text not null check (note_code ~ '^[a-z0-9_.:-]{1,64}$'),
  reviewed_at      timestamptz not null,
  audit_event_id   uuid not null unique references c10_gov003_demo.audit_events,
  audit_receipt_id uuid not null unique references c10_gov003_demo.audit_receipts,
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);

create table c10_gov003_demo.incident_hold_releases (       -- release never deletes a hold; it adds a row
  hold_id          uuid primary key references c10_gov003_demo.incident_holds,
  tenant_id        uuid not null,
  business_id      uuid not null,
  released_by      uuid not null references c10_gov003_demo.identities,
  reason_code      text not null check (reason_code ~ '^[a-z0-9_.:-]{1,64}$'),
  released_at      timestamptz not null,
  audit_event_id   uuid not null unique references c10_gov003_demo.audit_events,
  audit_receipt_id uuid not null unique references c10_gov003_demo.audit_receipts,
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);

create table c10_gov003_demo.incident_evidence_tombstones ( -- purge never edits history; it adds a tombstone
  evidence_id      uuid primary key references c10_gov003_demo.incident_evidence_items,
  case_id          uuid not null,
  tenant_id        uuid not null,
  business_id      uuid not null,
  sha256_retained  text not null check (sha256_retained ~ '^[0-9a-f]{64}$'),
  purged_by        uuid not null references c10_gov003_demo.identities,
  reason_code      text not null check (reason_code ~ '^[a-z0-9_.:-]{1,64}$'),
  purged_at        timestamptz not null,
  audit_event_id   uuid not null unique references c10_gov003_demo.audit_events,
  audit_receipt_id uuid not null unique references c10_gov003_demo.audit_receipts,
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);

comment on table c10_gov003_demo.incident_holds is
  'Engineering control in a mutable database: NOT a legal-hold certification. Legal retention decisions are an Owner/counsel gate.';
comment on table c10_gov003_demo.incident_evidence_items is
  'Immutable evidence manifest entries (opaque refs + SHA-256). Tamper-evident via item digest chain and audit link; not WORM.';

-- ---------------------------------------------------------------------------------------------------------
-- Digest + protection rules (mirrored by internal/gov003/server/evidence-manifest.mjs)
-- ---------------------------------------------------------------------------------------------------------
create function c10_gov003_demo.inc_item_digest_of(
  p_prior text, p_case uuid, p_seq int, p_ref text, p_kind text, p_sha text, p_len bigint, p_source text,
  p_retain timestamptz, p_added timestamptz, p_by uuid)
returns text
language sql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select c10_gov003_demo.g3_sha256(concat_ws('|', 'g3m1', p_prior, p_case, p_seq, p_ref, p_kind, p_sha, p_len,
    p_source, coalesce(c10_gov003_demo.utc_iso(p_retain), ''), c10_gov003_demo.utc_iso(p_added), p_by));
$$;

create function c10_gov003_demo.inc_empty_manifest_digest(p_case uuid) returns text
language sql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$ select c10_gov003_demo.g3_sha256('g3m1|empty|' || p_case) $$;

-- Reasons why evidence may NOT be purged right now. Empty array = not protected by any rule in this schema.
--   item_retention : the item's own retain_until is in the future
--   hold_active    : a covering hold (case-wide or item) has no release row
--   hold_retention : a covering hold's retention_until is still in the future (even if released)
create function c10_gov003_demo._inc_protection(p_evidence uuid, p_now timestamptz default clock_timestamp())
returns text[]
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare ev record; r text[] := '{}';
begin
  select i.evidence_id as eid, i.case_id as cid, i.retain_until as ru into ev
    from c10_gov003_demo.incident_evidence_items i where i.evidence_id = p_evidence;
  if not found then return r; end if;
  if ev.ru is not null and ev.ru > p_now then r := r || 'item_retention'; end if;
  if exists (select 1 from c10_gov003_demo.incident_holds h
              where h.case_id = ev.cid and (h.evidence_id is null or h.evidence_id = ev.eid)
                and not exists (select 1 from c10_gov003_demo.incident_hold_releases x where x.hold_id = h.hold_id)) then
    r := r || 'hold_active';
  end if;
  if exists (select 1 from c10_gov003_demo.incident_holds h
              where h.case_id = ev.cid and (h.evidence_id is null or h.evidence_id = ev.eid)
                and h.retention_until > p_now) then
    r := r || 'hold_retention';
  end if;
  return r;
end $$;

-- Defense in depth beneath the purge function: even the table owner cannot UPDATE/DELETE held evidence
-- (G3H02), and cannot add a tombstone for protected evidence (G3H02). Unheld evidence is still never
-- deletable: protect_table() raises G3H01. (Superuser/DBA can bypass triggers: engineering control only.)
create function c10_gov003_demo._inc_guard_evidence() returns trigger
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
begin
  if cardinality(c10_gov003_demo._inc_protection(old.evidence_id)) > 0 then
    raise exception 'evidence_under_hold: % of evidence under hold/retention is blocked', tg_op using errcode = 'G3H02';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;

create function c10_gov003_demo._inc_guard_tombstone() returns trigger
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
begin
  if cardinality(c10_gov003_demo._inc_protection(new.evidence_id)) > 0 then
    raise exception 'evidence_under_hold: purge of protected evidence is blocked' using errcode = 'G3H02';
  end if;
  return new;
end $$;

select c10_gov003_demo.protect_table('c10_gov003_demo.incident_cases');
select c10_gov003_demo.protect_table('c10_gov003_demo.incident_evidence_items');
select c10_gov003_demo.protect_table('c10_gov003_demo.incident_holds');
select c10_gov003_demo.protect_table('c10_gov003_demo.incident_hold_reviews');
select c10_gov003_demo.protect_table('c10_gov003_demo.incident_hold_releases');
select c10_gov003_demo.protect_table('c10_gov003_demo.incident_evidence_tombstones');

-- Trigger names sort before g3_no_update_delete / g3_insert_guard, so G3H02 is raised first for held evidence.
create trigger g3_hold_guard before update or delete on c10_gov003_demo.incident_evidence_items
  for each row execute function c10_gov003_demo._inc_guard_evidence();
create trigger g3_hold_guard before insert on c10_gov003_demo.incident_evidence_tombstones
  for each row execute function c10_gov003_demo._inc_guard_tombstone();

-- ---------------------------------------------------------------------------------------------------------
-- RLS + read-only scoped views
-- ---------------------------------------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['incident_cases','incident_evidence_items','incident_holds','incident_hold_reviews',
                           'incident_hold_releases','incident_evidence_tombstones'] loop
    execute format('alter table c10_gov003_demo.%I enable row level security', t);
    execute format('create policy %I on c10_gov003_demo.%I for select to c10g3_reader, c10g3_backend
                    using (c10_gov003_demo.can_read_business(tenant_id, business_id))', t || '_read', t);
    execute format('revoke all on c10_gov003_demo.%I from public', t);
    execute format('grant select on c10_gov003_demo.%I to c10g3_reader, c10g3_backend', t);
  end loop;
end $$;

create view c10_gov003_demo.v_incident_cases with (security_invoker = true) as
  select case_id, tenant_id, business_id, site_id, case_ref, severity, category, opened_by, opened_at,
         audit_receipt_id
    from c10_gov003_demo.incident_cases;

create view c10_gov003_demo.v_incident_evidence with (security_invoker = true) as
  select i.evidence_id, i.case_id, i.tenant_id, i.business_id, i.item_seq, i.evidence_ref, i.kind, i.sha256,
         i.byte_length, i.source_ref, i.retain_until, i.added_by, i.added_at, i.prior_digest, i.item_digest,
         i.audit_receipt_id, (t.evidence_id is not null) as purged, t.purged_at
    from c10_gov003_demo.incident_evidence_items i
    left join c10_gov003_demo.incident_evidence_tombstones t on t.evidence_id = i.evidence_id;

create view c10_gov003_demo.v_incident_holds with (security_invoker = true) as
  select h.hold_id, h.case_id, h.tenant_id, h.business_id, h.evidence_id, h.hold_ref, h.reason_category,
         h.retention_until, h.placed_by, h.placed_at, h.audit_receipt_id,
         coalesce(rv.decision, 'pending') as review_status, rv.reviewer_id,
         (rl.hold_id is not null) as released, rl.released_by, rl.released_at,
         (rl.hold_id is null or h.retention_until > clock_timestamp()) as in_force
    from c10_gov003_demo.incident_holds h
    left join c10_gov003_demo.incident_hold_reviews rv on rv.hold_id = h.hold_id
    left join c10_gov003_demo.incident_hold_releases rl on rl.hold_id = h.hold_id;

revoke all on c10_gov003_demo.v_incident_cases, c10_gov003_demo.v_incident_evidence,
              c10_gov003_demo.v_incident_holds from public;
grant select on c10_gov003_demo.v_incident_cases, c10_gov003_demo.v_incident_evidence,
                c10_gov003_demo.v_incident_holds to c10g3_reader, c10g3_backend;

-- ---------------------------------------------------------------------------------------------------------
-- Internal helpers (owner only)
-- ---------------------------------------------------------------------------------------------------------
create function c10_gov003_demo._inc_gate(p_tenant uuid, p_business uuid, p_site uuid, p_claimed uuid, p_idem text)
returns uuid
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare a uuid := c10_gov003_demo.actor_id();
begin
  if a is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if p_claimed is not null and p_claimed <> a then
    raise exception 'forged_actor: caller-supplied actor does not match the server-derived actor'
      using errcode = 'G3A01';
  end if;
  if p_tenant is null or p_business is null
     or not c10_gov003_demo.scope_exists(p_tenant, p_business, p_site, null)
     or not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  if p_idem is not null and p_idem !~ '^[A-Za-z0-9_.:-]{8,100}$' then
    raise exception 'incident_param_invalid: idempotency key must be 8-100 chars [A-Za-z0-9_.:-]' using errcode = 'G3A03';
  end if;
  return a;
end $$;

create function c10_gov003_demo._inc_case(p_tenant uuid, p_business uuid, p_case_ref text)
returns c10_gov003_demo.incident_cases
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare c c10_gov003_demo.incident_cases;
begin
  select * into c from c10_gov003_demo.incident_cases x
   where x.tenant_id = p_tenant and x.business_id = p_business and x.case_ref = p_case_ref;
  if not found then
    raise exception 'scope_denied: no such incident case in your scope' using errcode = 'G3A02';
  end if;
  return c;
end $$;

-- Existing audit event for this (namespaced) idempotency key; G3C01 when it does not match this request.
create function c10_gov003_demo._inc_replay(
  p_tenant uuid, p_business uuid, p_idem text, p_actions text[], p_source_id text, p_payload_sha text)
returns uuid
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare e record;
begin
  select x.event_id as eid, x.action as act, x.source_id as sid, x.payload_sha256 as psha into e
    from c10_gov003_demo.audit_events x
   where x.tenant_id = p_tenant and x.business_id = p_business and x.idempotency_key = 'inc.' || p_idem;
  if not found then return null; end if;
  if e.act = any (p_actions) and e.sid = p_source_id and (p_payload_sha is null or e.psha = p_payload_sha) then
    return e.eid;
  end if;
  raise exception 'idempotency_conflict: key reused with a different incident request' using errcode = 'G3C01';
end $$;

create function c10_gov003_demo._inc_audit(
  p_tenant uuid, p_business uuid, p_site uuid, p_case_ref text, p_case uuid, p_action text, p_idem text, p_payload jsonb)
returns table (event_id uuid, receipt_id uuid, event_digest text, replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare ap record;
begin
  select * into ap from c10_gov003_demo._append_audit(p_tenant, p_business, p_site, null, 'gov003.incident',
    p_case_ref, 'v1', p_action, clock_timestamp(), 'inc-' || replace(p_case::text, '-', ''), 'inc.' || p_idem,
    p_payload, null, 'incident', 1, null, null);
  return query select ap.event_id, ap.receipt_id, ap.event_digest, ap.replayed;
end $$;

create function c10_gov003_demo._inc_lock(p_key text) returns void
language sql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$ select pg_advisory_xact_lock(hashtextextended('g3inc|' || p_key, 0)) $$;

create function c10_gov003_demo._inc_check_token(p_val text, p_what text) returns void
language plpgsql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
begin
  if p_val is null or p_val !~ '^[a-z0-9_.:-]{1,64}$' then
    raise exception 'incident_param_invalid: % must be a lowercase token', p_what using errcode = 'G3A03';
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------------
-- open_incident
-- ---------------------------------------------------------------------------------------------------------
create function c10_gov003_demo.open_incident(
  p_tenant uuid, p_business uuid, p_site uuid, p_case_ref text, p_severity text, p_category text,
  p_idem text, p_claimed_actor uuid default null)
returns table (outcome text, case_id uuid, case_ref text, audit_receipt_id uuid, audit_event_id uuid, replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  a uuid; v_payload jsonb; v_sha text; v_ev uuid; ap record; c record; v_id uuid := gen_random_uuid();
begin
  a := c10_gov003_demo._inc_gate(p_tenant, p_business, p_site, p_claimed_actor, p_idem);
  if p_idem is null or p_case_ref is null or p_case_ref !~ '^[A-Za-z0-9_.:/#-]{1,128}$' or c10_gov003_demo.looks_secret(p_case_ref) then
    raise exception 'incident_param_invalid: case_ref must be an opaque reference' using errcode = 'G3A03';
  end if;
  if p_severity is null or p_severity not in ('low','medium','high','critical')
     or p_category is null or p_category not in ('operational','security','fraud_review','access','data_integrity','other') then
    raise exception 'incident_param_invalid: severity/category' using errcode = 'G3A03';
  end if;
  v_payload := jsonb_build_object('case_ref', p_case_ref, 'severity', p_severity, 'reason_code', p_category,
                                  'status', 'open');
  v_sha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(v_payload));
  perform c10_gov003_demo._inc_lock(p_tenant || '|' || p_business || '|' || p_idem);
  v_ev := c10_gov003_demo._inc_replay(p_tenant, p_business, p_idem, array['incident.open'], p_case_ref, v_sha);
  if v_ev is not null then
    select x.case_id as cid, x.case_ref as cref, x.audit_receipt_id as rid, x.audit_event_id as eid into c
      from c10_gov003_demo.incident_cases x where x.audit_event_id = v_ev;
    return query select 'replayed'::text, c.cid, c.cref, c.rid, c.eid, true;
    return;
  end if;
  if exists (select 1 from c10_gov003_demo.incident_cases x
              where x.tenant_id = p_tenant and x.business_id = p_business and x.case_ref = p_case_ref) then
    raise exception 'idempotency_conflict: case_ref already exists' using errcode = 'G3C01';
  end if;
  select * into ap from c10_gov003_demo._inc_audit(p_tenant, p_business, p_site, p_case_ref, v_id, 'incident.open', p_idem, v_payload);
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.incident_cases (case_id, tenant_id, business_id, site_id, case_ref, severity, category,
      opened_by, opened_at, audit_event_id, audit_receipt_id)
    values (v_id, p_tenant, p_business, p_site, p_case_ref, p_severity, p_category, a, clock_timestamp(),
            ap.event_id, ap.receipt_id);
  perform set_config('c10_gov003.writer', '', true);
  return query select 'created'::text, v_id, p_case_ref, ap.receipt_id, ap.event_id, false;
end $$;

-- ---------------------------------------------------------------------------------------------------------
-- add_evidence (append-only manifest entry; digest chained to the previous entry)
-- ---------------------------------------------------------------------------------------------------------
create function c10_gov003_demo.add_evidence(
  p_tenant uuid, p_business uuid, p_case_ref text, p_evidence_ref text, p_kind text, p_sha256 text,
  p_byte_length bigint, p_source_ref text, p_retain_until timestamptz, p_idem text,
  p_claimed_actor uuid default null)
returns table (outcome text, evidence_id uuid, item_seq int, item_digest text, manifest_digest text,
               audit_receipt_id uuid, audit_event_id uuid, replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  a uuid; cs c10_gov003_demo.incident_cases; v_payload jsonb; v_sha text; v_ev uuid; ap record; it record;
  v_prior text; v_seq int; v_id uuid := gen_random_uuid(); v_now timestamptz; v_dig text;
begin
  a := c10_gov003_demo._inc_gate(p_tenant, p_business, null, p_claimed_actor, p_idem);
  cs := c10_gov003_demo._inc_case(p_tenant, p_business, p_case_ref);
  if p_idem is null or p_evidence_ref is null or p_evidence_ref !~ '^[A-Za-z0-9_.:/#-]{1,128}$'
     or c10_gov003_demo.looks_secret(p_evidence_ref)
     or p_source_ref is null or p_source_ref !~ '^[A-Za-z0-9_.:/#-]{1,128}$' or c10_gov003_demo.looks_secret(p_source_ref) then
    raise exception 'incident_param_invalid: evidence_ref/source_ref must be opaque references' using errcode = 'G3A03';
  end if;
  if p_kind is null or p_kind not in ('log_extract','document','image','export_csv','db_snapshot_ref','other') then
    raise exception 'incident_param_invalid: evidence kind' using errcode = 'G3A03';
  end if;
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'incident_param_invalid: sha256 must be 64 lowercase hex characters' using errcode = 'G3A03';
  end if;
  if p_byte_length is null or p_byte_length < 0 or p_byte_length > 1000000000000 then
    raise exception 'incident_param_invalid: byte_length' using errcode = 'G3A03';
  end if;
  v_payload := jsonb_strip_nulls(jsonb_build_object('case_ref', p_case_ref, 'evidence_ref', p_evidence_ref,
      'entity_kind', p_kind, 'artifact_sha256', p_sha256, 'count', p_byte_length::text, 'source_ref', p_source_ref,
      'window_end', c10_gov003_demo.utc_iso(p_retain_until)));
  v_sha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(v_payload));
  perform c10_gov003_demo._inc_lock(p_tenant || '|' || p_business || '|' || p_idem);
  perform c10_gov003_demo._inc_lock('case|' || cs.case_id);
  v_ev := c10_gov003_demo._inc_replay(p_tenant, p_business, p_idem, array['incident.evidence.add'], p_case_ref, v_sha);
  if v_ev is not null then
    select x.evidence_id as eid, x.item_seq as sq, x.item_digest as dg, x.audit_receipt_id as rid, x.audit_event_id as aid into it
      from c10_gov003_demo.incident_evidence_items x where x.audit_event_id = v_ev;
    return query select 'replayed'::text, it.eid, it.sq, it.dg,
      (select y.item_digest from c10_gov003_demo.incident_evidence_items y
        where y.case_id = cs.case_id order by y.item_seq desc limit 1),
      it.rid, it.aid, true;
    return;
  end if;
  if exists (select 1 from c10_gov003_demo.incident_evidence_items x
              where x.case_id = cs.case_id and x.evidence_ref = p_evidence_ref) then
    raise exception 'idempotency_conflict: evidence_ref already bound to this case' using errcode = 'G3C01';
  end if;
  select x.item_seq as sq, x.item_digest as dg into it
    from c10_gov003_demo.incident_evidence_items x where x.case_id = cs.case_id order by x.item_seq desc limit 1;
  if found then v_seq := it.sq + 1; v_prior := it.dg;
  else v_seq := 1; v_prior := repeat('0', 64); end if;
  v_now := clock_timestamp();
  v_dig := c10_gov003_demo.inc_item_digest_of(v_prior, cs.case_id, v_seq, p_evidence_ref, p_kind, p_sha256,
             p_byte_length, p_source_ref, p_retain_until, v_now, a);
  select * into ap from c10_gov003_demo._inc_audit(p_tenant, p_business, cs.site_id, p_case_ref, cs.case_id,
    'incident.evidence.add', p_idem, v_payload);
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.incident_evidence_items (evidence_id, case_id, tenant_id, business_id, item_seq,
      evidence_ref, kind, sha256, byte_length, source_ref, retain_until, added_by, added_at, prior_digest,
      item_digest, audit_event_id, audit_receipt_id)
    values (v_id, cs.case_id, p_tenant, p_business, v_seq, p_evidence_ref, p_kind, p_sha256, p_byte_length,
            p_source_ref, p_retain_until, a, v_now, v_prior, v_dig, ap.event_id, ap.receipt_id);
  perform set_config('c10_gov003.writer', '', true);
  return query select 'created'::text, v_id, v_seq, v_dig, v_dig, ap.receipt_id, ap.event_id, false;
end $$;

-- ---------------------------------------------------------------------------------------------------------
-- set_hold / review_hold / release_hold
-- ---------------------------------------------------------------------------------------------------------
create function c10_gov003_demo.set_hold(
  p_tenant uuid, p_business uuid, p_case_ref text, p_evidence_ref text, p_hold_ref text,
  p_reason_category text, p_retention_until timestamptz, p_idem text, p_claimed_actor uuid default null)
returns table (outcome text, hold_id uuid, hold_ref text, review_status text, retention_until timestamptz,
               placed_by uuid, audit_receipt_id uuid, audit_event_id uuid, replayed boolean, notice text)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  a uuid; cs c10_gov003_demo.incident_cases; v_payload jsonb; v_sha text; v_ev uuid; ap record; h record;
  v_eid uuid; v_id uuid := gen_random_uuid(); v_now timestamptz;
  v_notice constant text := 'Engineering control in a mutable database only. This is not a legal-hold certification; legal retention decisions are an Owner/counsel gate.';
begin
  a := c10_gov003_demo._inc_gate(p_tenant, p_business, null, p_claimed_actor, p_idem);
  cs := c10_gov003_demo._inc_case(p_tenant, p_business, p_case_ref);
  if p_idem is null or p_hold_ref is null or p_hold_ref !~ '^[A-Za-z0-9_.:/#-]{1,128}$' or c10_gov003_demo.looks_secret(p_hold_ref)
     or p_retention_until is null then
    raise exception 'incident_param_invalid: hold_ref must be an opaque reference and retention_until is required' using errcode = 'G3A03';
  end if;
  if p_reason_category is null or p_reason_category not in
     ('security_incident','fraud_review','owner_directive','counsel_request','regulatory_inquiry','other') then
    raise exception 'incident_param_invalid: hold reason category' using errcode = 'G3A03';
  end if;
  if p_evidence_ref is not null then
    select i.evidence_id into v_eid from c10_gov003_demo.incident_evidence_items i
     where i.case_id = cs.case_id and i.evidence_ref = p_evidence_ref;
    if v_eid is null then
      raise exception 'scope_denied: no such evidence item in this case' using errcode = 'G3A02';
    end if;
  end if;
  v_payload := jsonb_strip_nulls(jsonb_build_object('case_ref', p_case_ref, 'hold_ref', p_hold_ref,
      'reason_code', p_reason_category, 'window_end', c10_gov003_demo.utc_iso(p_retention_until),
      'evidence_ref', p_evidence_ref, 'status', 'active'));
  v_sha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(v_payload));
  perform c10_gov003_demo._inc_lock(p_tenant || '|' || p_business || '|' || p_idem);
  v_ev := c10_gov003_demo._inc_replay(p_tenant, p_business, p_idem, array['incident.hold.set'], p_case_ref, v_sha);
  if v_ev is not null then
    select x.hold_id as hid, x.hold_ref as href, x.retention_until as ru, x.placed_by as pb, x.audit_receipt_id as rid,
           x.audit_event_id as aid into h
      from c10_gov003_demo.incident_holds x where x.audit_event_id = v_ev;
    return query select 'replayed'::text, h.hid, h.href,
      coalesce((select r.decision from c10_gov003_demo.incident_hold_reviews r where r.hold_id = h.hid), 'pending'),
      h.ru, h.pb, h.rid, h.aid, true, v_notice;
    return;
  end if;
  v_now := clock_timestamp();
  if p_retention_until <= v_now then
    raise exception 'incident_param_invalid: retention_until must be in the future' using errcode = 'G3A03';
  end if;
  if exists (select 1 from c10_gov003_demo.incident_holds x where x.case_id = cs.case_id and x.hold_ref = p_hold_ref) then
    raise exception 'idempotency_conflict: hold_ref already exists for this case' using errcode = 'G3C01';
  end if;
  select * into ap from c10_gov003_demo._inc_audit(p_tenant, p_business, cs.site_id, p_case_ref, cs.case_id,
    'incident.hold.set', p_idem, v_payload);
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.incident_holds (hold_id, case_id, tenant_id, business_id, evidence_id, hold_ref,
      reason_category, retention_until, placed_by, placed_at, audit_event_id, audit_receipt_id)
    values (v_id, cs.case_id, p_tenant, p_business, v_eid, p_hold_ref, p_reason_category, p_retention_until, a, v_now,
            ap.event_id, ap.receipt_id);
  perform set_config('c10_gov003.writer', '', true);
  return query select 'created'::text, v_id, p_hold_ref, 'pending'::text, p_retention_until, a, ap.receipt_id,
    ap.event_id, false, v_notice;
end $$;

create function c10_gov003_demo._inc_hold(p_case c10_gov003_demo.incident_cases, p_hold_ref text)
returns c10_gov003_demo.incident_holds
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare h c10_gov003_demo.incident_holds;
begin
  select * into h from c10_gov003_demo.incident_holds x where x.case_id = p_case.case_id and x.hold_ref = p_hold_ref;
  if not found then raise exception 'scope_denied: no such hold in this case' using errcode = 'G3A02'; end if;
  return h;
end $$;

-- The reviewer must be an Owner of the business AND a different identity than the one that placed the hold.
create function c10_gov003_demo.review_hold(
  p_tenant uuid, p_business uuid, p_case_ref text, p_hold_ref text, p_decision text, p_note_code text,
  p_idem text, p_claimed_actor uuid default null)
returns table (outcome text, hold_id uuid, review_status text, reviewer_id uuid, audit_receipt_id uuid,
               replayed boolean, notice text)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  a uuid; cs c10_gov003_demo.incident_cases; h c10_gov003_demo.incident_holds; v_payload jsonb; v_sha text;
  v_ev uuid; ap record; rv record;
  v_notice constant text := 'Engineering control in a mutable database only. This is not a legal-hold certification; legal retention decisions are an Owner/counsel gate.';
begin
  a := c10_gov003_demo._inc_gate(p_tenant, p_business, null, p_claimed_actor, p_idem);
  cs := c10_gov003_demo._inc_case(p_tenant, p_business, p_case_ref);
  if p_idem is null or p_decision is null or p_decision not in ('approved','rejected') then
    raise exception 'incident_param_invalid: decision must be approved or rejected' using errcode = 'G3A03';
  end if;
  perform c10_gov003_demo._inc_check_token(p_note_code, 'note_code');
  h := c10_gov003_demo._inc_hold(cs, p_hold_ref);
  v_payload := jsonb_build_object('case_ref', p_case_ref, 'hold_ref', p_hold_ref, 'review_decision', p_decision,
                                  'note_code', p_note_code, 'status', 'reviewed');
  v_sha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(v_payload));
  perform c10_gov003_demo._inc_lock(p_tenant || '|' || p_business || '|' || p_idem);
  perform c10_gov003_demo._inc_lock('hold|' || h.hold_id);
  v_ev := c10_gov003_demo._inc_replay(p_tenant, p_business, p_idem, array['incident.hold.review'], p_case_ref, v_sha);
  if v_ev is not null then
    select x.decision as dec, x.reviewer_id as rid, x.audit_receipt_id as arid into rv
      from c10_gov003_demo.incident_hold_reviews x where x.audit_event_id = v_ev;
    return query select 'replayed'::text, h.hold_id, rv.dec, rv.rid, rv.arid, true, v_notice;
    return;
  end if;
  if a = h.placed_by then
    raise exception 'scope_denied: independent_review_required: the hold placer cannot review their own hold'
      using errcode = 'G3A02';
  end if;
  if exists (select 1 from c10_gov003_demo.incident_hold_reviews x where x.hold_id = h.hold_id) then
    raise exception 'idempotency_conflict: hold already has a terminal review' using errcode = 'G3C01';
  end if;
  select * into ap from c10_gov003_demo._inc_audit(p_tenant, p_business, cs.site_id, p_case_ref, cs.case_id,
    'incident.hold.review', p_idem, v_payload);
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.incident_hold_reviews (hold_id, tenant_id, business_id, reviewer_id, decision, note_code,
      reviewed_at, audit_event_id, audit_receipt_id)
    values (h.hold_id, p_tenant, p_business, a, p_decision, p_note_code, clock_timestamp(), ap.event_id, ap.receipt_id);
  perform set_config('c10_gov003.writer', '', true);
  return query select 'created'::text, h.hold_id, p_decision, a, ap.receipt_id, false, v_notice;
end $$;

-- release_hold ends the open-ended hold flag. It adds a row (never deletes). The hold's retention_until floor
-- still protects the evidence until it passes. Releasing needs an Owner who is NOT the hold placer.
create function c10_gov003_demo.release_hold(
  p_tenant uuid, p_business uuid, p_case_ref text, p_hold_ref text, p_reason_code text,
  p_idem text, p_claimed_actor uuid default null)
returns table (outcome text, hold_id uuid, released_by uuid, retention_until timestamptz, still_retained boolean,
               audit_receipt_id uuid, replayed boolean, notice text)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  a uuid; cs c10_gov003_demo.incident_cases; h c10_gov003_demo.incident_holds; v_payload jsonb; v_sha text;
  v_ev uuid; ap record; rl record;
  v_notice constant text := 'Engineering control in a mutable database only. This is not a legal-hold certification; legal retention decisions are an Owner/counsel gate.';
begin
  a := c10_gov003_demo._inc_gate(p_tenant, p_business, null, p_claimed_actor, p_idem);
  cs := c10_gov003_demo._inc_case(p_tenant, p_business, p_case_ref);
  if p_idem is null then raise exception 'incident_param_invalid: idempotency key' using errcode = 'G3A03'; end if;
  perform c10_gov003_demo._inc_check_token(p_reason_code, 'reason_code');
  h := c10_gov003_demo._inc_hold(cs, p_hold_ref);
  v_payload := jsonb_build_object('case_ref', p_case_ref, 'hold_ref', p_hold_ref, 'reason_code', p_reason_code,
                                  'status', 'released');
  v_sha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(v_payload));
  perform c10_gov003_demo._inc_lock(p_tenant || '|' || p_business || '|' || p_idem);
  perform c10_gov003_demo._inc_lock('hold|' || h.hold_id);
  v_ev := c10_gov003_demo._inc_replay(p_tenant, p_business, p_idem, array['incident.hold.release'], p_case_ref, v_sha);
  if v_ev is not null then
    select x.released_by as rb, x.audit_receipt_id as arid into rl
      from c10_gov003_demo.incident_hold_releases x where x.audit_event_id = v_ev;
    return query select 'replayed'::text, h.hold_id, rl.rb, h.retention_until, h.retention_until > clock_timestamp(),
      rl.arid, true, v_notice;
    return;
  end if;
  if a = h.placed_by then
    raise exception 'scope_denied: independent_release_required: the hold placer cannot release their own hold'
      using errcode = 'G3A02';
  end if;
  if exists (select 1 from c10_gov003_demo.incident_hold_releases x where x.hold_id = h.hold_id) then
    raise exception 'idempotency_conflict: hold already released' using errcode = 'G3C01';
  end if;
  select * into ap from c10_gov003_demo._inc_audit(p_tenant, p_business, cs.site_id, p_case_ref, cs.case_id,
    'incident.hold.release', p_idem, v_payload);
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.incident_hold_releases (hold_id, tenant_id, business_id, released_by, reason_code,
      released_at, audit_event_id, audit_receipt_id)
    values (h.hold_id, p_tenant, p_business, a, p_reason_code, clock_timestamp(), ap.event_id, ap.receipt_id);
  perform set_config('c10_gov003.writer', '', true);
  return query select 'created'::text, h.hold_id, a, h.retention_until, h.retention_until > clock_timestamp(),
    ap.receipt_id, false, v_notice;
end $$;

-- ---------------------------------------------------------------------------------------------------------
-- purge_evidence_attempt: the retention/purge service of the isolated test bed.
-- While any hold or future retention-until covers the evidence it REFUSES: outcome = 'refused' with
-- error_code = 'G3H02', and the refusal is AUDITED. (A SQL function cannot both raise and keep an audit row in
-- the same transaction, so the refusal is returned as data; the append-only triggers raise G3H02/G3H01 for any
-- direct UPDATE/DELETE path.) When nothing protects the evidence it only appends a tombstone row: history,
-- manifest and the evidence item are never edited or deleted, and the SHA-256 stays on record.
-- ---------------------------------------------------------------------------------------------------------
create function c10_gov003_demo.purge_evidence_attempt(
  p_tenant uuid, p_business uuid, p_case_ref text, p_evidence_ref text, p_reason_code text,
  p_idem text, p_claimed_actor uuid default null)
returns table (outcome text, error_code text, protection text[], evidence_id uuid, audit_receipt_id uuid,
               replayed boolean, notice text)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  a uuid; cs c10_gov003_demo.incident_cases; ev record; v_prot text[]; v_payload jsonb; v_ev uuid; ap record;
  prev record; v_detail text;
  v_notice constant text := 'Engineering control in a mutable database only. This is not a legal-hold certification; legal retention decisions are an Owner/counsel gate.';
begin
  a := c10_gov003_demo._inc_gate(p_tenant, p_business, null, p_claimed_actor, p_idem);
  cs := c10_gov003_demo._inc_case(p_tenant, p_business, p_case_ref);
  if p_idem is null or p_evidence_ref is null then
    raise exception 'incident_param_invalid: idempotency key and evidence_ref are required' using errcode = 'G3A03';
  end if;
  perform c10_gov003_demo._inc_check_token(p_reason_code, 'reason_code');
  select i.evidence_id as eid, i.sha256 as sha into ev from c10_gov003_demo.incident_evidence_items i
   where i.case_id = cs.case_id and i.evidence_ref = p_evidence_ref;
  if not found then
    raise exception 'scope_denied: no such evidence item in this case' using errcode = 'G3A02';
  end if;
  perform c10_gov003_demo._inc_lock(p_tenant || '|' || p_business || '|' || p_idem);
  perform c10_gov003_demo._inc_lock('evidence|' || ev.eid);

  -- Replay of the same request returns the originally recorded decision (the state may have changed since).
  select x.event_id as eid, x.action as act, x.source_id as sid, x.payload as pl into prev
    from c10_gov003_demo.audit_events x
   where x.tenant_id = p_tenant and x.business_id = p_business and x.idempotency_key = 'inc.' || p_idem;
  if found then
    if prev.act in ('incident.purge.blocked', 'incident.purge.tombstone') and prev.sid = p_case_ref
       and prev.pl ->> 'evidence_ref' = p_evidence_ref and prev.pl ->> 'reason_code' = p_reason_code then
      select r.receipt_id as rid into ap from c10_gov003_demo.audit_receipts r where r.event_id = prev.eid;
      if prev.act = 'incident.purge.blocked' then
        return query select 'refused'::text, 'G3H02'::text, string_to_array(prev.pl ->> 'detail_code', '.'),
          ev.eid, ap.rid, true, v_notice;
      else
        return query select 'tombstoned'::text, null::text, '{}'::text[], ev.eid, ap.rid, true, v_notice;
      end if;
      return;
    end if;
    raise exception 'idempotency_conflict: key reused with a different incident request' using errcode = 'G3C01';
  end if;

  if exists (select 1 from c10_gov003_demo.incident_evidence_tombstones t where t.evidence_id = ev.eid) then
    return query select 'already_purged'::text, null::text, '{}'::text[], ev.eid, null::uuid, false, v_notice;
    return;
  end if;

  v_prot := c10_gov003_demo._inc_protection(ev.eid);
  if cardinality(v_prot) > 0 then
    v_detail := array_to_string(v_prot, '.');
    v_payload := jsonb_build_object('case_ref', p_case_ref, 'evidence_ref', p_evidence_ref, 'status', 'blocked',
                                    'detail_code', v_detail, 'reason_code', p_reason_code);
    select * into ap from c10_gov003_demo._inc_audit(p_tenant, p_business, cs.site_id, p_case_ref, cs.case_id,
      'incident.purge.blocked', p_idem, v_payload);
    return query select 'refused'::text, 'G3H02'::text, v_prot, ev.eid, ap.receipt_id, false, v_notice;
    return;
  end if;

  v_payload := jsonb_build_object('case_ref', p_case_ref, 'evidence_ref', p_evidence_ref, 'status', 'tombstoned',
                                  'detail_code', 'no_hold', 'reason_code', p_reason_code);
  select * into ap from c10_gov003_demo._inc_audit(p_tenant, p_business, cs.site_id, p_case_ref, cs.case_id,
    'incident.purge.tombstone', p_idem, v_payload);
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.incident_evidence_tombstones (evidence_id, case_id, tenant_id, business_id, sha256_retained,
      purged_by, reason_code, purged_at, audit_event_id, audit_receipt_id)
    values (ev.eid, cs.case_id, p_tenant, p_business, ev.sha, a, p_reason_code, clock_timestamp(), ap.event_id, ap.receipt_id);
  perform set_config('c10_gov003.writer', '', true);
  return query select 'tombstoned'::text, null::text, '{}'::text[], ev.eid, ap.receipt_id, false, v_notice;
end $$;

-- ---------------------------------------------------------------------------------------------------------
-- Read functions: manifest integrity and single-item integrity
-- ---------------------------------------------------------------------------------------------------------
create function c10_gov003_demo.verify_manifest(
  p_tenant uuid, p_business uuid, p_case_ref text, p_expected_digest text default null)
returns table (ok boolean, item_count int, purged_count int, manifest_digest text, first_bad_seq int, reason text)
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  cs c10_gov003_demo.incident_cases; r record; prior text := repeat('0', 64); n int := 0; d text; pc int; ev record;
begin
  if c10_gov003_demo.actor_id() is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if p_tenant is null or p_business is null or not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  cs := c10_gov003_demo._inc_case(p_tenant, p_business, p_case_ref);
  select count(*)::int into pc from c10_gov003_demo.incident_evidence_tombstones t where t.case_id = cs.case_id;
  for r in select * from c10_gov003_demo.incident_evidence_items i where i.case_id = cs.case_id order by i.item_seq loop
    n := n + 1;
    if r.item_seq <> n then
      return query select false, n, pc, prior, r.item_seq, 'sequence_gap'::text; return;
    end if;
    if r.prior_digest <> prior then
      return query select false, n, pc, prior, r.item_seq, 'prior_digest_mismatch'::text; return;
    end if;
    d := c10_gov003_demo.inc_item_digest_of(r.prior_digest, r.case_id, r.item_seq, r.evidence_ref, r.kind, r.sha256,
           r.byte_length, r.source_ref, r.retain_until, r.added_at, r.added_by);
    if d <> r.item_digest then
      return query select false, n, pc, prior, r.item_seq, 'item_digest_mismatch'::text; return;
    end if;
    select e.action as act, e.payload as pl, e.source_id as sid into ev
      from c10_gov003_demo.audit_events e where e.event_id = r.audit_event_id;
    if not found or ev.act <> 'incident.evidence.add' or ev.sid <> p_case_ref
       or ev.pl ->> 'artifact_sha256' <> r.sha256 or ev.pl ->> 'evidence_ref' <> r.evidence_ref
       or ev.pl ->> 'count' <> r.byte_length::text then
      return query select false, n, pc, prior, r.item_seq, 'audit_link_mismatch'::text; return;
    end if;
    prior := r.item_digest;
  end loop;
  if n = 0 then prior := c10_gov003_demo.inc_empty_manifest_digest(cs.case_id); end if;
  if p_expected_digest is not null and p_expected_digest <> prior then
    raise exception 'manifest_digest_mismatch: supplied manifest digest does not match the recomputed digest'
      using errcode = 'G3A04';
  end if;
  return query select true, n, pc, prior, null::int, null::text;
end $$;

create function c10_gov003_demo.verify_evidence_item(
  p_tenant uuid, p_business uuid, p_case_ref text, p_evidence_ref text, p_sha256 text,
  p_byte_length bigint default null)
returns table (ok boolean, evidence_id uuid, purged boolean)
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare cs c10_gov003_demo.incident_cases; i record;
begin
  if c10_gov003_demo.actor_id() is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if p_tenant is null or p_business is null or not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  cs := c10_gov003_demo._inc_case(p_tenant, p_business, p_case_ref);
  select x.evidence_id as eid, x.sha256 as sha, x.byte_length as len,
         exists (select 1 from c10_gov003_demo.incident_evidence_tombstones t where t.evidence_id = x.evidence_id) as pg
    into i from c10_gov003_demo.incident_evidence_items x
   where x.case_id = cs.case_id and x.evidence_ref = p_evidence_ref;
  if not found then raise exception 'scope_denied: no such evidence item in this case' using errcode = 'G3A02'; end if;
  if p_sha256 is distinct from i.sha or (p_byte_length is not null and p_byte_length <> i.len) then
    raise exception 'evidence_hash_mismatch: supplied content does not match the manifest entry' using errcode = 'G3A04';
  end if;
  return query select true, i.eid, i.pg;
end $$;

-- ---------------------------------------------------------------------------------------------------------
-- Grants: writers to c10g3_backend only; read functions to backend + reader; helpers owner-only.
-- ---------------------------------------------------------------------------------------------------------
revoke all on function
  c10_gov003_demo.inc_item_digest_of(text,uuid,int,text,text,text,bigint,text,timestamptz,timestamptz,uuid),
  c10_gov003_demo.inc_empty_manifest_digest(uuid),
  c10_gov003_demo._inc_protection(uuid,timestamptz),
  c10_gov003_demo._inc_guard_evidence(), c10_gov003_demo._inc_guard_tombstone(),
  c10_gov003_demo._inc_gate(uuid,uuid,uuid,uuid,text),
  c10_gov003_demo._inc_case(uuid,uuid,text),
  c10_gov003_demo._inc_replay(uuid,uuid,text,text[],text,text),
  c10_gov003_demo._inc_audit(uuid,uuid,uuid,text,uuid,text,text,jsonb),
  c10_gov003_demo._inc_lock(text), c10_gov003_demo._inc_check_token(text,text),
  c10_gov003_demo._inc_hold(c10_gov003_demo.incident_cases,text),
  c10_gov003_demo.open_incident(uuid,uuid,uuid,text,text,text,text,uuid),
  c10_gov003_demo.add_evidence(uuid,uuid,text,text,text,text,bigint,text,timestamptz,text,uuid),
  c10_gov003_demo.set_hold(uuid,uuid,text,text,text,text,timestamptz,text,uuid),
  c10_gov003_demo.review_hold(uuid,uuid,text,text,text,text,text,uuid),
  c10_gov003_demo.release_hold(uuid,uuid,text,text,text,text,uuid),
  c10_gov003_demo.purge_evidence_attempt(uuid,uuid,text,text,text,text,uuid),
  c10_gov003_demo.verify_manifest(uuid,uuid,text,text),
  c10_gov003_demo.verify_evidence_item(uuid,uuid,text,text,text,bigint)
  from public;
grant execute on function
  c10_gov003_demo.open_incident(uuid,uuid,uuid,text,text,text,text,uuid),
  c10_gov003_demo.add_evidence(uuid,uuid,text,text,text,text,bigint,text,timestamptz,text,uuid),
  c10_gov003_demo.set_hold(uuid,uuid,text,text,text,text,timestamptz,text,uuid),
  c10_gov003_demo.review_hold(uuid,uuid,text,text,text,text,text,uuid),
  c10_gov003_demo.release_hold(uuid,uuid,text,text,text,text,uuid),
  c10_gov003_demo.purge_evidence_attempt(uuid,uuid,text,text,text,text,uuid)
  to c10g3_backend;
grant execute on function
  c10_gov003_demo.verify_manifest(uuid,uuid,text,text),
  c10_gov003_demo.verify_evidence_item(uuid,uuid,text,text,text,bigint)
  to c10g3_backend, c10g3_reader;
