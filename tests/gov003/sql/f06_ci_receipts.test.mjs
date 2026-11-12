// Feature 06 exact-commit-ci-receipts: head-SHA binding, run-url contract, stale-head validator, evidence reference,
// and "a caller-supplied GitHub URL is never certification".
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, dropDb, rows, one, exec, execAsync, lit } from '../lib/db.mjs';
import { T1, T2, B1, B2, U } from '../lib/ids.mjs';
import { buildReceipt } from '../../../internal/gov003/server/ci-receipt.mjs';

const DB = 'g3_f057_f06';
const ONLY = ['000', '010', '020', '030', '040', '050', '060', '070'];
const BE = (sub) => ({ role: 'c10g3_backend', sub });
const RD = (sub) => ({ role: 'c10g3_reader', sub });
const OWN = { role: 'c10g3_owner' };
const SHA1 = 'a1'.repeat(20); const SHA2 = 'b2'.repeat(20);
const REPO = 'mistybari99/CORE-10-CENTRAL';
const urlOf = (id, repo = REPO) => `https://github.com/${repo}/actions/runs/${id}`;
let n = 0; let runSeq = 7000000;
const key = (p = 'k') => `${p}-f06-${String(++n).padStart(6, '0')}`;
const arg = (v) => (v === null || v === undefined ? 'null' : typeof v === 'boolean' || typeof v === 'number' ? String(v) : typeof v === 'object' ? `${lit(JSON.stringify(v))}::jsonb` : lit(v));
const call = (fn, args, sub, ctx = null) => one(DB, `select * from c10_gov003_demo.${fn}(${args.map(arg).join(', ')})`, ctx ?? BE(sub));
const code = (fn) => { try { fn(); } catch (e) { return e.code; } return null; };
const setGate = (g, on) => exec(DB, `update c10_gov003_demo.real_evidence_gates set enabled = ${on} where gate = ${lit(g)}`, OWN);

const feature = (f) => call('register_readiness_feature', [T1, B1, f, `Title ${f}`, key('reg')], U.bizOwnerB1);
const head = (f, sha) => call('record_readiness_head', [T1, B1, f, sha, key('head')], U.bizOwnerB1);
/** record_ci_receipt with sane defaults; returns { row, in } so tests can build observations. */
const receipt = (f, o = {}) => {
  const run_id = o.run_id ?? String(++runSeq);
  const i = { feature: f, workflow: 'c10-gov003-standalone-pg17', run_id, url: urlOf(run_id), sha: SHA1, status: 'completed',
    conclusion: 'success', env: 'ci_isolated', attempt: 1, idem: key('ci'), claimed: null, sub: U.bizOwnerB1, ...o };
  const row = call('record_ci_receipt', [o.t ?? T1, o.b ?? B1, i.feature, i.workflow, i.run_id, i.url, i.sha, i.status,
    i.conclusion, i.env, i.attempt, i.idem, i.claimed], i.sub);
  return { row, i };
};
const obs = (i, over = {}) => ({ repo: REPO.toLowerCase(), run_id: i.run_id, run_url: i.url, head_sha: i.sha, workflow: i.workflow,
  run_status: i.status, conclusion: i.conclusion, observed_at: '2026-11-12T10:00:00.000Z', ...over });
const verify = (rid, o, kind = 'simulated_fixture', sub = U.bizOwnerB1, idem = key('ver')) =>
  call('verify_ci_receipt', [T1, B1, rid, kind, o, idem], sub);
const bind = (rid, sub = U.bizOwnerB1, idem = key('bind'), t = T1, b = B1) => call('bind_ci_receipt_to_readiness', [t, b, rid, idem], sub);
const derive = (f) => call('derive_readiness', [T1, B1, f], U.bizOwnerB1, RD(U.bizOwnerB1)).derive_readiness;
const cnt = (tbl) => Number(one(DB, `select count(*) c from c10_gov003_demo.${tbl}`, OWN).c);

before(() => { freshDb(DB, { only: ONLY }); });
after(() => dropDb(DB));

