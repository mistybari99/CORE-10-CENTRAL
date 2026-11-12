// Feature 05 readiness-states: typed state derived from proof rows, never from a manual boolean.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, dropDb, rows, one, exec, execAsync, lit } from '../lib/db.mjs';
import { T1, T2, B1, B2, S1, U } from '../lib/ids.mjs';

const DB = 'g3_f057_f05';
const ONLY = ['000', '010', '020', '030', '040', '050', '060', '070'];
const BE = (sub) => ({ role: 'c10g3_backend', sub });
const RD = (sub) => ({ role: 'c10g3_reader', sub });
const OWN = { role: 'c10g3_owner' };
const SHA = (c) => c.repeat(40);
const EV = (c) => c.repeat(64);
const SHA1 = 'a1'.repeat(20); const SHA2 = 'b2'.repeat(20); const SHA3 = 'c3'.repeat(20);
const STAFF_BIZ = '1d000000-0000-4000-8000-0000000000a1';
let n = 0;
const key = (p = 'k') => `${p}-f05-${String(++n).padStart(6, '0')}`;
const arg = (v) => (v === null || v === undefined ? 'null' : typeof v === 'boolean' || typeof v === 'number' ? String(v) : lit(v));
const call = (fn, args, sub, ctx = null) => one(DB, `select * from c10_gov003_demo.${fn}(${args.map(arg).join(', ')})`, ctx ?? BE(sub));
const code = (fn) => { try { fn(); } catch (e) { return e.code; } return null; };
const setGate = (g, on) => exec(DB, `update c10_gov003_demo.real_evidence_gates set enabled = ${on} where gate = ${lit(g)}`, OWN);

const feature = (f, sub = U.bizOwnerB1, t = T1, b = B1) => call('register_readiness_feature', [t, b, f, `Title of ${f}`, key('reg')], sub);
const head = (f, sha, sub = U.bizOwnerB1, extra = {}) =>
  call('record_readiness_head', [extra.t ?? T1, extra.b ?? B1, f, sha, extra.idem ?? key('head'), extra.claimed ?? null], sub);
const proof = (f, level, sha, env, o = {}) =>
  call('record_readiness_proof', [o.t ?? T1, o.b ?? B1, f, level, sha, env, o.run ?? 'run-0001', o.sim ?? false,
    o.ev ?? EV('e'), o.outcome ?? 'pass', o.idem ?? key('proof'), o.claimed ?? null], o.sub ?? U.bizOwnerB1);
const derive = (f, sub = U.bizOwnerB1, t = T1, b = B1) => call('derive_readiness', [t, b, f], sub, RD(sub)).derive_readiness;
const counts = () => one(DB, `select (select count(*) from c10_gov003_demo.readiness_features) f,
  (select count(*) from c10_gov003_demo.readiness_heads) h, (select count(*) from c10_gov003_demo.readiness_proofs) p,
  (select count(*) from c10_gov003_demo.audit_events) a`, OWN);

before(() => {
  freshDb(DB, { only: ONLY });
  exec(DB, `insert into c10_gov003_demo.identities values (${lit(STAFF_BIZ)}, 'staff_business_wide');
    insert into c10_gov003_demo.memberships (identity_id, tenant_id, business_id, site_id, role)
      values (${lit(STAFF_BIZ)}, ${lit(T1)}, ${lit(B1)}, null, 'staff');`, OWN);
});
after(() => dropDb(DB));

