// GOV-003 feature 08 risk-advisory-triage: positive + adversarial SQL suite (fresh DB, real psql backends).
// Run: node --test tests/gov003/sql/f08_risk.test.mjs   (Postgres at 127.0.0.1:55432, trust auth)
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { freshDb, dropDb, exec, rows, one, execAsync, adminExec, lit, uuidLit } from '../lib/db.mjs';
import { T1, T2, B1, B2, B3, U } from '../lib/ids.mjs';
import { evaluateRisk, assertAdvisoryOnly, reviewEligibility } from '../../../internal/gov003/server/risk.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const FIX = (f) => readFileSync(join(here, '..', 'fixtures', f), 'utf8');
const DB = 'g3_f089_f08';
const S = 'c10_gov003_demo';
const AS_OF = '2026-11-10T12:00:00Z';
const as = (sub) => ({ role: 'c10g3_backend', sub });
const owner = { role: 'c10g3_owner' };
const OWNER1 = U.bizOwnerB1; const OWNER1B = U.bizOwnerB1Second; const TOWN = U.tenantOwnerT1;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const codeOf = (fn) => { try { fn(); } catch (e) { return e.code; } return 'NO_ERROR'; };
const detect = (sub, t = T1, b = B1, asOf = AS_OF, claimed = null) =>
  rows(DB, `select rule_id, signal_key, created, signal_id, receipt_id from ${S}.run_risk_detection(${uuidLit(t)}, ${uuidLit(b)}, ${lit(asOf)}::timestamptz, ${uuidLit(claimed)})`, as(sub));
const review = (sub, sig, decision, reason, idem, claimed = null) =>
  rows(DB, `select * from ${S}.review_signal(${uuidLit(sig)}, ${lit(decision)}, ${lit(reason)}, ${lit(idem)}, ${uuidLit(claimed)})`, as(sub));
const sig = {}; // rule_id -> signal row (T1/B1)

// Independent catalog-free fingerprint of everything the risk module must NEVER touch.
const fingerprint = () => one(DB, `select jsonb_build_object(
  'stock', (select md5(coalesce(string_agg(t::text, '|' order by item_ref), '')) from ${S}.fx_stock_ledger t),
  'money', (select md5(coalesce(string_agg(t::text, '|' order by entry_id), '')) from ${S}.fx_money_ledger t),
  'approvals', (select md5(coalesce(string_agg(t::text, '|' order by approval_id), '')) from ${S}.fx_approvals t),
  'memberships', (select md5(coalesce(string_agg(t::text, '|' order by membership_id), '')) from ${S}.memberships t),
  'identities', (select md5(coalesce(string_agg(t::text, '|' order by identity_id), '')) from ${S}.identities t),
  'roles', (select md5(coalesce(string_agg(r::text, '|' order by rolname), '')) from pg_roles r where rolname like 'c10g3%'),
  'pg_memberships', (select md5(coalesce(string_agg(roleid::regrole::text || '>' || member::regrole::text, '|' order by roleid::regrole::text, member::regrole::text), '')) from pg_auth_members),
  'nonrisk_events', (select md5(coalesce(string_agg(e::text, '|' order by tenant_id, business_id, stream_seq), '')) from ${S}.audit_events e where source_domain not like 'gov003.%'),
  'nonrisk_event_count', (select count(*) from ${S}.audit_events where source_domain not like 'gov003.%'),
  'total_events', (select count(*) from ${S}.audit_events),
  'risk_events', (select count(*) from ${S}.audit_events where source_domain = 'gov003.risk')
) as fp`).fp;
const chainOk = (sub, t, b) => one(DB, `select * from ${S}.verify_chain(${uuidLit(t)}, ${uuidLit(b)})`, as(sub));

before(() => {
  freshDb(DB, { only: ['000', '010', '020', '030', '040', '080', '090'] });
  exec(DB, FIX('f08_09_events.sql'));
  exec(DB, FIX('f08_09_protected_state.sql'));
  exec(DB, `update ${S}.risk_rules set params = '{"max_silence_seconds":90000,"min_events":2,"basis":"event_time"}' where rule_id = 'stale_source';
            update ${S}.risk_rules set params = '{"window_seconds":600,"max_events":5}' where rule_id = 'volume_spike';`);
});
after(() => dropDb(DB));

test('writers are backend-only; internals are owner-only; ordinary roles cannot execute any of them', () => {
  const fns = [
    `${S}.append_event_logged(uuid,uuid,uuid,uuid,text,text,text,text,timestamptz,text,text,jsonb,text,text,uuid,uuid)`,
    `${S}.run_risk_detection(uuid,uuid,timestamptz,uuid)`, `${S}.review_signal(uuid,text,text,text,uuid)`];
  const internal = [`${S}._emit_signal(uuid,uuid,text,text,text,int,text,text,jsonb,timestamptz,timestamptz,jsonb,uuid[])`, `${S}._safe_ref(text)`];
  const priv = (role, fn) => (role === 'public'
    ? one(DB, `select exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                where p.oid = ${lit(fn)}::regprocedure and a.grantee = 0 and a.privilege_type = 'EXECUTE') as p`).p
    : one(DB, `select has_function_privilege(${lit(role)}, ${lit(fn)}, 'execute') as p`).p);
  for (const f of fns) {
    assert.equal(priv('c10g3_backend', f), true, `backend must execute ${f}`);
    for (const r of ['c10g3_app', 'c10g3_reader', 'public']) assert.equal(priv(r, f), false, `${r} must not execute ${f}`);
  }
  for (const f of internal) for (const r of ['c10g3_backend', 'c10g3_app', 'c10g3_reader', 'public']) assert.equal(priv(r, f), false);
  assert.equal(codeOf(() => exec(DB, `select * from ${S}._emit_signal(${uuidLit(T1)}, ${uuidLit(B1)}, 'dup_key', 'x-key-1', 'low', 10, 'Advisory only ...', null, '{}'::jsonb, null, null, '[]'::jsonb, '{}')`, as(OWNER1))), '42501');
});