test('f06 positive: receipt records head sha / workflow / run / conclusion / environment with a sha256 evidence reference', () => {
  feature('f06-pos'); head('f06-pos', SHA1);
  const { row, i } = receipt('f06-pos');
  assert.equal(row.result, 'created'); assert.equal(row.replayed, false);
  assert.equal(row.trust_label, 'offline_fixture/unverified'); assert.equal(row.head_is_current, true);
  assert.match(row.evidence_sha256, /^[0-9a-f]{64}$/);
  const v = one(DB, `select * from c10_gov003_demo.v_ci_receipts where receipt_id = ${lit(row.receipt_id)}`, RD(U.bizOwnerB1));
  assert.equal(v.head_sha, SHA1); assert.equal(v.workflow, 'c10-gov003-standalone-pg17'); assert.equal(v.run_id, i.run_id);
  assert.equal(v.run_url, i.url); assert.equal(v.conclusion, 'success'); assert.equal(v.environment, 'ci_isolated');
  assert.equal(v.origin, 'offline_fixture'); assert.equal(v.trust_label, 'offline_fixture/unverified'); assert.equal(v.is_current_head, true);
  assert.equal(v.repo_full, 'mistybari99/core-10-central');
  // immutable evidence reference == sha256 of the canonical receipt; Node and SQL agree byte for byte
  const js = buildReceipt({ feature_id: 'f06-pos', head_sha: SHA1, run_id: i.run_id, run_url: i.url, workflow: i.workflow,
    run_status: 'completed', conclusion: 'success', environment: 'ci_isolated', run_attempt: 1 });
  assert.equal(js.evidence_sha256, row.evidence_sha256);
  assert.equal(js.trust_label, 'offline_fixture/unverified');
  // replay returns the same receipt; changed payload under the same key conflicts
  const again = call('record_ci_receipt', [T1, B1, 'f06-pos', i.workflow, i.run_id, i.url, SHA1, 'completed', 'success', 'ci_isolated', 1, i.idem], U.bizOwnerB1);
  assert.equal(again.result, 'replayed'); assert.equal(again.replayed, true); assert.equal(again.receipt_id, row.receipt_id);
  assert.equal(again.audit_receipt_id, row.audit_receipt_id); assert.equal(again.evidence_sha256, row.evidence_sha256);
  assert.equal(code(() => call('record_ci_receipt', [T1, B1, 'f06-pos', i.workflow, i.run_id, i.url, SHA1, 'completed', 'failure', 'ci_isolated', 1, i.idem], U.bizOwnerB1)), 'G3C01');
  assert.equal(code(() => call('record_ci_receipt', [T1, B1, 'f06-pos', i.workflow, i.run_id, i.url, SHA2, 'completed', 'success', 'ci_isolated', 1, i.idem], U.bizOwnerB1)), 'G3C01');
  // same run / sha / status / conclusion under a new key is a duplicate, but queued -> completed progression is fine
  assert.equal(code(() => receipt('f06-pos', { run_id: i.run_id })), 'G3C01');
  const rid2 = String(++runSeq);
  assert.equal(receipt('f06-pos', { run_id: rid2, status: 'queued', conclusion: null }).row.result, 'created');
  assert.equal(receipt('f06-pos', { run_id: rid2 }).row.result, 'created');
});