test('f05 positive: feature registers, head recorded, proofs derive state; replay returns the same receipt', () => {
  const idem = key('reg');
  const a = call('register_readiness_feature', [T1, B1, 'f05-pos', 'Positive', idem], U.bizOwnerB1);
  assert.equal(a.result, 'created'); assert.equal(a.replayed, false);
  const b = call('register_readiness_feature', [T1, B1, 'f05-pos', 'Positive', idem], U.bizOwnerB1);
  assert.equal(b.result, 'replayed'); assert.equal(b.replayed, true); assert.equal(b.audit_receipt_id, a.audit_receipt_id);
  assert.equal(code(() => call('register_readiness_feature', [T1, B1, 'f05-pos', 'Changed title', idem], U.bizOwnerB1)), 'G3C01');
  assert.equal(code(() => feature('f05-pos')), 'G3C01'); // duplicate feature, new key
  const d0 = derive('f05-pos');
  assert.equal(d0.state, 'proposed'); assert.equal(d0.current_head_sha, null);
  assert.ok(d0.text.includes('head not registered'));
  const h = head('f05-pos', SHA1);
  assert.equal(h.head_seq, 1); assert.equal(h.readiness.state, 'proposed');
  const p1 = proof('f05-pos', 'code_built', SHA1, 'ci_isolated', { sim: true });
  assert.equal(p1.readiness.state, 'code_built');
  const p2 = proof('f05-pos', 'isolated_test_pass', SHA1, 'ci_isolated', { sim: true });
  assert.equal(p2.readiness.state, 'isolated_test_pass');
  assert.deepEqual(p2.readiness.satisfied_levels, ['code_built', 'isolated_test_pass']);
  assert.deepEqual(p2.readiness.simulated_levels, ['code_built', 'isolated_test_pass']);
  assert.equal(p2.readiness.certified, false);
  // every state links exact commit / environment / run / evidence
  const links = rows(DB, `select level, commit_sha, environment, run_ref, evidence_sha256, simulated, is_current_head
    from c10_gov003_demo.v_readiness_proofs where feature_id = 'f05-pos' order by proof_seq`, RD(U.bizOwnerB1));
  assert.equal(links.length, 2);
  for (const l of links) {
    assert.match(l.commit_sha, /^[0-9a-f]{40}$/); assert.match(l.evidence_sha256, /^[0-9a-f]{64}$/);
    assert.equal(l.environment, 'ci_isolated'); assert.equal(l.run_ref, 'run-0001'); assert.equal(l.is_current_head, true);
  }
  // replay of a proof: same proof, no new row
  const before = counts();
  const idem2 = key('proof');
  const r1 = proof('f05-pos', 'code_built', SHA1, 'ci_isolated', { sim: true, idem: idem2, run: 'run-0002' });
  const r2 = proof('f05-pos', 'code_built', SHA1, 'ci_isolated', { sim: true, idem: idem2, run: 'run-0002' });
  assert.equal(r2.replayed, true); assert.equal(r2.proof_id, r1.proof_id); assert.equal(r2.audit_receipt_id, r1.audit_receipt_id);
  assert.equal(Number(counts().p), Number(before.p) + 1);
  assert.equal(code(() => proof('f05-pos', 'code_built', SHA1, 'ci_isolated', { sim: true, idem: idem2, run: 'run-0003' })), 'G3C01');
  assert.equal(Number(counts().p), Number(before.p) + 1);
});

test('f05 Story C: green CI on SHA1, head is SHA2, no signed GoTrue, no deployment => not certified / stale CI / staging missing / deployment unverified', () => {
  feature('f05-storyc');
  head('f05-storyc', SHA1);
  proof('f05-storyc', 'code_built', SHA1, 'ci_isolated');
  proof('f05-storyc', 'isolated_test_pass', SHA1, 'ci_isolated');
  assert.equal(derive('f05-storyc').state, 'isolated_test_pass'); // green while SHA1 is head
  head('f05-storyc', SHA2);
  const d = derive('f05-storyc');
  assert.equal(d.state, 'proposed'); assert.equal(d.current_head_sha, SHA2);
  for (const t of ['not certified', 'stale CI', 'staging missing', 'deployment unverified']) assert.ok(d.text.includes(t), t);
  assert.match(d.summary, /not certified \/ stale CI \/ staging missing/);
  assert.deepEqual(d.stale, [{ level: 'code_built', commit_sha: SHA1 }, { level: 'isolated_test_pass', commit_sha: SHA1 }]);
  assert.equal(d.certified, false); assert.deepEqual(d.satisfied_levels, []);
  // adding valid synthetic proof on SHA2 improves ONLY the isolated simulation level
  proof('f05-storyc', 'code_built', SHA2, 'ci_isolated', { sim: true });
  proof('f05-storyc', 'isolated_test_pass', SHA2, 'ci_isolated', { sim: true });
  const e = derive('f05-storyc');
  assert.equal(e.state, 'isolated_test_pass');
  assert.ok(!e.text.includes('stale CI'));
  for (const t of ['not certified', 'staging missing', 'integration missing', 'deployment unverified', 'release not approved', 'simulation only']) assert.ok(e.text.includes(t), t);
  assert.deepEqual(e.missing_proofs, ['signed_stage_verified', 'integrated_verified', 'deployed_verified', 'released']);
  assert.equal(e.certified, false);
});

