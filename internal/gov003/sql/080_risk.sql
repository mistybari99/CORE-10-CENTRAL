-- 08 risk-advisory-triage: configured anomaly rules over audit_events -> explainable ADVISORY signal
-- -> independent human review. DEMO / NOT LIVE. Contract/test bed only.
--
-- HARD FENCE (by design, proven in tests):
--   * Signals are ADVISORY and REVIEW-ONLY. Nothing here freezes, blocks, fires, transfers, pays,
--     approves, elevates privilege or edits stock/money/approval/role data. The only writes made by
--     this file are: its own append-only signal/evidence/review/log tables and audit receipts.
--   * Reasons are phrased as advisories, never accusations (CHECK constraint on the table).
--   * Reviews: one terminal state per signal (UNIQUE + advisory lock), reviewer must be a business/
--     tenant owner of that business and must differ from the actors of the evidence events.
-- LIMITATION: the signal history is tamper-evident for ordinary principals only (see 020 header);
-- a privileged DBA/superuser can still rewrite storage. Rule configuration is mutable owner data.
\set ON_ERROR_STOP on
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

-- ---------------------------------------------------------------------------------------------------
-- Configured rules (global configuration; no tenant data). Thresholds are read by the detector.
-- ---------------------------------------------------------------------------------------------------
create table c10_gov003_demo.risk_rules (
  rule_id          text primary key check (rule_id ~ '^[a-z][a-z0-9_]{2,39}$'),
  title            text not null,
  description      text not null,
  enabled          boolean not null default true,
  default_severity text not null check (default_severity in ('low','medium','high')),
  params           jsonb not null default '{}'::jsonb
);
insert into c10_gov003_demo.risk_rules (rule_id, title, description, default_severity, params) values
  ('dup_key', 'Idempotency key replayed or conflicted repeatedly',
   'An idempotency key was resubmitted (exact replay) or reused with changed content several times.',
   'medium', '{"min_attempts":3}'),
  ('dup_content', 'Identical command content resubmitted under new keys',
   'The same command, source reference and content digest was recorded repeatedly under different idempotency keys.',
   'medium', '{"min_duplicates":3,"window_seconds":3600}'),
  ('volume_spike', 'Unexpected event volume in one window',
   'A source domain produced more events inside one fixed window than the configured expectation.',
   'medium', '{"window_seconds":600,"max_events":20}'),
  ('stale_source', 'Source has gone quiet',
   'No events from a previously active source domain for longer than the configured silence limit.',
   'low', '{"max_silence_seconds":3600,"min_events":2,"basis":"event_time"}'),
  ('unauthorized_command', 'Sensitive command outside owner role',
   'A command on the configured sensitive list was submitted by an identity that holds no owner role for that scope.',
   'high', '{"sensitive_prefixes":["approval.","grant.","role.","policy.","privilege.","freeze.","payment."]}'),
  ('grant_policy_diff', 'Permission catalog differs from approved baseline',
   'The live grant/RLS catalog differs from the owner-approved baseline (raised by the feature 09 diff).',
   'medium', '{}');
alter table c10_gov003_demo.risk_rules enable row level security;
create policy risk_rules_read on c10_gov003_demo.risk_rules for select
  to c10g3_reader, c10g3_backend using (true);
revoke all on c10_gov003_demo.risk_rules from public;
grant select on c10_gov003_demo.risk_rules to c10g3_reader, c10g3_backend;

-- ---------------------------------------------------------------------------------------------------
-- Idempotency attempt log. append_event() raises on conflict, which rolls its transaction back, so a
-- conflict cannot be remembered by 030 itself. append_event_logged() below wraps the unchanged core
-- append in a sub-transaction and records replays/conflicts here (append-only, scope-protected).
-- ---------------------------------------------------------------------------------------------------
create table c10_gov003_demo.idempotency_conflict_log (
  log_id                   bigint generated always as identity primary key,
  tenant_id                uuid not null,
  business_id              uuid not null,
  idempotency_key          text not null,
  outcome                  text not null check (outcome in ('replay','conflict')),
  original_event_id        uuid not null references c10_gov003_demo.audit_events,
  original_receipt_id      uuid not null references c10_gov003_demo.audit_receipts,
  attempted_action         text not null,
  attempted_payload_sha256 text not null check (attempted_payload_sha256 ~ '^[0-9a-f]{64}$'),
  actor_id                 uuid not null references c10_gov003_demo.identities,
  observed_at              timestamptz not null default clock_timestamp(),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);
create index idem_log_key_idx on c10_gov003_demo.idempotency_conflict_log
  (tenant_id, business_id, idempotency_key);
select c10_gov003_demo.protect_table('c10_gov003_demo.idempotency_conflict_log');

