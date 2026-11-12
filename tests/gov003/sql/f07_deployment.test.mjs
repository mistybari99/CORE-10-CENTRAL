// Feature 07 deployment-provenance: deployed proof is separate from built/tested proof; preview / queued != deployed;
// runtime probe contract with mismatch rejection; real vs simulated explicit.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, dropDb, rows, one, exec, execAsync, lit } from '../lib/db.mjs';
import { T1, T2, B1, B2, U } from '../lib/ids.mjs';
import { probeEvidenceSha256 } from '../../../internal/gov003/server/deploy-record.mjs';

const DB = 'g3_f057_f07';
const ONLY = ['000', '010', '020', '030', '040', '050', '060', '070'];
const BE = (sub) => ({ role: 'c10g3_backend', sub });
const RD = (sub) => ({ role: 'c10g3_reader', sub });
const OWN = { role: 'c10g3_owner' };
const SHA1 = 'a1'.repeat(20); const SHA2 = 'b2'.repeat(20);
const ART = 'c3d4'.repeat(16); const ART2 = 'e5f6'.repeat(16);
const EV = (c) => c.repeat(64);
const DEPLOYED_AT = new Date(Date.now() - 2 * 3600e3).toISOString();
const PROBE_AT = new Date(Date.now() - 3600e3).toISOString();
let n = 0;
const key = (p = 'k') => `${p}-f07-${String(++n).padStart(6, '0')}`;
const arg = (v) => (v === null || v === undefined ? 'null' : typeof v === 'boolean' || typeof v === 'number' ? String(v) : typeof v === 'object' ? `${lit(JSON.stringify(v))}::jsonb` : lit(v));
const call = (fn, args, sub, ctx = null) => one(DB, `select * from c10_gov003_demo.${fn}(${args.map(arg).join(', ')})`, ctx ?? BE(sub));
const code = (fn) => { try { fn(); } catch (e) { return e.code; } return null; };
const setGate = (g, on) => exec(DB, `update c10_gov003_demo.real_evidence_gates set enabled = ${on} where gate = ${lit(g)}`, OWN);
const cnt = (tbl) => Number(one(DB, `select count(*) c from c10_gov003_demo.${tbl}`, OWN).c);

const feature = (f) => call('register_readiness_feature', [T1, B1, f, `Title ${f}`, key('reg')], U.bizOwnerB1);
const head = (f, sha) => call('record_readiness_head', [T1, B1, f, sha, key('head')], U.bizOwnerB1);
const proof = (f, level, sha, env, o = {}) => call('record_readiness_proof', [T1, B1, f, level, sha, env, 'run-0001', o.sim ?? false, EV('e'), 'pass', key('proof')], U.bizOwnerB1);
const derive = (f) => call('derive_readiness', [T1, B1, f], U.bizOwnerB1, RD(U.bizOwnerB1)).derive_readiness;
const dep = (f, o = {}) => call('record_deployment', [o.t ?? T1, o.b ?? B1, f, o.env ?? 'staging', o.mode ?? 'simulated', o.status ?? 'deployed',
  o.sha ?? SHA1, o.art ?? ART, o.build ?? 'build-0001', o.branch ?? null, o.at === undefined ? (o.status && o.status !== 'deployed' ? null : DEPLOYED_AT) : o.at,
  o.ver ?? 'v1.2.3', o.health ?? 'ok', o.idem ?? key('dep'), o.claimed ?? null], o.sub ?? U.bizOwnerB1);
const probe = (did, o = {}) => call('record_runtime_probe', [o.t ?? T1, o.b ?? B1, did, o.mode ?? 'simulated', o.at ?? PROBE_AT, o.sha ?? SHA1,
  o.art ?? ART, o.ver ?? 'v1.2.3', o.health ?? 'ok', o.http ?? 200, o.idem ?? key('probe'), o.claimed ?? null], o.sub ?? U.bizOwnerB1);
const certify = (did, pid, sub = U.bizOwnerB1, idem = key('cert'), claimed = null) => call('certify_deployment', [T1, B1, did, pid, idem, claimed], sub);
const release = (f, sha, sub = U.bizOwnerB1, idem = key('rel')) => call('approve_release', [T1, B1, f, sha, 'rel-run-0001', EV('d'), idem], sub);

