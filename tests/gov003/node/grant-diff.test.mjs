// GOV-003 feature 09: pure unit tests for internal/gov003/server/grant-diff.mjs (no database).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  canonicalJson, sha256Hex, snapshotDigest, normalizeSnapshot, flattenSnapshot, classifyFinding, diffSnapshots,
  verifyBaselineIntegrity, assertNoCallerSuppliedComparison, assertAdvisoryDiff, SNAPSHOT_FORMAT, DIFF_FORMAT,
} from '../../../internal/gov003/server/grant-diff.mjs';

const g = (grantee, privilege, grantable = false) => ({ grantee, privilege, grantable });
const mini = () => ({
  format: SNAPSHOT_FORMAT, schema: 'c10_gov003_demo',
  schema_privileges: [g('c10g3_backend', 'USAGE'), g('c10g3_owner', 'CREATE'), g('c10g3_owner', 'USAGE')],
  functions: [
    { signature: 'append_event(p_tenant uuid)', owner: 'c10g3_owner', security_definer: true, config: ['search_path=pg_catalog, c10_gov003_demo, pg_temp'], grants: [g('c10g3_backend', 'EXECUTE'), g('c10g3_owner', 'EXECUTE')] },
    { signature: 'g3_sha256(p text)', owner: 'c10g3_owner', security_definer: false, config: [], grants: [g('c10g3_owner', 'EXECUTE'), g('c10g3_reader', 'EXECUTE')] },
  ],
  relations: [
    { name: 'audit_events', kind: 'r', owner: 'c10g3_owner', rls_enabled: true, rls_forced: false, options: [], grants: [g('c10g3_owner', 'SELECT'), g('c10g3_reader', 'SELECT')],
      column_grants: [], triggers: [{ name: 'g3_no_update_delete', enabled: 'O', function: 'deny_mutation' }] },
    { name: 'v_audit_events', kind: 'v', owner: 'c10g3_owner', rls_enabled: false, rls_forced: false, options: ['security_invoker=true'], grants: [g('c10g3_reader', 'SELECT')], column_grants: [], triggers: [] },
  ],
  policies: [{ table: 'audit_events', name: 'audit_events_read', command: 'r', permissive: true, roles: ['c10g3_backend', 'c10g3_reader'], using: 'can_read_business(tenant_id, business_id)', check: null }],
});
const clone = (o) => JSON.parse(JSON.stringify(o));
const deepFreeze = (o) => { Object.values(o).forEach((v) => typeof v === 'object' && v && deepFreeze(v)); return Object.freeze(o); };
const rulesOf = (d) => d.findings.map((f) => f.rule);

