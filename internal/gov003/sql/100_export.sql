-- GOV-003 feature 10 export-provenance. DEMO / NOT LIVE. Disposable test bed.
-- Scoped CSV export of the audit journal, byte-hash provenance, durable export receipt, audit receipt.
--
-- What this proves (engineering): the exporting actor is derived server-side, only an owner of the exact
-- business can export it, the CSV bytes are produced in SQL with the SAME normalization as
-- internal/gov003/server/csv-export.mjs (spec "g3csv1"), the SHA-256 of the exact bytes is stored in an
-- append-only export receipt AND in an audit event, and verify_export() rejects any altered bytes.
-- What this does NOT prove: a hash chain/receipt inside a mutable PostgreSQL database is tamper-EVIDENT for
-- ordinary principals; it is not WORM storage and does not stop a privileged DBA (see 020). The export file
-- itself is not retained here; only its hash and the receipt are.
--
-- CSV spec g3csv1 (identical in Node):
--   UTF-8 bytes, no BOM, header row, records separated and terminated by CRLF (RFC 4180).
--   Text cell: NFC -> strip C0/C1 controls (except TAB/LF/CR), bidi/format/zero-width and U+2028/2029 ->
--   NFC -> CRLF/CR become LF -> if the cell starts with = + - @ TAB CR LF it is prefixed with a single
--   quote -> reject if > 2048 characters -> quote when it contains , " CR or LF (quote doubled).
--   Integer column cells are digits only (never guarded). Row > 8192 bytes, > 10000 rows or > 8 MiB: error.
\set ON_ERROR_STOP on
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

-- ---------------------------------------------------------------------------------------------------------
-- CSV primitives (pure, no table access except the payload allowlist)
-- ---------------------------------------------------------------------------------------------------------
create function c10_gov003_demo.g3_csv_clean(p text) returns text
language plpgsql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare s text := normalize(coalesce(p, ''), NFC);
begin
  s := regexp_replace(s,
    '[\u0001-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u00AD\u061C\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]',
    '', 'g');
  s := normalize(s, NFC);
  s := regexp_replace(s, E'\r\n?', E'\n', 'g');
  return s;
end $$;

create function c10_gov003_demo.g3_csv_cell(p text, p_kind text default 'text') returns text
language plpgsql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare s text;
begin
  if p_kind = 'int' then
    if p is null or p !~ '^[0-9]{1,15}$' then
      raise exception 'export_cell_invalid: integer cell must be 1-15 digits' using errcode = 'G3A03';
    end if;
    return p;
  elsif p_kind is distinct from 'text' then
    raise exception 'export_cell_invalid: unknown cell kind' using errcode = 'G3A03';
  end if;
  s := c10_gov003_demo.g3_csv_clean(p);
  if s ~ E'^[=+@\t\r\n-]' then
    s := '''' || s;                         -- spreadsheet formula guard (OWASP CSV injection)
  end if;
  if char_length(s) > 2048 then
    raise exception 'export_cell_too_long: a cell exceeds 2048 characters' using errcode = 'G3A03';
  end if;
  if s ~ E'[",\r\n]' then
    s := '"' || replace(s, '"', '""') || '"';
  end if;
  return s;
end $$;

-- Payload cell: allowlisted fields only (payload_allowlist), sorted by key, "key=value;key=value".
-- Values that look like secrets/PII are replaced by [withheld]; every value is formula-guarded.
create function c10_gov003_demo.g3_csv_payload_text(p jsonb) returns text
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare k text; v jsonb; sv text; parts text[] := '{}';
begin
  if p is null or jsonb_typeof(p) <> 'object' then return ''; end if;
  for k, v in
    select j.key, j.value from jsonb_each(p) j
     where exists (select 1 from c10_gov003_demo.payload_allowlist a where a.field_name = j.key)
     order by j.key collate "C"
  loop
    if jsonb_typeof(v) = 'string' then sv := v #>> '{}';
    elsif jsonb_typeof(v) = 'null' then sv := '';
    else sv := v::text; end if;
    if c10_gov003_demo.looks_secret(sv) then
      sv := '[withheld]';
    else
      sv := replace(c10_gov003_demo.g3_csv_clean(sv), ';', '%3B');
      if sv ~ E'^[=+@\t\r\n-]' and sv !~ '^-?[0-9]+$' then sv := '''' || sv; end if;
    end if;
    parts := parts || (k || '=' || sv);
  end loop;
  return array_to_string(parts, ';');