before(() => { freshDb(DB, { only: ONLY }); });
after(() => dropDb(DB));

test('f07 positive: typed deployment record + probe contract; simulated vs real is explicit and replay is idempotent', () => {
  feature('f07-pos'); head('f07-pos', SHA1);
  const idem = key('dep');
  const d = dep('f07-pos', { idem, mode: 'simulated', env: 'staging' });
  assert.equal(d.result, 'created'); assert.equal(d.replayed, false);
  const v = one(DB, `select * from c10_gov003_demo.v_deployments where deployment_id = ${lit(d.deployment_id)}`, RD(U.bizOwnerB1));
  assert.equal(v.mode, 'simulated'); assert.equal(v.environment, 'staging'); assert.equal(v.deploy_status, 'deployed');
  assert.equal(v.source_commit, SHA1); assert.equal(v.artifact_sha256, ART); assert.equal(v.expected_version, 'v1.2.3');
  assert.equal(v.expected_health, 'ok'); assert.ok(v.deployed_at); assert.equal(v.is_current_head, true);
  assert.equal(v.has_passing_probe, false); assert.equal(v.runtime_verified, false);
  const r = dep('f07-pos', { idem, mode: 'simulated', env: 'staging' });
  assert.equal(r.replayed, true); assert.equal(r.deployment_id, d.deployment_id); assert.equal(r.audit_receipt_id, d.audit_receipt_id);
  assert.equal(code(() => dep('f07-pos', { idem, mode: 'simulated', env: 'staging', art: ART2 })), 'G3C01');
  assert.equal(code(() => dep('f07-pos', { idem, mode: 'simulated', env: 'production' })), 'G3C01');
  assert.equal(cnt('deployments'), 1);
  const p = probe(d.deployment_id, { mode: 'simulated' });
  assert.equal(p.result, 'created'); assert.equal(p.probe_result, 'pass'); assert.deepEqual(p.mismatch_codes, []);
  const pv = one(DB, `select * from c10_gov003_demo.v_deployment_probes where probe_id = ${lit(p.probe_id)}`, RD(U.bizOwnerB1));
  assert.equal(pv.mode, 'simulated'); assert.equal(pv.result, 'pass'); assert.equal(pv.observed_health, 'ok'); assert.equal(pv.http_status, 200);
  // evidence reference is the sha256 of the canonical observation: Node and SQL agree
  assert.equal(pv.evidence_sha256, probeEvidenceSha256(d.deployment_id, 'simulated', { observed_at: PROBE_AT, observed_source_commit: SHA1,
    observed_artifact_sha256: ART, observed_version: 'v1.2.3', observed_health: 'ok', http_status: 200 }));
  const pr = probe(d.deployment_id, { mode: 'simulated', idem: undefined });
  assert.equal(pr.result, 'created');
  // simulated evidence NEVER certifies and never moves readiness
  assert.equal(one(DB, `select has_passing_probe, runtime_verified from c10_gov003_demo.v_deployments where deployment_id = ${lit(d.deployment_id)}`, RD(U.bizOwnerB1)).runtime_verified, false);
  assert.equal(code(() => certify(d.deployment_id, p.probe_id)), 'G3C02');
  const s = derive('f07-pos');
  assert.equal(s.state, 'proposed'); assert.ok(s.text.includes('deployment unverified')); assert.equal(cnt('readiness_proofs'), 0);
  // a deployed probe replay returns the same probe; a changed observation under the same key conflicts
  const k = key('probe');
  const p1 = probe(d.deployment_id, { idem: k }); const p2 = probe(d.deployment_id, { idem: k });
  assert.equal(p2.replayed, true); assert.equal(p2.probe_id, p1.probe_id); assert.equal(p2.audit_receipt_id, p1.audit_receipt_id);
  assert.equal(code(() => probe(d.deployment_id, { idem: k, ver: 'v9.9.9' })), 'G3C01');
});

