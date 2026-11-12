// Feature 12: requirement -> feature -> source file -> test -> release graph validator (pure, zero dependencies).
// Mirrors SQL validate_trace()/trace_summary(); parity is asserted in tests/gov003/sql/f12_trace.test.mjs.
const SHA40 = /^[0-9a-f]{40}$/;
const STATUSES = new Set(['built', 'deferred', 'missing', 'proposed']);
const arr = (x) => (Array.isArray(x) ? x : []);

export function validateTrace(p) {
  const reqs = arr(p.requirements).map((r) => ({ id: r.id, status: r.status ?? null, hard: r.hard === true,
    dr: r.deferral_reason ?? '', dar: r.deferral_approval_ref ?? '' }));
  const feats = arr(p.features).map((f) => ({ id: f.id, head: f.head_sha ?? null, rids: arr(f.requirement_ids) }));
  const srcs = arr(p.source_files).map((s) => ({ id: s.path, fid: s.feature_id }));
  const tsts = arr(p.tests).map((t) => ({ id: t.id, fid: t.feature_id, passed: t.passed === true, sha: t.commit_sha ?? null }));
  const rels = arr(p.releases).map((e) => ({ id: e.id, fids: arr(e.feature_ids) }));
  const decl = arr(p.declared_requirement_ids);
  const v = [];
  const add = (code, subject, detail) => v.push({ code, subject, detail });
  const featById = new Map(feats.map((f) => [f.id, f]));
  const reqIds = new Set(reqs.map((r) => r.id));

  for (const [k, list] of [['requirement', reqs], ['feature', feats], ['source_file', srcs], ['test', tsts], ['release', rels]]) {
    const counts = new Map();
    for (const x of list) counts.set(x.id, (counts.get(x.id) ?? 0) + 1);
    for (const [id, n] of counts) if (n > 1) add('duplicate_id', `${k}:${id}`, `id appears ${n} times`);
  }
  for (const r of reqs) if (r.status === null || !STATUSES.has(r.status)) add('invalid_status', r.id, 'status must be built|deferred|missing|proposed');
  const frefs = feats.flatMap((f) => f.rids.map((rid) => ({ fid: f.id, rid })));
  for (const fr of frefs) if (!reqIds.has(fr.rid)) add('dangling_requirement_ref', fr.fid, `references unknown requirement ${fr.rid}`);
  for (const f of feats) if (f.rids.length === 0) add('orphan_feature', f.id, 'feature maps to no requirement');
  for (const r of reqs) if (r.status === 'built' && !frefs.some((fr) => fr.rid === r.id)) add('orphan_requirement', r.id, 'built requirement has no feature');
  for (const r of reqs) if (r.status === 'deferred' && r.dr === '') add('deferral_without_reason', r.id, 'deferred requirement carries no explicit reason');
  for (const r of reqs) if (r.status === 'deferred' && r.hard && r.dar === '') add('hard_requirement_deferred', r.id, 'hard requirement deferred without owner approval reference');
  for (const d of decl) if (!reqIds.has(d)) add('requirement_removed_from_denominator', d, 'declared requirement is absent from the requirement list');
  if (Object.prototype.hasOwnProperty.call(p, 'declared_requirement_ids')) {
    const declSet = new Set(decl);
    for (const r of reqs) if (!declSet.has(r.id)) add('undeclared_requirement', r.id, 'requirement is not in the declared denominator');
  }
  if (Object.prototype.hasOwnProperty.call(p, 'expected_requirement_count') && Number(p.expected_requirement_count) !== reqs.length) {
    add('denominator_count_mismatch', 'denominator', `expected ${p.expected_requirement_count} requirements, found ${reqs.length}`);
  }
  for (const s of srcs) if (!featById.has(s.fid)) add('orphan_source_file', s.id, 'source file references unknown feature');
  for (const t of tsts) if (!featById.has(t.fid)) add('orphan_test', t.id, 'test references unknown feature');
  for (const t of tsts) if (t.passed && !(t.sha !== null && SHA40.test(t.sha))) add('passing_test_without_exact_sha', t.id, 'passing test lacks an exact 40-hex commit sha');
  for (const t of tsts) {
    const f = featById.get(t.fid);
    if (t.passed && t.sha !== null && SHA40.test(t.sha) && f && f.head !== null && f.head !== t.sha) add('stale_test_sha', t.id, 'test sha differs from the feature head sha');
  }
  const good = tsts.filter((t) => t.passed && t.sha !== null && SHA40.test(t.sha) && !(featById.get(t.fid)?.head != null && featById.get(t.fid).head !== t.sha));
  for (const r of reqs) {
    if (r.status !== 'built') continue;
    const mine = frefs.filter((fr) => fr.rid === r.id);
    if (mine.length > 0 && !mine.some((fr) => good.some((g) => g.fid === fr.fid))) add('built_without_proof', r.id, 'built requirement has no passing exact-sha test');
  }
  for (const e of rels) for (const x of e.fids) if (!featById.has(x)) add('orphan_release', e.id, `release references unknown feature ${x}`);
  const cmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
  v.sort((a, b) => cmp(a.code, b.code) || cmp(a.subject, b.subject) || cmp(a.detail, b.detail));
  return { valid: v.length === 0, violations: v, summary: traceSummary(p) };
}

export function traceSummary(p) {
  const reqs = arr(p.requirements);
  const feats = arr(p.features);
  const frefs = feats.flatMap((f) => arr(f.requirement_ids).map((rid) => ({ fid: f.id, rid })));
  const featById = new Map(feats.map((f) => [f.id, f]));
  const good = arr(p.tests).filter((t) => t.passed === true && SHA40.test(t.commit_sha ?? '')
    && !(featById.get(t.feature_id)?.head_sha != null && featById.get(t.feature_id).head_sha !== t.commit_sha));
  const relFeats = new Set(arr(p.releases).flatMap((e) => arr(e.feature_ids)));
  const built = reqs.filter((r) => r.status === 'built');
  return {
    requirements: reqs.length,
    declared: arr(p.declared_requirement_ids).length,
    built: built.length,
    deferred: reqs.filter((r) => r.status === 'deferred').length,
    missing: reqs.filter((r) => r.status === 'missing').length,
    proposed: reqs.filter((r) => r.status === 'proposed').length,
    complete_chains: built.filter((r) => frefs.some((fr) => fr.rid === r.id
      && arr(p.source_files).some((s) => s.feature_id === fr.fid) && good.some((g) => g.feature_id === fr.fid))).length,
    released: built.filter((r) => frefs.some((fr) => fr.rid === r.id && relFeats.has(fr.fid))).length,
  };
}
