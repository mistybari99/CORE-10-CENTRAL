// Features 01 canonical-audit-event, 02 append-only-history, 03 idempotency-evidence, 04 scope-safe-observability.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, dropDb, rows, one, exec, execAsync, adminExec, lit } from '../lib/db.mjs';
import { T1, T2, B1, B2, B3, S1, S2, S3, S4, LE1, U } from '../lib/ids.mjs';

const DB = 'g3_f01_f04_core';
const be = (sub) => ({ role: 'c10g3_backend', sub });
const rd = (sub) => ({ role: 'c10g3_reader', sub });
let n = 0;
const key = (p = 'k') => `${p}-${String(++n).padStart(6, '0')}`;
const append = (sub, o = {}) => {
  const a = { t: T1, b: B1, s: S1, le: null, dom: 'stock', sid: 'sku-1', ver: 'v1', act: 'stock.adjust', corr: 'corr-1',
    idem: key('idem'), payload: { item_ref: 'sku-1', quantity_milli: '5000' }, sha: null, reason: 'inventory', claimed: null, ...o };
  const u = (x) => (x === null ? 'null' : lit(x));
  return one(DB, `select * from c10_gov003_demo.append_event(${u(a.t)}, ${u(a.b)}, ${u(a.s)}, ${u(a.le)}, ${lit(a.dom)}, ${lit(a.sid)}, ${lit(a.ver)}, ${lit(a.act)}, now(), ${lit(a.corr)}, ${lit(a.idem)}, ${lit(JSON.stringify(a.payload))}::jsonb, ${u(a.sha)}, ${lit(a.reason)}, ${u(a.claimed)}::uuid, null)`, be(sub));
};
const code = (fn) => { try { fn(); } catch (e) { return e.code; } return null; };

before(() => { freshDb(DB, { only: ['000', '010', '020', '030', '040'] }); });
after(() => dropDb(DB));

// ---------------------------------------------------------------- 01
test('f01 positive: event records who/what/when/why/scope/source-version/correlation with a receipt', () => {
  const r = append(U.staffS1, { idem: 'idem-f01-pos-0001', corr: 'corr-f01' });
  assert.equal(r.outcome, 'created'); assert.equal(r.replayed, false); assert.ok(r.receipt_id); assert.equal(r.stream_seq, 1);
  const e = one(DB, `select * from c10_gov003_demo.v_audit_events where event_id = '${r.event_id}'`, rd(U.bizOwnerB1));
  assert.equal(e.actor_id, U.staffS1); assert.equal(e.source_version, 'v1'); assert.equal(e.reason_category, 'inventory');
  assert.equal(e.correlation_id, 'corr-f01'); assert.equal(e.business_id, B1); assert.equal(e.site_id, S1); assert.equal(e.schema_version, 1);
  assert.match(e.payload_sha256, /^[0-9a-f]{64}$/); assert.ok(e.event_time && e.ingest_time);
});
test('f01 negative: forged client actor is rejected (server derives actor)', () => {
  assert.equal(code(() => append(U.staffS1, { claimed: U.tenantOwnerT1 })), 'G3A01');
  assert.equal(append(U.staffS1, { claimed: U.staffS1 }).outcome, 'created'); // matching claim is harmless, ignored for authority
});
test('f01 negative: missing, unknown and foreign business/site scope', () => {
  assert.equal(code(() => append(U.staffS1, { s: S3 })), 'G3A02');            // site of another business
  assert.equal(code(() => append(U.staffS1, { b: B2, s: S3 })), 'G3A02');      // business outside membership
  assert.equal(code(() => append(U.staffS1, { s: S2 })), 'G3A02');             // site-scoped staff on a different site
  assert.equal(code(() => append(U.staffS1, { s: null })), 'G3A02');           // site-scoped staff cannot write business level
  assert.equal(code(() => append(U.t2Owner, { t: T1 })), 'G3A02');             // foreign tenant
  assert.equal(code(() => append(U.tenantOwnerT1, { t: T2, b: B3, s: S4 })), 'G3A02');
  assert.equal(code(() => append(U.tenantOwnerT1, { t: T1, b: B3, s: S4 })), 'G3A02'); // business of other tenant
  assert.equal(code(() => append(U.tenantOwnerT1, { b: '00000000-0000-4000-8000-000000000000' })), 'G3A02');
  assert.equal(code(() => append(U.investorB1)), 'G3A02');
  assert.equal(code(() => append(U.revokedB1, { s: null })), 'G3A02');
  assert.equal(code(() => append(U.support, { s: null })), 'G3A02');
});
test('f01 negative: unauthenticated or unknown identity fails closed', () => {
  assert.throws(() => exec(DB, `select * from c10_gov003_demo.append_event('${T1}','${B1}','${S1}',null,'stock','sku-1','v1','stock.adjust',now(),'c','idem-noauth-1','{"item_ref":"a"}'::jsonb,null,'inventory')`, { role: 'c10g3_backend' }), /G3A05/);
  assert.equal(code(() => append(U.unknown)), 'G3A05');
});
test('f01 same-scope FK: legal entity must belong to the business', () => {
  assert.equal(append(U.bizOwnerB1, { le: LE1, s: null }).outcome, 'created');
  assert.equal(code(() => append(U.bizOwnerB2, { b: B2, s: null, le: LE1 })), 'G3A02');
});
test('f01 payload allowlist: unknown field, secret, PII, card, stack trace and non-string numbers are rejected', () => {
  const bad = [
    { password: 'x' }, { item_ref: 'sku-1', jwt: 'abc' }, { reason_code: 'ok', note_code: 'Bearer abc123' },
    { entity_ref: 'a@b.com' }, { entity_ref: '4111111111111111' }, { entity_ref: '01712345678' },
    { item_ref: 'eyJhbGciOiJIUzI1NiJ9.abc.def' }, { quantity_milli: 5 }, { quantity_milli: '5.5' },
    { item_ref: 'x'.repeat(200) }, { status: 'Has Space' }, { window_start: 'yesterday' }, { amount_minor: '12.50' },
  ];
  for (const p of bad) assert.equal(code(() => append(U.staffS1, { payload: p })), 'G3A03', JSON.stringify(p));
  assert.equal(code(() => append(U.staffS1, { payload: [] })), 'G3A03');
});
test('f01 decimals travel as exact strings and times as UTC ISO', () => {
  const r = append(U.staffS1, { payload: { amount_minor: '123456789012345678', currency: 'bdt', window_start: '2026-11-12T10:00:00.123456Z' } });
  assert.equal(r.outcome, 'created');
});