test('f07 negative: real mode fails closed in the isolated bed (no real runtime / probe)', () => {
  feature('f07-real'); head('f07-real', SHA1);
  assert.equal(code(() => dep('f07-real', { mode: 'real', env: 'production' })), 'G3E01');
  assert.equal(cnt('deployments') >= 1, true);
  const before = cnt('deployments');
  const sim = dep('f07-real', { mode: 'simulated', env: 'production' });
  assert.equal(cnt('deployments'), before + 1);
  assert.equal(code(() => probe(sim.deployment_id, { mode: 'real' })), 'G3C02'); // mode must equal deployment mode
  setGate('runtime_probe', true);
  const real = dep('f07-real', { mode: 'real', env: 'production' });                     // allowed only while the gate is open
  setGate('runtime_probe', false);
  assert.equal(code(() => probe(real.deployment_id, { mode: 'real' })), 'G3E01');
  const p = (() => { setGate('runtime_probe', true); try { return probe(real.deployment_id, { mode: 'real' }); } finally { setGate('runtime_probe', false); } })();
  assert.equal(p.probe_result, 'pass');
  assert.equal(code(() => certify(real.deployment_id, p.probe_id)), 'G3E01');           // gate closed again => no certification
  assert.equal(derive('f07-real').state, 'proposed');
});

test('f07 negative: preview branch / queued / building / failed deployments are never deployed-healthy without a runtime smoke probe', () => {
  feature('f07-prev'); head('f07-prev', SHA1);
  setGate('runtime_probe', true);
  try {
    const prev = dep('f07-prev', { mode: 'real', env: 'preview', branch: 'preview/feature-x', build: 'build-prev' });
    const pp = probe(prev.deployment_id, { mode: 'real' });
    assert.equal(pp.probe_result, 'pass');                                              // even a passing smoke probe of a preview...
    assert.equal(code(() => certify(prev.deployment_id, pp.probe_id)), 'G3C02');        // ...is not deployed proof
    assert.equal(one(DB, `select runtime_verified, has_passing_probe from c10_gov003_demo.v_deployments where deployment_id = ${lit(prev.deployment_id)}`, RD(U.bizOwnerB1)).runtime_verified, false);
    for (const status of ['queued', 'building', 'failed']) {
      const q = dep('f07-prev', { mode: 'real', env: 'staging', status, at: null });
      assert.equal(code(() => probe(q.deployment_id, { mode: 'real' })), 'G3C02', `probe ${status}`);
      assert.equal(code(() => certify(q.deployment_id, pp.probe_id)), 'G3C02', `certify ${status} with another deployment's probe`);
      assert.equal(code(() => certify(q.deployment_id, '00000000-0000-4000-8000-000000000000')), 'G3C02', `certify ${status} without a probe`);
    }
    // deployed status requires deployed_at and vice versa
    assert.equal(code(() => dep('f07-prev', { mode: 'real', status: 'queued', at: DEPLOYED_AT })), 'G3A03');
    assert.equal(code(() => dep('f07-prev', { mode: 'real', status: 'deployed', at: null })), 'G3A03');
    // no probe at all
    const bare = dep('f07-prev', { mode: 'real', env: 'staging' });
    assert.equal(code(() => certify(bare.deployment_id, '00000000-0000-4000-8000-000000000000')), 'G3C02');
    // generic proof writer cannot fabricate a deployed proof; a queued/preview state stays "deployment unverified"
    assert.equal(code(() => proof('f07-prev', 'deployed_verified', SHA1, 'staging')), 'G3A03');
    const d = derive('f07-prev');
    assert.equal(d.state, 'proposed'); assert.ok(d.text.includes('deployment unverified')); assert.equal(cnt('readiness_proofs'), 0);
  } finally { setGate('runtime_probe', false); }
});