test('fixture events chain verifies before any detection (baseline of history)', () => {
  assert.equal(chainOk(OWNER1, T1, B1).ok, true);
  assert.equal(chainOk(U.t2Owner, T2, B3).ok, true);
  assert.equal(one(DB, `select count(*)::int as n from ${S}.risk_signals`, owner).n, 0);
});

test('append_event_logged: replay and conflict are remembered; original event is never rewritten; core append_event unchanged', () => {
  const call = (sub, payload, key = 'idem-aux-0001', claimed = null, tenant = T1, biz = B1, site = '51000000-0000-4000-8000-000000000001') => rows(DB,
    `select * from ${S}.append_event_logged(${uuidLit(tenant)}, ${uuidLit(biz)}, ${uuidLit(site)}, null, 'erp.pos', 'order-3003', 'v1', 'sale.recorded',
      timestamptz '2026-11-10T09:45:00Z', 'corr-aux-1', ${lit(key)}, ${lit(JSON.stringify(payload))}::jsonb, null, 'finance', ${uuidLit(claimed)})`, as(sub));
  const p1 = { amount_minor: '100', currency: 'bdt' };
  const first = call(U.staffS1, p1)[0];
  assert.equal(first.outcome, 'created'); assert.equal(first.log_id, null);
  const rep = call(U.staffS1, p1)[0];
  assert.equal(rep.outcome, 'replayed'); assert.equal(rep.receipt_id, first.receipt_id); assert.ok(rep.log_id);
  const conflict = call(U.staffS1, { amount_minor: '101', currency: 'bdt' })[0];
  assert.equal(conflict.outcome, 'conflict');
  assert.equal(conflict.event_id, null, 'conflict must not disclose the original event/receipt');
  assert.equal(conflict.receipt_id, null);
  assert.ok(conflict.log_id);
  const log = rows(DB, `select outcome, original_event_id, actor_id from ${S}.idempotency_conflict_log where idempotency_key = 'idem-aux-0001' order by log_id`, owner);
  assert.deepEqual(log.map((l) => l.outcome), ['replay', 'conflict']);
  assert.ok(log.every((l) => l.original_event_id === first.event_id && l.actor_id === U.staffS1));
  assert.equal(one(DB, `select count(*)::int as n from ${S}.audit_events where idempotency_key = 'idem-aux-0001'`, owner).n, 1);
  assert.equal(one(DB, `select payload ->> 'amount_minor' as a from ${S}.audit_events where idempotency_key = 'idem-aux-0001'`, owner).a, '100');
  // the untouched core append still raises G3C01 for the same conflict
  assert.equal(codeOf(() => exec(DB, `select * from ${S}.append_event(${uuidLit(T1)}, ${uuidLit(B1)}, ${uuidLit('51000000-0000-4000-8000-000000000001')}, null, 'erp.pos', 'order-3003', 'v1', 'sale.recorded',
      timestamptz '2026-11-10T09:45:00Z', 'corr-aux-1', 'idem-aux-0001', '{"amount_minor":"999","currency":"bdt"}'::jsonb, null, 'finance')`, as(U.staffS1))), 'G3C01');
  // adversarial: forged actor, foreign scope, no authentication, investor
  assert.equal(codeOf(() => call(U.staffS1, p1, 'idem-aux-0002', U.bizOwnerB1)), 'G3A01');
  assert.equal(codeOf(() => call(U.staffS1, p1, 'idem-aux-0003', null, T2, B3, null)), 'G3A02');
  assert.equal(codeOf(() => call(U.investorB1, p1, 'idem-aux-0004')), 'G3A02');
  assert.equal(codeOf(() => call(U.unknown, p1, 'idem-aux-0005')), 'G3A05');
  // a staff member of Site 1 cannot log against Site 2 of the same business
  assert.equal(codeOf(() => call(U.staffS1, p1, 'idem-aux-0006', null, T1, B1, '51000000-0000-4000-8000-000000000002')), 'G3A02');
  // direct writes to the log are impossible for the backend role and for the owner outside the append path
  assert.equal(codeOf(() => exec(DB, `delete from ${S}.idempotency_conflict_log`, as(OWNER1))), '42501');
  assert.equal(codeOf(() => exec(DB, `update ${S}.idempotency_conflict_log set outcome = 'replay'`, owner)), 'G3H01');
});

