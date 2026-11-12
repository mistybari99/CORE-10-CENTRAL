// GOV-003 feature 09: pure, zero-dependency functions over a normalized, versioned catalog snapshot.
// DEMO / NOT LIVE contract. Mirrors the SQL comparator in internal/gov003/sql/090_grant_review.sql
// (_catalog_facts, _finding_class, catalog_diff); a parity test keeps the two in lock-step.
//
// This module is READ-ONLY by construction: it never builds, emits or executes GRANT/REVOKE/ALTER/
// CREATE POLICY. Findings are ADVISORY prompts for human review, never verdicts or automatic actions.
import { createHash } from 'node:crypto';

export const SNAPSHOT_FORMAT = 'g3cat-v1';
export const DIFF_FORMAT = 'g3catdiff-v1';
export const SEVERITY_ORDER = Object.freeze({ none: 0, low: 1, medium: 2, high: 3 });

/** Names a caller must never be able to supply: the baseline/diff is always the STORED, owner-approved one. */
export const CALLER_SUPPLIED_COMPARISON_KEYS = Object.freeze([
  'baseline', 'baseline_json', 'baseline_inventory', 'inventory', 'diff', 'findings', 'policy_comparison',
  'comparison', 'expected_catalog', 'no_differences',
]);

const bytewise = (a, b) => Buffer.compare(Buffer.from(String(a)), Buffer.from(String(b)));

export class GrantDiffError extends Error {
  constructor(code, message) { super(`${code}: ${message}`); this.code = code; }
}

/** Canonical JSON: keys sorted bytewise, no whitespace, integers only. Same bytes as canonical_json() in SQL. */
export function canonicalJson(v) {
  if (v === null || v === undefined) return 'null';
  switch (typeof v) {
    case 'string': return JSON.stringify(v);
    case 'boolean': return v ? 'true' : 'false';
    case 'number':
      if (!Number.isInteger(v)) throw new GrantDiffError('G3A03', 'non-integer number not allowed in canonical JSON');
      return String(v);
    case 'object':
      if (Array.isArray(v)) return `[${v.map(canonicalJson).join(',')}]`;
      return `{${Object.keys(v).sort(bytewise).map((k) => `${JSON.stringify(k)}:${canonicalJson(v[k])}`).join(',')}}`;
    default: throw new GrantDiffError('G3A03', `unsupported value type ${typeof v}`);
  }
}
export const sha256Hex = (s) => createHash('sha256').update(s, 'utf8').digest('hex');
export const snapshotDigest = (doc) => sha256Hex(canonicalJson(doc));

const grantSort = (a, b) => bytewise(a.grantee, b.grantee) || bytewise(a.privilege, b.privilege);

/** Validate the shape and return a deep-cloned snapshot with every array in canonical (bytewise) order. */
export function normalizeSnapshot(doc) {
  if (!doc || typeof doc !== 'object' || doc.format !== SNAPSHOT_FORMAT) {
    throw new GrantDiffError('G3A03', `snapshot format must be ${SNAPSHOT_FORMAT}`);
  }
  for (const k of ['schema_privileges', 'functions', 'relations', 'policies']) {
    if (!Array.isArray(doc[k])) throw new GrantDiffError('G3A03', `snapshot.${k} must be an array`);
  }
  const clone = JSON.parse(JSON.stringify(doc));
  clone.schema_privileges.sort(grantSort);
  clone.functions.sort((a, b) => bytewise(a.signature, b.signature));
  for (const f of clone.functions) { f.grants = (f.grants ?? []).sort(grantSort); f.config = f.config ?? []; }
  clone.relations.sort((a, b) => bytewise(a.name, b.name));
  for (const r of clone.relations) {
    r.grants = (r.grants ?? []).sort(grantSort);
    r.column_grants = (r.column_grants ?? []).sort((a, b) => bytewise(a.column, b.column) || grantSort(a, b));
    r.triggers = (r.triggers ?? []).sort((a, b) => bytewise(a.name, b.name));
    r.options = r.options ?? [];
  }
  clone.policies.sort((a, b) => bytewise(a.table, b.table) || bytewise(a.name, b.name));
  for (const p of clone.policies) p.roles = [...(p.roles ?? [])].sort(bytewise);
  return clone;
}

