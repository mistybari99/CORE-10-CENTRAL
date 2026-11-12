// Features 05/06/07 Node evaluators + SQL/Node PARITY on shared fixture cases.
// Zero dependencies (node:test + the psql helper). Database names start with g3_f057_.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, dropDb, rows, one, exec, lit } from '../lib/db.mjs';
import { T1, B1, U } from '../lib/ids.mjs';
import {
  LEVELS, LEVEL_NAMES, deriveReadiness, validateProofInput, isCurrentHead, currentHead,
} from '../../../internal/gov003/server/readiness.mjs';
import {
  parseRunUrl, buildReceipt, canonicalJson, sha256Hex, receiptTrust, trustLabel, certifies, validateReceiptHead, assertCurrentHead,
  assertRemoteVerifierAdapter, validateObservation, compareReceiptToObservation, verifyReceiptWithAdapter,
  createSimulatedGithubAdapter, createUnavailableGithubAdapter, proofsForReceipt, ReceiptError,
} from '../../../internal/gov003/server/ci-receipt.mjs';
import { buildDeployment, evaluateProbe, certifyDeployment, probeEvidenceSha256, DeployError, PROBE_CODES } from '../../../internal/gov003/server/deploy-record.mjs';

const DB = 'g3_f057_parity';
const ONLY = ['000', '010', '020', '030', '040', '050', '060', '070'];
const BE = (sub) => ({ role: 'c10g3_backend', sub });
const RD = (sub) => ({ role: 'c10g3_reader', sub });
const OWN = { role: 'c10g3_owner' };
const A = 'a1'.repeat(20); const B = 'b2'.repeat(20); const C = 'c3'.repeat(20);
const SHAS = [A, B, C];
const EV = 'ee'.repeat(32);
const ART = 'c3d4'.repeat(16);
const code = (fn) => { try { fn(); } catch (e) { return e.code; } return null; };
const setGate = (g, on) => exec(DB, `update c10_gov003_demo.real_evidence_gates set enabled = ${on} where gate = ${lit(g)}`, OWN);
let n = 0;
const key = () => `parity-key-${String(++n).padStart(7, '0')}`;
const FN = 'c10_gov003_demo';

const ENV_FOR = { code_built: 'ci_isolated', isolated_test_pass: 'ci_isolated', signed_stage_verified: 'staging_signed', integrated_verified: 'integration' };

// ---------------------------------------------------------------------------- SQL script builders
const sqlRegister = (f) => `select ${FN}.register_readiness_feature(${lit(T1)}, ${lit(B1)}, ${lit(f)}, 'Parity ${f}', ${lit(key())});`;
const sqlHead = (f, sha) => `select ${FN}.record_readiness_head(${lit(T1)}, ${lit(B1)}, ${lit(f)}, ${lit(sha)}, ${lit(key())});`;
const sqlProof = (f, level, sha, env, sim, outcome) =>
  `select ${FN}.record_readiness_proof(${lit(T1)}, ${lit(B1)}, ${lit(f)}, ${lit(level)}, ${lit(sha)}, ${lit(env)}, 'run-parity', ${sim}, ${lit(EV)}, ${lit(outcome)}, ${lit(key())});`;
const sqlDeployCert = (f, env, sha, art) => `
  select ${FN}.record_deployment(${lit(T1)}, ${lit(B1)}, ${lit(f)}, ${lit(env)}, 'real', 'deployed', ${lit(sha)}, ${lit(art)}, 'build-${env}', null, now() - interval '2 hours', 'v1.0.0', 'ok', ${lit(key())});
  select ${FN}.record_runtime_probe(${lit(T1)}, ${lit(B1)}, (select deployment_id from ${FN}.deployments order by recorded_at desc limit 1), 'real', now() - interval '1 hour', ${lit(sha)}, ${lit(art)}, 'v1.0.0', 'ok', 200, ${lit(key())});
  select ${FN}.certify_deployment(${lit(T1)}, ${lit(B1)}, (select deployment_id from ${FN}.deployments order by recorded_at desc limit 1), (select probe_id from ${FN}.deployment_probes order by recorded_at desc limit 1), ${lit(key())});`;
const sqlRelease = (f, sha) => `select ${FN}.approve_release(${lit(T1)}, ${lit(B1)}, ${lit(f)}, ${lit(sha)}, 'rel-parity', ${lit(EV)}, ${lit(key())});`;

