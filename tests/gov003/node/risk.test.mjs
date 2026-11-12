// GOV-003 feature 08: pure unit tests for internal/gov003/server/risk.mjs (no database).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  evaluateRisk, assertAdvisoryOnly, reviewEligibility, hasScopeRole, safeRef, looksSecret, utcIso, DEFAULT_RULES,
  grantDiffAdvisory, FORBIDDEN_ACTION_KEYS, ACK_REASONS, DISMISS_REASONS,
} from '../../../internal/gov003/server/risk.mjs';

const T = 't-1'; const B = 'b-1'; const OWNER = 'u-owner'; const STAFF = 'u-staff'; const OWNER2 = 'u-owner-2'; const INVESTOR = 'u-inv';
const memberships = Object.freeze([
  { identity_id: OWNER, tenant_id: T, business_id: B, site_id: null, role: 'business_owner', status: 'active' },
  { identity_id: OWNER2, tenant_id: T, business_id: null, site_id: null, role: 'tenant_owner', status: 'active' },
  { identity_id: STAFF, tenant_id: T, business_id: B, site_id: 's-1', role: 'staff', status: 'active' },
  { identity_id: INVESTOR, tenant_id: T, business_id: B, site_id: null, role: 'investor', status: 'active' },
  { identity_id: 'u-revoked', tenant_id: T, business_id: B, site_id: null, role: 'business_owner', status: 'revoked' },
].map(Object.freeze));

let seq = 0;
const ev = (o) => Object.freeze({
  event_id: `e-${++seq}`, tenant_id: T, business_id: B, site_id: null, stream_seq: seq, source_domain: 'erp.pos', source_id: `ord-${seq}`,
  action: 'sale.recorded', event_time: '2026-11-10T09:00:00.000000Z', ingest_time: '2026-11-10T09:00:01.000000Z', actor_id: OWNER,
  payload_sha256: `${String(seq).padStart(2, '0')}`.repeat(32), ...o,
});
const run = (events, extra = {}) => evaluateRisk({ tenantId: T, businessId: B, events, memberships, asOf: '2026-11-10T12:00:00Z', ...extra });
const deepFreeze = (o) => { Object.values(o).forEach((v) => typeof v === 'object' && v && deepFreeze(v)); return Object.freeze(o); };

test('duplicate content under new keys: raised at the threshold, silent below it, silent outside the window', () => {
  const mk = (n, gapS) => Array.from({ length: n }, (_, i) => ev({ source_id: 'ord-X', payload_sha256: 'ab'.repeat(32), event_time: utcIso(Date.parse('2026-11-10T09:00:00Z') + i * gapS * 1000) }));
  const hit = run(mk(3, 20)).filter((s) => s.rule_id === 'dup_content');
  assert.equal(hit.length, 1);
  assert.equal(hit[0].severity, 'medium'); assert.equal(hit[0].confidence_pct, 50); assert.equal(hit[0].context.count, '3');
  assert.equal(hit[0].evidence.length, 3); assert.equal(hit[0].signal_key, `dupcontent:erp.pos:ord-X:sale.recorded:${'ab'.repeat(8)}`);
  assert.equal(run(mk(2, 20)).filter((s) => s.rule_id === 'dup_content').length, 0, 'two is not enough');
  assert.equal(run(mk(3, 1900)).filter((s) => s.rule_id === 'dup_content').length, 0, 'spread wider than 3600s');
  assert.equal(run(mk(3, 1800)).filter((s) => s.rule_id === 'dup_content').length, 1, 'exactly at the window edge still counts');
  const six = run(mk(6, 20)).find((s) => s.rule_id === 'dup_content');
  assert.equal(six.severity, 'high'); assert.equal(six.confidence_pct, 80);
});

test('volume spike: strictly above the maximum inside one aligned window; windows are fixed buckets, not sliding', () => {
  const rules = { ...DEFAULT_RULES, volume_spike: { enabled: true, params: { window_seconds: 600, max_events: 5 } } };
  const burst = (n, start) => Array.from({ length: n }, (_, i) => ev({ source_domain: 'erp.stock', source_id: `m-${i}`, event_time: utcIso(Date.parse(start) + i * 10000), payload_sha256: `${i}`.padStart(2, '0').repeat(32) }));
  assert.equal(run(burst(5, '2026-11-10T10:00:00Z'), { rules }).filter((s) => s.rule_id === 'volume_spike').length, 0, 'equal to the maximum is not above it');
  const six = run(burst(6, '2026-11-10T10:00:00Z'), { rules }).filter((s) => s.rule_id === 'volume_spike');
  assert.equal(six.length, 1); assert.equal(six[0].confidence_pct, 58); assert.equal(six[0].severity, 'medium');
  assert.equal(six[0].signal_key, `volume:erp.stock:${Date.parse('2026-11-10T10:00:00Z') / 1000}`);
  // the same six events straddling a bucket boundary (09:58:30 .. 09:59:20 | 10:00:10...) split into 3+3 -> not a spike
  const split = run(burst(6, '2026-11-10T09:59:40Z'), { rules }).filter((s) => s.rule_id === 'volume_spike');
  assert.equal(split.length, 0);
  assert.equal(run(burst(15, '2026-11-10T10:00:00Z'), { rules }).find((s) => s.rule_id === 'volume_spike').severity, 'high');
});