test('detection is denied to forged, foreign, site-staff, investor, revoked, support, unknown and unauthenticated callers', () => {
  assert.equal(codeOf(() => detect(U.staffS1)), 'G3A02');
  assert.equal(codeOf(() => detect(U.investorB1)), 'G3A02');
  assert.equal(codeOf(() => detect(U.revokedB1)), 'G3A02');
  assert.equal(codeOf(() => detect(U.support)), 'G3A02');
  assert.equal(codeOf(() => detect(U.t2Owner)), 'G3A02', 'a T2 owner must not run detection on T1/B1');
  assert.equal(codeOf(() => detect(U.bizOwnerB2)), 'G3A02', 'owner of B2 must not run detection on B1');
  assert.equal(codeOf(() => detect(OWNER1, T1, B3)), 'G3A02', 'business that does not belong to the tenant');
  assert.equal(codeOf(() => detect(OWNER1, T2, B3)), 'G3A02');
  assert.equal(codeOf(() => detect(U.unknown)), 'G3A05');
  assert.equal(codeOf(() => rows(DB, `select * from ${S}.run_risk_detection(${uuidLit(T1)}, ${uuidLit(B1)})`, { role: 'c10g3_backend' })), 'G3A05');
  assert.equal(codeOf(() => detect(OWNER1, T1, B1, AS_OF, U.tenantOwnerT1)), 'G3A01', 'forged claimed actor');
  assert.equal(codeOf(() => exec(DB, `select * from ${S}.run_risk_detection(${uuidLit(T1)}, ${uuidLit(B1)})`, { role: 'c10g3_app', sub: OWNER1 })), '42501');
  assert.equal(one(DB, `select count(*)::int as n from ${S}.risk_signals`, owner).n, 0, 'denied attempts must create nothing');
});

let fpBeforeDetection;
test('owner detection raises one advisory signal per configured rule (duplicate key, duplicate content, volume, stale, unauthorized)', () => {
  fpBeforeDetection = fingerprint();
  const out = detect(OWNER1);
  assert.deepEqual(out.map((r) => r.rule_id), ['dup_key', 'dup_content', 'volume_spike', 'stale_source', 'unauthorized_command']);
  assert.ok(out.every((r) => r.created === true));
  const all = rows(DB, `select * from ${S}.v_risk_signals order by rule_id`, as(OWNER1));
  assert.equal(all.length, 5);
  for (const s of all) sig[s.rule_id] = s;
  assert.equal(sig.dup_key.signal_key, 'dupkey:idem-dup-0001');
  assert.equal(sig.dup_key.severity, 'medium'); assert.equal(sig.dup_key.confidence_pct, 65);
  assert.equal(sig.dup_content.context.count, '3'); assert.equal(sig.dup_content.source_domain, 'erp.pos');
  assert.equal(sig.volume_spike.context.count, '7'); assert.equal(sig.volume_spike.context.expected_count, '5');
  assert.equal(sig.stale_source.source_domain, 'erp.supplier_feed');
  assert.equal(sig.stale_source.context.last_seen_at, '2026-11-09T08:05:00.000000Z');
  assert.equal(sig.unauthorized_command.severity, 'medium');
  assert.equal(sig.unauthorized_command.context.detail_code, 'role_insufficient');
  for (const s of all) {
    assert.equal(s.status, 'open'); assert.equal(s.disposition, 'advisory_review_only');
    assert.ok(s.confidence_pct >= 0 && s.confidence_pct <= 100);
    assert.ok(s.detected_at && s.context && s.rule_id && s.reason);
  }
  // negative controls: the owner's own sensitive command and the quiet domains are NOT flagged
  assert.equal(all.filter((s) => s.signal_key.startsWith('unauth:')).length, 1);
  assert.equal(all.filter((s) => s.rule_id === 'stale_source').length, 1);
});

test('re-running detection is idempotent: no duplicate signals, no duplicate receipts', () => {
  const before = one(DB, `select (select count(*) from ${S}.risk_signals)::int as s, (select count(*) from ${S}.audit_events where source_domain = 'gov003.risk')::int as e`, owner);
  const out = detect(OWNER1B);
  assert.ok(out.every((r) => r.created === false));
  assert.deepEqual(out.map((r) => r.signal_id).sort(), Object.values(sig).map((s) => s.signal_id).sort());
  const after = one(DB, `select (select count(*) from ${S}.risk_signals)::int as s, (select count(*) from ${S}.audit_events where source_domain = 'gov003.risk')::int as e`, owner);
  assert.deepEqual(after, before);
});

test('every signal links evidence that resolves to real events/receipts/log rows in the same scope', () => {
  for (const s of Object.values(sig)) {
    const ev = rows(DB, `select * from ${S}.v_risk_signal_evidence where signal_id = ${uuidLit(s.signal_id)} order by evidence_id`, as(OWNER1));
    assert.ok(ev.length >= 1, `${s.rule_id} needs evidence`);
    for (const e of ev) {
      assert.equal(e.tenant_id, T1); assert.equal(e.business_id, B1);
      if (e.evidence_kind === 'audit_event') {
        const r = one(DB, `select count(*)::int as n from ${S}.v_audit_events where event_id = ${uuidLit(e.event_id)} and receipt_id = ${uuidLit(e.receipt_id)}`, as(OWNER1));
        assert.equal(r.n, 1, 'evidence event + receipt must exist in the owner-visible journal');
      } else {
        assert.equal(e.evidence_kind, 'idempotency_log');
        assert.equal(one(DB, `select count(*)::int as n from ${S}.v_idempotency_attempts where log_id = ${e.log_id}`, as(OWNER1)).n, 1);
      }
    }
  }
  const dk = rows(DB, `select evidence_kind from ${S}.v_risk_signal_evidence where signal_id = ${uuidLit(sig.dup_key.signal_id)} order by evidence_id`, as(OWNER1));
  assert.deepEqual(dk.map((e) => e.evidence_kind), ['audit_event', 'idempotency_log', 'idempotency_log', 'idempotency_log']);
  const dc = rows(DB, `select count(*)::int as n from ${S}.v_risk_signal_evidence where signal_id = ${uuidLit(sig.dup_content.signal_id)} and evidence_kind = 'audit_event'`, as(OWNER1));
  assert.equal(dc[0].n, 3);
});