test('f05 negative: an old SHA pass is never reused for a new SHA (and counts again only if that SHA is head again)', () => {
  feature('f05-oldsha');
  head('f05-oldsha', SHA1);
  proof('f05-oldsha', 'code_built', SHA1, 'ci_isolated');
  head('f05-oldsha', SHA2);
  assert.equal(derive('f05-oldsha').state, 'proposed');
  assert.equal(one(DB, `select c10_gov003_demo.readiness_head_is_current(${lit(T1)}, ${lit(B1)}, 'f05-oldsha', ${lit(SHA1)}) v`, RD(U.bizOwnerB1)).v, false);
  assert.equal(one(DB, `select c10_gov003_demo.readiness_head_is_current(${lit(T1)}, ${lit(B1)}, 'f05-oldsha', ${lit(SHA2)}) v`, RD(U.bizOwnerB1)).v, true);
  assert.equal(code(() => head('f05-oldsha', SHA2)), 'G3C01'); // head unchanged
  const back = head('f05-oldsha', SHA1);                         // head legitimately returns to SHA1
  assert.equal(back.head_seq, 3); assert.equal(back.readiness.state, 'code_built');
});

test('f05 negative: a failing proof after a pass on the same sha regresses the level', () => {
  feature('f05-regress'); head('f05-regress', SHA1);
  proof('f05-regress', 'code_built', SHA1, 'ci_isolated');
  proof('f05-regress', 'isolated_test_pass', SHA1, 'ci_isolated');
  assert.equal(derive('f05-regress').state, 'isolated_test_pass');
  proof('f05-regress', 'isolated_test_pass', SHA1, 'ci_isolated', { outcome: 'fail' });
  const d = derive('f05-regress');
  assert.equal(d.state, 'code_built'); assert.ok(d.text.includes('isolated tests missing'));
});

test('f05 negative: no manual green — nothing carries a settable state, and proofs/heads/features cannot be rewritten', () => {
  assert.deepEqual(rows(DB, `select column_name from information_schema.columns where table_schema = 'c10_gov003_demo'
    and table_name in ('readiness_features','readiness_heads','readiness_proofs')
    and column_name in ('state','status','is_green','green','ready','readiness','certified')`, OWN), []);
  assert.deepEqual(rows(DB, `select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'c10_gov003_demo' and p.proname ~ '^(set_|mark_|force_)' and p.proname ~ 'readiness|green|state'`, OWN), []);
  feature('f05-immut'); head('f05-immut', SHA1); proof('f05-immut', 'code_built', SHA1, 'ci_isolated');
  for (const tbl of ['readiness_features', 'readiness_heads', 'readiness_proofs']) {
    assert.equal(code(() => exec(DB, `update c10_gov003_demo.${tbl} set tenant_id = tenant_id`, OWN)), 'G3H01', `update ${tbl}`);
    assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.${tbl}`, OWN)), 'G3H01', `delete ${tbl}`);
    assert.equal(code(() => exec(DB, `truncate c10_gov003_demo.${tbl} cascade`, OWN)), 'G3H01', `truncate ${tbl}`);
    assert.equal(code(() => exec(DB, `update c10_gov003_demo.${tbl} set tenant_id = tenant_id`, BE(U.bizOwnerB1))), '42501');
    assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.${tbl}`, BE(U.bizOwnerB1))), '42501');
    assert.equal(code(() => exec(DB, `insert into c10_gov003_demo.${tbl} (tenant_id, business_id) select tenant_id, business_id from c10_gov003_demo.${tbl}`, BE(U.bizOwnerB1))), '42501');
  }
  // owner bypass attempt: direct insert without the audited append path is refused
  assert.equal(code(() => exec(DB, `insert into c10_gov003_demo.readiness_proofs
    (tenant_id, business_id, feature_id, level, commit_sha, environment, run_ref, simulated, evidence_sha256, outcome,
     recorded_by, idempotency_key, audit_receipt_id, audit_seq)
    select tenant_id, business_id, feature_id, 'released', commit_sha, 'production', 'x', false, evidence_sha256, 'pass',
           recorded_by, 'forged-key-0001', audit_receipt_id, 1 from c10_gov003_demo.readiness_proofs limit 1`, OWN)), 'G3H01');
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.readiness_proofs`, RD(U.bizOwnerB1))), null); // reader may SELECT (RLS-scoped)
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.readiness_proofs`, { role: 'c10g3_app', sub: U.bizOwnerB1 })), '42501');
});