-- ---------------------------------------------------------------------------------------------------
-- Immutable signals, evidence links, reviews.
-- ---------------------------------------------------------------------------------------------------
create table c10_gov003_demo.risk_signals (
  signal_id          uuid primary key,
  tenant_id          uuid not null,
  business_id        uuid not null,
  rule_id            text not null references c10_gov003_demo.risk_rules,
  signal_key         text not null check (length(signal_key) between 3 and 400),
  severity           text not null check (severity in ('low','medium','high')),
  disposition        text not null default 'advisory_review_only' check (disposition = 'advisory_review_only'),
  confidence_pct     int  not null check (confidence_pct between 0 and 100),
  reason             text not null check (
                       length(reason) between 20 and 700
                       and reason ~* 'advisory'
                       and reason !~* '(fraud|theft|thief|steal|stole|embezzl|criminal|guilty|culprit|crime)'),
  source_domain      text,
  window_start       timestamptz,
  window_end         timestamptz,
  context            jsonb not null default '{}'::jsonb,
  evidence_actor_ids uuid[] not null default '{}',
  detected_by        uuid not null references c10_gov003_demo.identities,
  detected_at        timestamptz not null default clock_timestamp(),
  event_id           uuid not null references c10_gov003_demo.audit_events,
  receipt_id         uuid not null references c10_gov003_demo.audit_receipts,
  unique (tenant_id, business_id, signal_key),
  unique (signal_id, tenant_id, business_id),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);
select c10_gov003_demo.protect_table('c10_gov003_demo.risk_signals');

create table c10_gov003_demo.risk_signal_evidence (
  evidence_id   bigint generated always as identity primary key,
  signal_id     uuid not null,
  tenant_id     uuid not null,
  business_id   uuid not null,
  evidence_kind text not null check (evidence_kind in ('audit_event','idempotency_log','catalog_diff')),
  event_id      uuid references c10_gov003_demo.audit_events,
  receipt_id    uuid references c10_gov003_demo.audit_receipts,
  log_id        bigint references c10_gov003_demo.idempotency_conflict_log,
  ref           text check (ref is null or ref ~ '^[A-Za-z0-9_.:/#-]{1,128}$'),  -- e.g. catalog diff id (090)
  check ((evidence_kind = 'audit_event' and event_id is not null and receipt_id is not null)
      or (evidence_kind = 'idempotency_log' and log_id is not null)
      or (evidence_kind = 'catalog_diff' and ref is not null)),
  foreign key (signal_id, tenant_id, business_id)
    references c10_gov003_demo.risk_signals (signal_id, tenant_id, business_id)
);
create index risk_evidence_signal_idx on c10_gov003_demo.risk_signal_evidence (signal_id);
select c10_gov003_demo.protect_table('c10_gov003_demo.risk_signal_evidence');

create table c10_gov003_demo.risk_signal_reviews (
  review_id    uuid primary key,
  signal_id    uuid not null unique,          -- EXACTLY ONE terminal state per signal
  tenant_id    uuid not null,
  business_id  uuid not null,
  decision     text not null check (decision in ('acknowledge','dismiss')),
  reason_code  text not null check (reason_code ~ '^[a-z][a-z0-9_]{2,39}$'),
  reviewer_id  uuid not null references c10_gov003_demo.identities,
  request_idem text not null check (request_idem ~ '^[A-Za-z0-9_.:-]{8,128}$'),
  reviewed_at  timestamptz not null default clock_timestamp(),
  event_id     uuid not null references c10_gov003_demo.audit_events,
  receipt_id   uuid not null references c10_gov003_demo.audit_receipts,
  foreign key (signal_id, tenant_id, business_id)
    references c10_gov003_demo.risk_signals (signal_id, tenant_id, business_id)
);
select c10_gov003_demo.protect_table('c10_gov003_demo.risk_signal_reviews');

-- Defense in depth: even a direct (owner-path) insert cannot record a self-review.
create function c10_gov003_demo.risk_review_independence() returns trigger
language plpgsql
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare ev uuid[];
begin
  select s.evidence_actor_ids into ev from c10_gov003_demo.risk_signals s where s.signal_id = new.signal_id;
  if ev is not null and new.reviewer_id = any (ev) then
    raise exception 'independent_review_required: reviewer is an actor of the evidence' using errcode = 'G3A06';
  end if;
  return new;
end $$;
create trigger g3_review_independence before insert on c10_gov003_demo.risk_signal_reviews
  for each row execute function c10_gov003_demo.risk_review_independence();

alter table c10_gov003_demo.idempotency_conflict_log enable row level security;
alter table c10_gov003_demo.risk_signals enable row level security;
alter table c10_gov003_demo.risk_signal_evidence enable row level security;
alter table c10_gov003_demo.risk_signal_reviews enable row level security;
create policy idem_log_read on c10_gov003_demo.idempotency_conflict_log for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
create policy risk_signals_read on c10_gov003_demo.risk_signals for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
create policy risk_evidence_read on c10_gov003_demo.risk_signal_evidence for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
create policy risk_reviews_read on c10_gov003_demo.risk_signal_reviews for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
revoke all on c10_gov003_demo.idempotency_conflict_log, c10_gov003_demo.risk_signals,
              c10_gov003_demo.risk_signal_evidence, c10_gov003_demo.risk_signal_reviews from public;