end $$;

create function c10_gov003_demo._exp_line(
  p_event uuid, p_seq bigint, p_time timestamptz, p_action text, p_domain text, p_source_id text,
  p_source_version text, p_receipt uuid, p_digest text, p_payload jsonb)
returns text
language plpgsql stable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare line text;
begin
  line := concat_ws(',',
    c10_gov003_demo.g3_csv_cell(p_event::text),
    c10_gov003_demo.g3_csv_cell(p_seq::text, 'int'),
    c10_gov003_demo.g3_csv_cell(c10_gov003_demo.utc_iso(p_time)),
    c10_gov003_demo.g3_csv_cell(p_action),
    c10_gov003_demo.g3_csv_cell(p_domain),
    c10_gov003_demo.g3_csv_cell(p_source_id),
    c10_gov003_demo.g3_csv_cell(p_source_version),
    c10_gov003_demo.g3_csv_cell(p_receipt::text),
    c10_gov003_demo.g3_csv_cell(p_digest),
    c10_gov003_demo.g3_csv_cell(c10_gov003_demo.g3_csv_payload_text(p_payload)));
  if octet_length(line) > 8192 then
    raise exception 'export_row_too_long: a CSV record exceeds 8192 bytes' using errcode = 'G3A03';
  end if;
  return line;
end $$;

-- ---------------------------------------------------------------------------------------------------------
-- Durable, append-only export receipt
-- ---------------------------------------------------------------------------------------------------------
create table c10_gov003_demo.export_receipts (
  export_receipt_id uuid primary key,
  tenant_id         uuid not null,
  business_id       uuid not null,
  actor_id          uuid not null references c10_gov003_demo.identities,
  idempotency_key   text not null check (idempotency_key ~ '^[A-Za-z0-9_.:-]{8,100}$'),
  report_id         text not null check (report_id = 'audit_journal_v1'),
  csv_spec          text not null check (csv_spec = 'g3csv1'),
  filter_params     jsonb not null,
  filter_sha256     text not null check (filter_sha256 ~ '^[0-9a-f]{64}$'),
  source_seq        bigint not null check (source_seq >= 0),
  source_version    text not null check (source_version ~ '^[A-Za-z0-9_.:+-]{1,64}$'),
  row_count         int not null check (row_count >= 0),
  byte_sha256       text not null check (byte_sha256 ~ '^[0-9a-f]{64}$'),
  byte_length       int not null check (byte_length > 0),
  audit_event_id    uuid not null unique references c10_gov003_demo.audit_events,
  audit_receipt_id  uuid not null unique references c10_gov003_demo.audit_receipts,
  issued_at         timestamptz not null,
  receipt_digest    text not null check (receipt_digest ~ '^[0-9a-f]{64}$'),
  unique (tenant_id, business_id, idempotency_key),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);
create index export_receipts_hash_idx on c10_gov003_demo.export_receipts (tenant_id, business_id, byte_sha256);
select c10_gov003_demo.protect_table('c10_gov003_demo.export_receipts');

alter table c10_gov003_demo.export_receipts enable row level security;
create policy export_receipts_read on c10_gov003_demo.export_receipts for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
revoke all on c10_gov003_demo.export_receipts from public;
grant select on c10_gov003_demo.export_receipts to c10g3_reader, c10g3_backend;

create view c10_gov003_demo.v_export_receipts with (security_invoker = true) as
  select export_receipt_id, tenant_id, business_id, actor_id, idempotency_key, report_id, csv_spec,
         filter_params, filter_sha256, source_seq, source_version, row_count, byte_sha256, byte_length,
         audit_event_id, audit_receipt_id, issued_at, receipt_digest
    from c10_gov003_demo.export_receipts;