test('f05 negative: synthetic/simulated evidence can never satisfy signed, integrated, deployed or released', () => {
  feature('f05-sim'); head('f05-sim', SHA1);
  proof('f05-sim', 'code_built', SHA1, 'ci_isolated', { sim: true });
  proof('f05-sim', 'isolated_test_pass', SHA1, 'ci_isolated', { sim: true });
  assert.equal(code(() => proof('f05-sim', 'signed_stage_verified', SHA1, 'staging_signed', { sim: true })), 'G3C02');
  assert.equal(code(() => proof('f05-sim', 'integrated_verified', SHA1, 'integration', { sim: true })), 'G3C02');
  assert.equal(code(() => proof('f05-sim', 'signed_stage_verified', SHA1, 'ci_isolated', { sim: true })), 'G3A03'); // wrong env
  // dedicated paths cannot be reached through the generic writer
  assert.equal(code(() => proof('f05-sim', 'deployed_verified', SHA1, 'production')), 'G3A03');
  assert.equal(code(() => proof('f05-sim', 'released', SHA1, 'production')), 'G3A03');
  assert.equal(code(() => proof('f05-sim', 'proposed', SHA1, 'local')), 'G3A03');
  // a "real" claim with the gate closed fails closed (no authentic signed GoTrue in the bed)
  assert.equal(code(() => proof('f05-sim', 'signed_stage_verified', SHA1, 'staging_signed', { sim: false })), 'G3E01');
  assert.equal(code(() => proof('f05-sim', 'integrated_verified', SHA1, 'integration', { sim: false })), 'G3E01');
  const d = derive('f05-sim');
  assert.equal(d.state, 'isolated_test_pass'); assert.equal(d.certified, false);
  assert.ok(d.text.includes('staging missing')); assert.ok(d.text.includes('simulation only'));
  // trigger-level defence: direct owner insert of a simulated signed proof is refused by the table guard
  assert.equal(code(() => exec(DB, `select set_config('c10_gov003.writer','append_path',false);
    insert into c10_gov003_demo.readiness_proofs
    (tenant_id, business_id, feature_id, level, commit_sha, environment, run_ref, simulated, evidence_sha256, outcome,
     recorded_by, idempotency_key, audit_receipt_id, audit_seq)
    select tenant_id, business_id, feature_id, 'signed_stage_verified', commit_sha, 'staging_signed', 'x', true, evidence_sha256,
           'pass', recorded_by, 'forged-key-0002', audit_receipt_id, 1 from c10_gov003_demo.readiness_proofs limit 1`, OWN)), 'G3C02');
});