test('f07 probe contract: expected source hash / version / health mismatches are computed server-side and REJECT certification', () => {
  feature('f07-mm'); head('f07-mm', SHA1);
  setGate('runtime_probe', true);
  try {
    const d = dep('f07-mm', { mode: 'real', env: 'staging' });
    const cases = {
      source_commit_mismatch: { sha: SHA2 }, artifact_hash_mismatch: { art: ART2 }, version_mismatch: { ver: 'v0.0.1' },
      health_not_ok: { health: 'degraded' }, http_status_not_200: { http: 503 },
      probe_before_deploy: { at: new Date(new Date(DEPLOYED_AT).getTime() - 60e3).toISOString() },
    };
    for (const [c, over] of Object.entries(cases)) {
      const p = probe(d.deployment_id, { mode: 'real', ...over });
      assert.equal(p.probe_result, 'fail', c); assert.deepEqual(p.mismatch_codes, [c], c);
      assert.equal(code(() => certify(d.deployment_id, p.probe_id)), 'G3C02', c);
    }
    const all = probe(d.deployment_id, { mode: 'real', sha: SHA2, art: ART2, ver: 'x', health: 'down', http: 500 });
    assert.deepEqual(all.mismatch_codes, ['source_commit_mismatch', 'artifact_hash_mismatch', 'version_mismatch', 'health_not_ok', 'http_status_not_200']);
    assert.equal(one(DB, `select has_passing_probe, runtime_verified from c10_gov003_demo.v_deployments where deployment_id = ${lit(d.deployment_id)}`, RD(U.bizOwnerB1)).has_passing_probe, false);
    // result cannot be supplied by the caller: the function has no result parameter, and the table forbids lying rows
    assert.equal(code(() => exec(DB, `select set_config('c10_gov003.writer','append_path',false);
      insert into c10_gov003_demo.deployment_probes (tenant_id, business_id, deployment_id, mode, observed_at, observed_source_commit,
        observed_artifact_sha256, observed_version, observed_health, http_status, result, mismatch_codes, evidence_sha256, recorded_by, idempotency_key, audit_receipt_id)
      select tenant_id, business_id, deployment_id, mode, observed_at, observed_source_commit, observed_artifact_sha256, observed_version,
             'down', 500, 'pass', '{source_commit_mismatch}', evidence_sha256, recorded_by, 'forged-probe-0001', audit_receipt_id
        from c10_gov003_demo.deployment_probes limit 1`, OWN)), '23514');
    // malformed probe observations
    for (const bad of [{ sha: 'zz' }, { art: 'abc' }, { ver: 'bad version!' }, { health: 'green' }, { http: 99 }, { http: 700 }, { mode: 'maybe' }, { idem: 'x' }]) {
      assert.equal(code(() => probe(d.deployment_id, { mode: 'real', ...bad })), 'G3A03', JSON.stringify(bad));
    }
    assert.equal(code(() => probe(d.deployment_id, { mode: 'real', at: new Date(Date.now() + 3600e3).toISOString() })), 'G3A03');
    assert.equal(code(() => probe('00000000-0000-4000-8000-000000000000', { mode: 'real' })), 'G3C02');
    // a later PASSING probe is separate evidence and certifies
    const ok = probe(d.deployment_id, { mode: 'real' });
    assert.equal(ok.probe_result, 'pass');
    assert.equal(certify(d.deployment_id, ok.probe_id).result, 'created');
  } finally { setGate('runtime_probe', false); }
});