grant select on c10_gov003_demo.idempotency_conflict_log, c10_gov003_demo.risk_signals,
                c10_gov003_demo.risk_signal_evidence, c10_gov003_demo.risk_signal_reviews
  to c10g3_reader, c10g3_backend;

create view c10_gov003_demo.v_risk_signals with (security_invoker = true) as
  select s.signal_id, s.tenant_id, s.business_id, s.rule_id, s.signal_key, s.severity, s.disposition,
         s.confidence_pct, s.reason, s.source_domain, s.window_start, s.window_end, s.context,
         s.evidence_actor_ids, s.detected_at, s.event_id as receipt_event_id, s.receipt_id,
         case when r.review_id is null then 'open'
              when r.decision = 'acknowledge' then 'acknowledged' else 'dismissed' end as status,
         r.decision as review_decision, r.reason_code as review_reason_code, r.reviewer_id,
         r.reviewed_at, r.receipt_id as review_receipt_id
    from c10_gov003_demo.risk_signals s
    left join c10_gov003_demo.risk_signal_reviews r on r.signal_id = s.signal_id;
create view c10_gov003_demo.v_risk_signal_evidence with (security_invoker = true) as
  select e.evidence_id, e.signal_id, e.tenant_id, e.business_id, e.evidence_kind, e.event_id,
         e.receipt_id, e.log_id, e.ref
    from c10_gov003_demo.risk_signal_evidence e;
create view c10_gov003_demo.v_idempotency_attempts with (security_invoker = true) as
  select l.log_id, l.tenant_id, l.business_id, l.idempotency_key, l.outcome, l.original_event_id,
         l.original_receipt_id, l.attempted_action, l.attempted_payload_sha256, l.actor_id, l.observed_at
    from c10_gov003_demo.idempotency_conflict_log l;
revoke all on c10_gov003_demo.v_risk_signals, c10_gov003_demo.v_risk_signal_evidence,
              c10_gov003_demo.v_idempotency_attempts from public;
grant select on c10_gov003_demo.v_risk_signals, c10_gov003_demo.v_risk_signal_evidence,
                c10_gov003_demo.v_idempotency_attempts to c10g3_reader, c10g3_backend;

-- ---------------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------------
create function c10_gov003_demo._safe_ref(p text) returns text
language sql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select case when p ~ '^[A-Za-z0-9_.:/#-]{1,128}$' and not c10_gov003_demo.looks_secret(p) then p end;
$$;

-- Logged append: identical to append_event (030, unchanged) but remembers replays/conflicts.
-- A conflict is RETURNED as outcome 'conflict' (no event/receipt ids are disclosed) instead of raised,
-- because a raised error would roll back the log row. The adapter must treat 'conflict' as an error.
create function c10_gov003_demo.append_event_logged(
  p_tenant uuid, p_business uuid, p_site uuid, p_entity uuid,
  p_source_domain text, p_source_id text, p_source_version text, p_action text,
  p_event_time timestamptz, p_correlation text, p_idem text,
  p_payload jsonb, p_payload_sha text, p_reason text,
  p_claimed_actor uuid default null, p_event_id uuid default null)
returns table (outcome text, event_id uuid, receipt_id uuid, stream_seq bigint, event_digest text,
               receipt_digest text, replayed boolean, payload_sha256 text, log_id bigint)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  a uuid := c10_gov003_demo.actor_id();
  r record; o record; v_log bigint; v_sha text;
begin
  begin
    select * into r from c10_gov003_demo._append_audit(p_tenant, p_business, p_site, p_entity,
      p_source_domain, p_source_id, p_source_version, p_action, p_event_time, p_correlation, p_idem,
      p_payload, p_payload_sha, p_reason, 1, p_claimed_actor, p_event_id);
  exception when sqlstate 'G3C01' then
    -- All scope/actor/payload checks passed before the conflict was raised.
    v_sha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(p_payload));
    select e.event_id as eid, rc.receipt_id as rid into o
      from c10_gov003_demo.audit_events e
      join c10_gov003_demo.audit_receipts rc on rc.event_id = e.event_id
     where e.tenant_id = p_tenant and e.business_id = p_business and e.idempotency_key = p_idem;
    perform set_config('c10_gov003.writer', 'append_path', true);
    insert into c10_gov003_demo.idempotency_conflict_log
      (tenant_id, business_id, idempotency_key, outcome, original_event_id, original_receipt_id,
       attempted_action, attempted_payload_sha256, actor_id)
    values (p_tenant, p_business, p_idem, 'conflict', o.eid, o.rid, p_action, v_sha, a)
    returning idempotency_conflict_log.log_id into v_log;
    perform set_config('c10_gov003.writer', '', true);
    return query select 'conflict'::text, null::uuid, null::uuid, null::bigint, null::text, null::text,
                        false, v_sha, v_log;
    return;
  end;
  if r.replayed then
    perform set_config('c10_gov003.writer', 'append_path', true);
    insert into c10_gov003_demo.idempotency_conflict_log
      (tenant_id, business_id, idempotency_key, outcome, original_event_id, original_receipt_id,
       attempted_action, attempted_payload_sha256, actor_id)
    values (p_tenant, p_business, p_idem, 'replay', r.event_id, r.receipt_id, p_action, r.payload_sha256, a)
    returning idempotency_conflict_log.log_id into v_log;
    perform set_config('c10_gov003.writer', '', true);
  end if;
  return query select r.outcome, r.event_id, r.receipt_id, r.stream_seq, r.event_digest,
                      r.receipt_digest, r.replayed, r.payload_sha256, v_log;