test('each signal has an immutable audit receipt (source_domain gov003.risk) and the chain still verifies', () => {
  for (const s of Object.values(sig)) {
    const r = one(DB, `select e.source_domain, e.action, e.payload, e.event_id, e.actor_id, r.receipt_digest
        from ${S}.v_audit_events e join ${S}.audit_receipts r on r.receipt_id = e.receipt_id
       where e.receipt_id = ${uuidLit(s.receipt_id)}`, as(OWNER1));
    assert.equal(r.source_domain, 'gov003.risk'); assert.equal(r.action, 'risk.signal_raised');
    assert.equal(r.payload.signal_ref, s.signal_id); assert.equal(r.payload.reason_code, s.rule_id);
    assert.equal(r.payload.note_code, 'advisory_only'); assert.equal(r.actor_id, OWNER1, 'actor derived server-side');
    assert.match(r.receipt_digest, /^[0-9a-f]{64}$/);
  }
  assert.deepEqual(chainOk(OWNER1, T1, B1), { ok: true, checked: one(DB, `select count(*)::int as n from ${S}.audit_events where business_id = ${uuidLit(B1)}`, owner).n, first_bad_seq: null, reason: null });
});

test('advisory language: every reason is review-only wording, never an accusation; the table forbids anything else', () => {
  for (const s of Object.values(sig)) {
    assertAdvisoryOnly({ disposition: s.disposition, reason: s.reason });
    assert.match(s.reason, /^Advisory only:/); assert.match(s.reason, /no action was taken|No permission was changed/);
  }
  const ins = (reason, disp = 'advisory_review_only') => exec(DB, `select set_config('c10_gov003.writer','append_path',false);
    insert into ${S}.risk_signals (signal_id, tenant_id, business_id, rule_id, signal_key, disposition, severity, confidence_pct, reason, detected_by, event_id, receipt_id)
    select gen_random_uuid(), tenant_id, business_id, 'dup_key', 'x-lang-' || md5(${lit(reason + disp)}), ${lit(disp)}, 'low', 10, ${lit(reason)}, detected_by, event_id, receipt_id from ${S}.risk_signals limit 1`, owner);
  assert.equal(codeOf(() => ins('Advisory only: this person committed fraud and must be stopped.')), '23514');
  assert.equal(codeOf(() => ins('This employee is guilty of theft; freeze the account immediately please.')), '23514');
  assert.equal(codeOf(() => ins('Advisory only: unusual volume, human review is required, nothing done.', 'auto_freeze')), '23514');
  assert.equal(codeOf(() => ins('Advisory only: unusual volume seen; human review is required; nothing was done.')), 'NO_ERROR');
  exec(DB, `select set_config('c10_gov003.writer','',false)`, owner);
  const cols = rows(DB, `select table_name, column_name from information_schema.columns where table_schema = '${S}' and table_name in
    ('risk_signals','risk_signal_evidence','risk_signal_reviews','idempotency_conflict_log','catalog_snapshots','catalog_baselines','catalog_diffs')`, owner);
  assert.deepEqual(cols.filter((c) => /(freeze|block|suspend|terminate|fire|debit|transfer|escalat)/i.test(c.column_name)), []);
});

test('signals, evidence, reviews and the log are immutable for every principal', () => {
  for (const t of ['risk_signals', 'risk_signal_evidence', 'risk_signal_reviews', 'idempotency_conflict_log']) {
    assert.equal(codeOf(() => exec(DB, `update ${S}.${t} set tenant_id = tenant_id`, as(OWNER1))), '42501', `${t} update (backend)`);
    assert.equal(codeOf(() => exec(DB, `delete from ${S}.${t}`, as(OWNER1))), '42501', `${t} delete (backend)`);
    assert.equal(codeOf(() => exec(DB, `truncate ${S}.${t}`, as(OWNER1))), '42501', `${t} truncate (backend)`);
    assert.equal(codeOf(() => exec(DB, `update ${S}.${t} set tenant_id = tenant_id`, owner)), 'G3H01', `${t} update (owner role bypass attempt)`);
    assert.equal(codeOf(() => exec(DB, `delete from ${S}.${t}`, owner)), 'G3H01', `${t} delete (owner role bypass attempt)`);
    assert.equal(codeOf(() => exec(DB, `truncate ${S}.${t}`, owner)), 'G3H01', `${t} truncate (owner role bypass attempt)`);
  }
  assert.equal(codeOf(() => exec(DB, `insert into ${S}.risk_signals (signal_id) values (gen_random_uuid())`, as(OWNER1))), '42501');
  assert.equal(codeOf(() => exec(DB, `insert into ${S}.risk_signals (signal_id) values (gen_random_uuid())`, owner)), 'G3H01', 'owner direct INSERT outside the append path');
  assert.equal(codeOf(() => exec(DB, `select * from ${S}.risk_signals`, { role: 'c10g3_app', sub: OWNER1 })), '42501');
});