test('f07 full real ladder (future adapters simulated by opening gates): deployed proof is separate; staging cannot release; production can; new head makes it stale', () => {
  const f = 'f07-ladder'; feature(f); head(f, SHA1);
  for (const g of ['signed_gotrue', 'integration_env', 'runtime_probe']) setGate(g, true);
  try {
    // deployed proof alone does not lift the ladder (built/tested proof is a SEPARATE requirement)
    const stg = dep(f, { mode: 'real', env: 'staging', build: 'build-stg' });
    const sp = probe(stg.deployment_id, { mode: 'real' });
    const cIdem = key('cert');
    const c1 = certify(stg.deployment_id, sp.probe_id, U.bizOwnerB1, cIdem);
    assert.equal(c1.readiness.state, 'proposed');
    assert.deepEqual(c1.readiness.satisfied_levels, ['deployed_verified']);
    for (const t of ['isolated tests missing', 'staging missing', 'integration missing']) assert.ok(c1.readiness.text.includes(t), t);
    const dp = one(DB, `select level, environment, run_ref, source_kind, source_id, simulated, evidence_sha256, commit_sha from c10_gov003_demo.v_readiness_proofs where proof_id = ${lit(c1.proof_id)}`, RD(U.bizOwnerB1));
    assert.equal(dp.level, 'deployed_verified'); assert.equal(dp.environment, 'staging'); assert.equal(dp.run_ref, 'build-stg');
    assert.equal(dp.source_kind, 'deployment_probe'); assert.equal(dp.source_id, sp.probe_id); assert.equal(dp.simulated, false);
    assert.equal(dp.commit_sha, SHA1); assert.equal(dp.evidence_sha256, one(DB, `select evidence_sha256 e from c10_gov003_demo.v_deployment_probes where probe_id = ${lit(sp.probe_id)}`, RD(U.bizOwnerB1)).e);
    assert.equal(code(() => certify(stg.deployment_id, sp.probe_id)), 'G3C01');                       // one probe, one proof
    const rep = certify(stg.deployment_id, sp.probe_id, U.bizOwnerB1, cIdem);
    assert.equal(rep.replayed, true); assert.equal(rep.proof_id, c1.proof_id); assert.equal(rep.audit_receipt_id, c1.audit_receipt_id);
    // build the rest of the ladder
    proof(f, 'code_built', SHA1, 'ci_isolated'); proof(f, 'isolated_test_pass', SHA1, 'ci_isolated');
    proof(f, 'signed_stage_verified', SHA1, 'staging_signed'); proof(f, 'integrated_verified', SHA1, 'integration');
    const mid = derive(f);
    assert.equal(mid.state, 'deployed_verified'); assert.deepEqual(mid.missing_proofs, ['released']);
    // a staging runtime proof cannot be released
    assert.equal(code(() => release(f, SHA1)), 'G3C02');
    // production deployment of the same head
    const prod = dep(f, { mode: 'real', env: 'production', build: 'build-prod', art: ART2 });
    const pp = probe(prod.deployment_id, { mode: 'real', art: ART2 });
    certify(prod.deployment_id, pp.probe_id);
    // owner approval; non-owners cannot
    assert.equal(code(() => release(f, SHA1, U.investorB1)), 'G3A02');
    assert.equal(code(() => release(f, SHA1, U.staffS1)), 'G3A02');
    assert.equal(code(() => release(f, SHA2)), 'G3C01');
    const rel = release(f, SHA1, U.tenantOwnerT1);
    assert.equal(rel.result, 'created'); assert.equal(rel.readiness.state, 'released'); assert.equal(rel.readiness.certified, true);
    assert.ok(!rel.readiness.text.includes('not certified')); assert.deepEqual(rel.readiness.missing_proofs, []);
    // new source HEAD: nothing carries over
    head(f, SHA2);
    const stale = derive(f);
    assert.equal(stale.state, 'proposed'); assert.equal(stale.certified, false);
    assert.ok(stale.text.includes('stale CI')); assert.ok(stale.text.includes('stale evidence'));
    assert.equal(stale.stale.length, 6);
    // a deployment of the OLD commit cannot certify the new head
    const old = dep(f, { mode: 'real', env: 'production', sha: SHA1, build: 'build-old', art: ART });
    const op = probe(old.deployment_id, { mode: 'real', sha: SHA1 });
    assert.equal(code(() => certify(old.deployment_id, op.probe_id)), 'G3C01');
  } finally { for (const g of ['signed_gotrue', 'integration_env', 'runtime_probe']) setGate(g, false); }
});

