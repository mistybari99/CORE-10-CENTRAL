-- Trusted append boundary: actor derived server-side, scope-checked, idempotent, hash-chained, receipted.
\set ON_ERROR_STOP on
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

create function c10_gov003_demo.utc_iso(p timestamptz) returns text
language sql immutable
set search_path = pg_catalog
as $$ select to_char(p at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') $$;

create function c10_gov003_demo.event_digest_of(
  p_prior text, p_event uuid, p_tenant uuid, p_business uuid, p_site uuid, p_seq bigint,
  p_domain text, p_source_id text, p_source_version text, p_action text,
  p_event_time timestamptz, p_ingest_time timestamptz, p_actor uuid, p_corr text, p_idem text,
  p_payload_sha text, p_reason text, p_schema int)
returns text
language sql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select c10_gov003_demo.g3_sha256(concat_ws('|', 'g3e1', p_prior, p_event, p_tenant, p_business,
    coalesce(p_site::text, ''), p_seq, p_domain, p_source_id, p_source_version, p_action,
    c10_gov003_demo.utc_iso(p_event_time), c10_gov003_demo.utc_iso(p_ingest_time), p_actor, p_corr,
    p_idem, p_payload_sha, p_reason, p_schema));
$$;

create function c10_gov003_demo.receipt_digest_of(
  p_receipt uuid, p_event uuid, p_event_digest text, p_payload_sha text, p_idem text, p_issued timestamptz)
returns text
language sql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select c10_gov003_demo.g3_sha256(concat_ws('|', 'g3r1', p_receipt, p_event, p_event_digest,
    p_payload_sha, p_idem, c10_gov003_demo.utc_iso(p_issued)));
$$;

-- INTERNAL. Only owner-run functions call this (it is not granted to any other role).
create function c10_gov003_demo._append_audit(
  p_tenant uuid, p_business uuid, p_site uuid, p_entity uuid,
  p_source_domain text, p_source_id text, p_source_version text, p_action text,
  p_event_time timestamptz, p_correlation text, p_idem text,
  p_payload jsonb, p_payload_sha text, p_reason text, p_schema_version int,
  p_claimed_actor uuid, p_event_id uuid)
returns table (outcome text, event_id uuid, receipt_id uuid, stream_seq bigint, event_digest text,
               receipt_digest text, replayed boolean, payload_sha256 text)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  a uuid := c10_gov003_demo.actor_id();
  computed text;
  ex record;
  head record;
  v_seq bigint; v_prior text; v_eid uuid; v_rid uuid; v_ing timestamptz; v_edig text; v_rdig text;
begin
  if a is null then
    raise exception 'actor_unauthenticated' using errcode = 'G3A05';
  end if;
  if p_claimed_actor is not null and p_claimed_actor <> a then
    raise exception 'forged_actor: caller-supplied actor does not match the server-derived actor'
      using errcode = 'G3A01';
  end if;
  if p_tenant is null or p_business is null or p_source_domain is null or p_source_id is null
     or p_source_version is null or p_action is null or p_event_time is null or p_correlation is null
     or p_idem is null or p_payload is null or p_reason is null then
    raise exception 'scope_denied: missing required scope or field' using errcode = 'G3A02';
  end if;
  if not c10_gov003_demo.scope_exists(p_tenant, p_business, p_site, p_entity)
     or not c10_gov003_demo.can_write_scope(p_tenant, p_business, p_site) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  perform c10_gov003_demo.validate_payload(p_payload);
  computed := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(p_payload));
  if p_payload_sha is not null and p_payload_sha <> computed then
    raise exception 'payload_hash_mismatch: supplied digest does not match canonical payload'
      using errcode = 'G3A04';
  end if;

  -- One stored result per (tenant, business, key), even with simultaneous independent sessions.
  perform pg_advisory_xact_lock(hashtextextended('g3idem|' || p_tenant || '|' || p_business || '|' || p_idem, 0));

  select e.event_id as eid, e.payload_sha256 as psha, e.action as act, e.source_domain as sd,
         e.source_id as sid, r.receipt_id as rid, e.stream_seq as sq, e.event_digest as edig,
         r.receipt_digest as rdig
    into ex
    from c10_gov003_demo.audit_events e
    join c10_gov003_demo.audit_receipts r on r.event_id = e.event_id
   where e.tenant_id = p_tenant and e.business_id = p_business and e.idempotency_key = p_idem;
  if found then
    if ex.psha = computed and ex.act = p_action and ex.sd = p_source_domain and ex.sid = p_source_id then
      return query select 'replayed'::text, ex.eid, ex.rid, ex.sq, ex.edig, ex.rdig, true, computed;
      return;
    end if;
    raise exception 'idempotency_conflict: key reused with a different payload or command'
      using errcode = 'G3C01';
  end if;

  insert into c10_gov003_demo.audit_chain_heads (tenant_id, business_id, last_seq, last_digest)
    values (p_tenant, p_business, 0, repeat('0', 64))
    on conflict do nothing;
  select h.last_seq, h.last_digest into head
    from c10_gov003_demo.audit_chain_heads h
   where h.tenant_id = p_tenant and h.business_id = p_business for update;
  v_seq := head.last_seq + 1;
  v_prior := head.last_digest;
  v_eid := coalesce(p_event_id, gen_random_uuid());
  v_rid := gen_random_uuid();
  v_ing := clock_timestamp();
  v_edig := c10_gov003_demo.event_digest_of(v_prior, v_eid, p_tenant, p_business, p_site, v_seq,
              p_source_domain, p_source_id, p_source_version, p_action, p_event_time, v_ing, a,
              p_correlation, p_idem, computed, p_reason, p_schema_version);
  v_rdig := c10_gov003_demo.receipt_digest_of(v_rid, v_eid, v_edig, computed, p_idem, v_ing);

  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.audit_events
    (event_id, tenant_id, business_id, legal_entity_id, site_id, stream_seq, source_domain, source_id,
     source_version, action, event_time, ingest_time, actor_id, correlation_id, idempotency_key,
     payload, payload_sha256, prior_digest, event_digest, reason_category, schema_version)
  values (v_eid, p_tenant, p_business, p_entity, p_site, v_seq, p_source_domain, p_source_id,
     p_source_version, p_action, p_event_time, v_ing, a, p_correlation, p_idem,
     p_payload, computed, v_prior, v_edig, p_reason, p_schema_version);
  insert into c10_gov003_demo.audit_receipts
    (receipt_id, event_id, tenant_id, business_id, idempotency_key, payload_sha256, event_digest,
     issued_at, receipt_digest)
  values (v_rid, v_eid, p_tenant, p_business, p_idem, computed, v_edig, v_ing, v_rdig);
  perform set_config('c10_gov003.writer', '', true);

  update c10_gov003_demo.audit_chain_heads h
     set last_seq = v_seq, last_digest = v_edig
   where h.tenant_id = p_tenant and h.business_id = p_business;

  return query select 'created'::text, v_eid, v_rid, v_seq, v_edig, v_rdig, false, computed;