test('stale source: boundary exact, basis selectable, needs min_events, own gov003 domains and other scopes ignored', () => {
  const feed = (n, t) => Array.from({ length: n }, (_, i) => ev({ source_domain: 'erp.feed', event_time: t, ingest_time: utcIso(Date.parse(t) + 5000 + i) }));
  const asOf = '2026-11-10T12:00:00Z';
  const rulesFor = (secs, basis = 'event_time') => ({ ...DEFAULT_RULES, stale_source: { enabled: true, params: { max_silence_seconds: secs, min_events: 2, basis } } });
  const lastMs = Date.parse('2026-11-10T11:00:00Z');
  const stale = (events, rules) => run(events, { rules, asOf }).filter((s) => s.rule_id === 'stale_source');
  assert.equal(stale(feed(2, '2026-11-10T11:00:00Z'), rulesFor(3600)).length, 0, 'silence == limit is not stale');
  const s = stale(feed(2, '2026-11-10T11:00:00Z'), rulesFor(3599));
  assert.equal(s.length, 1); assert.equal(s[0].severity, 'low'); assert.equal(s[0].confidence_pct, 60);
  assert.equal(s[0].context.last_seen_at, utcIso(lastMs)); assert.equal(s[0].context.count, '3600');
  assert.equal(stale(feed(2, '2026-11-10T11:00:00Z'), rulesFor(1000))[0].severity, 'medium', '3x the limit raises severity');
  assert.equal(stale(feed(1, '2026-11-10T08:00:00Z'), rulesFor(60)).length, 0, 'one event is not an established source');
  const ing = stale(feed(2, '2026-11-10T11:00:00Z'), rulesFor(3500, 'ingest_time'));
  assert.equal(ing.length, 1); assert.equal(ing[0].context.count, String(3600 - 6), 'ingest basis measures from the latest ingest time');
  const own = feed(3, '2026-11-09T00:00:00Z').map((e) => ({ ...e, source_domain: 'gov003.risk' }));
  assert.equal(stale(own, rulesFor(60)).length, 0);
  const foreign = feed(3, '2026-11-09T00:00:00Z').map((e) => ({ ...e, business_id: 'b-2' }));
  assert.equal(stale(foreign, rulesFor(60)).length, 0, 'events of another business are never evaluated');
});

test('unauthorized command: staff -> medium/70, no active role -> high/85, owners and non-sensitive commands are not flagged', () => {
  const evs = [
    ev({ action: 'approval.override', actor_id: STAFF, site_id: 's-1', source_domain: 'erp.approvals' }),
    ev({ action: 'approval.grant', actor_id: OWNER, source_domain: 'erp.approvals' }),
    ev({ action: 'policy.change', actor_id: OWNER2, source_domain: 'erp.approvals' }),
    ev({ action: 'stock.moved', actor_id: STAFF, site_id: 's-1' }),
    ev({ action: 'payment.release', actor_id: 'u-revoked', source_domain: 'erp.pay' }),
    ev({ action: 'role.elevate', actor_id: INVESTOR, source_domain: 'erp.iam' }),
    ev({ action: 'approval.override', actor_id: STAFF, site_id: 's-2', source_domain: 'erp.approvals' }),
  ];
  const out = run(evs).filter((s) => s.rule_id === 'unauthorized_command');
  assert.deepEqual(out.map((s) => [s.signal_key, s.severity, s.confidence_pct, s.context.detail_code]), [
    [`unauth:${evs[0].event_id}`, 'medium', 70, 'role_insufficient'],
    [`unauth:${evs[4].event_id}`, 'high', 85, 'no_active_role'],
    [`unauth:${evs[5].event_id}`, 'high', 85, 'no_active_role'],
    [`unauth:${evs[6].event_id}`, 'high', 85, 'no_active_role'], // staff of site s-1 holds no role on site s-2
  ]);
  assert.match(out[0].reason, /command "approval.override" is on the configured sensitive list/);
});