test('reads are business-scoped: site staff, investor, revoked, support, other owners and T2 see zero rows and zero counts', () => {
  assert.equal(rows(DB, `select * from ${S}.v_risk_signals`, as(OWNER1)).length, 5);
  assert.equal(rows(DB, `select * from ${S}.v_risk_signals`, as(TOWN)).length, 5, 'tenant owner');
  for (const [label, sub] of [['staff', U.staffS1], ['investor', U.investorB1], ['revoked', U.revokedB1], ['support', U.support],
    ['owner of B2', U.bizOwnerB2], ['T2 owner', U.t2Owner], ['unknown', U.unknown]]) {
    for (const v of ['v_risk_signals', 'v_risk_signal_evidence', 'v_idempotency_attempts']) {
      assert.deepEqual(one(DB, `select count(*)::int as n from ${S}.${v}`, as(sub)), { n: 0 }, `${label} must not count rows in ${v}`);
    }
  }
  assert.equal(rows(DB, `select * from ${S}.v_risk_signals`, { role: 'c10g3_reader', sub: OWNER1 }).length, 5);
  // the rule configuration is global, non-tenant data
  assert.equal(rows(DB, `select rule_id from ${S}.risk_rules`, as(U.staffS1)).length, 6);
  assert.equal(codeOf(() => exec(DB, `update ${S}.risk_rules set enabled = false`, as(OWNER1))), '42501');
});

test('Node matchers (internal/gov003/server/risk.mjs) reproduce the SQL signals exactly: same rule, key, severity, confidence, reason, context, evidence', () => {
  const ev = rows(DB, `select event_id, tenant_id, business_id, site_id, stream_seq, source_domain, source_id, action,
      ${S}.utc_iso(event_time) as event_time, ${S}.utc_iso(ingest_time) as ingest_time, actor_id, payload_sha256 from ${S}.audit_events`, owner);
  const logs = rows(DB, `select log_id, tenant_id, business_id, idempotency_key, outcome, original_event_id, actor_id from ${S}.idempotency_conflict_log`, owner);
  const memberships = rows(DB, `select identity_id, tenant_id, business_id, site_id, role, status from ${S}.memberships`, owner);
  const rules = Object.fromEntries(rows(DB, `select rule_id, enabled, params from ${S}.risk_rules`, owner).map((r) => [r.rule_id, { enabled: r.enabled, params: r.params }]));
  const js = evaluateRisk({ tenantId: T1, businessId: B1, events: ev, logs, memberships, rules, asOf: AS_OF });
  // the aux idempotency key used earlier (idem-aux-0001) has only 2 attempts (< min 3): no signal, same on both sides
  assert.deepEqual(js.map((s) => s.rule_id), ['dup_key', 'dup_content', 'volume_spike', 'stale_source', 'unauthorized_command']);
  for (const j of js) {
    const sql = sig[j.rule_id];
    assert.equal(j.signal_key, sql.signal_key, `${j.rule_id} key`);
    assert.equal(j.severity, sql.severity); assert.equal(j.confidence_pct, sql.confidence_pct);
    assert.equal(j.reason, sql.reason, `${j.rule_id} reason`);
    assert.deepEqual(j.context, sql.context, `${j.rule_id} context`);
    assert.equal(j.source_domain, sql.source_domain);
    const ms = (x) => (x === null ? null : Date.parse(x));
    assert.equal(j.window_start, ms(sql.window_start)); assert.equal(j.window_end, ms(sql.window_end));
    assert.deepEqual([...j.evidence_actor_ids], [...sql.evidence_actor_ids].sort());
    const evRows = rows(DB, `select evidence_kind, event_id, log_id from ${S}.v_risk_signal_evidence where signal_id = ${uuidLit(sql.signal_id)} order by evidence_id`, owner);
    assert.deepEqual(j.evidence, evRows.map((r) => (r.evidence_kind === 'audit_event' ? { kind: 'audit_event', event_id: r.event_id } : { kind: 'idempotency_log', log_id: r.log_id })));
    assertAdvisoryOnly(j);
  }
});

test('review: forged actor, unauthenticated, foreign scope, investor, revoked, site staff, support and unknown signals are denied; nothing is stored', () => {
  const s = sig.dup_content.signal_id;
  assert.equal(codeOf(() => review(OWNER1B, s, 'dismiss', 'false_positive', 'rev-idem-0001', U.tenantOwnerT1)), 'G3A01', 'forged actor');
  assert.equal(codeOf(() => rows(DB, `select * from ${S}.review_signal(${uuidLit(s)}, 'dismiss', 'false_positive', 'rev-idem-0001')`, { role: 'c10g3_backend' })), 'G3A05');
  for (const [label, sub] of [['staff', U.staffS1], ['investor', U.investorB1], ['revoked', U.revokedB1], ['support', U.support],
    ['T2 owner', U.t2Owner], ['owner of B2', U.bizOwnerB2]]) {
    assert.equal(codeOf(() => review(sub, s, 'dismiss', 'false_positive', 'rev-idem-0001')), 'G3A02', label);
  }
  assert.equal(codeOf(() => review(U.unknown, s, 'dismiss', 'false_positive', 'rev-idem-0001')), 'G3A05');
  assert.equal(codeOf(() => review(OWNER1B, '00000000-0000-4000-8000-000000000000', 'dismiss', 'false_positive', 'rev-idem-0001')), 'G3A02', 'unknown signal is indistinguishable from foreign');
  assert.equal(codeOf(() => exec(DB, `select * from ${S}.review_signal(${uuidLit(s)}, 'dismiss', 'false_positive', 'rev-idem-0001')`, { role: 'c10g3_app', sub: OWNER1B })), '42501');
  assert.equal(codeOf(() => review(OWNER1B, s, 'approve', 'false_positive', 'rev-idem-0001')), 'G3A03', 'only acknowledge|dismiss');
  assert.equal(codeOf(() => review(OWNER1B, s, 'acknowledge', 'false_positive', 'rev-idem-0001')), 'G3A03', 'reason must fit the decision');
  assert.equal(codeOf(() => review(OWNER1B, s, 'dismiss', 'free text; drop table', 'rev-idem-0001')), 'G3A03');
  assert.equal(codeOf(() => review(OWNER1B, s, 'dismiss', 'false_positive', 'short')), 'G3A03');
  assert.equal(one(DB, `select count(*)::int as n from ${S}.risk_signal_reviews`, owner).n, 0);
});