test('f06 validation: SHA must be 40 lowercase hex; run URL must match the GitHub Actions run pattern exactly', () => {
  feature('f06-val'); head('f06-val', SHA1);
  for (const sha of ['A1'.repeat(20), 'a1'.repeat(19), 'a1'.repeat(21), 'g1'.repeat(20), '', ' ' + 'a1'.repeat(19) + 'a']) {
    assert.equal(code(() => receipt('f06-val', { sha })), 'G3A03', `sha ${JSON.stringify(sha)}`);
  }
  const rid = '8100001';
  const badUrls = [
    `http://github.com/${REPO}/actions/runs/${rid}`, `https://gitlab.com/${REPO}/actions/runs/${rid}`,
    `https://github.com.evil.example/${REPO}/actions/runs/${rid}`, `https://evil@github.com/${REPO}/actions/runs/${rid}`,
    `https://github.com/${REPO}/actions/runs/${rid}?x=1`, `https://github.com/${REPO}/actions/runs/${rid}#frag`,
    `https://github.com/${REPO}/actions/runs/${rid}/`, `https://github.com/${REPO}/actions/runs/${rid}/attempts/1`,
    `https://github.com/${REPO}/actions/runs/abc`, `https://github.com/${REPO}/actions/${rid}`, `https://github.com/${REPO}/pull/${rid}`,
    `https://github.com/${REPO}/actions/runs/${rid}\n`, `https://github.com/mistybari99/../actions/runs/${rid}`, `https://github.com/ /x/actions/runs/${rid}`,
    `https://GITHUB.com/${REPO}/actions/runs/${rid}`, `javascript:alert(1)`, '', `https://github.com/${REPO}/actions/runs/${'9'.repeat(25)}`,
  ];
  for (const url of badUrls) assert.equal(code(() => receipt('f06-val', { run_id: rid, url })), 'G3A03', `url ${JSON.stringify(url)}`);
  assert.equal(code(() => receipt('f06-val', { run_id: '8100002', url: urlOf('8100003') })), 'G3A03'); // url id != run id
  assert.equal(code(() => receipt('f06-val', { run_id: '8100004', url: urlOf('8100004', 'someone-else/other-repo') })), 'G3A03'); // untrusted repo
  assert.equal(code(() => receipt('f06-val', { status: 'completed', conclusion: null })), 'G3A03');
  assert.equal(code(() => receipt('f06-val', { status: 'queued', conclusion: 'success' })), 'G3A03');
  assert.equal(code(() => receipt('f06-val', { status: 'in_progress', conclusion: 'success' })), 'G3A03');
  assert.equal(code(() => receipt('f06-val', { status: 'completed', conclusion: 'green' })), 'G3A03');
  assert.equal(code(() => receipt('f06-val', { env: 'somewhere' })), 'G3A03');
  assert.equal(code(() => receipt('f06-val', { workflow: 'x; drop table' })), 'G3A03');
  assert.equal(code(() => receipt('f06-val', { attempt: 0 })), 'G3A03');
  assert.equal(code(() => receipt('f06-val', { idem: 'short' })), 'G3A03');
  assert.equal(code(() => receipt('f06-nope')), 'G3C02');
  // a correct upper/lower-case GitHub owner is accepted (repo compare is case-insensitive) and stored lower-case
  assert.equal(receipt('f06-val', { run_id: '8100010', url: urlOf('8100010', 'MISTYBARI99/core-10-central') }).row.result, 'created');
});

test('f06 negative: a caller-supplied (well-formed) GitHub URL is NEVER certification', () => {
  feature('f06-fake'); head('f06-fake', SHA1);
  const { row } = receipt('f06-fake');
  assert.equal(row.trust_label, 'offline_fixture/unverified');
  assert.equal(code(() => bind(row.receipt_id)), 'G3C02');                  // unverified cannot reach readiness
  assert.equal(derive('f06-fake').state, 'proposed');
  assert.equal(cnt('readiness_proofs'), 0);
  // remote GitHub verification is unavailable (gate closed): github_api cannot be claimed
  const i = { run_id: one(DB, `select run_id from c10_gov003_demo.ci_receipts where receipt_id = ${lit(row.receipt_id)}`, OWN).run_id };
  assert.equal(code(() => verify(row.receipt_id, obs({ ...i, url: urlOf(i.run_id), sha: SHA1, workflow: 'c10-gov003-standalone-pg17', status: 'completed', conclusion: 'success' }), 'github_api')), 'G3E01');
  assert.equal(cnt('ci_receipt_verifications'), 0);
  assert.equal(one(DB, `select trust_label from c10_gov003_demo.v_ci_receipts where receipt_id = ${lit(row.receipt_id)}`, RD(U.bizOwnerB1)).trust_label, 'offline_fixture/unverified');
});