test('canonicalJson: bytewise key order, no whitespace, integers only, stable unicode; sha256 known vector', () => {
  assert.equal(canonicalJson({ b: 1, a: [true, null, 'x'], 'é': 'é', B: 2 }), '{"B":2,"a":[true,null,"x"],"b":1,"é":"é"}');
  assert.equal(canonicalJson({ z: undefined, y: 'q"\\\n' }), '{"y":"q\\"\\\\\\n","z":null}');
  assert.throws(() => canonicalJson({ a: 1.5 }), /G3A03/);
  assert.equal(sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assert.equal(snapshotDigest(mini()), snapshotDigest(clone(mini())));
});

test('normalizeSnapshot validates, sorts every array bytewise, and never mutates its input', () => {
  const d = deepFreeze(mini());
  const n = normalizeSnapshot(d);
  assert.equal(canonicalJson(n), canonicalJson(d), 'already canonical');
  const shuffled = mini(); shuffled.functions.reverse(); shuffled.relations.reverse(); shuffled.schema_privileges.reverse();
  shuffled.policies[0].roles.reverse(); shuffled.functions[0].grants.reverse();
  assert.equal(canonicalJson(normalizeSnapshot(shuffled)), canonicalJson(n));
  assert.throws(() => normalizeSnapshot({ ...mini(), format: 'v0' }), /G3A03/);
  assert.throws(() => normalizeSnapshot({ ...mini(), policies: null }), /G3A03/);
  assert.throws(() => normalizeSnapshot(null), /G3A03/);
});

test('flattenSnapshot produces one stable key per grant / object / policy / trigger', () => {
  const m = flattenSnapshot(mini());
  assert.ok(m.has('schema_grant|c10g3_backend|USAGE'));
  assert.ok(m.has('function|append_event(p_tenant uuid)'));
  assert.ok(m.has('function_grant|append_event(p_tenant uuid)|c10g3_backend|EXECUTE'));
  assert.ok(m.has('relation|audit_events')); assert.ok(m.has('relation_grant|audit_events|c10g3_reader|SELECT'));
  assert.ok(m.has('trigger|audit_events|g3_no_update_delete')); assert.ok(m.has('policy|audit_events|audit_events_read'));
  assert.equal(m.size, 3 + 2 + 4 + 2 + 3 + 1 + 1);
});

test('identical snapshots: empty advisory diff in the versioned format', () => {
  const d = diffSnapshots(mini(), mini());
  assert.equal(d.format, DIFF_FORMAT); assert.equal(d.label, 'ADVISORY');
  assert.equal(d.finding_count, 0); assert.equal(d.max_severity, 'none'); assert.deepEqual(d.severity_counts, { high: 0, medium: 0, low: 0 });
  assert.equal(d.baseline_sha256, d.current_sha256);
});

test('unexpected GRANT: EXECUTE on a definer function to PUBLIC / app is HIGH advisory; INSERT on audit table to backend is HIGH', () => {
  const cur = mini();
  cur.functions[0].grants.push(g('PUBLIC', 'EXECUTE'), g('c10g3_app', 'EXECUTE'));
  cur.relations[0].grants.push(g('c10g3_backend', 'INSERT'));
  const d = diffSnapshots(mini(), cur);
  assert.equal(d.finding_count, 3); assert.equal(d.max_severity, 'high'); assert.deepEqual(d.severity_counts, { high: 3, medium: 0, low: 0 });
  assert.deepEqual(rulesOf(d), ['GP01_EXEC_PUBLIC_OR_APP', 'GP01_EXEC_PUBLIC_OR_APP', 'GP05_WRITE_GRANT_ADDED']);
  assert.deepEqual(d.findings.map((f) => f.key), [
    'function_grant|append_event(p_tenant uuid)|PUBLIC|EXECUTE',
    'function_grant|append_event(p_tenant uuid)|c10g3_app|EXECUTE',
    'relation_grant|audit_events|c10g3_backend|INSERT']);
  assert.ok(d.findings.every((f) => f.change === 'added' && f.baseline === null && f.current !== null));
  assert.equal(assertAdvisoryDiff(d), true);
});

test('permissive OR policy added is HIGH; restrictive policy added is LOW; permissive->restrictive swap and removal are classified', () => {
  const cur = mini();
  cur.policies.push({ table: 'audit_events', name: 'or_all', command: 'r', permissive: true, roles: ['PUBLIC'], using: 'true', check: null });
  assert.deepEqual(rulesOf(diffSnapshots(mini(), cur)), ['GP20_PERMISSIVE_POLICY_ADDED']);
  const cur2 = mini(); cur2.policies.push({ table: 'audit_events', name: 'only_r', command: 'r', permissive: false, roles: ['c10g3_reader'], using: 'true', check: null });
  const d2 = diffSnapshots(mini(), cur2);
  assert.deepEqual([d2.max_severity, rulesOf(d2)], ['low', ['GP21_RESTRICTIVE_POLICY_ADDED']]);
  const base3 = mini(); base3.policies.push({ ...cur2.policies[1] });
  assert.deepEqual(rulesOf(diffSnapshots(base3, mini())), ['GP22_RESTRICTIVE_POLICY_REMOVED']);
  const cur4 = clone(base3); cur4.policies[1].permissive = true;
  assert.deepEqual(rulesOf(diffSnapshots(base3, cur4)), ['GP25_POLICY_MADE_PERMISSIVE']);
  const cur5 = mini(); cur5.policies[0].using = 'true';
  assert.deepEqual(rulesOf(diffSnapshots(mini(), cur5)), ['GP24_POLICY_CHANGED']);
});

test('classifyFinding matrix: severity is advisory metadata only', () => {
  const cases = [
    ['function_grant', 'added', 'function_grant|f()|PUBLIC|EXECUTE', null, {}, false, ['high', 'GP01_EXEC_PUBLIC_OR_APP']],
    ['function_grant', 'added', 'function_grant|f()|c10g3_reader|EXECUTE', null, {}, true, ['high', 'GP02_EXEC_DEFINER_WIDENED']],
    ['function_grant', 'added', 'function_grant|f()|c10g3_reader|EXECUTE', null, {}, false, ['medium', 'GP03_EXEC_GRANT_ADDED']],
    ['function_grant', 'removed', 'function_grant|f()|c10g3_reader|EXECUTE', {}, null, false, ['low', 'GP04_GRANT_REMOVED']],
    ['relation_grant', 'added', 'relation_grant|t|c10g3_reader|DELETE', null, {}, null, ['high', 'GP05_WRITE_GRANT_ADDED']],
    ['relation_grant', 'added', 'relation_grant|t|PUBLIC|SELECT', null, {}, null, ['high', 'GP06_READ_GRANT_WIDENED']],
    ['relation_grant', 'added', 'relation_grant|t|c10g3_reader|SELECT', null, {}, null, ['medium', 'GP07_TABLE_GRANT_ADDED']],
    ['schema_grant', 'added', 'schema_grant|c10g3_x|CREATE', null, {}, null, ['high', 'GP08_SCHEMA_PRIVILEGE_WIDENED']],
    ['schema_grant', 'added', 'schema_grant|c10g3_x|USAGE', null, {}, null, ['medium', 'GP09_SCHEMA_GRANT_ADDED']],
    ['column_grant', 'added', 'column_grant|t|c|c10g3_x|UPDATE', null, {}, null, ['high', 'GP05_WRITE_GRANT_ADDED']],
    ['function', 'added', 'function|f()', null, { security_definer: true }, null, ['medium', 'GP15_DEFINER_FUNCTION_ADDED']],
    ['function', 'changed', 'function|f()', {}, {}, null, ['high', 'GP17_FUNCTION_ATTRIBUTE_CHANGED']],
    ['relation', 'changed', 'relation|t', { rls_enabled: true }, { rls_enabled: false }, null, ['high', 'GP12_RLS_DISABLED']],
    ['relation', 'changed', 'relation|v', { options: ['security_invoker=true'], rls_enabled: false }, { options: [], rls_enabled: false }, null, ['high', 'GP14_VIEW_INVOKER_LOST']],
    ['trigger', 'changed', 'trigger|t|x', { enabled: 'O' }, { enabled: 'D' }, null, ['high', 'GP31_TRIGGER_DISABLED']],
    ['trigger', 'removed', 'trigger|t|x', { enabled: 'O' }, null, null, ['high', 'GP30_TRIGGER_REMOVED']],
    ['mystery', 'added', 'mystery|x', null, {}, null, ['medium', 'GP99_UNCLASSIFIED']],
  ];
  for (const [type, change, key, b, c, def, want] of cases) assert.deepEqual(classifyFinding(type, change, key, b, c, def), want, `${type}/${change}/${key}`);
});

test('removed grants and objects are LOW advisory (loosening is more important than tightening)', () => {
  const cur = mini();
  cur.functions[1].grants = cur.functions[1].grants.filter((x) => x.grantee !== 'c10g3_reader');
  cur.functions = cur.functions.filter((f) => !f.signature.startsWith('append_event'));
  const d = diffSnapshots(mini(), cur);
  assert.equal(d.max_severity, 'low'); assert.ok(d.findings.every((f) => f.change === 'removed'));
});

test('diff is pure and deterministic: frozen inputs are untouched, findings are bytewise-sorted, input order is irrelevant', () => {
  const b = deepFreeze(mini()); const c0 = mini();
  c0.relations[0].grants.push(g('c10g3_backend', 'INSERT')); c0.functions[0].grants.push(g('PUBLIC', 'EXECUTE'));
  const c = deepFreeze(c0);
  const d1 = diffSnapshots(b, c); const d2 = diffSnapshots(b, c);
  assert.deepEqual(d1, d2);
  const keys = d1.findings.map((f) => f.key);
  assert.deepEqual(keys, [...keys].sort((x, y) => Buffer.compare(Buffer.from(x), Buffer.from(y))));
  const shuffled = clone(c0); shuffled.relations.reverse(); shuffled.functions.reverse();
  assert.deepEqual(diffSnapshots(b, shuffled).findings, d1.findings);
});

test('the module can only describe: a diff never carries SQL, and assertAdvisoryDiff rejects non-advisory documents', () => {
  const cur = mini(); cur.functions[0].grants.push(g('PUBLIC', 'EXECUTE'));
  const d = diffSnapshots(mini(), cur);
  assert.doesNotMatch(JSON.stringify(d), /\b(REVOKE|ALTER|CREATE POLICY|DROP POLICY)\b/);
  assert.equal(assertAdvisoryDiff(d), true);
  assert.throws(() => assertAdvisoryDiff({ ...d, label: 'ENFORCED' }), /ADVISORY/);
  assert.throws(() => assertAdvisoryDiff({ ...d, remediation: 'REVOKE ALL ON x FROM PUBLIC' }), /executable SQL/);
  assert.throws(() => assertAdvisoryDiff({ ...d, remediation: 'GRANT SELECT ON t TO x' }), /executable SQL/);
});

test('baseline integrity: only a stored, approved, receipted row whose inventory matches its digest counts; fabricated JSON does not', () => {
  const inv = mini();
  const row = { baseline_id: 'bl-1', approved_by: 'u-owner', receipt_id: 'r-1', inventory: inv, inventory_sha256: snapshotDigest(inv) };
  assert.deepEqual(verifyBaselineIntegrity(row), { ok: true, reasons: [] });
  const claimsClean = { ...row, inventory: { ...inv, policies: [] } };
  assert.deepEqual(verifyBaselineIntegrity(claimsClean), { ok: false, reasons: ['digest_mismatch'] });
  assert.deepEqual(verifyBaselineIntegrity({ ...row, approved_by: null, receipt_id: null }).reasons, ['missing_approved_by', 'missing_receipt']);
  assert.deepEqual(verifyBaselineIntegrity(inv), { ok: false, reasons: ['missing_baseline_id', 'missing_approved_by', 'missing_receipt', 'bad_format'] }, 'a bare inventory is not a baseline');
  assert.equal(verifyBaselineIntegrity(null).ok, false);
  assert.equal(verifyBaselineIntegrity({ ...row, inventory: { ...inv, format: 'v0' } }).ok, false);
});

test('API guard: caller-supplied baseline / diff / "no differences" claims are rejected before any comparison', () => {
  for (const k of ['baseline', 'baseline_json', 'inventory', 'diff', 'findings', 'policy_comparison', 'no_differences']) {
    assert.throws(() => assertNoCallerSuppliedComparison({ tenant_id: 't', [k]: {} }), /G3A03/, k);
  }
  assert.equal(assertNoCallerSuppliedComparison({ tenant_id: 't', business_id: 'b', baseline_id: 'x', idem: 'k' }), true);
  assert.equal(assertNoCallerSuppliedComparison(undefined), true);
});