revoke all on c10_gov003_demo.v_export_receipts from public;
grant select on c10_gov003_demo.v_export_receipts to c10g3_reader, c10g3_backend;

create function c10_gov003_demo.export_receipt_digest_of(
  p_id uuid, p_tenant uuid, p_business uuid, p_actor uuid, p_idem text, p_filter_sha text,
  p_source_seq bigint, p_source_version text, p_rows int, p_byte_sha text, p_byte_len int,
  p_audit_event_digest text, p_issued timestamptz)
returns text
language sql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select c10_gov003_demo.g3_sha256(concat_ws('|', 'g3x1', p_id, p_tenant, p_business, p_actor, p_idem,
    p_filter_sha, p_source_seq, p_source_version, p_rows, p_byte_sha, p_byte_len, p_audit_event_digest,
    c10_gov003_demo.utc_iso(p_issued)));
$$;

-- ---------------------------------------------------------------------------------------------------------
-- Report builder (shared by first export and exact replay). Bound to a source snapshot (source_seq).
-- ---------------------------------------------------------------------------------------------------------
create function c10_gov003_demo._exp_build_csv(p_tenant uuid, p_business uuid, p_filter jsonb, p_source_seq bigint)
returns table (csv text, row_count int)
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  v_max int := (p_filter ->> 'max_rows')::int;
  n int; body text; v_out text;
  header constant text :=
    'event_id,stream_seq,event_time,action,source_domain,source_id,source_version,receipt_id,event_digest,payload_fields';
begin
  select count(*)::int, string_agg(q.line, E'\r\n' order by q.stream_seq)
    into n, body
    from (
      select e.stream_seq,
             c10_gov003_demo._exp_line(e.event_id, e.stream_seq, e.event_time, e.action, e.source_domain,
               e.source_id, e.source_version, rc.receipt_id, e.event_digest, e.payload) as line
        from c10_gov003_demo.audit_events e
        join c10_gov003_demo.audit_receipts rc on rc.event_id = e.event_id
       where e.tenant_id = p_tenant and e.business_id = p_business
         and e.stream_seq <= p_source_seq
         and (p_filter ->> 'from' is null or e.event_time >= (p_filter ->> 'from')::timestamptz)
         and (p_filter ->> 'to' is null or e.event_time < (p_filter ->> 'to')::timestamptz)
         and (p_filter ->> 'action' is null or e.action = p_filter ->> 'action')
         and (p_filter ->> 'source_domain' is null or e.source_domain = p_filter ->> 'source_domain')
       order by e.stream_seq
       limit v_max + 1
    ) q;
  if n > v_max then
    raise exception 'export_truncated: matching rows exceed the cap of % rows; narrow the filter (no silent cut)', v_max
      using errcode = 'G3A03';
  end if;
  v_out := header || E'\r\n' || case when n > 0 then body || E'\r\n' else '' end;
  if octet_length(v_out) > 8388608 then
    raise exception 'export_too_large: CSV exceeds 8 MiB' using errcode = 'G3A03';
  end if;
  return query select v_out, n;
end $$;

create function c10_gov003_demo._exp_gate(p_tenant uuid, p_business uuid, p_claimed uuid) returns uuid
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
  -- One indistinguishable answer for missing, foreign, site-only, investor, revoked and support: no count leak.
  if p_tenant is null or p_business is null
     or not c10_gov003_demo.scope_exists(p_tenant, p_business, null, null)
     or not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  return a;
end $$;

-- ---------------------------------------------------------------------------------------------------------
-- export_audit_csv: authorized, filtered, hashed, receipted. SECURITY DEFINER; actor is NEVER caller-supplied.
-- ---------------------------------------------------------------------------------------------------------
create function c10_gov003_demo.export_audit_csv(
  p_tenant uuid, p_business uuid, p_idem text,
  p_from timestamptz default null, p_to timestamptz default null,
  p_action text default null, p_source_domain text default null,
  p_max_rows int default 10000, p_claimed_actor uuid default null)