end $$;

-- INTERNAL signal emitter. Owner-run only. Idempotent per (tenant, business, signal_key).
-- Appends the immutable signal receipt (audit, source_domain 'gov003.risk') then the signal and its
-- evidence links. p_evidence: [{"kind":"audit_event","event_id":..}|{"kind":"idempotency_log","log_id":..}
-- |{"kind":"catalog_diff","ref":..}].
create function c10_gov003_demo._emit_signal(
  p_tenant uuid, p_business uuid, p_rule_id text, p_signal_key text, p_severity text,
  p_confidence int, p_reason text, p_source_domain text, p_context jsonb,
  p_window_start timestamptz, p_window_end timestamptz, p_evidence jsonb, p_evidence_actors uuid[])
returns table (signal_id uuid, receipt_id uuid, created boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  a uuid := c10_gov003_demo.actor_id();
  ex record; rc record; sid uuid; ev jsonb; evk text; first_ref text; n int; ev_event uuid; ev_rcpt uuid;
  ev_tenant uuid; ev_business uuid; ev_log bigint; actors uuid[];
begin
  if a is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if not c10_gov003_demo.scope_exists(p_tenant, p_business, null, null)
     or not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  if not exists (select 1 from c10_gov003_demo.risk_rules rr where rr.rule_id = p_rule_id) then
    raise exception 'unknown_rule' using errcode = 'G3A03';
  end if;
  perform c10_gov003_demo.validate_payload(coalesce(p_context, '{}'::jsonb));
  perform pg_advisory_xact_lock(hashtextextended('g3sig|' || p_tenant || '|' || p_business || '|' || p_signal_key, 0));

  select s.signal_id as sid, s.receipt_id as rid into ex
    from c10_gov003_demo.risk_signals s
   where s.tenant_id = p_tenant and s.business_id = p_business and s.signal_key = p_signal_key;
  if found then
    return query select ex.sid, ex.rid, false;
    return;
  end if;

  sid := gen_random_uuid();
  n := jsonb_array_length(coalesce(p_evidence, '[]'::jsonb));
  first_ref := coalesce(p_evidence -> 0 ->> 'event_id', p_evidence -> 0 ->> 'ref', p_evidence -> 0 ->> 'log_id');
  select coalesce(array_agg(distinct x order by x), '{}') into actors from unnest(coalesce(p_evidence_actors, '{}')) x;

  select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
    'gov003.risk', 'signal-' || sid::text, 'v1', 'risk.signal_raised', clock_timestamp(),
    'risk-signal-' || sid::text, 'risk-signal:' || sid::text,
    jsonb_strip_nulls(jsonb_build_object(
      'signal_ref', sid::text, 'reason_code', p_rule_id, 'severity', p_severity,
      'note_code', 'advisory_only', 'count', n::text, 'evidence_ref', first_ref,
      'window_start', case when p_window_start is null then null else c10_gov003_demo.utc_iso(p_window_start) end,
      'window_end', case when p_window_end is null then null else c10_gov003_demo.utc_iso(p_window_end) end)),
    null, 'security', 1, null, null);

  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.risk_signals
    (signal_id, tenant_id, business_id, rule_id, signal_key, severity, confidence_pct, reason,
     source_domain, window_start, window_end, context, evidence_actor_ids, detected_by, event_id, receipt_id)
  values (sid, p_tenant, p_business, p_rule_id, p_signal_key, p_severity, p_confidence, p_reason,
     p_source_domain, p_window_start, p_window_end, coalesce(p_context, '{}'::jsonb), actors, a,
     rc.event_id, rc.receipt_id);
  for ev in select value from jsonb_array_elements(coalesce(p_evidence, '[]'::jsonb)) loop
    evk := ev ->> 'kind';
    ev_event := null; ev_rcpt := null; ev_log := null; ev_tenant := null; ev_business := null;
    if evk = 'audit_event' then
      select e.event_id, rcp.receipt_id, e.tenant_id, e.business_id into ev_event, ev_rcpt, ev_tenant, ev_business
        from c10_gov003_demo.audit_events e
        join c10_gov003_demo.audit_receipts rcp on rcp.event_id = e.event_id
       where e.event_id = (ev ->> 'event_id')::uuid;
      if ev_event is null or ev_tenant <> p_tenant or ev_business <> p_business then
        raise exception 'scope_denied: evidence outside the signal scope' using errcode = 'G3A02';
      end if;
      insert into c10_gov003_demo.risk_signal_evidence (signal_id, tenant_id, business_id, evidence_kind, event_id, receipt_id)
        values (sid, p_tenant, p_business, 'audit_event', ev_event, ev_rcpt);
    elsif evk = 'idempotency_log' then
      select l.log_id, l.tenant_id, l.business_id into ev_log, ev_tenant, ev_business
        from c10_gov003_demo.idempotency_conflict_log l where l.log_id = (ev ->> 'log_id')::bigint;
      if ev_log is null or ev_tenant <> p_tenant or ev_business <> p_business then
        raise exception 'scope_denied: evidence outside the signal scope' using errcode = 'G3A02';
      end if;
      insert into c10_gov003_demo.risk_signal_evidence (signal_id, tenant_id, business_id, evidence_kind, log_id)
        values (sid, p_tenant, p_business, 'idempotency_log', ev_log);
    elsif evk = 'catalog_diff' then
      insert into c10_gov003_demo.risk_signal_evidence (signal_id, tenant_id, business_id, evidence_kind, ref)
        values (sid, p_tenant, p_business, 'catalog_diff', ev ->> 'ref');
    else
      raise exception 'unknown_evidence_kind' using errcode = 'G3A03';
    end if;
  end loop;
  perform set_config('c10_gov003.writer', '', true);

  return query select sid, rc.receipt_id, true;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- Detector. Callable by an owner of the business only. Reads audit_events/log, writes ONLY signals.