test('f05 ladder with gates opened (future adapters): contiguity, release prerequisites, owner-only release', () => {
  feature('f05-ladder'); head('f05-ladder', SHA1);
  setGate('signed_gotrue', true); setGate('integration_env', true);
  try {
    // integration proof first does NOT lift the state: ladder is contiguous
    proof('f05-ladder', 'integrated_verified', SHA1, 'integration');
    assert.equal(derive('f05-ladder').state, 'proposed');
    proof('f05-ladder', 'code_built', SHA1, 'isolated_pg');
    proof('f05-ladder', 'isolated_test_pass', SHA1, 'isolated_pg');
    assert.equal(derive('f05-ladder').state, 'isolated_test_pass');
    const s = proof('f05-ladder', 'signed_stage_verified', SHA1, 'staging_signed');
    assert.equal(s.readiness.state, 'integrated_verified');   // integration proof already present -> contiguous now
    assert.deepEqual(s.readiness.simulated_levels, []);
    assert.deepEqual(s.readiness.missing_proofs, ['deployed_verified', 'released']);
    // release prerequisites: deployed proof missing
    assert.equal(code(() => call('approve_release', [T1, B1, 'f05-ladder', SHA1, 'rel-run-1', EV('a'), key('rel')], U.bizOwnerB1)), 'G3C02');
    assert.equal(code(() => call('approve_release', [T1, B1, 'f05-ladder', SHA2, 'rel-run-1', EV('a'), key('rel')], U.bizOwnerB1)), 'G3C01'); // not the head
    // business-wide staff can write proofs but cannot approve a release
    assert.equal(proof('f05-ladder', 'code_built', SHA1, 'local', { sub: STAFF_BIZ }).result, 'created');
    assert.equal(code(() => call('approve_release', [T1, B1, 'f05-ladder', SHA1, 'rel-run-1', EV('a'), key('rel')], STAFF_BIZ)), 'G3A02');
    // forged actor on release
    assert.equal(code(() => call('approve_release', [T1, B1, 'f05-ladder', SHA1, 'rel-run-1', EV('a'), key('rel'), U.tenantOwnerT1], U.bizOwnerB1)), 'G3A01');
  } finally { setGate('signed_gotrue', false); setGate('integration_env', false); }
});