returns table (outcome text, export_receipt_id uuid, audit_receipt_id uuid, audit_event_id uuid,
               row_count int, byte_length int, byte_sha256 text, filter_sha256 text,
               source_version text, issued_at timestamptz, receipt_digest text, replayed boolean,
               csv_text text)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  a uuid;
  v_filter jsonb; v_fsha text;
  ex record; hd record; ap record; b record;
  v_seq bigint; v_sdig text; v_sver text;
  v_id uuid := gen_random_uuid(); v_issued timestamptz; v_len int; v_sha text; v_rdig text;
begin
  a := c10_gov003_demo._exp_gate(p_tenant, p_business, p_claimed_actor);
  if p_idem is null or p_idem !~ '^[A-Za-z0-9_.:-]{8,100}$' then
    raise exception 'export_param_invalid: idempotency key must be 8-100 chars [A-Za-z0-9_.:-]' using errcode = 'G3A03';
  end if;
  if p_max_rows is null or p_max_rows < 1 or p_max_rows > 10000 then
    raise exception 'export_param_invalid: max_rows must be 1..10000' using errcode = 'G3A03';
  end if;
  if p_action is not null and p_action !~ '^[a-z][a-z0-9_.-]{1,63}$' then
    raise exception 'export_param_invalid: action filter' using errcode = 'G3A03';
  end if;
  if p_source_domain is not null and p_source_domain !~ '^[a-z][a-z0-9_.-]{1,63}$' then
    raise exception 'export_param_invalid: source_domain filter' using errcode = 'G3A03';
  end if;
  if p_from is not null and p_to is not null and p_from >= p_to then
    raise exception 'export_param_invalid: from must be before to' using errcode = 'G3A03';
  end if;

  v_filter := jsonb_strip_nulls(jsonb_build_object(
    'action', p_action, 'from', c10_gov003_demo.utc_iso(p_from), 'max_rows', p_max_rows::text,
    'report_id', 'audit_journal_v1', 'source_domain', p_source_domain, 'to', c10_gov003_demo.utc_iso(p_to)));
  v_fsha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(v_filter));

  -- One stored result per (tenant, business, key) even with simultaneous independent sessions.
  perform pg_advisory_xact_lock(hashtextextended('g3xidem|' || p_tenant || '|' || p_business || '|' || p_idem, 0));

  select r.* into ex from c10_gov003_demo.export_receipts r
   where r.tenant_id = p_tenant and r.business_id = p_business and r.idempotency_key = p_idem;
  if found then
    if ex.actor_id <> a then
      raise exception 'idempotency_conflict: export key already used by a different actor' using errcode = 'G3C01';
    end if;
    if ex.filter_sha256 <> v_fsha then
      raise exception 'idempotency_conflict: export key reused with a different normalized filter'
        using errcode = 'G3C01';
    end if;
    -- Exact replay: same receipt; bytes are regenerated from the same snapshot and must hash identically.
    select * into b from c10_gov003_demo._exp_build_csv(p_tenant, p_business, ex.filter_params, ex.source_seq);
    if c10_gov003_demo.g3_sha256(b.csv) <> ex.byte_sha256 or b.row_count <> ex.row_count then
      raise exception 'export_replay_mismatch: regenerated bytes differ from the recorded hash (history altered?)'
        using errcode = 'G3A04';
    end if;
    return query select 'replayed'::text, ex.export_receipt_id, ex.audit_receipt_id, ex.audit_event_id,
      ex.row_count, ex.byte_length, ex.byte_sha256, ex.filter_sha256, ex.source_version, ex.issued_at,
      ex.receipt_digest, true, b.csv;
    return;
  end if;

  -- Source snapshot = current head of this business's audit chain (the export's own event comes after it).
  select e.stream_seq as sq, e.event_digest as dg into hd
    from c10_gov003_demo.audit_events e
   where e.tenant_id = p_tenant and e.business_id = p_business
   order by e.stream_seq desc limit 1;
  if found then v_seq := hd.sq; v_sdig := hd.dg; else v_seq := 0; v_sdig := repeat('0', 64); end if;
  v_sver := 'seq' || v_seq || '.' || left(v_sdig, 16);

  select * into b from c10_gov003_demo._exp_build_csv(p_tenant, p_business, v_filter, v_seq);
  v_len := octet_length(convert_to(b.csv, 'UTF8'));
  v_sha := c10_gov003_demo.g3_sha256(b.csv);

  select * into ap from c10_gov003_demo._append_audit(
    p_tenant, p_business, null, null, 'gov003.export', 'g3x:' || v_id, v_sver, 'export.csv',
    clock_timestamp(), 'export.' || replace(v_id::text, '-', ''), 'export.' || p_idem,
    jsonb_build_object('report_id', 'audit_journal_v1', 'filter_ref', v_fsha, 'row_count', b.row_count::text,
                       'artifact_sha256', v_sha, 'receipt_ref', 'g3x:' || v_id),
    null, 'export', 1, null, null);
  if ap.replayed then
    raise exception 'idempotency_conflict: export audit key already used without an export receipt'
      using errcode = 'G3C01';
  end if;

  v_issued := clock_timestamp();
  v_rdig := c10_gov003_demo.export_receipt_digest_of(v_id, p_tenant, p_business, a, p_idem, v_fsha, v_seq,
              v_sver, b.row_count, v_sha, v_len, ap.event_digest, v_issued);
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.export_receipts
    (export_receipt_id, tenant_id, business_id, actor_id, idempotency_key, report_id, csv_spec, filter_params,
     filter_sha256, source_seq, source_version, row_count, byte_sha256, byte_length, audit_event_id,
     audit_receipt_id, issued_at, receipt_digest)
  values (v_id, p_tenant, p_business, a, p_idem, 'audit_journal_v1', 'g3csv1', v_filter,
     v_fsha, v_seq, v_sver, b.row_count, v_sha, v_len, ap.event_id,
     ap.receipt_id, v_issued, v_rdig);
  perform set_config('c10_gov003.writer', '', true);

  return query select 'created'::text, v_id, ap.receipt_id, ap.event_id, b.row_count, v_len, v_sha, v_fsha,
    v_sver, v_issued, v_rdig, false, b.csv;