-- Node mirror: internal/gov003/server/risk.mjs (evaluateRisk) - keep the two in lock-step.
-- ---------------------------------------------------------------------------------------------------
create function c10_gov003_demo.run_risk_detection(
  p_tenant uuid, p_business uuid, p_as_of timestamptz default null, p_claimed_actor uuid default null)
returns table (signal_id uuid, rule_id text, signal_key text, created boolean, receipt_id uuid)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  a uuid := c10_gov003_demo.actor_id();
  asof timestamptz := coalesce(p_as_of, clock_timestamp());
  rl record; g record; em record;
  minatt int; mindup int; win int; maxev int; maxsil int; minev int; basis text;
  sev text; conf int; ev jsonb; ctx jsonb; skey text; silence bigint; prefixes jsonb; staff_cov boolean;
  actors uuid[];
begin
  if a is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if p_claimed_actor is not null and p_claimed_actor <> a then
    raise exception 'forged_actor: caller-supplied actor does not match the server-derived actor'
      using errcode = 'G3A01';
  end if;
  if p_tenant is null or p_business is null
     or not c10_gov003_demo.scope_exists(p_tenant, p_business, null, null)
     or not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('g3riskdet|' || p_tenant || '|' || p_business, 0));

  -- (a1) idempotency key replayed / conflicting repeatedly ------------------------------------------
  select * into rl from c10_gov003_demo.risk_rules r where r.rule_id = 'dup_key' and r.enabled;
  if found then
    minatt := coalesce((rl.params ->> 'min_attempts')::int, 3);
    for g in
      select l.idempotency_key as ikey, count(*)::int as attempts,
             (count(*) filter (where l.outcome = 'conflict'))::int as conflicts,
             (array_agg(l.original_event_id order by l.log_id))[1] as orig_event,
             (array_agg(l.log_id order by l.log_id))[1:10] as log_ids,
             array_agg(distinct l.actor_id) as attempt_actors
        from c10_gov003_demo.idempotency_conflict_log l
       where l.tenant_id = p_tenant and l.business_id = p_business
       group by l.idempotency_key
      having count(*) >= minatt
       order by l.idempotency_key collate "C"
    loop
      sev := case when g.conflicts >= 2 then 'high'
                  when g.conflicts = 1 or g.attempts >= 2 * minatt then 'medium' else 'low' end;
      conf := least(95, 55 + 10 * g.conflicts + 5 * (g.attempts - minatt));
      select array_agg(distinct x) into actors
        from unnest(g.attempt_actors || (select e.actor_id from c10_gov003_demo.audit_events e
                                          where e.event_id = g.orig_event)) x;
      ev := jsonb_build_array(jsonb_build_object('kind', 'audit_event', 'event_id', g.orig_event))
            || (select coalesce(jsonb_agg(jsonb_build_object('kind', 'idempotency_log', 'log_id', lid)), '[]'::jsonb)
                  from unnest(g.log_ids) lid);
      ctx := jsonb_strip_nulls(jsonb_build_object(
        'entity_ref', c10_gov003_demo._safe_ref(g.ikey), 'count', g.attempts::text,
        'expected_count', minatt::text, 'detail_code', 'idempotency_resubmitted'));
      select * into em from c10_gov003_demo._emit_signal(p_tenant, p_business, 'dup_key',
        'dupkey:' || g.ikey, sev, conf,
        format('Advisory only: an idempotency key was submitted %s time(s) after its first use (%s with changed content). '
               'This may indicate a retry loop or a client defect. Human review is required; no action was taken.',
               g.attempts, g.conflicts),
        null, ctx, null, null, ev, actors);
      return query select em.signal_id, 'dup_key'::text, 'dupkey:' || g.ikey, em.created, em.receipt_id;
    end loop;
  end if;

  -- (a2) identical command content resubmitted under different keys ---------------------------------
  select * into rl from c10_gov003_demo.risk_rules r where r.rule_id = 'dup_content' and r.enabled;
  if found then
    mindup := coalesce((rl.params ->> 'min_duplicates')::int, 3);
    win := coalesce((rl.params ->> 'window_seconds')::int, 3600);
    for g in
      select e.source_domain as sd, e.source_id as sid, e.action as act, e.payload_sha256 as psha,
             count(*)::int as n, min(e.event_time) as t0, max(e.event_time) as t1,
             (array_agg(e.event_id order by e.stream_seq))[1:10] as ids,
             array_agg(distinct e.actor_id) as actors
        from c10_gov003_demo.audit_events e
       where e.tenant_id = p_tenant and e.business_id = p_business
         and e.source_domain not like 'gov003.%' and e.event_time <= asof
       group by e.source_domain, e.source_id, e.action, e.payload_sha256
      having count(*) >= mindup and max(e.event_time) - min(e.event_time) <= make_interval(secs => win)
       order by e.source_domain collate "C", e.source_id collate "C", e.action collate "C", e.payload_sha256
    loop
      skey := 'dupcontent:' || g.sd || ':' || g.sid || ':' || g.act || ':' || left(g.psha, 16);
      sev := case when g.n >= 2 * mindup then 'high' else 'medium' end;
      conf := least(90, 50 + 10 * (g.n - mindup));
      ev := (select jsonb_agg(jsonb_build_object('kind', 'audit_event', 'event_id', i)) from unnest(g.ids) i);
      ctx := jsonb_strip_nulls(jsonb_build_object(
        'source_ref', c10_gov003_demo._safe_ref(g.sid), 'count', g.n::text, 'expected_count', '1',
        'window_start', c10_gov003_demo.utc_iso(g.t0), 'window_end', c10_gov003_demo.utc_iso(g.t1),
        'detail_code', 'content_resubmitted'));
      select * into em from c10_gov003_demo._emit_signal(p_tenant, p_business, 'dup_content', skey, sev, conf,
        format('Advisory only: %s events with identical content were recorded for the same source reference and command '
               'within %s seconds, each under a different idempotency key. This may be a duplicate submission; '
               'human review is required and no action was taken.', g.n, win),
        g.sd, ctx, g.t0, g.t1, ev, g.actors);
      return query select em.signal_id, 'dup_content'::text, skey, em.created, em.receipt_id;
    end loop;
  end if;

  -- (b1) unexpected volume in one fixed window -------------------------------------------------------
  select * into rl from c10_gov003_demo.risk_rules r where r.rule_id = 'volume_spike' and r.enabled;
  if found then
    win := coalesce((rl.params ->> 'window_seconds')::int, 600);
    maxev := coalesce((rl.params ->> 'max_events')::int, 20);
    for g in
      select e.source_domain as sd,
             date_bin(make_interval(secs => win), e.event_time, timestamptz '2000-01-01 00:00:00+00') as bstart,
             count(*)::int as n,
             (array_agg(e.event_id order by e.stream_seq))[1:10] as ids,
             array_agg(distinct e.actor_id) as actors
        from c10_gov003_demo.audit_events e
       where e.tenant_id = p_tenant and e.business_id = p_business
         and e.source_domain not like 'gov003.%' and e.event_time <= asof
       group by e.source_domain, 2
      having count(*) > maxev
       order by e.source_domain collate "C", 2
    loop
      skey := 'volume:' || g.sd || ':' || (extract(epoch from g.bstart))::bigint::text;
      sev := case when g.n >= 3 * maxev then 'high' else 'medium' end;
      conf := least(90, 50 + ((g.n - maxev) * 40) / maxev);
      ev := (select jsonb_agg(jsonb_build_object('kind', 'audit_event', 'event_id', i)) from unnest(g.ids) i);
      ctx := jsonb_strip_nulls(jsonb_build_object(
        'source_ref', c10_gov003_demo._safe_ref(g.sd), 'count', g.n::text, 'expected_count', maxev::text,
        'window_start', c10_gov003_demo.utc_iso(g.bstart),
        'window_end', c10_gov003_demo.utc_iso(g.bstart + make_interval(secs => win)),
        'detail_code', 'volume_above_expected'));
      select * into em from c10_gov003_demo._emit_signal(p_tenant, p_business, 'volume_spike', skey, sev, conf,
        format('Advisory only: %s events from source "%s" fell inside one %s-second window, above the configured '
               'expected maximum of %s. This may be a legitimate burst or a duplicated feed; human review is '
               'required and no action was taken.', g.n, g.sd, win, maxev),
        g.sd, ctx, g.bstart, g.bstart + make_interval(secs => win), ev, g.actors);
      return query select em.signal_id, 'volume_spike'::text, skey, em.created, em.receipt_id;
    end loop;
  end if;

  -- (b2) stale source ---------------------------------------------------------------------------------
  select * into rl from c10_gov003_demo.risk_rules r where r.rule_id = 'stale_source' and r.enabled;
  if found then
    maxsil := coalesce((rl.params ->> 'max_silence_seconds')::int, 3600);
    minev := coalesce((rl.params ->> 'min_events')::int, 2);
    basis := case when rl.params ->> 'basis' = 'ingest_time' then 'ingest_time' else 'event_time' end;
    for g in
      select e.source_domain as sd, count(*)::int as n,
             max(case when basis = 'ingest_time' then e.ingest_time else e.event_time end) as lastseen,
             (array_agg(e.event_id order by case when basis = 'ingest_time' then e.ingest_time else e.event_time end desc,
                                            e.stream_seq desc))[1] as last_event,
             (array_agg(e.actor_id order by case when basis = 'ingest_time' then e.ingest_time else e.event_time end desc,
                                            e.stream_seq desc))[1] as last_actor
        from c10_gov003_demo.audit_events e
       where e.tenant_id = p_tenant and e.business_id = p_business
         and e.source_domain not like 'gov003.%'
       group by e.source_domain
      having count(*) >= minev
       order by e.source_domain collate "C"
    loop
      silence := floor(extract(epoch from (asof - g.lastseen)))::bigint;
      continue when silence <= maxsil;
      skey := 'stale:' || g.sd || ':' || g.last_event::text;
      sev := case when silence > 3 * maxsil then 'medium' else 'low' end;
      conf := case when silence > 3 * maxsil then 80 else 60 end;
      ev := jsonb_build_array(jsonb_build_object('kind', 'audit_event', 'event_id', g.last_event));
      ctx := jsonb_strip_nulls(jsonb_build_object(
        'source_ref', c10_gov003_demo._safe_ref(g.sd), 'last_seen_at', c10_gov003_demo.utc_iso(g.lastseen),
        'observed_at', c10_gov003_demo.utc_iso(asof), 'count', silence::text, 'expected_count', maxsil::text,
        'detail_code', 'source_silent'));
      select * into em from c10_gov003_demo._emit_signal(p_tenant, p_business, 'stale_source', skey, sev, conf,
        format('Advisory only: no events were received from source "%s" for %s seconds, longer than the configured '
               'limit of %s seconds. The source may be paused or disconnected; human review is required and no '
               'action was taken.', g.sd, silence, maxsil),
        g.sd, ctx, g.lastseen, asof, ev, array[g.last_actor]);
      return query select em.signal_id, 'stale_source'::text, skey, em.created, em.receipt_id;
    end loop;
  end if;

  -- (c1) sensitive command from an identity without an owner role ----------------------------------
  select * into rl from c10_gov003_demo.risk_rules r where r.rule_id = 'unauthorized_command' and r.enabled;
  if found then
    prefixes := coalesce(rl.params -> 'sensitive_prefixes', '[]'::jsonb);
    for g in
      select e.event_id as eid, e.action as act, e.actor_id as actor, e.site_id as site, e.tenant_id as tid,
             e.business_id as bid, e.source_domain as sd, e.event_time as et
        from c10_gov003_demo.audit_events e
       where e.tenant_id = p_tenant and e.business_id = p_business
         and e.source_domain not like 'gov003.%' and e.event_time <= asof
         and exists (select 1 from jsonb_array_elements_text(prefixes) p where left(e.action, length(p)) = p)
         and not c10_gov003_demo.has_scope_role(e.actor_id, e.tenant_id, e.business_id, e.site_id,
                                                array['tenant_owner','business_owner'])
       order by e.stream_seq
    loop
      staff_cov := c10_gov003_demo.has_scope_role(g.actor, g.tid, g.bid, g.site, array['staff']);
      skey := 'unauth:' || g.eid::text;
      sev := case when staff_cov then 'medium' else 'high' end;
      conf := case when staff_cov then 70 else 85 end;
      ev := jsonb_build_array(jsonb_build_object('kind', 'audit_event', 'event_id', g.eid));
      ctx := jsonb_strip_nulls(jsonb_build_object(
        'source_ref', c10_gov003_demo._safe_ref(g.sd), 'observed_at', c10_gov003_demo.utc_iso(g.et),
        'detail_code', case when staff_cov then 'role_insufficient' else 'no_active_role' end));
      select * into em from c10_gov003_demo._emit_signal(p_tenant, p_business, 'unauthorized_command', skey, sev, conf,
        format('Advisory only: command "%s" is on the configured sensitive list but was submitted by an identity that '
               'currently holds no owner role for this scope. It may reflect a permission gap or a role change; '
               'human review is required and no action was taken.', g.act),
        g.sd, ctx, g.et, g.et, ev, array[g.actor]);
      return query select em.signal_id, 'unauthorized_command'::text, skey, em.created, em.receipt_id;
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- Human triage. One terminal state per signal; independent reviewer; audit receipt per review.
-- G3A01 forged actor | G3A02 scope denied | G3A03 invalid input | G3A05 unauthenticated
-- G3A06 reviewer not independent | G3C02 signal already reviewed (race loser / second review)
-- ---------------------------------------------------------------------------------------------------
create function c10_gov003_demo.review_signal(
  p_signal_id uuid, p_decision text, p_reason_code text, p_idem text, p_claimed_actor uuid default null)