/** Flatten a snapshot into comparable facts keyed exactly like _catalog_facts() in SQL. */
export function flattenSnapshot(doc) {
  const m = new Map();
  const put = (key, type, value) => m.set(key, { key, type, value });
  for (const g of doc.schema_privileges) {
    put(`schema_grant|${g.grantee}|${g.privilege}`, 'schema_grant', { grantable: g.grantable ?? null });
  }
  for (const f of doc.functions) {
    put(`function|${f.signature}`, 'function',
      { owner: f.owner ?? null, security_definer: f.security_definer ?? null, config: f.config ?? null });
    for (const g of f.grants ?? []) {
      put(`function_grant|${f.signature}|${g.grantee}|${g.privilege}`, 'function_grant', { grantable: g.grantable ?? null });
    }
  }
  for (const r of doc.relations) {
    put(`relation|${r.name}`, 'relation', {
      kind: r.kind ?? null, owner: r.owner ?? null, rls_enabled: r.rls_enabled ?? null,
      rls_forced: r.rls_forced ?? null, options: r.options ?? null,
    });
    for (const g of r.grants ?? []) {
      put(`relation_grant|${r.name}|${g.grantee}|${g.privilege}`, 'relation_grant', { grantable: g.grantable ?? null });
    }
    for (const g of r.column_grants ?? []) {
      put(`column_grant|${r.name}|${g.column}|${g.grantee}|${g.privilege}`, 'column_grant', { grantable: g.grantable ?? null });
    }
    for (const t of r.triggers ?? []) {
      put(`trigger|${r.name}|${t.name}`, 'trigger', { enabled: t.enabled ?? null, function: t.function ?? null });
    }
  }
  for (const p of doc.policies) {
    put(`policy|${p.table}|${p.name}`, 'policy', {
      command: p.command ?? null, permissive: p.permissive ?? null, roles: p.roles ?? null,
      using: p.using ?? null, check: p.check ?? null,
    });
  }
  return m;
}

/** Advisory classification. Returns [severity, rule]. Mirrors _finding_class() in SQL. */
export function classifyFinding(type, change, key, bval, cval, isDefiner) {
  const part = (i) => key.split('|')[i - 1];
  const truthy = (v) => v === true;
  if (type === 'function_grant') {
    const grantee = part(3);
    if (change === 'added') {
      if (grantee === 'PUBLIC' || grantee === 'c10g3_app') return ['high', 'GP01_EXEC_PUBLIC_OR_APP'];
      if (truthy(isDefiner)) return ['high', 'GP02_EXEC_DEFINER_WIDENED'];
      return ['medium', 'GP03_EXEC_GRANT_ADDED'];
    }
    if (change === 'removed') return ['low', 'GP04_GRANT_REMOVED'];
    return ['medium', 'GP03_EXEC_GRANT_ADDED'];
  }
  if (type === 'relation_grant') {
    const grantee = part(3); const priv = part(4);
    if (change === 'added') {
      if (['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'].includes(priv)) return ['high', 'GP05_WRITE_GRANT_ADDED'];
      if (grantee === 'PUBLIC' || grantee === 'c10g3_app') return ['high', 'GP06_READ_GRANT_WIDENED'];
      return ['medium', 'GP07_TABLE_GRANT_ADDED'];
    }
    if (change === 'removed') return ['low', 'GP04_GRANT_REMOVED'];
    return ['medium', 'GP07_TABLE_GRANT_ADDED'];
  }
  if (type === 'column_grant') {
    const priv = part(5);
    if (change === 'added') {
      if (priv === 'INSERT' || priv === 'UPDATE') return ['high', 'GP05_WRITE_GRANT_ADDED'];
      return ['medium', 'GP07_TABLE_GRANT_ADDED'];
    }
    if (change === 'removed') return ['low', 'GP04_GRANT_REMOVED'];
    return ['medium', 'GP07_TABLE_GRANT_ADDED'];
  }
  if (type === 'schema_grant') {
    const grantee = part(2); const priv = part(3);
    if (change === 'added') {
      if (priv === 'CREATE' || grantee === 'PUBLIC') return ['high', 'GP08_SCHEMA_PRIVILEGE_WIDENED'];
      return ['medium', 'GP09_SCHEMA_GRANT_ADDED'];
    }
    if (change === 'removed') return ['low', 'GP04_GRANT_REMOVED'];
    return ['medium', 'GP09_SCHEMA_GRANT_ADDED'];
  }
  if (type === 'function') {
    if (change === 'added') {
      return truthy(cval?.security_definer) ? ['medium', 'GP15_DEFINER_FUNCTION_ADDED'] : ['low', 'GP16_FUNCTION_ADDED_OR_REMOVED'];
    }
    if (change === 'removed') return ['low', 'GP16_FUNCTION_ADDED_OR_REMOVED'];
    return ['high', 'GP17_FUNCTION_ATTRIBUTE_CHANGED'];
  }
  if (type === 'relation') {
    if (change === 'added') return ['medium', 'GP10_RELATION_ADDED'];
    if (change === 'removed') return ['low', 'GP11_RELATION_REMOVED'];
    if (truthy(bval?.rls_enabled) && !truthy(cval?.rls_enabled)) return ['high', 'GP12_RLS_DISABLED'];
    if ((bval?.options ?? []).includes('security_invoker=true') && !(cval?.options ?? []).includes('security_invoker=true')) {
      return ['high', 'GP14_VIEW_INVOKER_LOST'];
    }
    return ['medium', 'GP13_RELATION_ATTRIBUTE_CHANGED'];
  }
  if (type === 'policy') {
    if (change === 'added') {
      return truthy(cval?.permissive) ? ['high', 'GP20_PERMISSIVE_POLICY_ADDED'] : ['low', 'GP21_RESTRICTIVE_POLICY_ADDED'];
    }
    if (change === 'removed') {
      // coalesce(permissive, true): an unknown baseline flag is treated as permissive (low), like SQL.
      const basePerm = bval?.permissive === undefined || bval?.permissive === null ? true : bval.permissive === true;
      return !basePerm ? ['high', 'GP22_RESTRICTIVE_POLICY_REMOVED'] : ['low', 'GP23_POLICY_REMOVED'];
    }
    if (!truthy(bval?.permissive) && truthy(cval?.permissive)) return ['high', 'GP25_POLICY_MADE_PERMISSIVE'];
    return ['medium', 'GP24_POLICY_CHANGED'];
  }
  if (type === 'trigger') {
    if (change === 'removed') return ['high', 'GP30_TRIGGER_REMOVED'];
    if (change === 'changed' && cval?.enabled !== 'O') return ['high', 'GP31_TRIGGER_DISABLED'];
    return ['low', 'GP32_TRIGGER_ADDED_OR_RESTORED'];
  }
  return ['medium', 'GP99_UNCLASSIFIED'];
}