end $$;

-- PUBLIC (backend-only) append RPC. Actor is NEVER taken from the caller; p_claimed_actor exists only
-- so a forged client assertion is detected and rejected.
create function c10_gov003_demo.append_event(
  p_tenant uuid, p_business uuid, p_site uuid, p_entity uuid,
  p_source_domain text, p_source_id text, p_source_version text, p_action text,
  p_event_time timestamptz, p_correlation text, p_idem text,
  p_payload jsonb, p_payload_sha text, p_reason text,
  p_claimed_actor uuid default null, p_event_id uuid default null)
returns table (outcome text, event_id uuid, receipt_id uuid, stream_seq bigint, event_digest text,
               receipt_digest text, replayed boolean, payload_sha256 text)
language sql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select * from c10_gov003_demo._append_audit(p_tenant, p_business, p_site, p_entity, p_source_domain,
    p_source_id, p_source_version, p_action, p_event_time, p_correlation, p_idem, p_payload,
    p_payload_sha, p_reason, 1, p_claimed_actor, p_event_id);
$$;

-- Read-only chain verification (tamper-evidence for ordinary rewrites; see limitation above).
create function c10_gov003_demo.verify_chain(p_tenant uuid, p_business uuid)
returns table (ok boolean, checked bigint, first_bad_seq bigint, reason text)
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare r record; prior text := repeat('0', 64); n bigint := 0; exp_seq bigint := 1; d text; rd text;
begin
  if not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  for r in select e.*, rc.receipt_id as rid, rc.receipt_digest as rdig, rc.issued_at as issued,
                  rc.event_digest as rc_event_digest, rc.payload_sha256 as rc_payload_sha
             from c10_gov003_demo.audit_events e
             left join c10_gov003_demo.audit_receipts rc on rc.event_id = e.event_id
            where e.tenant_id = p_tenant and e.business_id = p_business
            order by e.stream_seq loop
    n := n + 1;
    if r.stream_seq <> exp_seq then
      return query select false, n, r.stream_seq, 'sequence_gap'::text; return;
    end if;
    if r.prior_digest <> prior then
      return query select false, n, r.stream_seq, 'prior_digest_mismatch'::text; return;
    end if;
    if r.payload_sha256 <> c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(r.payload)) then
      return query select false, n, r.stream_seq, 'payload_hash_mismatch'::text; return;
    end if;
    d := c10_gov003_demo.event_digest_of(r.prior_digest, r.event_id, r.tenant_id, r.business_id,
           r.site_id, r.stream_seq, r.source_domain, r.source_id, r.source_version, r.action,
           r.event_time, r.ingest_time, r.actor_id, r.correlation_id, r.idempotency_key,
           r.payload_sha256, r.reason_category, r.schema_version);
    if d <> r.event_digest then
      return query select false, n, r.stream_seq, 'event_digest_mismatch'::text; return;
    end if;
    if r.rid is null then
      return query select false, n, r.stream_seq, 'receipt_missing'::text; return;
    end if;
    rd := c10_gov003_demo.receipt_digest_of(r.rid, r.event_id, r.event_digest, r.payload_sha256,
            r.idempotency_key, r.issued);
    if rd <> r.rdig or r.rc_event_digest <> r.event_digest or r.rc_payload_sha <> r.payload_sha256 then
      return query select false, n, r.stream_seq, 'receipt_digest_mismatch'::text; return;
    end if;
    prior := r.event_digest;
    exp_seq := exp_seq + 1;
  end loop;
  return query select true, n, null::bigint, null::text;