returns table (review_id uuid, signal_id uuid, decision text, reason_code text, receipt_id uuid, replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  a uuid := c10_gov003_demo.actor_id();
  s record; ex record; rc record; v_rid uuid := gen_random_uuid(); ok_reason boolean;
begin
  if a is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if p_claimed_actor is not null and p_claimed_actor <> a then
    raise exception 'forged_actor: caller-supplied actor does not match the server-derived actor'
      using errcode = 'G3A01';
  end if;
  if p_signal_id is null or p_decision is null or p_reason_code is null or p_idem is null
     or p_decision not in ('acknowledge','dismiss')
     or p_idem !~ '^[A-Za-z0-9_.:-]{8,128}$' then
    raise exception 'invalid_review_input' using errcode = 'G3A03';
  end if;
  select sg.signal_id as sid, sg.tenant_id as tid, sg.business_id as bid, sg.severity as sev,
         sg.evidence_actor_ids as ev_actors into s
    from c10_gov003_demo.risk_signals sg where sg.signal_id = p_signal_id;
  -- Unknown signal and foreign-scope signal are indistinguishable to the caller (no existence leak).
  if not found or not c10_gov003_demo.can_read_business(s.tid, s.bid) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  ok_reason := case p_decision
    when 'acknowledge' then p_reason_code in ('followup_required','under_investigation','known_issue')
    else p_reason_code in ('false_positive','expected_activity','duplicate_signal','test_activity','accepted_risk') end;
  if not ok_reason then
    raise exception 'invalid_review_input: reason_code not allowed for this decision' using errcode = 'G3A03';
  end if;
  if a = any (s.ev_actors) then
    raise exception 'independent_review_required: reviewer is an actor of the evidence events'
      using errcode = 'G3A06';
  end if;

  -- Serialize reviewers of one signal across independent sessions: exactly one terminal state.
  perform pg_advisory_xact_lock(hashtextextended('g3review|' || p_signal_id::text, 0));
  select rv.review_id as rid, rv.reviewer_id as who, rv.request_idem as idem, rv.decision as dec,
         rv.reason_code as rcode, rv.receipt_id as rcpt into ex
    from c10_gov003_demo.risk_signal_reviews rv where rv.signal_id = p_signal_id;
  if found then
    if ex.who = a and ex.idem = p_idem and ex.dec = p_decision and ex.rcode = p_reason_code then
      return query select ex.rid, p_signal_id, ex.dec, ex.rcode, ex.rcpt, true;
      return;
    end if;
    raise exception 'signal_already_reviewed: a terminal review state already exists' using errcode = 'G3C02';
  end if;

  begin
    select * into rc from c10_gov003_demo._append_audit(s.tid, s.bid, null, null,
      'gov003.risk', 'review-' || p_signal_id::text, 'v1', 'risk.signal_reviewed', clock_timestamp(),
      'risk-review-' || p_signal_id::text, 'risk-review:' || p_signal_id::text,
      jsonb_build_object('signal_ref', p_signal_id::text, 'review_decision', p_decision,
                         'reason_code', p_reason_code, 'severity', s.sev, 'note_code', 'review_only'),
      null, 'review', 1, null, null);
    perform set_config('c10_gov003.writer', 'append_path', true);
    insert into c10_gov003_demo.risk_signal_reviews
      (review_id, signal_id, tenant_id, business_id, decision, reason_code, reviewer_id, request_idem,
       event_id, receipt_id)
    values (v_rid, p_signal_id, s.tid, s.bid, p_decision, p_reason_code, a, p_idem, rc.event_id, rc.receipt_id);
    perform set_config('c10_gov003.writer', '', true);
  exception when unique_violation then
    raise exception 'signal_already_reviewed: a terminal review state already exists' using errcode = 'G3C02';
  end;
  return query select v_rid, p_signal_id, p_decision, p_reason_code, rc.receipt_id, false;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- Grants. Writers: EXECUTE only to the trusted backend. Internals: owner only.
-- ---------------------------------------------------------------------------------------------------
revoke all on function
  c10_gov003_demo.risk_review_independence(),
  c10_gov003_demo._safe_ref(text),
  c10_gov003_demo.append_event_logged(uuid,uuid,uuid,uuid,text,text,text,text,timestamptz,text,text,jsonb,text,text,uuid,uuid),
  c10_gov003_demo._emit_signal(uuid,uuid,text,text,text,int,text,text,jsonb,timestamptz,timestamptz,jsonb,uuid[]),
  c10_gov003_demo.run_risk_detection(uuid,uuid,timestamptz,uuid),
  c10_gov003_demo.review_signal(uuid,text,text,text,uuid)
  from public;
grant execute on function
  c10_gov003_demo.append_event_logged(uuid,uuid,uuid,uuid,text,text,text,text,timestamptz,text,text,jsonb,text,text,uuid,uuid),
  c10_gov003_demo.run_risk_detection(uuid,uuid,timestamptz,uuid),
  c10_gov003_demo.review_signal(uuid,text,text,text,uuid)
  to c10g3_backend;