test('f06 remote verifier contract: matching simulated observation => simulated_verified; every mismatch is REJECTED and stores nothing', () => {
  feature('f06-ver'); head('f06-ver', SHA1);
  const { row, i } = receipt('f06-ver');
  const before = cnt('ci_receipt_verifications');
  const mismatches = {
    head_sha_mismatch: { head_sha: SHA2 }, conclusion_mismatch: { conclusion: 'failure' }, run_status_mismatch: { run_status: 'in_progress', conclusion: null },
    run_url_mismatch: { run_url: urlOf(i.run_id, 'mistybari99/Other') }, run_id_mismatch: { run_id: '1' }, repo_mismatch: { repo: 'other/repo' },
    workflow_mismatch: { workflow: 'another-workflow' },
  };
  for (const [codeName, over] of Object.entries(mismatches)) {
    let err = null; try { verify(row.receipt_id, obs(i, over)); } catch (e) { err = e; }
    assert.equal(err?.code, 'G3C02', codeName); assert.match(err.detail, /remote_mismatch/, codeName);
    if (codeName !== 'run_status_mismatch' && codeName !== 'conclusion_mismatch') assert.match(err.detail, new RegExp(codeName), codeName);
  }
  for (const bad of [{ head_sha: 'ABC' }, { extra_field: 'x' }, { observed_at: 'yesterday' }, { run_status: 'done' }, { run_id: 'x' }]) {
    assert.equal(code(() => verify(row.receipt_id, obs(i, bad))), 'G3A03', JSON.stringify(bad));
  }
  assert.equal(code(() => verify(row.receipt_id, [1, 2])), 'G3A03');
  assert.equal(code(() => verify(row.receipt_id, obs(i), 'carrier_pigeon')), 'G3A03');
  assert.equal(code(() => verify('00000000-0000-4000-8000-000000000000', obs(i))), 'G3C02');
  assert.equal(cnt('ci_receipt_verifications'), before); // nothing persisted by rejected attempts
  const ok = verify(row.receipt_id, obs(i), 'simulated_fixture', U.bizOwnerB1, 'ver-f06-ok-0001');
  assert.equal(ok.result, 'created'); assert.equal(ok.trust_label, 'offline_fixture/simulated_verified');
  const replay = verify(row.receipt_id, obs(i), 'simulated_fixture', U.bizOwnerB1, 'ver-f06-ok-0001');
  assert.equal(replay.replayed, true); assert.equal(replay.verification_id, ok.verification_id); assert.equal(replay.audit_receipt_id, ok.audit_receipt_id);
  assert.equal(code(() => verify(row.receipt_id, obs(i, { observed_at: '2026-11-12T11:00:00.000Z' }), 'simulated_fixture', U.bizOwnerB1, 'ver-f06-ok-0001')), 'G3C01');
  assert.equal(one(DB, `select trust_label from c10_gov003_demo.v_ci_receipts where receipt_id = ${lit(row.receipt_id)}`, RD(U.bizOwnerB1)).trust_label, 'offline_fixture/simulated_verified');
});

test('f06 delivery truth: verified isolated CI on the current head improves only the isolated SIMULATION level', () => {
  feature('f06-bind'); head('f06-bind', SHA1);
  const { row, i } = receipt('f06-bind');
  verify(row.receipt_id, obs(i));
  const idem = key('bind');
  const b = bind(row.receipt_id, U.bizOwnerB1, idem);
  assert.equal(b.result, 'created'); assert.equal(b.head_is_current, true); assert.equal(b.proof_ids.length, 2);
  assert.equal(b.readiness.state, 'isolated_test_pass');
  assert.deepEqual(b.readiness.simulated_levels, ['code_built', 'isolated_test_pass']);
  for (const t of ['not certified', 'staging missing', 'deployment unverified', 'simulation only']) assert.ok(b.readiness.text.includes(t), t);
  const proofs = rows(DB, `select level, simulated, environment, run_ref, source_kind, evidence_sha256, commit_sha from c10_gov003_demo.v_readiness_proofs where feature_id = 'f06-bind' order by level`, RD(U.bizOwnerB1));
  assert.deepEqual(proofs.map((p) => p.level), ['code_built', 'isolated_test_pass']);
  assert.ok(proofs.every((p) => p.simulated && p.source_kind === 'ci_receipt' && p.evidence_sha256 === row.evidence_sha256 && p.commit_sha === SHA1 && p.run_ref === `gh-run-${i.run_id}`));
  const r = bind(row.receipt_id, U.bizOwnerB1, idem);
  assert.equal(r.replayed, true); assert.deepEqual(r.proof_ids, b.proof_ids); assert.equal(r.audit_receipt_id, b.audit_receipt_id);
  assert.equal(code(() => bind(row.receipt_id)), 'G3C01');                  // already bound: one receipt, one binding
  assert.equal(cnt('readiness_proofs'), 2);
  // never lifts above isolated: a CI receipt in staging_signed / integration / staging / production / local cannot bind
  for (const env of ['staging_signed', 'integration', 'staging', 'production', 'local']) {
    const x = receipt('f06-bind', { env }); verify(x.row.receipt_id, obs(x.i));
    assert.equal(code(() => bind(x.row.receipt_id)), 'G3C02', env);
  }
  assert.equal(derive('f06-bind').state, 'isolated_test_pass');
});