end $$;

-- ---------------------------------------------------------------------------------------------------------
-- verify_export: recompute the byte hash of a claimed file against its durable receipt.
-- A claimed export with no receipt visible to the caller is reported as G3A04 (missing receipt), identically
-- for "does not exist" and "not yours" so that nothing about foreign tenants leaks.
-- ---------------------------------------------------------------------------------------------------------
create function c10_gov003_demo.verify_export(p_receipt uuid, p_csv text)
returns table (ok boolean, export_receipt_id uuid, row_count int, byte_length int, byte_sha256 text,
               audit_receipt_id uuid, source_version text, issued_at timestamptz)
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare r record; ev record; rc record; v_len int; v_sha text; v_rdig text;
begin
  if c10_gov003_demo.actor_id() is null then
    raise exception 'actor_unauthenticated' using errcode = 'G3A05';
  end if;
  select x.* into r from c10_gov003_demo.export_receipts x where x.export_receipt_id = p_receipt;
  if not found or not c10_gov003_demo.can_read_business(r.tenant_id, r.business_id) then
    raise exception 'export_receipt_missing: no export receipt in your scope for this claim' using errcode = 'G3A04';
  end if;
  if p_csv is null then
    raise exception 'export_content_hash_mismatch: no content supplied' using errcode = 'G3A04';
  end if;
  v_len := octet_length(convert_to(p_csv, 'UTF8'));
  v_sha := c10_gov003_demo.g3_sha256(p_csv);
  if v_sha <> r.byte_sha256 or v_len <> r.byte_length then
    raise exception 'export_content_hash_mismatch: supplied bytes do not match the recorded SHA-256' using errcode = 'G3A04';
  end if;
  select e.event_digest as dg, e.action as act, e.payload as pl into ev
    from c10_gov003_demo.audit_events e where e.event_id = r.audit_event_id;
  select c.event_digest as dg into rc from c10_gov003_demo.audit_receipts c where c.receipt_id = r.audit_receipt_id;
  v_rdig := c10_gov003_demo.export_receipt_digest_of(r.export_receipt_id, r.tenant_id, r.business_id, r.actor_id,
              r.idempotency_key, r.filter_sha256, r.source_seq, r.source_version, r.row_count, r.byte_sha256,
              r.byte_length, ev.dg, r.issued_at);
  if ev.dg is null or rc.dg is distinct from ev.dg or ev.act <> 'export.csv'
     or v_rdig <> r.receipt_digest
     or ev.pl ->> 'artifact_sha256' <> r.byte_sha256 or ev.pl ->> 'row_count' <> r.row_count::text then
    raise exception 'export_receipt_tampered: receipt does not match its audit event' using errcode = 'G3A04';
  end if;
  return query select true, r.export_receipt_id, r.row_count, r.byte_length, r.byte_sha256, r.audit_receipt_id,
    r.source_version, r.issued_at;
