// GOV-003 local demo API: Story A / B / C end to end over REAL HTTP against a disposable PostgreSQL database
// (g3_demo_test: strict-ordered migrations + deterministic seed + the demo fixture). DEMO / NOT LIVE.
// Run: node --test "tests/gov003/demo/*.test.mjs"   (Postgres at 127.0.0.1:55432, trust auth)
// Simulated identities come from the fixture adapter (X-Demo-Identity); they are NOT signed GoTrue evidence.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import http from 'node:http';
import { spawn, spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { startDemoServer } from '../../../internal/gov003/server/demo-server.mjs';
import { exec, one, dropDb } from '../lib/db.mjs';
import { T1, T2, B1, B2, B3, S1 } from '../lib/ids.mjs';
import { parseCsv } from '../../../internal/gov003/server/csv-export.mjs';

const DB = 'g3_demo_test';
let srv;
const key = (p) => `${p}-${randomUUID()}`;
const sc = (t = T1, b = B1) => ({ tenant_id: t, business_id: b });
const qs = (o) => new URLSearchParams(o).toString();
const sha = (s) => createHash('sha256').update(Buffer.from(s, 'utf8')).digest('hex');

async function call(path, who, { method = 'GET', body, headers = {} } = {}) {
  const h = { ...(who ? { 'x-demo-identity': who } : {}), ...headers };
  if (body !== undefined) h['content-type'] = 'application/json';
  const r = await fetch(srv.url + path, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  let json = null; try { json = JSON.parse(text); } catch { /* keep null */ }
  return { status: r.status, json, text, headers: r.headers };
}
const get = (path, who, s = sc(), extra = {}) => call(`${path}?${qs({ ...s, ...extra })}`, who);
const post = (path, who, body) => call(path, who, { method: 'POST', body });
const appendBody = (o = {}) => ({ ...sc(), site_id: S1, source_domain: 'pos.sales', source_id: 'ORD-T-1', action: 'order.created', reason_category: 'operational',
  payload: { status: 'new', amount_minor: '1000', currency: 'bdt' }, idempotency_key: key('t-append'), ...o });
const auditTotal = async (who = 'business_owner_b1', s = sc()) => (await get('/api/audit', who, s, { limit: 1 })).json.total_count;
const nonGovCount = () => Number(one(DB, "select count(*)::int as c from c10_gov003_demo.audit_events where source_domain not like 'gov003.%'").c);
const protectedFingerprint = () => one(DB, `select jsonb_build_object(
  'stock', (select md5(string_agg(t::text, '|' order by item_ref)) from c10_gov003_demo.fx_stock_ledger t),
  'money', (select md5(string_agg(t::text, '|' order by entry_id)) from c10_gov003_demo.fx_money_ledger t),
  'approvals', (select md5(string_agg(t::text, '|' order by approval_id)) from c10_gov003_demo.fx_approvals t),
  'memberships', (select md5(string_agg(t::text, '|' order by membership_id)) from c10_gov003_demo.memberships t),
  'identities', (select md5(string_agg(t::text, '|' order by identity_id)) from c10_gov003_demo.identities t)) as fp`).fp;

before(async () => {
  srv = await startDemoServer({ env: { ...process.env, G3_DEMO: '1' }, database: DB });
  // stand-in stock / money / approval tables (test-only, disposable DB): proves signals and reviews never touch them
  exec(DB, readFileSync(new URL('../fixtures/f08_09_protected_state.sql', import.meta.url).pathname, 'utf8'));
});
after(async () => { await srv?.close(); dropDb(DB); });

// =================================================================================== Story A
test('story A: me lists fixture scopes and the DB decides what each identity may do', async () => {
  const owner = (await call('/api/me', 'business_owner_b1')).json;
  assert.equal(owner.signed, false);
  assert.equal(owner.banner, 'DEMO / NOT LIVE');
  assert.equal(owner.targets.find((x) => x.business_id === B1).can_read, true);
  assert.equal(owner.targets.find((x) => x.business_id === B3).can_read, false);
  const staff = (await call('/api/me', 'staff_s1')).json;
  assert.equal(staff.targets.find((x) => x.business_id === B1).can_read, false);
  assert.equal(staff.targets.find((x) => x.business_id === B1).sites.find((s) => s.site_id === S1).can_write, true);
  const investor = (await call('/api/me', 'investor_b1')).json;
  assert.ok(investor.targets.every((x) => !x.can_read && !x.can_write && x.sites.every((s) => !s.can_write)));
});

test('story A: append, exact replay returns the SAME receipt, changed payload is 409, concurrent duplicates store one result', async () => {
  const before = await auditTotal();
  const b = appendBody();
  const first = await post('/api/audit/append', 'business_owner_b1', b);
  assert.equal(first.status, 201, first.text);
  assert.equal(first.json.replayed, false);
  const replay = await post('/api/audit/append', 'business_owner_b1', b);
  assert.equal(replay.status, 200);
  assert.equal(replay.json.replayed, true);
  assert.equal(replay.json.receipt_id, first.json.receipt_id);
  assert.equal(replay.json.event_digest, first.json.event_digest);
  assert.equal(await auditTotal(), before + 1, 'replay must not repeat the effect');

  const changed = await post('/api/audit/append', 'business_owner_b1', { ...b, payload: { ...b.payload, amount_minor: '1001' } });
  assert.equal(changed.status, 409);
  assert.equal(changed.json.error, 'idempotency_conflict');
  assert.equal(await auditTotal(), before + 1);

  const raceBody = appendBody({ source_id: 'ORD-RACE-1' });
  const rs = await Promise.all(Array.from({ length: 6 }, () => post('/api/audit/append', 'business_owner_b1', raceBody)));
  assert.equal(rs.filter((r) => r.status === 201).length, 1, 'exactly one creator');
  assert.equal(rs.filter((r) => r.status === 200).length, 5);
  assert.equal(new Set(rs.map((r) => r.json.receipt_id)).size, 1, 'one stored result / one receipt');
  assert.equal(await auditTotal(), before + 2);
});

test('story A: the actor is server-derived: a site-staff append is journalled under staff_s1, never a client claim', async () => {
  const r = await post('/api/audit/append', 'staff_s1', appendBody({ source_id: 'ORD-STAFF-1' }));
  assert.equal(r.status, 201, r.text);
  const j = await get('/api/audit', 'business_owner_b1', sc(), { source_domain: 'pos.sales', limit: 200 });
  const ev = j.json.events.find((e) => e.source_id === 'ORD-STAFF-1');
  assert.equal(ev.actor_id_label, 'staff_s1');
  // staff may write at the site but may not read the journal, nor write at business level
  assert.equal((await get('/api/audit', 'staff_s1')).status, 403);
  const bizLevel = appendBody({ source_id: 'ORD-STAFF-2' }); delete bizLevel.site_id;
  assert.equal((await post('/api/audit/append', 'staff_s1', bizLevel)).status, 403);
  assert.equal((await post('/api/audit/append', 'investor_b1', appendBody())).status, 403);
  assert.equal((await post('/api/audit/append', 'revoked_b1', appendBody())).status, 403);
});

test('story A: owner sees a filtered count and the chain verifies', async () => {
  const all = (await get('/api/audit', 'business_owner_b1', sc(), { limit: 200 })).json;
  const some = (await get('/api/audit', 'business_owner_b1', sc(), { action: 'order.created', limit: 200 })).json;
  assert.ok(some.filtered_count > 0 && some.filtered_count < all.total_count);
  assert.equal(some.filtered_count, some.events.length);
  assert.ok(some.events.every((e) => e.action === 'order.created'));
  assert.equal(all.events.length, all.total_count);
  assert.ok(all.events.every((e) => /^[0-9a-f]{64}$/.test(e.event_digest) && e.receipt_id && e.correlation_id && e.source_version));
  const v = (await get('/api/audit/verify', 'business_owner_b1')).json;
  assert.equal(v.ok, true);
  assert.equal(v.checked, all.total_count);
  assert.match(v.limitation, /not WORM/);
  // tenant owner sees the same business; the second tenant owner sees only their own
  assert.equal((await get('/api/audit', 'tenant_owner_t1')).status, 200);
  const t2 = await get('/api/audit', 'tenant_owner_t2', sc(T2, B3));
  assert.equal(t2.status, 200);
  assert.equal(t2.json.total_count, 2);
  assert.ok(t2.json.events.every((e) => e.source_id.startsWith('ORD-300')));
});

test('story A: export has a byte hash that matches recomputed bytes, a receipt, replay and a tamper check', async () => {
  const bad = await post('/api/audit/append', 'business_owner_b1', appendBody({ site_id: undefined, source_id: '-refund-9', action: 'sale.refund' }));
  assert.equal(bad.status, 201, bad.text);
  const idem = key('t-export');
  const body = { ...sc(), idempotency_key: idem, max_rows: 1000 };
  const ex = await post('/api/export', 'business_owner_b1', body);
  assert.equal(ex.status, 201, ex.text);
  const { receipt, csv } = ex.json;
  assert.equal(receipt.byte_sha256, sha(csv), 'logged SHA-256 equals recomputed exact bytes');
  assert.equal(ex.json.sha256_matches, true);
  assert.equal(receipt.byte_length, Buffer.byteLength(csv, 'utf8'));
  const rows = parseCsv(csv);
  assert.equal(rows.length - 1, receipt.row_count, 'row count in the receipt equals the CSV data rows');
  assert.ok(rows.some((r) => r[5] === "'-refund-9"), 'formula-leading cell is neutralised with a quote');
  assert.ok(!/bearer|password|@example/i.test(csv));
  const replay = await post('/api/export', 'business_owner_b1', body);
  assert.equal(replay.status, 200);
  assert.equal(replay.json.receipt.export_receipt_id, receipt.export_receipt_id);
  assert.equal(replay.json.receipt.byte_sha256, receipt.byte_sha256);
  const filtered = await post('/api/export', 'business_owner_b1', { ...body, idempotency_key: key('t-export'), action: 'order.created' });
  assert.ok(filtered.json.receipt.row_count < receipt.row_count && filtered.json.receipt.row_count > 0);
  assert.equal((await post('/api/export', 'business_owner_b1', { ...body, action: 'order.created' })).status, 409, 'same key, different filter');

  const ok = await post('/api/export/verify', 'business_owner_b1', { export_receipt_id: receipt.export_receipt_id, csv });
  assert.equal(ok.status, 200);
  assert.equal(ok.json.ok, true);
  const altered = await post('/api/export/verify', 'business_owner_b1', { export_receipt_id: receipt.export_receipt_id, csv: `${csv}x` });
  assert.equal(altered.status, 422);
  assert.equal(altered.json.error, 'integrity_check_failed');
  // a foreign identity cannot verify (or even confirm the existence of) the receipt
  const foreign = await post('/api/export/verify', 'tenant_owner_t2', { export_receipt_id: receipt.export_receipt_id, csv });
  assert.equal(foreign.status, 422);
  const hist = (await get('/api/export', 'business_owner_b1')).json;
  assert.ok(hist.receipts.some((r) => r.export_receipt_id === receipt.export_receipt_id));
});

test('story A: site-only, investor, revoked, support, unrelated and T2 identities get 403 and learn no counts', async () => {
  const denied = ['staff_s1', 'investor_b1', 'revoked_b1', 'tenant_owner_t2', 'support_operator', 'business_owner_b2'];
  const bodies = new Set();
  for (const who of denied) {
    for (const path of ['/api/audit', '/api/audit/verify', '/api/signals', '/api/readiness', '/api/incidents', '/api/trace', '/api/grants/diff', '/api/export']) {
      const r = await get(path, who);
      assert.equal(r.status, 403, `${who} ${path}`);
      assert.equal(r.json.error, 'scope_denied');
      assert.ok(!('total_count' in r.json) && !('filtered_count' in r.json) && !('events' in r.json));
      bodies.add(`${r.json.error}|${r.json.message}`);
    }
    const ex = await post('/api/export', who, { ...sc(), idempotency_key: key('t-deny') });
    assert.equal(ex.status, 403, who);
    assert.ok(!('csv' in ex.json));
  }
  assert.equal(bodies.size, 1, 'one generic denial body for every denied identity and endpoint (no existence leak)');
  // a business that does not exist is indistinguishable from a foreign one
  const ghost = await get('/api/audit', 'business_owner_b1', sc(T1, 'b1000000-0000-4000-8000-0000000000aa'));
  const foreignB3 = await get('/api/audit', 'business_owner_b1', sc(T2, B3));
  assert.equal(ghost.status, 403); assert.equal(foreignB3.status, 403);
  assert.deepEqual({ ...ghost.json, request_id: 0 }, { ...foreignB3.json, request_id: 0 });
  // the other tenant's owner cannot read business A, and business A's owner cannot read business B
  assert.equal((await get('/api/audit', 'business_owner_b1', sc(T1, B2))).status, 403);
  assert.equal((await get('/api/audit', 'business_owner_b2', sc(T1, B2))).status, 200);
});

test('forged actor/role/tenant/service-role in body, query or headers is rejected 400 and writes nothing', async () => {
  const total = await auditTotal();
  const events = nonGovCount();
  for (const extra of [{ actor_id: '1d000000-0000-4000-8000-000000000002' }, { actor: 'business_owner_b1' }, { role: 'business_owner' }, { tenant_role: 'owner' },
    { service_role: true }, { is_admin: true }, { claims: { sub: 'x' } }, { tenant: 'Tenant One' }, { business_name: 'Business A' }]) {
    const r = await post('/api/audit/append', 'staff_s1', appendBody(extra));
    assert.equal(r.status, 400, JSON.stringify(extra));
    assert.equal(r.json.error, 'bad_request');
  }
  const nested = await post('/api/audit/append', 'staff_s1', appendBody({ payload: { status: 'new', role: 'owner' } }));
  assert.equal(nested.status, 400);
  const unknown = await post('/api/audit/append', 'staff_s1', appendBody({ surprise: 1 }));
  assert.equal(unknown.status, 400);
  for (const h of [{ 'x-actor-id': '1d000000-0000-4000-8000-000000000002' }, { 'x-role': 'business_owner' }, { 'x-service-role': '1' }, { authorization: 'Bearer abc' }, { 'x-tenant-id': T1 }]) {
    const r = await call(`/api/audit?${qs(sc())}`, 'staff_s1', { headers: h });
    assert.equal(r.status, 400, JSON.stringify(h));
  }
  assert.equal((await call(`/api/audit?${qs({ ...sc(), actor: 'x' })}`, 'business_owner_b1')).status, 400);
  assert.equal((await call(`/api/audit?${qs({ ...sc(), role: 'owner' })}`, 'business_owner_b1')).status, 400);
  assert.equal(await auditTotal(), total);
  assert.equal(nonGovCount(), events);
  // a forged header can never upgrade a low identity: staff still cannot read
  assert.equal((await call(`/api/audit?${qs(sc())}`, 'staff_s1', { headers: { 'x-demo-identity': 'staff_s1' } })).status, 403);
  // a secret-looking payload value is refused (422) and not stored
  const secret = await post('/api/audit/append', 'business_owner_b1', appendBody({ site_id: undefined, payload: { item_ref: 'password=hunter2' } }));
  assert.equal(secret.status, 422);
  assert.equal(await auditTotal(), total);
});

// =================================================================================== Story B
test('story B: detect raises advisory signals linked to original evidence; nothing else changes', async () => {
  const fp = protectedFingerprint();
  const events = nonGovCount();
  const d = await post('/api/signals/detect', 'business_owner_b1', sc());
  assert.equal(d.status, 200, d.text);
  assert.ok(d.json.created >= 3);
  const again = await post('/api/signals/detect', 'business_owner_b1', sc());
  assert.equal(again.json.created, 0, 'detection is idempotent per signal key');
  const list = (await get('/api/signals', 'business_owner_b1')).json;
  assert.match(list.advisory_notice, /ADVISORY ONLY/);
  const rules = new Set(list.signals.map((s) => s.rule_id));
  for (const r of ['dup_content', 'stale_source', 'dup_key']) assert.ok(rules.has(r), `rule ${r} fired`);
  for (const s of list.signals) {
    assert.equal(s.disposition, 'advisory_review_only');
    assert.match(s.reason, /advisory/i);
    assert.doesNotMatch(s.reason, /fraud|theft|steal|criminal|guilty/i);
    assert.ok(s.evidence.length > 0 && s.evidence.some((e) => e.event_id || e.log_id));
    assert.equal(s.status, 'open');
  }
  const dup = list.signals.find((s) => s.rule_id === 'dup_content');
  assert.ok(dup.evidence.length >= 3 && dup.evidence.every((e) => /^[0-9a-f]{64}$/.test(e.event_digest) && e.stream_seq > 0), 'links to the original evidence events');
  assert.deepEqual(dup.evidence_actor_labels, ['staff_s1']);
  assert.equal(nonGovCount(), events, 'detection wrote no business event');
  assert.deepEqual(protectedFingerprint(), fp, 'stock / money / approvals / roles untouched');
  // foreign and low identities cannot detect or list
  for (const who of ['staff_s1', 'investor_b1', 'tenant_owner_t2']) {
    assert.equal((await post('/api/signals/detect', who, sc())).status, 403);
  }
});

test('story B: independent owner dismisses with a reason; a second reviewer gets 409; one terminal state per signal', async () => {
  const fp = protectedFingerprint();
  const events = nonGovCount();
  const list = (await get('/api/signals', 'business_owner_b1')).json.signals;
  const sig = list.find((s) => s.rule_id === 'dup_content');
  const rid = `/api/signals/${sig.signal_id}/review`;
  for (const who of ['staff_s1', 'investor_b1', 'revoked_b1', 'tenant_owner_t2', 'support_operator']) {
    const r = await post(rid, who, { decision: 'dismiss', reason_code: 'duplicate_signal', idempotency_key: key('t-rev') });
    assert.equal(r.status, 403, who);
  }
  assert.equal((await post(rid, 'business_owner_b1', { decision: 'dismiss', reason_code: 'followup_required', idempotency_key: key('t-rev') })).status, 422, 'reason must fit the decision');
  assert.equal((await post(rid, 'business_owner_b1', { decision: 'dismiss', reason_code: 'duplicate_signal' })).status, 400, 'idempotency key required');
  assert.equal((await post(rid, 'business_owner_b1', { decision: 'dismiss', reason_code: 'duplicate_signal', idempotency_key: key('t-rev'), reviewer_id: 'x' })).status, 400, 'reviewer is never caller-supplied');
  const k1 = key('t-rev');
  const ok = await post(rid, 'business_owner_b1', { decision: 'dismiss', reason_code: 'duplicate_signal', idempotency_key: k1 });
  assert.equal(ok.status, 201, ok.text);
  assert.match(ok.json.advisory_notice, /no stock, money, approval or role/i);
  const replay = await post(rid, 'business_owner_b1', { decision: 'dismiss', reason_code: 'duplicate_signal', idempotency_key: k1 });
  assert.equal(replay.status, 200); assert.equal(replay.json.receipt_id, ok.json.receipt_id);
  const second = await post(rid, 'business_owner_b1_second', { decision: 'acknowledge', reason_code: 'known_issue', idempotency_key: key('t-rev') });
  assert.equal(second.status, 409);
  assert.equal((await post(rid, 'business_owner_b1', { decision: 'acknowledge', reason_code: 'known_issue', idempotency_key: key('t-rev') })).status, 409);
  const after = (await get('/api/signals', 'tenant_owner_t1')).json.signals.find((s) => s.signal_id === sig.signal_id);
  assert.equal(after.status, 'dismissed');
  assert.equal(after.reviewer_id_label, 'business_owner_b1');
  assert.equal(after.review_reason_code, 'duplicate_signal');
  assert.equal(nonGovCount(), events);
  assert.deepEqual(protectedFingerprint(), fp);
  assert.equal((await get('/api/audit/verify', 'business_owner_b1')).json.ok, true, 'append-only history intact');
});

test('story B: two reviewers racing on one signal produce exactly one terminal state', async () => {
  const sig = (await get('/api/signals', 'business_owner_b1')).json.signals.find((s) => s.status === 'open');
  assert.ok(sig, 'an open signal remains');
  const rid = `/api/signals/${sig.signal_id}/review`;
  const rs = await Promise.all([
    post(rid, 'business_owner_b1', { decision: 'dismiss', reason_code: 'expected_activity', idempotency_key: key('t-race') }),
    post(rid, 'business_owner_b1_second', { decision: 'acknowledge', reason_code: 'under_investigation', idempotency_key: key('t-race') }),
    post(rid, 'tenant_owner_t1', { decision: 'dismiss', reason_code: 'accepted_risk', idempotency_key: key('t-race') })]);
  assert.equal(rs.filter((r) => r.status === 201).length, 1, rs.map((r) => r.status).join());
  assert.equal(rs.filter((r) => r.status === 409).length, 2);
});

// =================================================================================== Story C
test('story C: readiness shows not certified / stale CI / staging missing / deployment unverified; synthetic proof never reaches signed or release', async () => {
  const r = (await get('/api/readiness', 'business_owner_b1')).json;
  assert.deepEqual(r.levels.slice(-1), ['released']);
  const stale = r.features.find((f) => f.feature_id === 'storyc.export-provenance').readiness;
  for (const text of ['not certified', 'stale CI', 'staging missing', 'deployment unverified']) assert.ok(stale.text.includes(text), text);
  assert.equal(stale.certified, false);
  assert.equal(stale.state, 'proposed');
  assert.match(stale.current_head_sha, /^9f8e7d6c/);
  assert.ok(stale.stale.length >= 1 && stale.stale.every((s) => s.commit_sha.startsWith('3d1c5a9e')), 'green CI is bound to the OLD sha');
  const sim = r.features.find((f) => f.feature_id === 'storyc.simulated-green').readiness;
  assert.equal(sim.state, 'isolated_test_pass');
  assert.ok(sim.text.includes('simulation only'));
  for (const lv of ['signed_stage_verified', 'integrated_verified', 'deployed_verified', 'released']) {
    assert.ok(!sim.satisfied_levels.includes(lv), `synthetic green must not satisfy ${lv}`);
    assert.ok(sim.missing_proofs.includes(lv));
  }
  assert.ok(r.features.every((f) => f.readiness.certified === false));
  assert.ok(r.proofs.every((p) => p.simulated === true));
  assert.match(r.notice, /never satisfy signed-session, integration, deployment or release/);
});

test('story C: incident evidence survives an attempted purge while a hold is active', async () => {
  const before = (await get('/api/incidents', 'business_owner_b1')).json;
  assert.equal(before.cases.length, 1);
  assert.equal(before.evidence.length, 2);
  assert.equal(before.manifests['INC-DEMO-0001'].ok, true);
  assert.ok(before.holds[0].in_force);
  const req = { ...sc(), evidence_ref: 'EV-LOG-0001', reason_code: 'retention_expiry' };
  const p1 = await post('/api/incidents/INC-DEMO-0001/purge-attempt', 'business_owner_b1', { ...req, idempotency_key: key('t-purge') });
  assert.equal(p1.status, 409, p1.text);
  assert.equal(p1.json.outcome, 'refused');
  assert.equal(p1.json.code, 'G3H02');
  assert.ok(p1.json.protection.includes('hold_active'));
  assert.ok(p1.json.audit_receipt_id, 'the refusal is itself receipted');
  const p2 = await post('/api/incidents/INC-DEMO-0001/purge-attempt', 'business_owner_b1_second', { ...req, evidence_ref: 'EV-CSV-0001', idempotency_key: key('t-purge') });
  assert.equal(p2.status, 409);
  const afterInc = (await get('/api/incidents', 'business_owner_b1')).json;
  assert.equal(afterInc.evidence.length, 2);
  assert.ok(afterInc.evidence.every((e) => e.purged === false));
  assert.deepEqual(afterInc.manifests['INC-DEMO-0001'], before.manifests['INC-DEMO-0001']);
  assert.match(afterInc.notice, /not a legal-hold certification/);
  for (const who of ['staff_s1', 'investor_b1', 'tenant_owner_t2', 'support_operator', 'business_owner_b2']) {
    assert.equal((await post('/api/incidents/INC-DEMO-0001/purge-attempt', who, { ...req, idempotency_key: key('t-purge') })).status, 403, who);
  }
  assert.equal((await post('/api/incidents/NOPE-0001/purge-attempt', 'business_owner_b1', { ...req, idempotency_key: key('t-purge') })).status, 403, 'unknown case is indistinguishable from foreign');
});

test('requirement trace shows a valid and an invalid snapshot (orphan/missing proof is caught, never silently fixed)', async () => {
  const tr = (await get('/api/trace', 'business_owner_b1')).json;
  assert.equal(tr.snapshots.length, 2);
  assert.ok(tr.snapshots.some((s) => s.verdict === 'valid' && s.violations.length === 0));
  const invalid = tr.snapshots.find((s) => s.verdict === 'invalid');
  assert.ok(invalid.violations.some((v) => v.code === 'passing_test_without_exact_sha'));
});

test('grant review: diff against the stored baseline is advisory, read-only, owner-only and never changes a permission', async () => {
  const hasPriv = () => one(DB, "select has_table_privilege('c10g3_app', 'c10_gov003_demo.v_audit_events', 'select') as p").p;
  assert.equal(hasPriv(), true, 'the deliberate demo drift exists');
  const g = (await get('/api/grants/diff', 'business_owner_b1')).json;
  assert.equal(g.baselines.length, 1);
  assert.match(g.notice, /never runs GRANT, REVOKE or ALTER/);
  const d = await post('/api/grants/diff', 'business_owner_b1', { ...sc(), idempotency_key: key('t-diff') });
  assert.equal(d.status, 201, d.text);
  assert.ok(d.json.finding_count >= 1);
  assert.equal(d.json.max_severity, 'high');
  assert.match(d.json.advisory_notice, /No permission was changed/);
  const after = (await get('/api/grants/diff', 'business_owner_b1')).json;
  assert.equal(after.diffs[0].label, 'ADVISORY');
  assert.ok(after.diffs[0].diff.findings.some((f) => f.key.includes('c10g3_app') && f.severity === 'high'));
  assert.equal(hasPriv(), true, 'the drift was reported, not auto-revoked');
  for (const who of ['staff_s1', 'investor_b1', 'tenant_owner_t2', 'support_operator']) {
    for (const path of ['/api/grants/diff', '/api/grants/snapshot', '/api/grants/baseline']) {
      assert.equal((await post(path, who, { ...sc(), idempotency_key: key('t-g') })).status, 403, `${who} ${path}`);
    }
  }
  // a caller-supplied baseline is ignored: the diff only ever compares against the stored baseline
  const ignored = await post('/api/grants/diff', 'business_owner_b1', { ...sc(), baseline: { functions: [] }, idempotency_key: key('t-g') });
  assert.equal(ignored.status, 201);
  assert.ok(ignored.json.finding_count >= 1);
});

test('safe error demo: the synthetic secret-laden error is scrubbed; no planted secret reaches the response or the database', async () => {
  const r = await post('/api/errors/demo', 'staff_s1', { ...sc(), site_id: S1 });
  assert.equal(r.status, 201, r.text);
  assert.equal(r.json.raw_text_returned, false);
  assert.equal(r.json.projection.error_code, 'INTERNAL');
  assert.equal(r.json.projection.public_message, 'An internal error occurred.');
  assert.match(r.json.projection.scrubbed_detail, /\[redacted/);
  const planted = ['hunter2', 'Pa55w0rd', 'ops.demo@', '4111111111111111', 'eyJ', '/srv/app', 'db.internal'];
  for (const p of planted) assert.ok(!r.text.includes(p), `response leaks ${p}`);
  assert.doesNotMatch(r.text, /bearer\s+[A-Za-z0-9]/i);
  const stored = JSON.stringify(one(DB, 'select jsonb_agg(to_jsonb(s)) as a from c10_gov003_demo.safe_errors s').a);
  for (const p of planted) assert.ok(!stored.includes(p), `database stores ${p}`);
  // scoped visibility: the owner sees it; investor and support (no grant) get a generic denial
  const list = (await get('/api/errors', 'business_owner_b1')).json;
  assert.ok(list.errors.length >= 1);
  assert.equal((await get('/api/errors', 'investor_b1')).status, 403);
  assert.equal((await get('/api/errors', 'support_operator')).status, 403, 'support is not automatically granted business diagnostics');
  assert.equal((await get('/api/errors', 'tenant_owner_t2')).status, 403);
  assert.equal((await post('/api/errors/demo', 'investor_b1', { ...sc() })).status, 403);
});

test('every response (success, denial, error, 404) carries the strict security headers and the demo-mode header', async () => {
  const { assertStrictCsp } = await import('../../../internal/gov003/server/csp.mjs');
  const samples = [await call('/api/me', 'business_owner_b1'), await get('/api/audit', 'staff_s1'), await call('/api/nope', 'business_owner_b1'),
    await call('/api/audit', 'business_owner_b1'), await call('/api/me', 'not_a_label')];
  assert.deepEqual(samples.map((s) => s.status), [200, 403, 404, 400, 401]);
  for (const s of samples) {
    assert.equal(s.headers.get('x-demo-mode'), 'DEMO / NOT LIVE');
    const csp = s.headers.get('content-security-policy');
    assert.ok(assertStrictCsp(csp));
    assert.doesNotMatch(csp, /unsafe-inline|unsafe-eval/);
    assert.equal(s.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(s.headers.get('x-frame-options'), 'DENY');
    assert.equal(s.headers.get('cache-control'), 'no-store');
    assert.match(s.headers.get('content-type'), /application\/json/);
  }
  // DNS-rebinding guard: a non-loopback Host header is refused (fetch cannot set Host, so use node:http)
  const wrong = await new Promise((resolve, reject) => {
    const rq = http.request({ host: '127.0.0.1', port: srv.port, path: '/api/me', headers: { host: 'evil.example', 'x-demo-identity': 'business_owner_b1' } }, (res) => {
      let b = ''; res.on('data', (c) => { b += c; }); res.on('end', () => resolve({ status: res.statusCode, body: b }));
    });
    rq.on('error', reject); rq.end();
  });
  assert.equal(wrong.status, 403);
  assert.doesNotMatch(wrong.body, /events|targets/);
});

// =================================================================================== optional browser run
const CHROME = ['chromium', 'chromium-browser', 'google-chrome', 'google-chrome-stable'].map((b) => spawnSync('which', [b], { encoding: 'utf8' }).stdout.trim()).find(Boolean);
// NOTE: Chrome must be spawned ASYNCHRONOUSLY: the API server lives in this process, a blocking spawnSync would starve it.
function run(bin, args, timeoutMs = 90000) {
  return new Promise((resolve) => {
    const ch = spawn(bin, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = ''; let err = '';
    ch.stdout.on('data', (c) => { out += c; if (out.length > 32e6) ch.kill(); });
    ch.stderr.on('data', (c) => { err += c; if (err.length > 1e6) err = err.slice(-1e5); });
    const timer = setTimeout(() => ch.kill('SIGKILL'), timeoutMs);
    ch.on('close', (status) => { clearTimeout(timer); resolve({ status, out, err }); });
    ch.on('error', (e) => { clearTimeout(timer); resolve({ status: -1, out, err: String(e) }); });
  });
}
test('browser (optional): headless Chrome renders the real UI at 390 and 1440 px from live API data', { skip: CHROME ? false : 'no chromium/chrome binary on this machine' }, async () => {
  const dir = mkdtempSync(join(tmpdir(), 'g3-shot-'));
  try {
    for (const [w, hgt] of [[390, 1400], [1440, 1000]]) {
      const file = join(dir, `shot-${w}.png`);
      const base = ['--headless=new', '--no-sandbox', '--disable-gpu', '--hide-scrollbars', `--user-data-dir=${join(dir, `p${w}`)}`, `--window-size=${w},${hgt}`, '--virtual-time-budget=8000'];
      const url = `${srv.url}/?lang=en&view=audit&as=business_owner_b1`;
      const shot = await run(CHROME, [...base, `--screenshot=${file}`, url]);
      assert.equal(shot.status, 0, shot.err.slice(-500));
      const png = readFileSync(file);
      assert.equal(png.subarray(1, 4).toString('latin1'), 'PNG');
      assert.ok(png.length > 8000, `screenshot ${w}px is not blank (${png.length} bytes)`);
      const dom = await run(CHROME, [...base, '--dump-dom', url]);
      assert.match(dom.out, /DEMO \/ NOT LIVE/);
      assert.match(dom.out, /class="entry/, 'journal rows were rendered from the live API');
      assert.doesNotMatch(dom.out, /Access denied/);
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