test('f06 negative: queued / in-progress / failed CI never certifies; failure regresses isolated pass', () => {
  feature('f06-state'); head('f06-state', SHA1);
  for (const status of ['queued', 'in_progress']) {
    const x = receipt('f06-state', { status, conclusion: null }); verify(x.row.receipt_id, obs(x.i));
    assert.equal(code(() => bind(x.row.receipt_id)), 'G3C02', status);
  }
  assert.equal(derive('f06-state').state, 'proposed');
  const ok = receipt('f06-state'); verify(ok.row.receipt_id, obs(ok.i)); bind(ok.row.receipt_id);
  assert.equal(derive('f06-state').state, 'isolated_test_pass');
  const bad = receipt('f06-state', { conclusion: 'failure' }); verify(bad.row.receipt_id, obs(bad.i));
  const b = bind(bad.row.receipt_id);
  assert.equal(b.proof_ids.length, 1); assert.equal(b.readiness.state, 'code_built');
});

test('f06 stale-head: an old SHA pass is recorded but never reused for the new SHA (Story C via CI receipts)', () => {
  feature('f06-stale'); head('f06-stale', SHA1);
  const old = receipt('f06-stale', { sha: SHA1 }); verify(old.row.receipt_id, obs(old.i));
  assert.equal(bind(old.row.receipt_id).readiness.state, 'isolated_test_pass');
  head('f06-stale', SHA2);                                                    // source HEAD moves
  const chk = call('validate_ci_receipt_head', [T1, B1, old.row.receipt_id], null, RD(U.bizOwnerB1)).validate_ci_receipt_head;
  assert.equal(chk.stale, true); assert.equal(chk.receipt_head_sha, SHA1); assert.equal(chk.current_head_sha, SHA2);
  assert.equal(chk.trust_label, 'offline_fixture/simulated_verified');
  assert.equal(one(DB, `select is_current_head from c10_gov003_demo.v_ci_receipts where receipt_id = ${lit(old.row.receipt_id)}`, RD(U.bizOwnerB1)).is_current_head, false);
  const d = derive('f06-stale');
  assert.equal(d.state, 'proposed');
  for (const t of ['not certified', 'stale CI', 'staging missing', 'deployment unverified']) assert.ok(d.text.includes(t), t);
  // a receipt for the new head SHA is recorded fresh and only then does the level return
  const fresh = receipt('f06-stale', { sha: SHA2 }); verify(fresh.row.receipt_id, obs(fresh.i));
  assert.equal(fresh.row.head_is_current, true);
  const e = bind(fresh.row.receipt_id);
  assert.equal(e.readiness.state, 'isolated_test_pass'); assert.ok(!e.readiness.text.includes('stale CI'));
  // binding an OLD receipt later cannot hijack the new head: proofs stay bound to the receipt's own sha
  const late = receipt('f06-stale', { sha: SHA1 }); verify(late.row.receipt_id, obs(late.i));
  const l = bind(late.row.receipt_id);
  assert.equal(l.head_is_current, false);
  assert.ok(l.readiness.satisfied_levels.every((lv) => ['code_built', 'isolated_test_pass'].includes(lv)));
});

test('f06 even a (future) remote-verified receipt only certifies isolated levels, never signed / deployed / released', () => {
  feature('f06-remote'); head('f06-remote', SHA1);
  setGate('github_remote', true);
  try {
    const { row, i } = receipt('f06-remote');
    const v = verify(row.receipt_id, obs(i), 'github_api');
    assert.equal(v.trust_label, 'remote_verified');
    const b = bind(row.receipt_id);
    assert.deepEqual(b.readiness.simulated_levels, []);
    assert.equal(b.readiness.state, 'isolated_test_pass'); assert.equal(b.readiness.certified, false);
    for (const t of ['not certified', 'staging missing', 'integration missing', 'deployment unverified', 'release not approved']) assert.ok(b.readiness.text.includes(t), t);
    assert.ok(!b.readiness.text.includes('simulation only'));
  } finally { setGate('github_remote', false); }
});