// ---------------------------------------------------------------- 02
test('f02 negative: ordinary principals cannot INSERT/UPDATE/DELETE/TRUNCATE audit history', () => {
  for (const role of ['c10g3_backend', 'c10g3_reader', 'c10g3_app']) {
    for (const stmt of [
      `insert into c10_gov003_demo.audit_events (event_id) values (gen_random_uuid())`,
      `update c10_gov003_demo.audit_events set action = 'x'`, `delete from c10_gov003_demo.audit_events`,
      `truncate c10_gov003_demo.audit_events`, `delete from c10_gov003_demo.audit_receipts`,
      `update c10_gov003_demo.audit_chain_heads set last_seq = 0`,
    ]) assert.equal(code(() => exec(DB, stmt, { role, sub: U.bizOwnerB1 })), '42501', `${role}: ${stmt}`);
  }
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.audit_events`, { role: 'c10g3_app', sub: U.bizOwnerB1 })), '42501');
});
test('f02 negative: owner-role bypass attempts are blocked by append-only triggers', () => {
  const o = { role: 'c10g3_owner' };
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.audit_events set action = 'x'`, o)), 'G3H01');
  assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.audit_events`, o)), 'G3H01');
  assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.audit_receipts`, o)), 'G3H01');
  // TRUNCATE is refused either by the append-only trigger or earlier by the receipts foreign key: blocked both ways.
  assert.ok(['G3H01', '0A000'].includes(code(() => exec(DB, `truncate c10_gov003_demo.audit_events`, o))));
  assert.ok(['G3H01', '0A000'].includes(code(() => exec(DB, `truncate c10_gov003_demo.audit_events, c10_gov003_demo.audit_receipts`, o))));
  assert.equal(code(() => exec(DB, `insert into c10_gov003_demo.audit_events select * from c10_gov003_demo.audit_events limit 1`, o)), 'G3H01');
});
test('f02 RPC grants: only the backend role may append; direct and public execution is refused', () => {
  const call = (role) => exec(DB, `select * from c10_gov003_demo.append_event('${T1}','${B1}','${S1}',null,'stock','sku-1','v1','stock.adjust',now(),'c','idem-grant-${role}','{"item_ref":"a"}'::jsonb,null,'inventory')`, { role, sub: U.staffS1 });
  assert.equal(code(() => call('c10g3_reader')), '42501');
  assert.equal(code(() => call('c10g3_app')), '42501');
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo._append_audit('${T1}','${B1}',null,null,'a','b','v1','x.y',now(),'c','idem-internal-1','{}'::jsonb,null,'other',1,null,null)`, be(U.bizOwnerB1))), '42501');
});
test('f02 hash chain: sequence, prior digest and receipts verify; ordering is gapless', () => {
  const v = one(DB, `select * from c10_gov003_demo.verify_chain('${T1}','${B1}')`, be(U.bizOwnerB1));
  assert.equal(v.ok, true, JSON.stringify(v)); assert.ok(v.checked >= 3);
  const seqs = rows(DB, `select stream_seq from c10_gov003_demo.v_audit_events order by stream_seq`, rd(U.bizOwnerB1)).map((r) => r.stream_seq);
  assert.deepEqual(seqs, seqs.map((_, i) => i + 1));
});
test('f02 stated limitation: a privileged superuser CAN rewrite storage, but verify_chain DETECTS it', () => {
  const t = 'g3_f02_tamper';
  freshDb(t, { only: ['000', '010', '020', '030'] });
  try {
    const q = (sub, e) => one(t, `select * from c10_gov003_demo.append_event('${T1}','${B1}','${S1}',null,'stock','sku-1','v1','stock.adjust',now(),'c','${e}','{"item_ref":"a"}'::jsonb,null,'inventory')`, be(sub));
    q(U.staffS1, 'idem-tamper-0001'); q(U.staffS1, 'idem-tamper-0002');
    assert.equal(one(t, `select ok from c10_gov003_demo.verify_chain('${T1}','${B1}')`, be(U.bizOwnerB1)).ok, true);
    // Privileged maintenance outside the product guardrails (what a DBA could do). NOT preventable inside the database.
    exec(t, `alter table c10_gov003_demo.audit_events disable trigger g3_no_update_delete;
             update c10_gov003_demo.audit_events set payload = '{"item_ref":"forged"}' where stream_seq = 1;
             alter table c10_gov003_demo.audit_events enable trigger g3_no_update_delete;`);
    const v = one(t, `select * from c10_gov003_demo.verify_chain('${T1}','${B1}')`, be(U.bizOwnerB1));
    assert.equal(v.ok, false); assert.equal(v.first_bad_seq, 1); assert.equal(v.reason, 'payload_hash_mismatch');
  } finally { dropDb(t); }
});

// ---------------------------------------------------------------- 03
test('f03 replay: same key + exact same payload returns the original receipt and appends nothing', () => {
  const k = 'idem-f03-replay-1';
  const a = append(U.staffS1, { idem: k });
  const before = one(DB, `select count(*)::int c from c10_gov003_demo.audit_events`, { role: 'c10g3_owner' }).c;
  const b = append(U.staffS1, { idem: k });
  assert.equal(b.replayed, true); assert.equal(b.outcome, 'replayed');
  for (const f of ['receipt_id', 'event_id', 'event_digest', 'receipt_digest', 'stream_seq']) assert.equal(b[f], a[f]);
  assert.equal(one(DB, `select count(*)::int c from c10_gov003_demo.audit_events`, { role: 'c10g3_owner' }).c, before);
});
test('f03 replay is insensitive to JSON key order (canonical payload digest)', () => {
  const k = 'idem-f03-order-01';
  const a = append(U.staffS1, { idem: k, payload: { item_ref: 'sku-9', quantity_milli: '1000' } });
  const b = append(U.staffS1, { idem: k, payload: { quantity_milli: '1000', item_ref: 'sku-9' } });
  assert.equal(b.replayed, true); assert.equal(b.receipt_id, a.receipt_id);
});
test('f03 negative: same key + changed payload / command conflicts (G3C01)', () => {
  const k = 'idem-f03-conf-001';
  append(U.staffS1, { idem: k });
  assert.equal(code(() => append(U.staffS1, { idem: k, payload: { item_ref: 'sku-1', quantity_milli: '5001' } })), 'G3C01');
  assert.equal(code(() => append(U.staffS1, { idem: k, act: 'stock.remove' })), 'G3C01');
  assert.equal(code(() => append(U.staffS1, { idem: k, sid: 'sku-2' })), 'G3C01');
});
test('f03 negative: receipt mismatch (supplied digest differs from canonical payload) is rejected', () => {
  assert.equal(code(() => append(U.staffS1, { sha: 'f'.repeat(64) })), 'G3A04');
});
test('f03 idempotency keys are scoped per business (same key in another business is independent)', () => {
  const a = append(U.bizOwnerB1, { idem: 'idem-f03-scope-01', s: null });
  const b = append(U.bizOwnerB2, { idem: 'idem-f03-scope-01', b: B2, s: null });
  assert.notEqual(a.event_id, b.event_id); assert.equal(b.stream_seq, 1);
});
test('f03 REAL concurrency: two independent PostgreSQL sessions race on one key -> exactly one stored result', async () => {
  const k = 'idem-f03-race-0001';
  const sql = (hold) => `begin;
    select outcome, event_id, receipt_id, replayed from c10_gov003_demo.append_event('${T1}','${B2}',null,null,'stock','sku-race','v1','stock.adjust',now(),'corr-race','${k}','{"item_ref":"sku-race","quantity_milli":"7000"}'::jsonb,null,'inventory');
    ${hold ? 'select pg_sleep(1.2);' : ''}
    commit;`;
  const ctx = be(U.bizOwnerB2);
  const slow = execAsync(DB, sql(true), ctx);
  await new Promise((r) => setTimeout(r, 300));            // second backend starts while the first still holds its lock
  const fast = execAsync(DB, sql(false), ctx);
  const [a, b] = await Promise.all([slow, fast]);
  assert.ok(a.ok && b.ok, JSON.stringify([a.error?.message, b.error?.message]));
  const parse = (o) => o.out.trim().split('\n')[0].split('|');
  const ra = parse(a), rb = parse(b);
  assert.deepEqual([ra[0], rb[0]].sort(), ['created', 'replayed']);
  assert.equal(ra[2], rb[2], 'both sessions must see the same receipt id');
  assert.equal(one(DB, `select count(*)::int c from c10_gov003_demo.v_audit_events where idempotency_key = '${k}'`, rd(U.bizOwnerB2)).c, 1);
});
test('f03 REAL concurrency: parallel distinct keys keep a gapless, verifiable chain', async () => {
  const jobs = Array.from({ length: 6 }, (_, i) => execAsync(DB, `select * from c10_gov003_demo.append_event('${T1}','${B2}',null,null,'stock','sku-p${i}','v1','stock.adjust',now(),'corr-par','idem-par-chain-${i}','{"item_ref":"sku-p${i}"}'::jsonb,null,'inventory')`, be(U.bizOwnerB2)));
  const res = await Promise.all(jobs);
  assert.ok(res.every((r) => r.ok), JSON.stringify(res.map((r) => r.error?.message)));
  const v = one(DB, `select * from c10_gov003_demo.verify_chain('${T1}','${B2}')`, be(U.bizOwnerB2));
  assert.equal(v.ok, true);
});

// ---------------------------------------------------------------- 04
const sErr = (sub, o = {}) => one(DB, `select * from c10_gov003_demo.record_safe_error('${T1}','${B1}','${S1}', ${lit(o.code ?? 'COMMAND_REJECTED')}, ${lit(o.detail ?? 'failed')}, ${lit(JSON.stringify(o.ctx ?? {}))}::jsonb, 'corr-obs')`, be(sub));
test('f04 scrub: tokens, JWT, credentials, URLs, emails, phones and stack frames never reach the projection', () => {
  const detail = `boom Bearer abc.def.ghi password=hunter2 token: sk_live_AAAA postgres://u:pw@db/x user ana@example.com call +8801712345678 key eyJhbGciOiJIUzI1NiJ9.payload.sig
    at Object.run (/srv/app/secret.js:10:5)
    at next (/srv/app/other.js:1:1)`;
  const r = sErr(U.staffS1, { detail });
  for (const leak of ['hunter2', 'sk_live', 'postgres://', 'ana@example.com', '8801712345678', 'eyJhbG', 'abc.def.ghi', '/srv/app', 'secret.js', 'Object.run']) {
    assert.ok(!r.scrubbed_detail.includes(leak), `leaked ${leak}: ${r.scrubbed_detail}`);
  }
  assert.ok(!r.scrubbed_detail.includes('\n'));
  const stored = one(DB, `select to_jsonb(v)::text as t from c10_gov003_demo.v_safe_errors v where error_id = '${r.error_id}'`, rd(U.bizOwnerB1)).t;
  assert.ok(!/hunter2|sk_live|eyJhbG|ana@example/.test(stored));
});
test('f04 history: safe error records are append-only even for the owner role', () => {
  sErr(U.staffS1);
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.safe_errors set public_message = 'x'`, { role: 'c10g3_owner' })), 'G3H01');
  assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.safe_errors`, { role: 'c10g3_owner' })), 'G3H01');
});
test('f04 allowlist: unknown error codes and non-allowlisted context are rejected', () => {
  assert.equal(code(() => sErr(U.staffS1, { code: 'MADE_UP' })), 'G3A03');
  assert.equal(code(() => sErr(U.staffS1, { ctx: { stack: 'x' } })), 'G3A03');
  assert.equal(code(() => sErr(U.staffS1, { ctx: { entity_ref: 'a@b.com' } })), 'G3A03');
});
test('f04 negative: foreign tenant sees no rows and no counts; site staff/investor/revoked see nothing', () => {
  sErr(U.staffS1);
  assert.ok(one(DB, `select count(*)::int c from c10_gov003_demo.v_safe_errors`, rd(U.bizOwnerB1)).c >= 2);
  for (const sub of [U.t2Owner, U.staffS1, U.investorB1, U.revokedB1, U.bizOwnerB2]) {
    assert.equal(one(DB, `select count(*)::int c from c10_gov003_demo.v_safe_errors`, rd(sub)).c, 0, sub);
    assert.equal(one(DB, `select count(*)::int c from c10_gov003_demo.safe_errors`, rd(sub)).c, 0, sub);
  }
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.v_safe_errors`, { role: 'c10g3_app', sub: U.bizOwnerB1 })), '42501');
});
test('f04 negative: writing an error outside scope is denied (no cross-tenant error injection)', () => {
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.record_safe_error('${T1}','${B2}',null,'INTERNAL','x','{}'::jsonb,'c')`, be(U.staffS1))), 'G3A02');
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.record_safe_error('${T2}','${B3}',null,'INTERNAL','x','{}'::jsonb,'c')`, be(U.staffS1))), 'G3A02');
});
test('f04 support operator: no automatic access; scoped, time-boxed, audited grant; overreach denied', () => {
  const sees = (sub) => one(DB, `select count(*)::int c from c10_gov003_demo.v_safe_errors`, rd(sub)).c;
  assert.equal(sees(U.support), 0);                                                         // no automatic cross-business access
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.grant_support_access('${T1}','${B1}','${U.support}', now() + interval '1 day', 'grant-by-staff-01')`, be(U.staffS1))), 'G3A02');
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.grant_support_access('${T1}','${B1}','${U.support}', now() + interval '30 days', 'grant-too-long-01')`, be(U.bizOwnerB1))), '23514'); // max 7 days
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.grant_support_access('${T1}','${B1}','${U.staffS1}', now() + interval '1 day', 'grant-not-support')`, be(U.bizOwnerB1))), 'G3A02');
  const g = one(DB, `select * from c10_gov003_demo.grant_support_access('${T1}','${B1}','${U.support}', now() + interval '1 day', 'grant-support-ok-01')`, be(U.bizOwnerB1));
  assert.ok(g.receipt_id);
  assert.ok(sees(U.support) >= 2);                                                          // sees B1 errors only
  assert.equal(one(DB, `select count(*)::int c from c10_gov003_demo.v_safe_errors where business_id = '${B2}'`, rd(U.support)).c, 0);
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.v_audit_events`, rd(U.support))) , null);
  assert.equal(one(DB, `select count(*)::int c from c10_gov003_demo.v_audit_events`, rd(U.support)).c, 0); // never the audit journal
  exec(DB, `alter table c10_gov003_demo.support_grants disable row level security`, { role: 'c10g3_owner' });
  exec(DB, `update c10_gov003_demo.support_grants set expires_at = clock_timestamp() - interval '1 second', granted_at = clock_timestamp() - interval '1 hour'`, { role: 'c10g3_owner' });
  assert.equal(sees(U.support), 0);                                                         // expired => closed again
});

// ---------------------------------------------------------------- Story A
test('Story A: owner sees filtered journal; site-only, investor, revoked and T2 cannot see or count it', () => {
  const count = (sub) => one(DB, `select count(*)::int c from c10_gov003_demo.v_audit_events where business_id = '${B1}'`, rd(sub)).c;
  const owner = count(U.bizOwnerB1);
  assert.ok(owner >= 8);
  assert.equal(count(U.tenantOwnerT1), owner);
  assert.equal(count(U.bizOwnerB1Second), owner);
  for (const sub of [U.staffS1, U.investorB1, U.revokedB1, U.t2Owner, U.bizOwnerB2, U.support]) assert.equal(count(sub), 0, sub);
  assert.equal(one(DB, `select count(*)::int c from c10_gov003_demo.v_audit_events`, rd(U.t2Owner)).c, 0);
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.verify_chain('${T1}','${B1}')`, be(U.t2Owner))), 'G3A02');
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.verify_chain('${T1}','${B1}')`, be(U.investorB1))), 'G3A02');
});