end $$;

revoke all on function c10_gov003_demo.g3_sha256(text), c10_gov003_demo.canonical_json(jsonb),
  c10_gov003_demo.validate_payload(jsonb), c10_gov003_demo.looks_secret(text),
  c10_gov003_demo.utc_iso(timestamptz), c10_gov003_demo.deny_mutation(),
  c10_gov003_demo.require_append_path(), c10_gov003_demo.protect_table(regclass),
  c10_gov003_demo.event_digest_of(text,uuid,uuid,uuid,uuid,bigint,text,text,text,text,timestamptz,timestamptz,uuid,text,text,text,text,int),
  c10_gov003_demo.receipt_digest_of(uuid,uuid,text,text,text,timestamptz),
  c10_gov003_demo._append_audit(uuid,uuid,uuid,uuid,text,text,text,text,timestamptz,text,text,jsonb,text,text,int,uuid,uuid),
  c10_gov003_demo.append_event(uuid,uuid,uuid,uuid,text,text,text,text,timestamptz,text,text,jsonb,text,text,uuid,uuid),
  c10_gov003_demo.verify_chain(uuid,uuid)
  from public;
grant execute on function c10_gov003_demo.canonical_json(jsonb), c10_gov003_demo.g3_sha256(text)
  to c10g3_backend, c10g3_reader;
grant execute on function c10_gov003_demo.append_event(uuid,uuid,uuid,uuid,text,text,text,text,timestamptz,text,text,jsonb,text,text,uuid,uuid)
  to c10g3_backend;
grant execute on function c10_gov003_demo.verify_chain(uuid,uuid) to c10g3_backend, c10g3_reader;