test('f06 negative: receipts and verifications are immutable (UPDATE/DELETE/TRUNCATE/INSERT)', () => {
  const rid = one(DB, 'select receipt_id from c10_gov003_demo.ci_receipts limit 1', OWN).receipt_id;
  for (const tbl of ['ci_receipts', 'ci_receipt_verifications']) {
    assert.equal(code(() => exec(DB, `update c10_gov003_demo.${tbl} set tenant_id = tenant_id`, OWN)), 'G3H01', tbl);
    assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.${tbl}`, OWN)), 'G3H01', tbl);
    assert.equal(code(() => exec(DB, `truncate c10_gov003_demo.${tbl} cascade`, OWN)), 'G3H01', tbl);
    assert.equal(code(() => exec(DB, `update c10_gov003_demo.${tbl} set tenant_id = tenant_id`, BE(U.bizOwnerB1))), '42501');
    assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.${tbl}`, BE(U.bizOwnerB1))), '42501');
  }
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.ci_receipts set conclusion = 'success', head_sha = ${lit(SHA2)} where receipt_id = ${lit(rid)}`, OWN)), 'G3H01');
  assert.equal(code(() => exec(DB, `insert into c10_gov003_demo.ci_receipts (tenant_id, business_id) values (${lit(T1)}, ${lit(B1)})`, OWN)), 'G3H01');
});

test('f06 negative: forged actor, foreign tenant, investor, revoked, support and site-only identities are denied; no cross-tenant counts', () => {
  feature('f06-scope'); head('f06-scope', SHA1);
  const { row, i } = receipt('f06-scope'); verify(row.receipt_id, obs(i));
  assert.equal(code(() => receipt('f06-scope', { claimed: U.tenantOwnerT1 })), 'G3A01');
  assert.equal(receipt('f06-scope', { claimed: U.bizOwnerB1 }).row.result, 'created');
  assert.equal(code(() => call('verify_ci_receipt', [T1, B1, row.receipt_id, 'simulated_fixture', obs(i), key('ver'), U.t2Owner], U.bizOwnerB1)), 'G3A01');
  assert.equal(code(() => call('bind_ci_receipt_to_readiness', [T1, B1, row.receipt_id, key('bind'), U.t2Owner], U.bizOwnerB1)), 'G3A01');
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.record_ci_receipt(${lit(T1)}, ${lit(B1)}, 'f06-scope', 'wf-1', '9', ${lit(urlOf('9'))}, ${lit(SHA1)}, 'completed', 'success', 'ci_isolated', 1, 'idem-noauth-0001')`, { role: 'c10g3_backend' })), 'G3A05');
  for (const sub of [U.t2Owner, U.investorB1, U.revokedB1, U.support, U.staffS1, U.bizOwnerB2]) {
    assert.equal(code(() => receipt('f06-scope', { sub })), 'G3A02', `record ${sub}`);
    assert.equal(code(() => verify(row.receipt_id, obs(i), 'simulated_fixture', sub)), 'G3A02', `verify ${sub}`);
    assert.equal(code(() => bind(row.receipt_id, sub)), 'G3A02', `bind ${sub}`);
    assert.equal(code(() => call('validate_ci_receipt_head', [T1, B1, row.receipt_id], sub, RD(sub))), 'G3A02', `validate ${sub}`);
    assert.deepEqual(rows(DB, 'select 1 from c10_gov003_demo.v_ci_receipts', RD(sub)), [], `view ${sub}`);
    assert.deepEqual(rows(DB, 'select 1 from c10_gov003_demo.v_ci_receipt_verifications', RD(sub)), [], `ver view ${sub}`);
    assert.equal(one(DB, 'select count(*) c from c10_gov003_demo.ci_receipts', RD(sub)).c, 0, `count ${sub}`);
  }
  assert.equal(code(() => receipt('f06-scope', { t: T2, sub: U.t2Owner })), 'G3A02');           // foreign feature scope
  assert.equal(code(() => receipt('f06-scope', { t: T2, sub: U.tenantOwnerT1 })), 'G3A02');
  assert.ok(Number(one(DB, 'select count(*) c from c10_gov003_demo.ci_receipts', RD(U.bizOwnerB1)).c) > 5);
});