/** One session per case: all steps, then fetch SQL's derivation and the raw rows Node will re-derive. */
function runCase(feature, steps) {
  let sql = sqlRegister(feature);
  for (const s of steps) {
    if (s[0] === 'head') sql += sqlHead(feature, s[1]);
    else if (s[0] === 'proof') sql += sqlProof(feature, s[1], s[2], s[3] ?? ENV_FOR[s[1]], s[4] ?? false, s[5] ?? 'pass');
    else if (s[0] === 'deploy_cert') sql += sqlDeployCert(feature, s[1], s[2], s[3] ?? ART);
    else if (s[0] === 'release') sql += sqlRelease(feature, s[1]);
    else throw new Error(`unknown step ${s[0]}`);
  }
  exec(DB, sql, BE(U.bizOwnerB1));
  const sqlDerived = one(DB, `select ${FN}.derive_readiness(${lit(T1)}, ${lit(B1)}, ${lit(feature)}) d`, RD(U.bizOwnerB1)).d;
  const heads = rows(DB, `select head_seq, head_sha from ${FN}.v_readiness_heads where feature_id = ${lit(feature)}`, RD(U.bizOwnerB1));
  const proofs = rows(DB, `select level, commit_sha, outcome, simulated, audit_seq, proof_seq from ${FN}.v_readiness_proofs where feature_id = ${lit(feature)}`, RD(U.bizOwnerB1));
  return { sqlDerived, nodeDerived: deriveReadiness({ featureId: feature, heads, proofs }), heads, proofs };
}
const parity = (feature, steps) => {
  const r = runCase(feature, steps);
  assert.deepStrictEqual(r.nodeDerived, r.sqlDerived, `parity ${feature}`);
  return r.nodeDerived;
};

before(() => {
  freshDb(DB, { only: ONLY });
  for (const g of ['signed_gotrue', 'integration_env', 'runtime_probe']) setGate(g, true); // parity needs the real levels reachable
});
after(() => dropDb(DB));

// ---------------------------------------------------------------------------- readiness.mjs unit tests
test('node readiness: level table is ordered and matches the SQL reference data', () => {
  assert.deepEqual(LEVEL_NAMES, ['proposed', 'code_built', 'isolated_test_pass', 'signed_stage_verified', 'integrated_verified', 'deployed_verified', 'released']);
  const sql = rows(DB, `select level, rank, allowed_envs, allows_simulated, gate, dedicated_path from ${FN}.readiness_levels order by rank`, OWN);
  assert.equal(sql.length, LEVELS.length);
  sql.forEach((r, i) => {
    const l = LEVELS[i];
    assert.deepEqual([r.level, r.rank, r.allowed_envs, r.allows_simulated, r.gate, r.dedicated_path],
      [l.level, l.rank, l.envs, l.allowsSimulated, l.gate, l.dedicatedPath], l.level);
  });
});

test('node readiness Story C: green CI on SHA1, head SHA2, no signed GoTrue, no deployment => not certified / stale CI / staging missing / deployment unverified', () => {
  const proofs = [
    { level: 'code_built', commit_sha: A, outcome: 'pass', simulated: false, audit_seq: 3 },
    { level: 'isolated_test_pass', commit_sha: A, outcome: 'pass', simulated: false, audit_seq: 4 },
  ];
  const ok = deriveReadiness({ featureId: 'f', heads: [{ head_seq: 1, head_sha: A }], proofs });
  assert.equal(ok.state, 'isolated_test_pass');
  const d = deriveReadiness({ featureId: 'f', heads: [{ head_seq: 1, head_sha: A }, { head_seq: 2, head_sha: B }], proofs });
  assert.equal(d.state, 'proposed'); assert.equal(d.certified, false);
  for (const t of ['not certified', 'stale CI', 'staging missing', 'deployment unverified']) assert.ok(d.text.includes(t), t);
  assert.deepEqual(d.stale.map((s) => s.commit_sha), [A, A]);
  const e = deriveReadiness({ featureId: 'f', heads: [{ head_seq: 1, head_sha: A }, { head_seq: 2, head_sha: B }],
    proofs: [...proofs, { level: 'code_built', commit_sha: B, outcome: 'pass', simulated: true, audit_seq: 7 }, { level: 'isolated_test_pass', commit_sha: B, outcome: 'pass', simulated: true, audit_seq: 8 }] });
  assert.equal(e.state, 'isolated_test_pass'); assert.ok(e.text.includes('simulation only')); assert.ok(!e.text.includes('stale CI'));
  assert.equal(e.certified, false);
});