test('idempotency key replays/conflicts: threshold, severity ladder, evidence links back to the original event', () => {
  const orig = ev({ actor_id: STAFF, site_id: 's-1' });
  const log = (n, conflicts) => Array.from({ length: n }, (_, i) => ({ log_id: i + 1, tenant_id: T, business_id: B, idempotency_key: 'key-0001', outcome: i < conflicts ? 'conflict' : 'replay', original_event_id: orig.event_id, actor_id: i % 2 ? OWNER : STAFF }));
  assert.equal(run([orig], { logs: log(2, 1) }).filter((s) => s.rule_id === 'dup_key').length, 0);
  const one = run([orig], { logs: log(3, 0) }).find((s) => s.rule_id === 'dup_key');
  assert.equal(one.severity, 'low'); assert.equal(one.confidence_pct, 55);
  assert.deepEqual(one.evidence[0], { kind: 'audit_event', event_id: orig.event_id });
  assert.deepEqual(one.evidence.slice(1).map((e) => e.log_id), [1, 2, 3]);
  assert.deepEqual(one.evidence_actor_ids, [OWNER, STAFF].sort());
  assert.equal(run([orig], { logs: log(3, 1) }).find((s) => s.rule_id === 'dup_key').severity, 'medium');
  assert.equal(run([orig], { logs: log(6, 0) }).find((s) => s.rule_id === 'dup_key').severity, 'medium', 'six replays = 2x threshold');
  const hi = run([orig], { logs: log(4, 2) }).find((s) => s.rule_id === 'dup_key');
  assert.equal(hi.severity, 'high'); assert.equal(hi.confidence_pct, 80);
  assert.equal(run([orig], { logs: log(3, 0).map((l) => ({ ...l, business_id: 'b-2' })) }).filter((s) => s.rule_id === 'dup_key').length, 0);
  assert.equal(run([orig], { logs: log(3, 0), rules: { ...DEFAULT_RULES, dup_key: { enabled: false, params: {} } } }).filter((s) => s.rule_id === 'dup_key').length, 0);
});

test('purity and determinism: inputs are never mutated, output is identical on re-run, evidence is capped at 10', () => {
  const events = Array.from({ length: 30 }, (_, i) => ev({ source_id: 'ord-Z', payload_sha256: 'cd'.repeat(32), event_time: utcIso(Date.parse('2026-11-10T09:00:00Z') + i * 1000) }));
  const input = deepFreeze({ tenantId: T, businessId: B, events, logs: [], memberships, asOf: '2026-11-10T12:00:00Z', rules: DEFAULT_RULES });
  const a = evaluateRisk(input); const b = evaluateRisk(input);
  assert.deepEqual(a, b);
  assert.ok(a.every((s) => s.evidence.length <= 10));
  assert.equal(a.find((s) => s.rule_id === 'dup_content').context.count, '30');
});

test('every raised advisory reads as advisory, asks for human review, and carries no action field', () => {
  const evs = [
    ev({ action: 'approval.override', actor_id: STAFF, site_id: 's-1', source_domain: 'erp.approvals' }),
    ...Array.from({ length: 4 }, () => ev({ source_id: 'ord-D', payload_sha256: 'ef'.repeat(32) })),
  ];
  const out = run(evs, { rules: { ...DEFAULT_RULES, stale_source: { enabled: true, params: { max_silence_seconds: 10, min_events: 2, basis: 'event_time' } } } });
  assert.ok(out.length >= 3);
  for (const s of out) {
    assert.equal(assertAdvisoryOnly(s), true);
    assert.equal(s.disposition, 'advisory_review_only');
    assert.ok(FORBIDDEN_ACTION_KEYS.every((k) => !(k in s)));
    assert.doesNotMatch(s.reason, /fraud|theft|steal|guilty|criminal/i);
  }
  const g = grantDiffAdvisory({ diff: { finding_count: 4, max_severity: 'high' }, baselineId: 'bl-1', diffId: 'df-1', detectorId: OWNER });
  assert.equal(assertAdvisoryOnly(g), true); assert.deepEqual(g.evidence_actor_ids, [OWNER]);
  assert.equal(grantDiffAdvisory({ diff: { finding_count: 0, max_severity: 'none' }, baselineId: 'b', diffId: 'd' }), null);
});