end $$;

-- Missing-receipt detector: every export.csv audit event must have an export receipt, and vice versa.
create function c10_gov003_demo.export_ledger_check(p_tenant uuid, p_business uuid)
returns table (ok boolean, receipts bigint, audit_events bigint, orphan_audit_events bigint)
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare nr bigint; ne bigint; orph bigint;
begin
  if c10_gov003_demo.actor_id() is null then
    raise exception 'actor_unauthenticated' using errcode = 'G3A05';
  end if;
  if p_tenant is null or p_business is null or not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  select count(*) into nr from c10_gov003_demo.export_receipts r
   where r.tenant_id = p_tenant and r.business_id = p_business;
  select count(*) into ne from c10_gov003_demo.audit_events e
   where e.tenant_id = p_tenant and e.business_id = p_business
     and e.source_domain = 'gov003.export' and e.action = 'export.csv';
  select count(*) into orph from c10_gov003_demo.audit_events e
   where e.tenant_id = p_tenant and e.business_id = p_business
     and e.source_domain = 'gov003.export' and e.action = 'export.csv'
     and not exists (select 1 from c10_gov003_demo.export_receipts r where r.audit_event_id = e.event_id);
  return query select (orph = 0 and nr = ne), nr, ne, orph;
end $$;

comment on function c10_gov003_demo.export_audit_csv(uuid,uuid,text,timestamptz,timestamptz,text,text,int,uuid) is
  'DEMO/NOT LIVE. Scoped CSV export with byte-hash receipt. Engineering provenance control in a mutable database; not WORM, not a legal evidence certification.';
comment on table c10_gov003_demo.export_receipts is
  'Append-only export receipts (tamper-evident for ordinary principals; a privileged DBA can still alter storage).';

revoke all on function
  c10_gov003_demo.g3_csv_clean(text), c10_gov003_demo.g3_csv_cell(text,text),
  c10_gov003_demo.g3_csv_payload_text(jsonb),
  c10_gov003_demo._exp_line(uuid,bigint,timestamptz,text,text,text,text,uuid,text,jsonb),
  c10_gov003_demo.export_receipt_digest_of(uuid,uuid,uuid,uuid,text,text,bigint,text,int,text,int,text,timestamptz),
  c10_gov003_demo._exp_build_csv(uuid,uuid,jsonb,bigint),
  c10_gov003_demo._exp_gate(uuid,uuid,uuid),
  c10_gov003_demo.export_audit_csv(uuid,uuid,text,timestamptz,timestamptz,text,text,int,uuid),
  c10_gov003_demo.verify_export(uuid,text),
  c10_gov003_demo.export_ledger_check(uuid,uuid)
  from public;
grant execute on function c10_gov003_demo.g3_csv_clean(text), c10_gov003_demo.g3_csv_cell(text,text),
  c10_gov003_demo.g3_csv_payload_text(jsonb) to c10g3_backend, c10g3_reader;
grant execute on function c10_gov003_demo.export_audit_csv(uuid,uuid,text,timestamptz,timestamptz,text,text,int,uuid)
  to c10g3_backend;
grant execute on function c10_gov003_demo.verify_export(uuid,text) to c10g3_backend, c10g3_reader;
grant execute on function c10_gov003_demo.export_ledger_check(uuid,uuid) to c10g3_backend, c10g3_reader;