test('review independence: the actor of the evidence events cannot review; the Node contract agrees', () => {
  // dup_content evidence actor = business owner B1 (3 events). stale evidence actor = business owner B1 too.
  assert.equal(codeOf(() => review(OWNER1, sig.dup_content.signal_id, 'dismiss', 'false_positive', 'rev-idem-0002')), 'G3A06');
  assert.equal(codeOf(() => review(OWNER1, sig.stale_source.signal_id, 'acknowledge', 'followup_required', 'rev-idem-0002')), 'G3A06');
  // unauthorized-command evidence actor = staff: a different owner is fine; staff could never review anyway (G3A02)
  assert.equal(codeOf(() => review(U.staffS1, sig.unauthorized_command.signal_id, 'dismiss', 'false_positive', 'rev-idem-0002')), 'G3A02');
  const memberships = rows(DB, `select identity_id, tenant_id, business_id, site_id, role, status from ${S}.memberships`, owner);
  const signal = { tenant_id: T1, business_id: B1, evidence_actor_ids: sig.dup_content.evidence_actor_ids };
  assert.equal(reviewEligibility({ signal, reviewerId: OWNER1, memberships, decision: 'dismiss', reasonCode: 'false_positive' }).code, 'G3A06');
  assert.equal(reviewEligibility({ signal, reviewerId: OWNER1B, memberships, decision: 'dismiss', reasonCode: 'false_positive' }).ok, true);
  assert.equal(reviewEligibility({ signal, reviewerId: U.t2Owner, memberships, decision: 'dismiss', reasonCode: 'false_positive' }).code, 'G3A02');
  assert.equal(reviewEligibility({ signal, reviewerId: U.investorB1, memberships, decision: 'dismiss', reasonCode: 'false_positive' }).code, 'G3A02');
  assert.equal(reviewEligibility({ signal, reviewerId: OWNER1B, memberships, decision: 'dismiss', reasonCode: 'known_issue' }).code, 'G3A03');
  assert.equal(reviewEligibility({ signal, reviewerId: OWNER1B, memberships, decision: 'dismiss', reasonCode: 'false_positive', existingReview: { x: 1 } }).code, 'G3C02');
  // defense in depth: even a direct owner-path insert cannot record a self-review
  assert.equal(codeOf(() => exec(DB, `select set_config('c10_gov003.writer','append_path',false);
    insert into ${S}.risk_signal_reviews (review_id, signal_id, tenant_id, business_id, decision, reason_code, reviewer_id, request_idem, event_id, receipt_id)
    select gen_random_uuid(), signal_id, tenant_id, business_id, 'dismiss', 'false_positive', ${uuidLit(OWNER1)}, 'direct-self-0001', event_id, receipt_id
      from ${S}.risk_signals where signal_id = ${uuidLit(sig.dup_content.signal_id)}`, owner)), 'G3A06');
  assert.equal(one(DB, `select count(*)::int as n from ${S}.risk_signal_reviews`, owner).n, 0);
});

test('independent owner dismisses with a reason: terminal state + audit receipt; stock/money/approvals/roles/audit history are unchanged', () => {
  const fp0 = fingerprint();
  const out = review(OWNER1B, sig.dup_content.signal_id, 'dismiss', 'expected_activity', 'rev-idem-0003')[0];
  assert.equal(out.decision, 'dismiss'); assert.equal(out.replayed, false); assert.ok(out.receipt_id);
  const fp1 = fingerprint();
  for (const k of ['stock', 'money', 'approvals', 'memberships', 'identities', 'roles', 'pg_memberships', 'nonrisk_events', 'nonrisk_event_count']) {
    assert.equal(fp1[k], fp0[k], `dismissal must not change ${k}`);
  }
  assert.equal(fp1.risk_events, fp0.risk_events + 1);
  assert.equal(fp1.total_events, fp0.total_events + 1);
  const v = one(DB, `select * from ${S}.v_risk_signals where signal_id = ${uuidLit(sig.dup_content.signal_id)}`, as(OWNER1));
  assert.equal(v.status, 'dismissed'); assert.equal(v.reviewer_id, OWNER1B); assert.equal(v.review_reason_code, 'expected_activity');
  const rc = one(DB, `select e.action, e.source_domain, e.actor_id, e.payload from ${S}.v_audit_events e where e.receipt_id = ${uuidLit(out.receipt_id)}`, as(OWNER1));
  assert.equal(rc.action, 'risk.signal_reviewed'); assert.equal(rc.source_domain, 'gov003.risk'); assert.equal(rc.actor_id, OWNER1B);
  assert.deepEqual(rc.payload, { signal_ref: sig.dup_content.signal_id, review_decision: 'dismiss', reason_code: 'expected_activity', severity: 'medium', note_code: 'review_only' });
  assert.equal(chainOk(OWNER1, T1, B1).ok, true);
});