test('node readiness: there is no way to set a state — input shape carries only heads and proofs; unknown extras are ignored', () => {
  const d = deriveReadiness({ featureId: 'f', heads: [{ head_seq: 1, head_sha: A }], proofs: [], state: 'released', certified: true, green: true });
  assert.equal(d.state, 'proposed'); assert.equal(d.certified, false);
  assert.equal(currentHead([{ head_seq: 1, head_sha: A }, { head_seq: 3, head_sha: C }, { head_seq: 2, head_sha: B }]).head_sha, C);
  assert.equal(isCurrentHead([{ head_seq: 1, head_sha: A }], B), false);
  assert.equal(isCurrentHead([], A), false);
});

test('node readiness validateProofInput: simulated can never satisfy real levels; gates default closed; dedicated paths need dedicated writers', () => {
  const base = { level: 'signed_stage_verified', commit_sha: A, environment: 'staging_signed', run_ref: 'run-1', simulated: false, evidence_sha256: EV, outcome: 'pass' };
  assert.equal(validateProofInput(base).code, 'G3E01');
  assert.equal(validateProofInput(base, { gates: { signed_gotrue: true } }).ok, true);
  assert.equal(validateProofInput({ ...base, simulated: true }, { gates: { signed_gotrue: true } }).code, 'G3C02');
  assert.equal(validateProofInput({ ...base, level: 'deployed_verified', environment: 'staging' }).code, 'G3A03');
  assert.equal(validateProofInput({ ...base, level: 'released', environment: 'production' }).code, 'G3A03');
  assert.equal(validateProofInput({ ...base, commit_sha: A.toUpperCase() }).code, 'G3A03');
  assert.equal(validateProofInput({ ...base, level: 'code_built', environment: 'ci_isolated', simulated: true }).ok, true);
});

// ---------------------------------------------------------------------------- SQL / Node parity
test('parity: fixed fixture cases derive identical readiness in SQL and Node', () => {
  const cases = {
    'par-empty': [],
    'par-head-only': [['head', A]],
    'par-storyc-1': [['head', A], ['proof', 'code_built', A], ['proof', 'isolated_test_pass', A]],
    'par-storyc-2': [['head', A], ['proof', 'code_built', A], ['proof', 'isolated_test_pass', A], ['head', B]],
    'par-storyc-3': [['head', A], ['proof', 'code_built', A], ['proof', 'isolated_test_pass', A], ['head', B], ['proof', 'code_built', B, null, true], ['proof', 'isolated_test_pass', B, null, true]],
    'par-fail-after-pass': [['head', A], ['proof', 'code_built', A], ['proof', 'isolated_test_pass', A], ['proof', 'isolated_test_pass', A, null, false, 'fail']],
    'par-pass-after-fail': [['head', A], ['proof', 'code_built', A], ['proof', 'isolated_test_pass', A, null, false, 'fail'], ['proof', 'isolated_test_pass', A]],
    'par-noncontiguous': [['head', A], ['proof', 'integrated_verified', A]],
    'par-proofs-before-head': [['proof', 'code_built', A], ['head', B], ['head', A]],
    'par-multi-stale': [['head', A], ['proof', 'code_built', A], ['head', B], ['proof', 'code_built', B], ['proof', 'isolated_test_pass', B], ['head', C]],
    'par-stale-then-fail': [['head', A], ['proof', 'code_built', A], ['proof', 'code_built', A, null, false, 'fail'], ['head', B]],
    'par-mixed-sim': [['head', A], ['proof', 'code_built', A, null, true], ['proof', 'isolated_test_pass', A, null, false]],
    'par-to-integrated': [['head', A], ['proof', 'code_built', A], ['proof', 'isolated_test_pass', A], ['proof', 'signed_stage_verified', A], ['proof', 'integrated_verified', A]],
    'par-staging-deployed': [['head', A], ['proof', 'code_built', A], ['proof', 'isolated_test_pass', A], ['proof', 'signed_stage_verified', A], ['proof', 'integrated_verified', A], ['deploy_cert', 'staging', A]],
    'par-released': [['head', A], ['proof', 'code_built', A], ['proof', 'isolated_test_pass', A], ['proof', 'signed_stage_verified', A], ['proof', 'integrated_verified', A], ['deploy_cert', 'production', A], ['release', A]],
    'par-released-then-newhead': [['head', A], ['proof', 'code_built', A], ['proof', 'isolated_test_pass', A], ['proof', 'signed_stage_verified', A], ['proof', 'integrated_verified', A], ['deploy_cert', 'production', A], ['release', A], ['head', B]],
    'par-deployed-only': [['head', A], ['deploy_cert', 'staging', A]],
  };
  const out = {};
  for (const [f, steps] of Object.entries(cases)) out[f] = parity(f, steps);
  assert.equal(out['par-released'].state, 'released'); assert.equal(out['par-released'].certified, true);
  assert.equal(out['par-released-then-newhead'].state, 'proposed');
  assert.equal(out['par-staging-deployed'].state, 'deployed_verified');
  assert.equal(out['par-deployed-only'].state, 'proposed');
  assert.equal(out['par-noncontiguous'].state, 'proposed');
  assert.deepEqual(out['par-multi-stale'].stale.map((x) => `${x.level}:${x.commit_sha.slice(0, 2)}`), ['code_built:a1', 'code_built:b2', 'isolated_test_pass:b2']);
  assert.equal(out['par-stale-then-fail'].stale.length, 0);   // newest proof on the old sha is a fail: not a stale PASS
  assert.deepEqual(out['par-mixed-sim'].simulated_levels, ['code_built']);
  assert.ok(!out['par-mixed-sim'].text.includes('simulation only'));
});