test('assertAdvisoryOnly rejects accusations, missing review language, wrong disposition and action keys', () => {
  const ok = { disposition: 'advisory_review_only', reason: 'Advisory only: unusual volume. Human review is required.' };
  assert.equal(assertAdvisoryOnly(ok), true);
  assert.throws(() => assertAdvisoryOnly({ ...ok, reason: 'Advisory only: the clerk committed fraud. Human review is required.' }), /not_advisory_only/);
  assert.throws(() => assertAdvisoryOnly({ ...ok, reason: 'Unusual volume. Human review is required.' }), /advisory/);
  assert.throws(() => assertAdvisoryOnly({ ...ok, reason: 'Advisory only: unusual volume.' }), /human review/);
  assert.throws(() => assertAdvisoryOnly({ ...ok, disposition: 'auto_freeze' }), /disposition/);
  for (const k of ['freeze', 'block', 'fire', 'transfer', 'approve', 'grant_role']) assert.throws(() => assertAdvisoryOnly({ ...ok, [k]: true }), new RegExp(k));
});

test('review eligibility: scope first, then input, then independence, then single terminal state (same order as SQL)', () => {
  const signal = { tenant_id: T, business_id: B, evidence_actor_ids: [STAFF] };
  const el = (o) => reviewEligibility({ signal, memberships, decision: 'dismiss', reasonCode: 'false_positive', reviewerId: OWNER2, ...o });
  assert.deepEqual(el({}), { ok: true, code: null, message: 'eligible' });
  assert.equal(el({ reviewerId: STAFF }).code, 'G3A02', 'site staff has no review right at all');
  assert.equal(el({ reviewerId: INVESTOR }).code, 'G3A02');
  assert.equal(el({ reviewerId: 'u-revoked' }).code, 'G3A02');
  assert.equal(el({ reviewerId: 'nobody' }).code, 'G3A02');
  assert.equal(el({ signal: { ...signal, tenant_id: 't-2' } }).code, 'G3A02', 'foreign tenant');
  assert.equal(el({ signal: null }).code, 'G3A02');
  assert.equal(el({ decision: 'approve' }).code, 'G3A03');
  assert.equal(el({ decision: 'acknowledge', reasonCode: 'false_positive' }).code, 'G3A03');
  assert.equal(el({ signal: { ...signal, evidence_actor_ids: [OWNER2] } }).code, 'G3A06');
  assert.equal(el({ existingReview: { id: 1 } }).code, 'G3C02');
  assert.equal(el({ reviewerId: STAFF, existingReview: { id: 1 } }).code, 'G3A02', 'denied callers learn nothing about review state');
  assert.deepEqual([...ACK_REASONS, ...DISMISS_REASONS].length, 8);
});

test('hasScopeRole mirrors SQL: site rows never cover a business-level target; revoked rows never count', () => {
  assert.equal(hasScopeRole(memberships, STAFF, T, B, 's-1', ['staff']), true);
  assert.equal(hasScopeRole(memberships, STAFF, T, B, null, ['staff']), false);
  assert.equal(hasScopeRole(memberships, STAFF, T, B, 's-2', ['staff']), false);
  assert.equal(hasScopeRole(memberships, OWNER2, T, 'b-anything', null, ['tenant_owner']), true, 'tenant owner covers every business of the tenant');
  assert.equal(hasScopeRole(memberships, OWNER2, 't-2', B, null, ['tenant_owner']), false);
  assert.equal(hasScopeRole(memberships, 'u-revoked', T, B, null, ['business_owner']), false);
});

test('redaction helpers: secrets and PII never become context references', () => {
  for (const bad of ['token-abc', 'user@example.com', 'eyJhbGciOiJIUzI1NiJ9abc', '4111111111111111', '123456789', 'has space']) assert.equal(safeRef(bad), null, bad);
  assert.equal(safeRef('order-1001'), 'order-1001');
  assert.equal(looksSecret('service_role key'), true); assert.equal(looksSecret('erp.pos'), false);
  const out = evaluateRisk({ tenantId: T, businessId: B, memberships, asOf: '2026-11-10T12:00:00Z',
    events: Array.from({ length: 3 }, () => ev({ source_id: 'token-777', payload_sha256: 'aa'.repeat(32) })) });
  const s = out.find((x) => x.rule_id === 'dup_content');
  assert.ok(s, 'the signal is still raised');
  assert.ok(!('source_ref' in s.context), 'but the secret-looking source id is not copied into context');
});

test('utcIso matches the SQL utc_iso() shape (microsecond precision, Z)', () => {
  assert.equal(utcIso(Date.parse('2026-11-10T09:00:00Z')), '2026-11-10T09:00:00.000000Z');
  assert.match(utcIso(1), /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/);
});