test('second review of the same signal: exact replay returns the stored review; any other reviewer/decision/key gets G3C02', () => {
  const s = sig.dup_content.signal_id;
  const again = review(OWNER1B, s, 'dismiss', 'expected_activity', 'rev-idem-0003')[0];
  assert.equal(again.replayed, true);
  assert.equal(codeOf(() => review(TOWN, s, 'acknowledge', 'followup_required', 'rev-idem-0004')), 'G3C02');
  assert.equal(codeOf(() => review(TOWN, s, 'dismiss', 'expected_activity', 'rev-idem-0003')), 'G3C02');
  assert.equal(codeOf(() => review(OWNER1B, s, 'acknowledge', 'known_issue', 'rev-idem-0005')), 'G3C02');
  assert.equal(codeOf(() => review(OWNER1B, s, 'dismiss', 'expected_activity', 'rev-idem-0099')), 'G3C02', 'same reviewer, new key');
  assert.equal(one(DB, `select count(*)::int as n from ${S}.risk_signal_reviews where signal_id = ${uuidLit(s)}`, owner).n, 1);
  assert.equal(one(DB, `select count(*)::int as n from ${S}.audit_events where idempotency_key = ${lit('risk-review:' + s)}`, owner).n, 1);
  // the UNIQUE(signal_id) constraint itself: even a direct owner-path second row is refused
  assert.equal(codeOf(() => exec(DB, `select set_config('c10_gov003.writer','append_path',false);
    insert into ${S}.risk_signal_reviews (review_id, signal_id, tenant_id, business_id, decision, reason_code, reviewer_id, request_idem, event_id, receipt_id)
    select gen_random_uuid(), signal_id, tenant_id, business_id, 'acknowledge', 'known_issue', ${uuidLit(TOWN)}, 'direct-dup-0001', event_id, receipt_id
      from ${S}.risk_signals where signal_id = ${uuidLit(s)}`, owner)), '23505');
  // acknowledge path for another signal by the tenant owner (not an evidence actor)
  const ack = review(TOWN, sig.unauthorized_command.signal_id, 'acknowledge', 'followup_required', 'rev-idem-0006')[0];
  assert.equal(ack.decision, 'acknowledge');
  assert.equal(one(DB, `select status from ${S}.v_risk_signals where signal_id = ${uuidLit(sig.unauthorized_command.signal_id)}`, as(OWNER1)).status, 'acknowledged');
});

test('REAL two-process race: one psql backend holds its review transaction open (pg_sleep); the second overlaps, WAITS on the advisory lock, then loses with G3C02', async () => {
  const s = sig.volume_spike.signal_id;
  const t0 = Date.now();
  const a = execAsync(DB, `begin;
      select review_id from ${S}.review_signal(${uuidLit(s)}, 'dismiss', 'test_activity', 'race-idem-A001');
      select pg_sleep(2.5);
      commit;`, as(OWNER1B));
  await sleep(500);
  const b = execAsync(DB, `select review_id from ${S}.review_signal(${uuidLit(s)}, 'acknowledge', 'followup_required', 'race-idem-B001');`, as(TOWN)).then((r) => ({ ...r, ms: Date.now() - t0 }));
  await sleep(900);
  // a THIRD independent connection proves B is genuinely blocked, not just slow
  const waiting = one(DB, `select count(*)::int as n from pg_locks where locktype = 'advisory' and not granted`).n;
  assert.ok(waiting >= 1, 'second reviewer must be waiting on the advisory lock while the first holds its transaction open');
  const [ra, rb] = await Promise.all([a, b]);
  assert.equal(ra.ok, true, ra.error?.message);
  assert.equal(rb.ok, false); assert.equal(rb.error.code, 'G3C02');
  assert.ok(rb.ms >= 2000, `loser must have waited for the winner's commit (took ${rb.ms}ms)`);
  const revs = rows(DB, `select decision, reviewer_id from ${S}.risk_signal_reviews where signal_id = ${uuidLit(s)}`, owner);
  assert.deepEqual(revs, [{ decision: 'dismiss', reviewer_id: OWNER1B }], 'EXACTLY ONE terminal state, from the winner');
  assert.equal(one(DB, `select count(*)::int as n from ${S}.audit_events where idempotency_key = ${lit('risk-review:' + s)}`, owner).n, 1);
  assert.equal(one(DB, `select status from ${S}.v_risk_signals where signal_id = ${uuidLit(s)}`, as(OWNER1)).status, 'dismissed');
});

test('REAL simultaneous race (no sleep): three independent backends review one signal at once -> exactly one winner, two G3C02', async () => {
  const s = sig.stale_source.signal_id;
  const mk = (sub, dec, why, idem) => execAsync(DB, `select review_id from ${S}.review_signal(${uuidLit(s)}, ${lit(dec)}, ${lit(why)}, ${lit(idem)});`, as(sub));
  const res = await Promise.all([
    mk(OWNER1B, 'dismiss', 'false_positive', 'race2-idem-A01'),
    mk(TOWN, 'acknowledge', 'known_issue', 'race2-idem-B01'),
    mk(TOWN, 'dismiss', 'accepted_risk', 'race2-idem-C01'),
  ]);
  // evidence actor of the stale signal is OWNER1 (excluded), so all three are eligible reviewers
  assert.equal(res.filter((r) => r.ok).length, 1, JSON.stringify(res.map((r) => r.error?.code)));
  assert.deepEqual(res.filter((r) => !r.ok).map((r) => r.error.code), ['G3C02', 'G3C02']);
  assert.equal(one(DB, `select count(*)::int as n from ${S}.risk_signal_reviews where signal_id = ${uuidLit(s)}`, owner).n, 1);
  assert.equal(one(DB, `select count(*)::int as n from ${S}.audit_events where idempotency_key = ${lit('risk-review:' + s)}`, owner).n, 1);
});

