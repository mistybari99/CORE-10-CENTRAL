-- Append-only audit history, hash chain, receipts, payload allowlist, canonical JSON.
-- LIMITATION (stated on purpose): a hash chain inside a mutable PostgreSQL database is tamper-EVIDENT
-- against ordinary principals, NOT legal WORM protection against a privileged DBA/superuser who can
-- disable triggers or rewrite storage. verify_chain() detects such edits; it cannot prevent them.
\set ON_ERROR_STOP on
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

create function c10_gov003_demo.g3_sha256(p text) returns text
language sql immutable parallel safe
set search_path = pg_catalog
as $$ select encode(sha256(convert_to(p, 'UTF8')), 'hex') $$;

-- Canonical JSON: sorted keys (bytewise), no whitespace, integers only (decimals travel as strings).
-- Byte-identical to internal/gov003/server/canonical.mjs for the supported value domain.
create function c10_gov003_demo.canonical_json(p jsonb) returns text
language plpgsql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare r text; k text; i int; n numeric; firstitem boolean := true;
begin
  case jsonb_typeof(p)
    when 'object' then
      r := '{';
      for k in select key from jsonb_object_keys(p) as key order by key collate "C" loop
        if not firstitem then r := r || ','; end if;
        firstitem := false;
        r := r || (to_jsonb(k))::text || ':' || c10_gov003_demo.canonical_json(p -> k);
      end loop;
      return r || '}';
    when 'array' then
      r := '[';
      for i in 0 .. jsonb_array_length(p) - 1 loop
        if i > 0 then r := r || ','; end if;
        r := r || c10_gov003_demo.canonical_json(p -> i);
      end loop;
      return r || ']';
    when 'string' then return p::text;
    when 'number' then
      n := (p #>> '{}')::numeric;
      if n <> trunc(n) then
        raise exception 'canonical_json: non-integer number not allowed (use decimal strings)'
          using errcode = 'G3A03';
      end if;
      return trunc(n)::text;
    when 'boolean' then return p::text;
    else return 'null';
  end case;
end $$;

-- Approved payload fields only. kind drives value validation (fail closed).
create table c10_gov003_demo.payload_allowlist (
  field_name text primary key check (field_name ~ '^[a-z][a-z0-9_]{0,62}$'),
  kind       text not null check (kind in ('enum','ref','money','count','ts','text'))
);
insert into c10_gov003_demo.payload_allowlist (field_name, kind) values
  ('amount_minor','money'), ('currency','enum'), ('item_ref','ref'), ('quantity_milli','count'),
  ('unit','enum'), ('status','enum'), ('old_status','enum'), ('new_status','enum'),
  ('reason_code','enum'), ('entity_ref','ref'), ('entity_kind','enum'), ('source_ref','ref'),
  ('channel','enum'), ('window_start','ts'), ('window_end','ts'), ('count','count'),
  ('expected_count','count'), ('row_count','count'), ('grant_ref','ref'), ('policy_ref','ref'),
  ('severity','enum'), ('note_code','enum'), ('signal_ref','ref'), ('review_decision','enum'),
  ('evidence_ref','ref'), ('artifact_sha256','ref'), ('commit_sha','ref'), ('report_id','ref'),
  ('filter_ref','ref'), ('hold_ref','ref'), ('case_ref','ref'), ('feature_id','ref'),
  ('requirement_id','ref'), ('receipt_ref','ref'), ('batch_ref','ref'), ('doc_ref','ref'),
  ('method','enum'), ('detail_code','enum'), ('observed_at','ts'), ('last_seen_at','ts');
alter table c10_gov003_demo.payload_allowlist enable row level security;
revoke all on c10_gov003_demo.payload_allowlist from public;

create function c10_gov003_demo.looks_secret(p text) returns boolean
language sql immutable
set search_path = pg_catalog
as $$
  select p ~ 'eyJ[A-Za-z0-9_-]{8,}'
      or p ~* '(bearer[[:space:]]|service[_-]?role|passw(or)?d|secret|api[_-]?key|token|private[_-]?key|authorization)'
      or p ~ '[^[:space:]@]+@[^[:space:]@]+\.[A-Za-z]{2,}'
      or p ~ '(^|[^0-9A-Za-z-])[0-9]{13,19}($|[^0-9A-Za-z-])'
      or p ~ '^[0-9]{9,}$'
      or p ~ E'\\n[[:space:]]+at ';
$$;

-- Defense-in-depth validation of an ALREADY-redacted payload. Rejects instead of silently dropping.
create function c10_gov003_demo.validate_payload(p jsonb) returns void
language plpgsql stable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare k text; v jsonb; kd text; s text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'payload_not_allowed: payload must be an object' using errcode = 'G3A03';
  end if;
  for k, v in select key, value from jsonb_each(p) loop
    select a.kind into kd from c10_gov003_demo.payload_allowlist a where a.field_name = k;
    if kd is null then
      raise exception 'payload_not_allowed: field "%" is not approved', left(k, 40) using errcode = 'G3A03';
    end if;
    if jsonb_typeof(v) not in ('string','number','boolean','null') then
      raise exception 'payload_not_allowed: field "%" must be scalar', k using errcode = 'G3A03';
    end if;
    if jsonb_typeof(v) = 'number' then
      raise exception 'payload_not_allowed: field "%" must be a string (decimals/ints travel as strings)', k
        using errcode = 'G3A03';
    end if;
    if jsonb_typeof(v) = 'string' then
      s := v #>> '{}';
      if length(s) > 256 then
        raise exception 'payload_not_allowed: field "%" too long', k using errcode = 'G3A03';
      end if;
      if kd = 'money' and s !~ '^-?[0-9]{1,18}$' then
        raise exception 'payload_not_allowed: field "%" must be integer minor units', k using errcode = 'G3A03';
      elsif kd = 'count' and s !~ '^-?[0-9]{1,15}$' then
        raise exception 'payload_not_allowed: field "%" must be an integer', k using errcode = 'G3A03';
      elsif kd = 'ts' and s !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$' then
        raise exception 'payload_not_allowed: field "%" must be UTC ISO time', k using errcode = 'G3A03';
      elsif kd = 'enum' and s !~ '^[a-z0-9_.:-]{1,64}$' then
        raise exception 'payload_not_allowed: field "%" must be an enum token', k using errcode = 'G3A03';
      elsif kd = 'ref' and (s !~ '^[A-Za-z0-9_.:/#-]{1,128}$' or c10_gov003_demo.looks_secret(s)) then
        raise exception 'payload_not_allowed: field "%" is not an opaque reference', k using errcode = 'G3A03';
      elsif kd = 'text' and c10_gov003_demo.looks_secret(s) then
        raise exception 'payload_not_allowed: field "%" looks sensitive', k using errcode = 'G3A03';
      end if;
    end if;
  end loop;
end $$;

create table c10_gov003_demo.audit_chain_heads (
  tenant_id   uuid not null,
  business_id uuid not null,
  last_seq    bigint not null,
  last_digest text not null,
  primary key (tenant_id, business_id),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);

create table c10_gov003_demo.audit_events (
  event_id        uuid primary key,
  tenant_id       uuid not null,
  business_id     uuid not null,
  legal_entity_id uuid,
  site_id         uuid,
  stream_seq      bigint not null,
  source_domain   text not null check (source_domain ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  source_id       text not null check (source_id ~ '^[A-Za-z0-9_.:/#-]{1,128}$'),
  source_version  text not null check (source_version ~ '^[A-Za-z0-9_.:+-]{1,64}$'),
  action          text not null check (action ~ '^[a-z][a-z0-9_.-]{1,63}$'),
  event_time      timestamptz not null,
  ingest_time     timestamptz not null,
  actor_id        uuid not null references c10_gov003_demo.identities,
  correlation_id  text not null check (correlation_id ~ '^[A-Za-z0-9_.:-]{1,128}$'),
  idempotency_key text not null check (idempotency_key ~ '^[A-Za-z0-9_.:-]{8,128}$'),
  payload         jsonb not null,
  payload_sha256  text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  prior_digest    text not null check (prior_digest ~ '^[0-9a-f]{64}$'),
  event_digest    text not null check (event_digest ~ '^[0-9a-f]{64}$'),
  reason_category text not null check (reason_category in
    ('operational','security','compliance','finance','inventory','access','readiness','export','incident','review','other')),
  schema_version  int not null check (schema_version = 1),
  unique (tenant_id, business_id, stream_seq),
  unique (tenant_id, business_id, idempotency_key),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses,
  foreign key (tenant_id, business_id, site_id) references c10_gov003_demo.sites,
  foreign key (tenant_id, business_id, legal_entity_id) references c10_gov003_demo.legal_entities
);
create index audit_events_scope_time_idx on c10_gov003_demo.audit_events (tenant_id, business_id, event_time);
create index audit_events_source_idx on c10_gov003_demo.audit_events (tenant_id, business_id, source_domain, source_id);

create table c10_gov003_demo.audit_receipts (
  receipt_id      uuid primary key,
  event_id        uuid not null unique references c10_gov003_demo.audit_events,
  tenant_id       uuid not null,
  business_id     uuid not null,
  idempotency_key text not null,
  payload_sha256  text not null,
  event_digest    text not null,
  issued_at       timestamptz not null,
  receipt_digest  text not null check (receipt_digest ~ '^[0-9a-f]{64}$'),
  unique (tenant_id, business_id, idempotency_key),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);

-- Immutability: nobody (including the table owner role) can UPDATE/DELETE/TRUNCATE history.
create function c10_gov003_demo.deny_mutation() returns trigger
language plpgsql
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
begin
  raise exception 'append_only_violation: % on % is not permitted', tg_op, tg_table_name
    using errcode = 'G3H01';
end $$;

-- Direct INSERT guard: rows may only arrive through the audited append functions.
create function c10_gov003_demo.require_append_path() returns trigger
language plpgsql
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
begin
  if coalesce(current_setting('c10_gov003.writer', true), '') <> 'append_path' then
    raise exception 'append_only_violation: direct INSERT into % is not permitted', tg_table_name
      using errcode = 'G3H01';
  end if;
  return new;
end $$;

create function c10_gov003_demo.protect_table(p_table regclass) returns void
language plpgsql
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
begin
  execute format('create trigger g3_no_update_delete before update or delete on %s
                  for each row execute function c10_gov003_demo.deny_mutation()', p_table);
  execute format('create trigger g3_no_truncate before truncate on %s
                  for each statement execute function c10_gov003_demo.deny_mutation()', p_table);
  execute format('create trigger g3_insert_guard before insert on %s
                  for each row execute function c10_gov003_demo.require_append_path()', p_table);
end $$;

select c10_gov003_demo.protect_table('c10_gov003_demo.audit_events');
select c10_gov003_demo.protect_table('c10_gov003_demo.audit_receipts');

-- Row level security: only owners of the business may read its journal. Writes: no policy => denied.
alter table c10_gov003_demo.audit_chain_heads enable row level security;
alter table c10_gov003_demo.audit_events enable row level security;
alter table c10_gov003_demo.audit_receipts enable row level security;
create policy audit_events_read on c10_gov003_demo.audit_events for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
create policy audit_receipts_read on c10_gov003_demo.audit_receipts for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));

revoke all on c10_gov003_demo.audit_chain_heads, c10_gov003_demo.audit_events,
              c10_gov003_demo.audit_receipts from public;
grant select on c10_gov003_demo.audit_events, c10_gov003_demo.audit_receipts to c10g3_reader, c10g3_backend;

create view c10_gov003_demo.v_audit_events with (security_invoker = true) as
  select e.event_id, e.tenant_id, e.business_id, e.legal_entity_id, e.site_id, e.stream_seq,
         e.source_domain, e.source_id, e.source_version, e.action, e.event_time, e.ingest_time,
         e.actor_id, e.correlation_id, e.idempotency_key, e.payload, e.payload_sha256,
         e.prior_digest, e.event_digest, e.reason_category, e.schema_version,
         r.receipt_id, r.receipt_digest
    from c10_gov003_demo.audit_events e
    join c10_gov003_demo.audit_receipts r on r.event_id = e.event_id;
revoke all on c10_gov003_demo.v_audit_events from public;
grant select on c10_gov003_demo.v_audit_events to c10g3_reader, c10g3_backend;