/** Normalized versioned diff of two snapshots. Same document (byte-for-byte canonical) as catalog_diff() in SQL. */
export function diffSnapshots(baseline, current) {
  const b = flattenSnapshot(normalizeSnapshot(baseline));
  const c = flattenSnapshot(normalizeSnapshot(current));
  const keys = [...new Set([...b.keys(), ...c.keys()])].sort(bytewise);
  const findings = [];
  for (const key of keys) {
    const bf = b.get(key); const cf = c.get(key);
    let change = null;
    if (!bf) change = 'added'; else if (!cf) change = 'removed';
    else if (canonicalJson(bf.value) !== canonicalJson(cf.value)) change = 'changed';
    if (!change) continue;
    const type = (cf ?? bf).type;
    const fnKey = `function|${key.split('|')[1]}`;
    const isDefiner = c.get(fnKey)?.value?.security_definer === true ? true : (c.has(fnKey) ? false : null);
    const [severity, rule] = classifyFinding(type, change, key, bf?.value, cf?.value, isDefiner);
    findings.push({
      key, change, fact_type: type, severity, rule, baseline: bf ? bf.value : null, current: cf ? cf.value : null,
    });
  }
  const counts = { high: 0, medium: 0, low: 0 };
  for (const f of findings) counts[f.severity] += 1;
  const max_severity = counts.high ? 'high' : counts.medium ? 'medium' : counts.low ? 'low' : 'none';
  return {
    format: DIFF_FORMAT,
    label: 'ADVISORY',
    baseline_sha256: snapshotDigest(baseline),
    current_sha256: snapshotDigest(current),
    finding_count: findings.length,
    max_severity,
    severity_counts: counts,
    findings,
  };
}

/** True when a diff is labelled advisory and carries no executable remediation. */
export function assertAdvisoryDiff(diff) {
  if (diff?.label !== 'ADVISORY') throw new GrantDiffError('G3A03', 'diff must be labelled ADVISORY');
  const text = JSON.stringify(diff);
  if (/\b(GRANT|REVOKE|ALTER|CREATE POLICY|DROP POLICY)\s+/.test(text.replace(/"[A-Z_]+"/g, ''))) {
    // Rule codes such as GP05_WRITE_GRANT_ADDED are quoted tokens and are excluded above.
    throw new GrantDiffError('G3A03', 'a diff must never carry executable SQL');
  }
  return true;
}

/**
 * A baseline is only trustworthy when it is a STORED, owner-approved row whose inventory still matches its
 * digest. Anything a caller types in (bare JSON, a row without approved_by/receipt) is rejected.
 */
export function verifyBaselineIntegrity(row) {
  const reasons = [];
  if (!row || typeof row !== 'object') return { ok: false, reasons: ['not_a_stored_row'] };
  if (!row.baseline_id) reasons.push('missing_baseline_id');
  if (!row.approved_by) reasons.push('missing_approved_by');
  if (!row.receipt_id) reasons.push('missing_receipt');
  if (row.inventory?.format !== SNAPSHOT_FORMAT) reasons.push('bad_format');
  else if (row.inventory_sha256 !== snapshotDigest(row.inventory)) reasons.push('digest_mismatch');
  return { ok: reasons.length === 0, reasons };
}

/** API guard: reject any request that tries to carry its own baseline / diff / "no differences" claim. */
export function assertNoCallerSuppliedComparison(params) {
  const bad = Object.keys(params ?? {}).filter((k) => CALLER_SUPPLIED_COMPARISON_KEYS.includes(k));
  if (bad.length) {
    throw new GrantDiffError('G3A03', `caller-supplied comparison data is not accepted (${bad.join(', ')}); use the stored baseline`);
  }
  return true;
}