test('f06 audit: every recorded receipt and verification is audited through gov003.ci with the evidence reference', () => {
  const rc = rows(DB, `select c.receipt_id, c.evidence_sha256, c.audit_receipt_id from c10_gov003_demo.v_ci_receipts c`, RD(U.bizOwnerB1));
  const ev = rows(DB, `select e.receipt_id, e.source_domain, e.action, e.payload from c10_gov003_demo.v_audit_events e where e.source_domain = 'gov003.ci'`, RD(U.bizOwnerB1));
  assert.ok(ev.length >= rc.length);
  for (const r of rc) {
    const hit = ev.find((e) => e.receipt_id === r.audit_receipt_id);
    assert.ok(hit, 'audit event for receipt'); assert.equal(hit.action, 'ci.receipt_recorded');
    assert.equal(hit.payload.evidence_ref, r.evidence_sha256); assert.equal(hit.payload.method, 'offline_fixture');
  }
  const actions = new Set(ev.map((e) => e.action));
  for (const a of ['ci.receipt_recorded', 'ci.receipt_verified', 'ci.receipt_bound']) assert.ok(actions.has(a), a);
  assert.equal(one(DB, `select ok from c10_gov003_demo.verify_chain(${lit(T1)}, ${lit(B1)})`, BE(U.bizOwnerB1)).ok, true);
  const c0 = cnt('audit_events');
  assert.equal(code(() => receipt('f06-scope', { url: 'http://x' })), 'G3A03');
  assert.equal(cnt('audit_events'), c0); // rejected command: no audit trace
});

test('f06 concurrency: two simultaneous identical receipts store exactly one', async () => {
  feature('f06-race'); head('f06-race', SHA1);
  const idem = key('race'); const rid = String(++runSeq);
  const sql = `select * from c10_gov003_demo.record_ci_receipt(${lit(T1)}, ${lit(B1)}, 'f06-race', 'wf-race', ${lit(rid)}, ${lit(urlOf(rid))}, ${lit(SHA1)}, 'completed', 'success', 'ci_isolated', 1, ${lit(idem)})`;
  const [x, y] = await Promise.all([execAsync(DB, sql, BE(U.bizOwnerB1)), execAsync(DB, sql, BE(U.bizOwnerB1))]);
  assert.ok(x.ok && y.ok);
  assert.deepEqual([x.out, y.out].map((o) => o.split('|')[0]).sort(), ['created', 'replayed']);
  assert.equal(one(DB, `select count(*) c from c10_gov003_demo.ci_receipts where idempotency_key = ${lit(idem)}`, OWN).c, 1);
  assert.equal(x.out.split('|')[1], y.out.split('|')[1]);
});

test('f06 privileges: writers are backend-only, SECURITY DEFINER owned by c10g3_owner with a pinned search_path', () => {
  const fns = rows(DB, `select p.proname, p.prosecdef, p.proconfig::text cfg, pg_get_userbyid(p.proowner) owner,
      has_function_privilege('c10g3_app', p.oid, 'execute') app, has_function_privilege('c10g3_reader', p.oid, 'execute') rd,
      has_function_privilege('c10g3_backend', p.oid, 'execute') be
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'c10_gov003_demo' and p.proname in ('record_ci_receipt','verify_ci_receipt','bind_ci_receipt_to_readiness','validate_ci_receipt_head','_f57_ci_trust','_f57_trust_label')`, OWN);
  assert.equal(fns.length, 6);
  for (const f of fns) { assert.equal(f.app, false); assert.equal(f.owner, 'c10g3_owner'); if (f.prosecdef) assert.match(f.cfg, /search_path=pg_catalog, c10_gov003_demo, pg_temp/); }
  for (const w of ['record_ci_receipt', 'verify_ci_receipt', 'bind_ci_receipt_to_readiness']) { const f = fns.find((x) => x.proname === w); assert.equal(f.be, true); assert.equal(f.rd, false); }
  for (const h of ['_f57_ci_trust', '_f57_trust_label']) { const f = fns.find((x) => x.proname === h); assert.equal(f.be, false); assert.equal(f.rd, false); }
});
