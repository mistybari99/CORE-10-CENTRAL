import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, dropDb, rows, one, exec, lit } from '../lib/db.mjs';
import { T1, T2, B1, U } from '../lib/ids.mjs';
import { validateTrace } from '../../../internal/gov003/server/trace-graph.mjs';

const DB = 'g3_f12_trace';
const SHA1 = 'a'.repeat(40);
const SHA2 = 'b'.repeat(40);
const backend = (sub) => ({ role: 'c10g3_backend', sub });

const good = () => ({
  expected_requirement_count: 3,
  declared_requirement_ids: ['R1', 'R2', 'R3'],
  requirements: [
    { id: 'R1', status: 'built', hard: true },
    { id: 'R2', status: 'built', hard: true },
    { id: 'R3', status: 'deferred', hard: false, deferral_reason: 'needs signed GoTrue (blocked)' },
  ],
  features: [
    { id: 'F1', requirement_ids: ['R1'], head_sha: SHA1 },
    { id: 'F2', requirement_ids: ['R2'], head_sha: SHA1 },
  ],
  source_files: [{ path: 'internal/gov003/sql/030_append_event.sql', feature_id: 'F1' }, { path: 'internal/gov003/sql/040_observability.sql', feature_id: 'F2' }],
  tests: [{ id: 'T1', feature_id: 'F1', passed: true, commit_sha: SHA1 }, { id: 'T2', feature_id: 'F2', passed: true, commit_sha: SHA1 }],
  releases: [{ id: 'REL1', feature_ids: ['F1'], commit_sha: SHA1 }],
});
const mut = (fn) => { const s = good(); fn(s); return s; };

before(() => { freshDb(DB, { only: ['000', '010', '020', '030', '040', '120'] }); });
after(() => dropDb(DB));

const sqlViol = (snap) => rows(DB, `select code, subject, detail from c10_gov003_demo.validate_trace(${lit(JSON.stringify(snap))}::jsonb)`, backend(U.bizOwnerB1));
const sqlSummary = (snap) => one(DB, `select c10_gov003_demo.trace_summary(${lit(JSON.stringify(snap))}::jsonb) as s`, backend(U.bizOwnerB1)).s;

const cases = {
  good: [good(), []],
  orphanFeature: [mut((s) => s.features.push({ id: 'F9', requirement_ids: [] })), ['orphan_feature']],
  danglingRef: [mut((s) => s.features[0].requirement_ids.push('R404')), ['dangling_requirement_ref']],
  duplicateReq: [mut((s) => s.requirements.push({ id: 'R1', status: 'built' })), ['denominator_count_mismatch', 'duplicate_id']],
  duplicateFeature: [mut((s) => s.features.push({ id: 'F1', requirement_ids: ['R1'], head_sha: SHA1 })), ['duplicate_id']],
  hardRemovedFromDenominator: [mut((s) => { s.declared_requirement_ids.push('R4'); s.expected_requirement_count = 4; }), ['denominator_count_mismatch', 'requirement_removed_from_denominator']],
  silentlyDroppedRequirement: [mut((s) => { s.requirements = s.requirements.filter((r) => r.id !== 'R2'); s.features = s.features.filter((f) => f.id !== 'F2'); s.source_files.pop(); s.tests.pop(); }), ['denominator_count_mismatch', 'requirement_removed_from_denominator']],
  passingWithoutSha: [mut((s) => { delete s.tests[0].commit_sha; }), ['built_without_proof', 'passing_test_without_exact_sha']],
  passingWithShortSha: [mut((s) => { s.tests[0].commit_sha = 'abc123'; }), ['built_without_proof', 'passing_test_without_exact_sha']],
  staleSha: [mut((s) => { s.features[0].head_sha = SHA2; }), ['built_without_proof', 'stale_test_sha']],
  hardDeferredNoApproval: [mut((s) => { s.requirements[2].hard = true; }), ['hard_requirement_deferred']],
  deferralNoReason: [mut((s) => { delete s.requirements[2].deferral_reason; }), ['deferral_without_reason']],
  invalidStatus: [mut((s) => { s.requirements[2].status = 'done'; }), ['invalid_status']],
  orphanSource: [mut((s) => s.source_files.push({ path: 'x.js', feature_id: 'F404' })), ['orphan_source_file']],
  orphanTest: [mut((s) => s.tests.push({ id: 'T9', feature_id: 'F404', passed: false, commit_sha: SHA1 })), ['orphan_test']],
  orphanRelease: [mut((s) => s.releases.push({ id: 'REL2', feature_ids: ['F404'] })), ['orphan_release']],
  builtNoFeature: [mut((s) => { s.requirements.push({ id: 'R4', status: 'built' }); s.declared_requirement_ids.push('R4'); s.expected_requirement_count = 4; }), ['orphan_requirement']],
  undeclared: [mut((s) => { s.declared_requirement_ids = ['R1', 'R2']; }), ['undeclared_requirement']],
};