test('tenant isolation: T2 detects and reviews its own signals; neither tenant can see, count or review the other\'s', () => {
  const t2 = detect(U.t2Owner, T2, B3);
  assert.deepEqual(t2.map((r) => r.rule_id), ['dup_content']);
  const t2rows = rows(DB, `select signal_id, tenant_id from ${S}.v_risk_signals`, as(U.t2Owner));
  assert.equal(t2rows.length, 1); assert.ok(t2rows.every((r) => r.tenant_id === T2));
  assert.equal(rows(DB, `select * from ${S}.v_risk_signals`, as(OWNER1)).every((r) => r.tenant_id === T1), true);
  const t2sig = t2rows[0].signal_id;
  assert.equal(codeOf(() => review(OWNER1, t2sig, 'dismiss', 'false_positive', 'x-tenant-0001')), 'G3A02', 'T1 owner cannot review a T2 signal');
  assert.equal(codeOf(() => review(TOWN, t2sig, 'dismiss', 'false_positive', 'x-tenant-0002')), 'G3A02');
  assert.equal(codeOf(() => review(U.t2Owner, sig.dup_key.signal_id, 'dismiss', 'false_positive', 'x-tenant-0003')), 'G3A02', 'T2 owner cannot review a T1 signal');
  assert.equal(chainOk(U.t2Owner, T2, B3).ok, true);
});

test('detection is config-driven: a disabled rule raises nothing; thresholds come from risk_rules (stale limit lowered -> more stale signals)', () => {
  exec(DB, `update ${S}.risk_rules set enabled = false where rule_id = 'unauthorized_command'`, owner);
  exec(DB, `update ${S}.risk_rules set params = '{"max_silence_seconds":3600,"min_events":2,"basis":"event_time"}' where rule_id = 'stale_source'`, owner);
  const out = detect(OWNER1, T1, B1, '2026-11-10T13:00:00Z');
  assert.equal(out.filter((r) => r.rule_id === 'unauthorized_command').length, 0);
  const stale = out.filter((r) => r.rule_id === 'stale_source' && r.created);
  assert.ok(stale.length >= 3, 'erp.pos, erp.stock, erp.approvals are now silent beyond 1h at 13:00');
  exec(DB, `update ${S}.risk_rules set enabled = true where rule_id = 'unauthorized_command'`, owner);
});

test('NO AUTONOMOUS ACTION: detection + dismissal + acknowledgement + races left stock, money, approvals, roles, memberships and event history untouched; chain verifies', () => {
  const after = fingerprint();
  for (const k of ['stock', 'money', 'approvals', 'memberships', 'identities', 'roles', 'pg_memberships', 'nonrisk_events', 'nonrisk_event_count']) {
    assert.equal(after[k], fpBeforeDetection[k], `${k} must be identical before and after`);
  }
  const sigCount = one(DB, `select count(*)::int as n from ${S}.risk_signals`, owner).n;
  const revCount = one(DB, `select count(*)::int as n from ${S}.risk_signal_reviews`, owner).n;
  assert.equal(after.risk_events, sigCount + revCount, 'the only new audit rows are signal and review receipts');
  assert.equal(after.total_events - fpBeforeDetection.total_events, sigCount + revCount);
  assert.equal(chainOk(OWNER1, T1, B1).ok, true);
  assert.equal(chainOk(U.t2Owner, T2, B3).ok, true);
  // the stand-in approval that the unauthorized-command signal is "about" is still pending: nothing was blocked or changed
  assert.deepEqual(rows(DB, `select approval_id, status from ${S}.fx_approvals order by 1`, owner), [{ approval_id: 'appr-77', status: 'pending' }, { approval_id: 'appr-78', status: 'approved' }]);
});

test('static fence: risk functions contain no GRANT/REVOKE/ALTER/DROP/TRUNCATE/dynamic SQL and only write their own append-only tables', () => {
  const names = ['append_event_logged', 'run_risk_detection', 'review_signal', '_emit_signal', '_safe_ref', 'risk_review_independence'];
  const srcs = rows(DB, `select proname, prosrc from pg_proc where pronamespace = '${S}'::regnamespace and proname = any (${`array[${names.map(lit).join(',')}]`})`, owner);
  assert.equal(srcs.length, names.length);
  const allowed = new Set([`${S}.idempotency_conflict_log`, `${S}.risk_signals`, `${S}.risk_signal_evidence`, `${S}.risk_signal_reviews`]);
  for (const { proname, prosrc } of srcs) {
    const code = prosrc.replace(/--[^\n]*/g, '').replace(/'(?:[^']|'')*'/g, "''");
    assert.doesNotMatch(code, /\b(grant|revoke|alter|drop|truncate|create|execute|copy|delete|update)\b/i, `${proname} must not run DDL/privilege/dynamic SQL or UPDATE/DELETE`);
    assert.doesNotMatch(code, /pg_terminate_backend|pg_cancel_backend|set_role|set\s+role/i, proname);
    for (const m of code.matchAll(/insert\s+into\s+([a-z0-9_.]+)/gi)) assert.ok(allowed.has(m[1]), `${proname} writes ${m[1]}`);
  }
  // the detector's reason text is generated server-side from constants; the signal table cannot hold an action column
  assert.doesNotMatch(adminExec(`select string_agg(proname, ',') from pg_proc where pronamespace = '${S}'::regnamespace`, DB), /\b(freeze|block_|auto_)/);
});