test('f07 negative: deployment and probe rows are immutable', () => {
  for (const tbl of ['deployments', 'deployment_probes']) {
    assert.equal(code(() => exec(DB, `update c10_gov003_demo.${tbl} set tenant_id = tenant_id`, OWN)), 'G3H01', tbl);
    assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.${tbl}`, OWN)), 'G3H01', tbl);
    assert.equal(code(() => exec(DB, `truncate c10_gov003_demo.${tbl} cascade`, OWN)), 'G3H01', tbl);
    assert.equal(code(() => exec(DB, `update c10_gov003_demo.${tbl} set tenant_id = tenant_id`, BE(U.bizOwnerB1))), '42501');
    assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.${tbl}`, BE(U.bizOwnerB1))), '42501');
    assert.equal(code(() => exec(DB, `insert into c10_gov003_demo.${tbl} (tenant_id, business_id) values (${lit(T1)}, ${lit(B1)})`, OWN)), 'G3H01');
  }
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.deployment_probes set result = 'pass', mismatch_codes = '{}'`, OWN)), 'G3H01');
});

test('f07 negative: forged actor, foreign tenant, investor, revoked, support and site-only identities are denied; no cross-tenant counts', () => {
  feature('f07-scope'); head('f07-scope', SHA1);
  const d = dep('f07-scope'); const p = probe(d.deployment_id);
  assert.equal(code(() => dep('f07-scope', { claimed: U.tenantOwnerT1 })), 'G3A01');
  assert.equal(code(() => probe(d.deployment_id, { claimed: U.t2Owner })), 'G3A01');
  assert.equal(code(() => certify(d.deployment_id, p.probe_id, U.bizOwnerB1, key('cert'), U.t2Owner)), 'G3A01');
  assert.equal(dep('f07-scope', { claimed: U.bizOwnerB1 }).result, 'created');
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.record_runtime_probe(${lit(T1)}, ${lit(B1)}, ${lit(d.deployment_id)}, 'simulated', ${lit(PROBE_AT)}, ${lit(SHA1)}, ${lit(ART)}, 'v1.2.3', 'ok', 200, 'idem-noauth-0001')`, { role: 'c10g3_backend' })), 'G3A05');
  for (const sub of [U.t2Owner, U.investorB1, U.revokedB1, U.support, U.staffS1, U.bizOwnerB2]) {
    assert.equal(code(() => dep('f07-scope', { sub })), 'G3A02', `dep ${sub}`);
    assert.equal(code(() => probe(d.deployment_id, { sub })), 'G3A02', `probe ${sub}`);
    assert.equal(code(() => certify(d.deployment_id, p.probe_id, sub)), 'G3A02', `certify ${sub}`);
    assert.deepEqual(rows(DB, 'select 1 from c10_gov003_demo.v_deployments', RD(sub)), [], `view ${sub}`);
    assert.deepEqual(rows(DB, 'select 1 from c10_gov003_demo.v_deployment_probes', RD(sub)), [], `pview ${sub}`);
    assert.equal(one(DB, 'select count(*) c from c10_gov003_demo.deployments', RD(sub)).c, 0, `count ${sub}`);
    assert.equal(one(DB, 'select count(*) c from c10_gov003_demo.deployment_probes', RD(sub)).c, 0, `pcount ${sub}`);
  }
  assert.equal(code(() => dep('f07-scope', { t: T2, sub: U.t2Owner })), 'G3A02');   // T1 feature through the T2 tenant
  assert.equal(code(() => dep('f07-scope', { t: T2, sub: U.tenantOwnerT1 })), 'G3A02');
  // a probe of a deployment in another business/tenant is not found through the caller's own scope
  assert.equal(code(() => probe(d.deployment_id, { b: B2, sub: U.bizOwnerB2 })), 'G3C02');
  assert.equal(code(() => call('certify_deployment', [T1, B2, d.deployment_id, p.probe_id, key('cert')], U.bizOwnerB2)), 'G3C02');
  // input validation
  for (const bad of [{ sha: 'A'.repeat(40) }, { art: 'abc' }, { env: 'qa' }, { mode: 'live' }, { status: 'done' }, { ver: 'v 1' }, { health: 'down' },
    { build: 'bad build' }, { branch: 'x y' }, { idem: 'short' }, { at: new Date(Date.now() + 3600e3).toISOString() }]) {
    assert.equal(code(() => dep('f07-scope', bad)), 'G3A03', JSON.stringify(bad));
  }
  assert.equal(code(() => dep('no-such-feature')), 'G3C02');
});