for (const [name, [snap, codes]] of Object.entries(cases)) {
  test(`f12 validator: ${name} (Node == SQL)`, () => {
    const node = validateTrace(snap);
    const sql = sqlViol(snap);
    assert.deepEqual(sql, node.violations, 'SQL and Node violation lists must be identical');
    assert.deepEqual([...new Set(node.violations.map((v) => v.code))].sort(), [...codes].sort());
    assert.deepEqual(sqlSummary(snap), node.summary);
  });
}

test('f12 summary: accounts for every requirement and reports chain completeness', () => {
  const s = validateTrace(good()).summary;
  assert.deepEqual(s, { requirements: 3, declared: 3, built: 2, deferred: 1, missing: 0, proposed: 0, complete_chains: 2, released: 1 });
});

test('f12 import: owner stores valid snapshot with receipt; replay returns the same snapshot', () => {
  const q = `select * from c10_gov003_demo.import_trace_snapshot('${T1}','${B1}',${lit(JSON.stringify(good()))}::jsonb,'local snapshot 1','trace-import-0001')`;
  const a = one(DB, q, backend(U.bizOwnerB1));
  assert.equal(a.verdict, 'valid'); assert.equal(a.replayed, false); assert.ok(a.receipt_id);
  const b = one(DB, q, backend(U.bizOwnerB1));
  assert.equal(b.replayed, true); assert.equal(b.snapshot_id, a.snapshot_id); assert.equal(b.receipt_id, a.receipt_id);
  assert.equal(one(DB, `select count(*)::int c from c10_gov003_demo.trace_snapshots`, { role: 'c10g3_owner' }).c, 1);
});

test('f12 import: invalid snapshot is stored as invalid evidence, never silently fixed', () => {
  const bad = cases.hardRemovedFromDenominator[0];
  const r = one(DB, `select * from c10_gov003_demo.import_trace_snapshot('${T1}','${B1}',${lit(JSON.stringify(bad))}::jsonb,'bad snapshot','trace-import-0002')`, backend(U.bizOwnerB1));
  assert.equal(r.verdict, 'invalid'); assert.ok(r.violation_count >= 2);
});

test('f12 import: same key with a changed snapshot conflicts', () => {
  const changed = mut((s) => { s.requirements[0].hard = false; });
  assert.throws(() => exec(DB, `select * from c10_gov003_demo.import_trace_snapshot('${T1}','${B1}',${lit(JSON.stringify(changed))}::jsonb,'x','trace-import-0001')`, backend(U.bizOwnerB1)), /G3C01/);
});

test('f12 import: investor, site staff, revoked, foreign tenant and unauthenticated are denied', () => {
  for (const sub of [U.investorB1, U.staffS1, U.revokedB1, U.t2Owner, U.support]) {
    assert.throws(() => exec(DB, `select * from c10_gov003_demo.import_trace_snapshot('${T1}','${B1}','{}'::jsonb,'x','trace-deny-${sub.slice(-2)}')`, backend(sub)), /G3A02/, sub);
  }
  assert.throws(() => exec(DB, `select * from c10_gov003_demo.import_trace_snapshot('${T1}','${B1}','{}'::jsonb,'x','trace-deny-none')`, { role: 'c10g3_backend' }), /G3A05/);
  assert.throws(() => exec(DB, `select * from c10_gov003_demo.import_trace_snapshot('${T2}','${B1}','{}'::jsonb,'x','trace-deny-x')`, backend(U.t2Owner)), /G3A02/);
});

test('f12 history: snapshots are append-only and scoped on read', () => {
  assert.throws(() => exec(DB, `update c10_gov003_demo.trace_snapshots set verdict = 'valid'`, { role: 'c10g3_owner' }), /G3H01/);
  assert.throws(() => exec(DB, `delete from c10_gov003_demo.trace_snapshots`, { role: 'c10g3_owner' }), /G3H01/);
  assert.equal(one(DB, `select count(*)::int c from c10_gov003_demo.v_trace_snapshots`, { role: 'c10g3_reader', sub: U.t2Owner }).c, 0);
  assert.equal(one(DB, `select count(*)::int c from c10_gov003_demo.v_trace_snapshots`, { role: 'c10g3_reader', sub: U.bizOwnerB1 }).c, 2);
  assert.equal(one(DB, `select ok from c10_gov003_demo.verify_chain('${T1}','${B1}')`, backend(U.bizOwnerB1)).ok, true);
});