test('f05 negative: forged actor, unauthenticated and invalid input are rejected on every writer', () => {
  feature('f05-forge');
  assert.equal(code(() => call('register_readiness_feature', [T1, B1, 'f05-forge-2', 'T', key('reg'), U.tenantOwnerT1], U.bizOwnerB1)), 'G3A01');
  assert.equal(code(() => head('f05-forge', SHA1, U.bizOwnerB1, { claimed: U.tenantOwnerT1 })), 'G3A01');
  assert.equal(code(() => proof('f05-forge', 'code_built', SHA1, 'local', { claimed: U.t2Owner })), 'G3A01');
  assert.equal(head('f05-forge', SHA1, U.bizOwnerB1, { claimed: U.bizOwnerB1 }).result, 'created'); // matching claim is ignored as authority
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.record_readiness_head(${lit(T1)}, ${lit(B1)}, 'f05-forge', ${lit(SHA2)}, 'idem-noauth-0001')`, { role: 'c10g3_backend' })), 'G3A05');
  assert.equal(code(() => proof('f05-forge', 'code_built', SHA1, 'local', { sub: U.unknown })), 'G3A05');
  const bad = [
    () => head('f05-forge', 'A'.repeat(40)), () => head('f05-forge', SHA('a').slice(1)), () => head('f05-forge', 'g'.repeat(40)),
    () => proof('f05-forge', 'code_built', SHA1, 'local', { ev: 'zz' }), () => proof('f05-forge', 'code_built', SHA1, 'local', { run: 'bad run' }),
    () => proof('f05-forge', 'code_built', SHA1, 'local', { run: 'Bearer abc123456' }), () => proof('f05-forge', 'code_built', SHA1, 'local', { idem: 'x' }),
    () => proof('f05-forge', 'code_built', SHA1, 'local', { outcome: 'green' }), () => proof('f05-forge', 'code_built', SHA1, 'nowhere'),
  ];
  for (const [i, fn] of bad.entries()) assert.equal(code(fn), 'G3A03', `bad input ${i}`);
  assert.equal(code(() => proof('no-such-feature', 'code_built', SHA1, 'local')), 'G3C02');
  assert.equal(code(() => head('no-such-feature', SHA1)), 'G3C02');
});

test('f05 negative: foreign tenant, other business, investor, revoked, support and site-only identities are denied', () => {
  feature('f05-scope'); head('f05-scope', SHA1);
  const denied = [U.t2Owner, U.investorB1, U.revokedB1, U.support, U.staffS1, U.bizOwnerB2];
  for (const sub of denied) {
    assert.equal(code(() => call('register_readiness_feature', [T1, B1, 'f05-x', 'T', key('reg')], sub)), 'G3A02', `register ${sub}`);
    assert.equal(code(() => head('f05-scope', SHA2, sub)), 'G3A02', `head ${sub}`);
    assert.equal(code(() => proof('f05-scope', 'code_built', SHA1, 'local', { sub })), 'G3A02', `proof ${sub}`);
    assert.equal(code(() => derive('f05-scope', sub)), 'G3A02', `derive ${sub}`);
    assert.equal(code(() => call('approve_release', [T1, B1, 'f05-scope', SHA1, 'run-1', EV('a'), key('rel')], sub)), 'G3A02', `release ${sub}`);
  }
  // foreign scope target with the right identity of another tenant/business
  assert.equal(code(() => call('register_readiness_feature', [T2, B1, 'f05-x', 'T', key('reg')], U.tenantOwnerT1)), 'G3A02'); // business not in tenant
  assert.equal(code(() => proof('f05-scope', 'code_built', SHA1, 'local', { t: T2, sub: U.t2Owner })), 'G3A02');
  assert.equal(code(() => proof('f05-scope', 'code_built', SHA1, 'local', { b: B2, sub: U.bizOwnerB1 })), 'G3A02');
  // tenant owner is allowed; no cross-tenant leakage in the read views or counts
  assert.equal(proof('f05-scope', 'code_built', SHA1, 'local', { sub: U.tenantOwnerT1 }).result, 'created');
  const mine = rows(DB, 'select feature_id from c10_gov003_demo.v_readiness_features', RD(U.bizOwnerB1));
  assert.ok(mine.length >= 1 && mine.every((r) => r.feature_id.startsWith('f05-')));
  for (const sub of denied) {
    assert.deepEqual(rows(DB, 'select feature_id from c10_gov003_demo.v_readiness_features', RD(sub)), [], `features view ${sub}`);
    assert.deepEqual(rows(DB, 'select 1 from c10_gov003_demo.v_readiness_proofs', RD(sub)), [], `proofs view ${sub}`);
    assert.deepEqual(rows(DB, 'select 1 from c10_gov003_demo.v_readiness_heads', RD(sub)), [], `heads view ${sub}`);
    assert.equal(one(DB, 'select count(*) c from c10_gov003_demo.readiness_proofs', RD(sub)).c, 0, `count ${sub}`);
  }
});

test('f05 audit: every state change is audited with source_domain gov003.readiness and the chain verifies', () => {
  const ev = rows(DB, `select source_domain, action, reason_category, payload from c10_gov003_demo.v_audit_events
    where source_domain = 'gov003.readiness'`, RD(U.bizOwnerB1));
  assert.ok(ev.length > 10);
  const actions = new Set(ev.map((e) => e.action));
  for (const a of ['readiness.feature_registered', 'readiness.head_recorded', 'readiness.proof_recorded']) assert.ok(actions.has(a), a);
  assert.ok(ev.every((e) => e.reason_category === 'readiness'));
  assert.ok(ev.every((e) => typeof e.payload.doc_ref === 'string' && e.payload.doc_ref.startsWith('cmd:')));
  const v = one(DB, `select * from c10_gov003_demo.verify_chain(${lit(T1)}, ${lit(B1)})`, BE(U.bizOwnerB1));
  assert.equal(v.ok, true);
  // a rejected command leaves no audit trace and no row (atomic)
  const c0 = counts();
  assert.equal(code(() => proof('f05-scope', 'code_built', SHA1, 'nowhere')), 'G3A03');
  assert.equal(code(() => proof('f05-scope', 'signed_stage_verified', SHA1, 'staging_signed')), 'G3E01');
  const c1 = counts();
  assert.equal(c1.a, c0.a); assert.equal(c1.p, c0.p);
});

test('f05 concurrency: two simultaneous identical proofs store one result; simultaneous heads get distinct sequences', async () => {
  feature('f05-race'); head('f05-race', SHA1);
  const idem = key('race');
  const sql = `select * from c10_gov003_demo.record_readiness_proof(${lit(T1)}, ${lit(B1)}, 'f05-race', 'code_built', ${lit(SHA1)}, 'local', 'run-race', false, ${lit(EV('c'))}, 'pass', ${lit(idem)})`;
  const [x, y] = await Promise.all([execAsync(DB, sql, BE(U.bizOwnerB1)), execAsync(DB, sql, BE(U.bizOwnerB1))]);
  assert.ok(x.ok && y.ok);
  const outs = [x.out, y.out].map((o) => o.split('|')[0]).sort();
  assert.deepEqual(outs, ['created', 'replayed']);
  assert.equal(one(DB, `select count(*) c from c10_gov003_demo.readiness_proofs where idempotency_key = ${lit(idem)}`, OWN).c, 1);
  const h2 = `select * from c10_gov003_demo.record_readiness_head(${lit(T1)}, ${lit(B1)}, 'f05-race', ${lit(SHA2)}, ${lit(key('hd'))})`;
  const h3 = `select * from c10_gov003_demo.record_readiness_head(${lit(T1)}, ${lit(B1)}, 'f05-race', ${lit(SHA3)}, ${lit(key('hd'))})`;
  const [p, q] = await Promise.all([execAsync(DB, h2, BE(U.bizOwnerB1)), execAsync(DB, h3, BE(U.bizOwnerB1))]);
  assert.ok(p.ok && q.ok);
  assert.deepEqual(rows(DB, `select head_seq from c10_gov003_demo.v_readiness_heads where feature_id = 'f05-race' order by head_seq`, RD(U.bizOwnerB1)).map((r) => r.head_seq), [1, 2, 3]);
});

test('f05 privileges: no f057 helper or writer is executable by PUBLIC or the app role; writers are backend-only', () => {
  const fns = rows(DB, `select p.proname, p.prosecdef, p.proconfig::text cfg,
      has_function_privilege('c10g3_app', p.oid, 'execute') app, has_function_privilege('c10g3_reader', p.oid, 'execute') rd,
      has_function_privilege('c10g3_backend', p.oid, 'execute') be, pg_get_userbyid(p.proowner) owner
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'c10_gov003_demo' and (p.proname like '\\_f57\\_%' or p.proname ~ '^(register_readiness|record_readiness|approve_release|derive_readiness|readiness_head)')`, OWN);
  assert.ok(fns.length >= 15);
  for (const f of fns) {
    assert.equal(f.app, false, `${f.proname} app`); assert.equal(f.owner, 'c10g3_owner');
    if (f.prosecdef) assert.match(f.cfg, /search_path=pg_catalog, c10_gov003_demo, pg_temp/, `${f.proname} search_path`);
  }
  const writers = ['register_readiness_feature', 'record_readiness_head', 'record_readiness_proof', 'approve_release'];
  for (const w of writers) { const f = fns.find((x) => x.proname === w); assert.equal(f.be, true); assert.equal(f.rd, false, `${w} reader`); }
  for (const internal of ['_f57_insert_proof', '_f57_derive', '_f57_actor']) { const f = fns.find((x) => x.proname === internal); assert.equal(f.be, false, internal); }
  assert.equal(code(() => exec(DB, `select c10_gov003_demo._f57_insert_proof(${lit(T1)}, ${lit(B1)}, 'f', 'released', ${lit(SHA1)}, 'production', 'r', false, ${lit(EV('a'))}, 'pass', 'idem-x-0001', ${lit(U.bizOwnerB1)}, null, 1, null, null)`, BE(U.bizOwnerB1))), '42501');
  // reader cannot write; app cannot call anything
  assert.equal(code(() => call('record_readiness_head', [T1, B1, 'f05-scope', SHA3, key('hd')], U.bizOwnerB1, RD(U.bizOwnerB1))), '42501');
  assert.equal(code(() => call('derive_readiness', [T1, B1, 'f05-scope'], U.bizOwnerB1, { role: 'c10g3_app', sub: U.bizOwnerB1 })), '42501');
});