test('f07 audit: every deployment, probe and certification is audited via gov003.deploy and the chain verifies', () => {
  const ev = rows(DB, `select source_domain, action, payload from c10_gov003_demo.v_audit_events where source_domain = 'gov003.deploy'`, RD(U.bizOwnerB1));
  const actions = new Set(ev.map((e) => e.action));
  for (const a of ['deploy.recorded', 'deploy.probe_recorded', 'deploy.certified']) assert.ok(actions.has(a), a);
  const rec = ev.find((e) => e.action === 'deploy.recorded');
  assert.match(rec.payload.artifact_sha256, /^[0-9a-f]{64}$/); assert.match(rec.payload.commit_sha, /^[0-9a-f]{40}$/);
  assert.ok(['simulated', 'real'].includes(rec.payload.method)); assert.ok(['preview', 'staging', 'production'].includes(rec.payload.detail_code));
  assert.equal(cnt('deployments'), Number(rows(DB, `select count(*) c from c10_gov003_demo.audit_events where action = 'deploy.recorded'`, OWN)[0].c));
  assert.equal(one(DB, `select ok from c10_gov003_demo.verify_chain(${lit(T1)}, ${lit(B1)})`, BE(U.bizOwnerB1)).ok, true);
  const a0 = cnt('audit_events'); const d0 = cnt('deployments');
  assert.equal(code(() => dep('f07-scope', { sha: 'nope' })), 'G3A03');
  assert.equal(code(() => dep('f07-scope', { mode: 'real' })), 'G3E01');
  assert.equal(cnt('audit_events'), a0); assert.equal(cnt('deployments'), d0);
});

test('f07 concurrency: two simultaneous identical probes store exactly one', async () => {
  feature('f07-race'); head('f07-race', SHA1);
  const d = dep('f07-race'); const idem = key('race');
  const sql = `select * from c10_gov003_demo.record_runtime_probe(${lit(T1)}, ${lit(B1)}, ${lit(d.deployment_id)}, 'simulated', ${lit(PROBE_AT)}, ${lit(SHA1)}, ${lit(ART)}, 'v1.2.3', 'ok', 200, ${lit(idem)})`;
  const [x, y] = await Promise.all([execAsync(DB, sql, BE(U.bizOwnerB1)), execAsync(DB, sql, BE(U.bizOwnerB1))]);
  assert.ok(x.ok && y.ok);
  assert.deepEqual([x.out, y.out].map((o) => o.split('|')[0]).sort(), ['created', 'replayed']);
  assert.equal(one(DB, `select count(*) c from c10_gov003_demo.deployment_probes where idempotency_key = ${lit(idem)}`, OWN).c, 1);
});

test('f07 privileges: writers backend-only; app role has nothing; definer functions pinned', () => {
  const fns = rows(DB, `select p.proname, p.prosecdef, p.proconfig::text cfg, pg_get_userbyid(p.proowner) owner,
      has_function_privilege('c10g3_app', p.oid, 'execute') app, has_function_privilege('c10g3_reader', p.oid, 'execute') rd,
      has_function_privilege('c10g3_backend', p.oid, 'execute') be
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'c10_gov003_demo' and p.proname in ('record_deployment','record_runtime_probe','certify_deployment')`, OWN);
  assert.equal(fns.length, 3);
  for (const f of fns) { assert.equal(f.app, false); assert.equal(f.rd, false); assert.equal(f.be, true); assert.equal(f.owner, 'c10g3_owner'); assert.equal(f.prosecdef, true); assert.match(f.cfg, /search_path=pg_catalog, c10_gov003_demo, pg_temp/); }
  assert.equal(code(() => call('record_deployment', [T1, B1, 'f07-scope', 'staging', 'simulated', 'deployed', SHA1, ART, 'b', null, DEPLOYED_AT, 'v1', 'ok', key('dep')], U.bizOwnerB1, RD(U.bizOwnerB1))), '42501');
  assert.equal(code(() => call('certify_deployment', [T1, B1, '00000000-0000-4000-8000-000000000000', '00000000-0000-4000-8000-000000000000', key('cert')], U.bizOwnerB1, { role: 'c10g3_app', sub: U.bizOwnerB1 })), '42501');
});