test('parity: 60 seeded random proof/head sequences derive identically in SQL and Node', () => {
  let s = 20261112; // mulberry32
  const rnd = () => { s |= 0; s = (s + 0x6d2b79f5) | 0; let t = Math.imul(s ^ (s >>> 15), 1 | s); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const pick = (a) => a[Math.floor(rnd() * a.length)];
  const generic = ['code_built', 'isolated_test_pass', 'signed_stage_verified', 'integrated_verified'];
  for (let c = 0; c < 60; c++) {
    const steps = []; let cur = null; const len = 3 + Math.floor(rnd() * 9);
    for (let i = 0; i < len; i++) {
      if (rnd() < 0.28 || cur === null) { let sha = pick(SHAS); if (sha === cur) sha = SHAS[(SHAS.indexOf(sha) + 1) % 3]; steps.push(['head', sha]); cur = sha; }
      else {
        const level = pick(generic); const lowLevel = level === 'code_built' || level === 'isolated_test_pass';
        steps.push(['proof', level, rnd() < 0.75 ? cur : pick(SHAS), null, lowLevel && rnd() < 0.4, rnd() < 0.8 ? 'pass' : 'fail']);
      }
    }
    parity(`par-fuzz-${c}`, steps);
  }
});

test('parity: proof input validation codes agree between Node and SQL (gates closed and open)', () => {
  const f = 'par-validate';
  exec(DB, sqlRegister(f) + sqlHead(f, A), BE(U.bizOwnerB1));
  const inputs = [];
  for (const level of [...generic(), 'deployed_verified', 'released', 'proposed', 'bogus']) {
    for (const environment of ['local', 'ci_isolated', 'isolated_pg', 'staging_signed', 'integration', 'staging', 'production']) {
      for (const simulated of [false, true]) inputs.push({ level, environment, simulated });
    }
  }
  const variants = [{ commit_sha: A.toUpperCase() }, { commit_sha: A.slice(1) }, { evidence_sha256: 'zz' }, { run_ref: 'bad ref' }, { outcome: 'green' }];
  for (const v of variants) inputs.push({ level: 'code_built', environment: 'local', simulated: false, ...v });
  function generic() { return ['code_built', 'isolated_test_pass', 'signed_stage_verified', 'integrated_verified']; }
  for (const gatesOpen of [false, true]) {
    for (const g of ['signed_gotrue', 'integration_env', 'runtime_probe']) setGate(g, gatesOpen);
    const gates = { signed_gotrue: gatesOpen, integration_env: gatesOpen, runtime_probe: gatesOpen };
    for (const [i, inp] of inputs.entries()) {
      const p = { commit_sha: A, evidence_sha256: EV, run_ref: 'run-validate', outcome: 'pass', ...inp };
      const nodeRes = validateProofInput(p, { gates });
      const sqlCode = code(() => exec(DB, `select ${FN}.record_readiness_proof(${lit(T1)}, ${lit(B1)}, ${lit(f)}, ${lit(p.level)}, ${lit(p.commit_sha)}, ${lit(p.environment)}, ${lit(p.run_ref)}, ${p.simulated}, ${lit(p.evidence_sha256)}, ${lit(p.outcome)}, ${lit(key())});`, BE(U.bizOwnerB1)));
      assert.equal(sqlCode, nodeRes.ok ? null : nodeRes.code, `gates=${gatesOpen} #${i} ${JSON.stringify(inp)}`);
    }
  }
  for (const g of ['signed_gotrue', 'integration_env', 'runtime_probe']) setGate(g, true);
});

test('parity: Node probe verdicts and evidence hashes equal the SQL runtime-probe computation', () => {
  const f = 'par-probe'; exec(DB, sqlRegister(f) + sqlHead(f, A), BE(U.bizOwnerB1));
  const deployedAt = new Date(Date.now() - 2 * 3600e3).toISOString();
  const d = one(DB, `select * from ${FN}.record_deployment(${lit(T1)}, ${lit(B1)}, ${lit(f)}, 'production', 'real', 'deployed', ${lit(A)}, ${lit(ART)}, 'build-p', null, ${lit(deployedAt)}, 'v1.0.0', 'ok', ${lit(key())})`, BE(U.bizOwnerB1));
  const deployment = buildDeployment({ feature_id: f, environment: 'production', mode: 'real', deploy_status: 'deployed', source_commit: A, artifact_sha256: ART, build_ref: 'build-p',
    deployed_at: deployedAt, expected_version: 'v1.0.0', expected_health: 'ok' }, { gates: { runtime_probe: true } });
  const at = new Date(Date.now() - 3600e3).toISOString();
  const obs = { mode: 'real', observed_at: at, observed_source_commit: A, observed_artifact_sha256: ART, observed_version: 'v1.0.0', observed_health: 'ok', http_status: 200 };
  const variants = [{}, { observed_source_commit: B }, { observed_artifact_sha256: 'f0'.repeat(32) }, { observed_version: 'v2' }, { observed_health: 'degraded' }, { http_status: 500 },
    { observed_at: new Date(Date.now() - 3 * 3600e3).toISOString() }, { observed_source_commit: B, observed_version: 'v2', observed_health: 'down', http_status: 502 }];
  for (const v of variants) {
    const o = { ...obs, ...v };
    const nodeRes = evaluateProbe(deployment, o);
    const sqlRes = one(DB, `select * from ${FN}.record_runtime_probe(${lit(T1)}, ${lit(B1)}, ${lit(d.deployment_id)}, 'real', ${lit(o.observed_at)}, ${lit(o.observed_source_commit)}, ${lit(o.observed_artifact_sha256)}, ${lit(o.observed_version)}, ${lit(o.observed_health)}, ${o.http_status}, ${lit(key())})`, BE(U.bizOwnerB1));
    assert.equal(sqlRes.probe_result, nodeRes.result, JSON.stringify(v)); assert.deepEqual(sqlRes.mismatch_codes, nodeRes.mismatch_codes, JSON.stringify(v));
    const ev = one(DB, `select evidence_sha256 e from ${FN}.v_deployment_probes where probe_id = ${lit(sqlRes.probe_id)}`, RD(U.bizOwnerB1)).e;
    assert.equal(ev, probeEvidenceSha256(d.deployment_id, 'real', o));
  }
});

// ---------------------------------------------------------------------------- ci-receipt.mjs unit tests
const URL_OK = 'https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/123456789';
const rcptInput = (o = {}) => ({ feature_id: 'feat-1', head_sha: A, run_id: '123456789', run_url: URL_OK, workflow: 'c10-gov003-standalone-pg17',
  run_status: 'completed', conclusion: 'success', environment: 'ci_isolated', run_attempt: 1, ...o });

test('node ci-receipt: SHA / run-URL validation contract and immutable evidence reference', () => {
  assert.deepEqual(parseRunUrl(URL_OK), { ok: true, owner: 'mistybari99', repo: 'CORE-10-CENTRAL', repo_full: 'mistybari99/core-10-central', run_id: '123456789' });
  for (const bad of ['http://github.com/a/b/actions/runs/1', 'https://github.com/a/b/actions/runs/1?x=1', 'https://github.com/a/b/actions/runs/1#x', 'https://github.com/a/b/actions/runs/1/',
    'https://evil.example/a/b/actions/runs/1', 'https://github.com.evil.example/a/b/actions/runs/1', 'https://u@github.com/a/b/actions/runs/1', 'https://github.com/a/b/actions/runs/x', 'https://github.com/a/b/pull/1', '', null, 42]) {
    assert.equal(parseRunUrl(bad).ok, false, String(bad));
  }
  const r = buildReceipt(rcptInput());
  assert.match(r.evidence_sha256, /^[0-9a-f]{64}$/); assert.equal(r.trust, 'unverified'); assert.equal(r.trust_label, 'offline_fixture/unverified');
  assert.equal(r.evidence_sha256, sha256Hex(canonicalJson(r.receipt)));
  assert.equal(buildReceipt(rcptInput()).evidence_sha256, r.evidence_sha256);                  // deterministic
  assert.notEqual(buildReceipt(rcptInput({ head_sha: B })).evidence_sha256, r.evidence_sha256); // sha bound into the evidence
  for (const bad of [{ head_sha: A.toUpperCase() }, { head_sha: A.slice(1) }, { run_id: '5' }, { run_url: 'https://github.com/someone/else/actions/runs/123456789' }, { conclusion: null }, { run_status: 'queued' },
    { environment: 'moon' }, { workflow: 'a;b' }, { run_attempt: 0 }, { feature_id: 'bad id' }]) {
    assert.equal(code(() => buildReceipt(rcptInput(bad))), 'G3A03', JSON.stringify(bad));
  }
  assert.equal(canonicalJson({ b: 1, a: [true, null, 'x'] }), '{"a":[true,null,"x"],"b":1}');
  assert.throws(() => canonicalJson({ x: 1.5 }), ReceiptError);
});

test('node ci-receipt: a caller-supplied URL never certifies; stale-head validator rejects old SHA reuse', () => {
  const { receipt, evidence_sha256 } = buildReceipt(rcptInput());
  assert.equal(certifies(receiptTrust([])), false);
  assert.equal(certifies(receiptTrust([{ verifier_kind: 'simulated_fixture' }])), false);
  assert.equal(certifies(receiptTrust([{ verifier_kind: 'github_api' }])), true);
  assert.equal(trustLabel(receiptTrust([{ verifier_kind: 'simulated_fixture' }])), 'offline_fixture/simulated_verified');
  assert.equal(code(() => proofsForReceipt(receipt, 'unverified', evidence_sha256)), 'G3C02');
  const sim = proofsForReceipt(receipt, 'simulated_verified', evidence_sha256);
  assert.deepEqual(sim.map((p) => [p.level, p.simulated, p.outcome]), [['code_built', true, 'pass'], ['isolated_test_pass', true, 'pass']]);
  assert.ok(proofsForReceipt(receipt, 'verified', evidence_sha256).every((p) => p.simulated === false));
  assert.equal(code(() => proofsForReceipt({ ...receipt, run_status: 'queued', conclusion: null }, 'verified', evidence_sha256)), 'G3C02');
  assert.equal(code(() => proofsForReceipt({ ...receipt, environment: 'staging_signed' }, 'verified', evidence_sha256)), 'G3C02');
  assert.deepEqual(proofsForReceipt({ ...receipt, conclusion: 'failure' }, 'verified', evidence_sha256).map((p) => [p.level, p.outcome]), [['isolated_test_pass', 'fail']]);
  assert.deepEqual(validateReceiptHead(A, A), { current: true, stale: false, code: null });
  assert.deepEqual(validateReceiptHead(A, B), { current: false, stale: true, code: 'G3C01' });
  assert.equal(validateReceiptHead(A, null).stale, true);
  assert.equal(code(() => assertCurrentHead(A, B)), 'G3C01');
  assert.equal(assertCurrentHead(B, B).current, true);
});

test('node ci-receipt: remote GitHub verifier adapter contract with rejection tests', async () => {
  const { receipt } = buildReceipt(rcptInput());
  const obs = (o = {}) => ({ repo: receipt.repo, run_id: receipt.run_id, run_url: receipt.run_url, head_sha: A, workflow: receipt.workflow, run_status: 'completed', conclusion: 'success', observed_at: '2026-11-12T10:00:00.000Z', ...o });
  // adapter shape contract
  for (const bad of [null, {}, { kind: 'simulated_fixture' }, { kind: 'carrier', fetchRun: async () => ({}) }, { fetchRun: async () => ({}) }]) assert.throws(() => assertRemoteVerifierAdapter(bad), ReceiptError);
  // match via simulated adapter => simulated_verified, never remote_verified
  const sim = createSimulatedGithubAdapter({ [receipt.run_id]: obs() });
  const ok = await verifyReceiptWithAdapter(receipt, sim);
  assert.equal(ok.ok, true); assert.equal(ok.trust, 'simulated_verified'); assert.equal(certifies(ok.trust), false); assert.match(ok.remote_payload_sha256, /^[0-9a-f]{64}$/);
  // every mismatch is rejected
  const mism = { head_sha_mismatch: { head_sha: B }, conclusion_mismatch: { conclusion: 'failure' }, run_status_mismatch: { run_status: 'in_progress', conclusion: null },
    run_url_mismatch: { run_url: 'https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/999' }, run_id_mismatch: { run_id: '1' }, repo_mismatch: { repo: 'x/y' }, workflow_mismatch: { workflow: 'other' } };
  for (const [name, over] of Object.entries(mism)) {
    const r = await verifyReceiptWithAdapter(receipt, createSimulatedGithubAdapter({ [receipt.run_id]: obs(over) }));
    assert.equal(r.ok, false, name); assert.equal(r.rejected, 'mismatch', name); assert.ok(r.mismatches.includes(name), name);
  }
  assert.deepEqual(compareReceiptToObservation(receipt, obs({ head_sha: B, conclusion: 'failure', workflow: 'o' })), ['head_sha_mismatch', 'workflow_mismatch', 'conclusion_mismatch']);
  // malformed observation / missing fixture / extra fields are rejected, not trusted
  for (const badObs of [obs({ head_sha: 'ABC' }), obs({ observed_at: 'now' }), obs({ run_status: 'done' }), { ...obs(), extra: 1 }, 'not-an-object', null]) {
    const r = await verifyReceiptWithAdapter(receipt, { kind: 'simulated_fixture', fetchRun: async () => badObs });
    assert.equal(r.ok, false); assert.equal(r.rejected, 'malformed_observation');
  }
  assert.throws(() => validateObservation({ ...obs(), extra: 1 }), ReceiptError);
  assert.equal((await verifyReceiptWithAdapter(receipt, createSimulatedGithubAdapter({}))).rejected, 'malformed_observation');
  assert.equal((await verifyReceiptWithAdapter(receipt, { kind: 'simulated_fixture', fetchRun: async () => { throw new Error('boom'); } })).rejected, 'adapter_error');
  // the real adapter is NOT built here: it fails closed
  const real = await verifyReceiptWithAdapter(receipt, createUnavailableGithubAdapter());
  assert.equal(real.ok, false); assert.equal(real.rejected, 'unavailable');
  // the receipt URL itself is never consulted as proof: a receipt whose URL matches but whose remote head differs is rejected
  const fakeUrl = buildReceipt(rcptInput({ head_sha: C })).receipt;
  assert.equal((await verifyReceiptWithAdapter(fakeUrl, sim)).ok, false);
});

// ---------------------------------------------------------------------------- deploy-record.mjs unit tests
const depInput = (o = {}) => ({ feature_id: 'feat-1', environment: 'production', mode: 'real', deploy_status: 'deployed', source_commit: A, artifact_sha256: ART,
  build_ref: 'build-1', deployed_at: '2026-11-12T08:00:00.000Z', expected_version: 'v1.0.0', ...o });
const probeObs = (o = {}) => ({ mode: 'real', observed_at: '2026-11-12T08:10:00.000Z', observed_source_commit: A, observed_artifact_sha256: ART, observed_version: 'v1.0.0', observed_health: 'ok', http_status: 200, ...o });

test('node deploy-record: typed record validation, real mode fails closed, preview/queued/simulated never certify', () => {
  const gates = { runtime_probe: true };
  const real = buildDeployment(depInput(), { gates });
  assert.equal(real.mode, 'real'); assert.equal(real.expected_health, 'ok');
  assert.equal(code(() => buildDeployment(depInput())), 'G3E01');                                 // gate closed by default
  assert.equal(buildDeployment(depInput({ mode: 'simulated' })).mode, 'simulated');
  for (const bad of [{ source_commit: 'xyz' }, { artifact_sha256: 'abc' }, { environment: 'qa' }, { deploy_status: 'live' }, { deployed_at: null }, { deploy_status: 'queued' }, { expected_version: 'v 1' }, { expected_health: 'down' }, { build_ref: 'bad ref' }]) {
    assert.equal(code(() => buildDeployment(depInput(bad), { gates })), 'G3A03', JSON.stringify(bad));
  }
  assert.equal(code(() => buildDeployment(depInput({ deployed_at: new Date(Date.now() + 3600e3).toISOString() }), { gates })), 'G3A03');
  const pass = { ...probeObs(), ...evaluateProbe(real, probeObs()), evidence_sha256: EV };
  assert.equal(pass.result, 'pass');
  const cert = certifyDeployment({ deployment: real, probe: pass, currentHeadSha: A, gates });
  assert.deepEqual([cert.level, cert.simulated, cert.environment, cert.commit_sha], ['deployed_verified', false, 'production', A]);
  assert.equal(code(() => certifyDeployment({ deployment: real, probe: pass, currentHeadSha: A })), 'G3E01');
  assert.equal(code(() => certifyDeployment({ deployment: real, probe: pass, currentHeadSha: B, gates })), 'G3C01');   // stale head
  assert.equal(code(() => certifyDeployment({ deployment: real, probe: null, currentHeadSha: A, gates })), 'G3C02');     // no runtime smoke probe
  assert.equal(code(() => certifyDeployment({ deployment: { ...real, environment: 'preview' }, probe: pass, currentHeadSha: A, gates })), 'G3C02');
  assert.equal(code(() => certifyDeployment({ deployment: { ...real, deploy_status: 'queued' }, probe: pass, currentHeadSha: A, gates })), 'G3C02');
  assert.equal(code(() => certifyDeployment({ deployment: { ...real, mode: 'simulated' }, probe: { ...pass, mode: 'simulated' }, currentHeadSha: A, gates })), 'G3C02');
  assert.equal(code(() => certifyDeployment({ deployment: real, probe: { ...pass, result: 'fail', mismatch_codes: ['version_mismatch'] }, currentHeadSha: A, gates })), 'G3C02');
  assert.equal(code(() => evaluateProbe({ ...real, deploy_status: 'queued' }, probeObs())), 'G3C02');
  assert.equal(code(() => evaluateProbe(real, probeObs({ mode: 'simulated' }))), 'G3C02');
  assert.equal(code(() => evaluateProbe(real, probeObs({ http_status: 'ok' }))), 'G3A03');
});

test('node deploy-record: each probe mismatch code is reported in contract order', () => {
  const real = buildDeployment(depInput(), { gates: { runtime_probe: true } });
  const single = {
    probe_before_deploy: { observed_at: '2026-11-12T07:00:00.000Z' }, source_commit_mismatch: { observed_source_commit: B }, artifact_hash_mismatch: { observed_artifact_sha256: 'f0'.repeat(32) },
    version_mismatch: { observed_version: 'v9' }, health_not_ok: { observed_health: 'degraded' }, http_status_not_200: { http_status: 503 },
  };
  for (const [c, over] of Object.entries(single)) assert.deepEqual(evaluateProbe(real, probeObs(over)), { result: 'fail', mismatch_codes: [c] }, c);
  const all = evaluateProbe(real, probeObs({ observed_at: '2026-11-12T07:00:00.000Z', observed_source_commit: B, observed_artifact_sha256: 'f0'.repeat(32), observed_version: 'v9', observed_health: 'down', http_status: 500 }));
  assert.deepEqual(all.mismatch_codes, PROBE_CODES);
  assert.throws(() => evaluateProbe(real, probeObs({ observed_health: 'green' })), DeployError);
});
