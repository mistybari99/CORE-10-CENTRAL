// GOV-003 feature 05 readiness evaluator. Pure Node, ZERO dependencies. DEMO / NOT LIVE contract core.
//
// Mirrors, rule for rule, c10_gov003_demo._f57_derive() / derive_readiness() in sql/050_readiness.sql.
// Parity with SQL is enforced by tests/gov003/node/readiness.test.mjs on shared fixture cases.
//
// Readiness is DERIVED from proof rows. There is no input that sets a state, a "green" boolean or a level.
//   state            = highest level reachable CONTIGUOUSLY from `proposed`
//   level satisfied  = latest proof for (level, CURRENT head sha) has outcome = pass
//   stale            = a pass proof exists for an OLD sha at a level that is not satisfied at the current head
//   simulated proofs can satisfy ONLY code_built / isolated_test_pass; real levels need a real-evidence gate.

export const LEVELS = Object.freeze([
  { level: 'proposed',              rank: 1, envs: [],                                   allowsSimulated: true,  gate: null,              dedicatedPath: true },
  { level: 'code_built',            rank: 2, envs: ['local', 'isolated_pg', 'ci_isolated'], allowsSimulated: true,  gate: null,              dedicatedPath: false },
  { level: 'isolated_test_pass',    rank: 3, envs: ['isolated_pg', 'ci_isolated'],        allowsSimulated: true,  gate: null,              dedicatedPath: false },
  { level: 'signed_stage_verified', rank: 4, envs: ['staging_signed'],                    allowsSimulated: false, gate: 'signed_gotrue',   dedicatedPath: false },
  { level: 'integrated_verified',   rank: 5, envs: ['integration'],                       allowsSimulated: false, gate: 'integration_env', dedicatedPath: false },
  { level: 'deployed_verified',     rank: 6, envs: ['staging', 'production'],             allowsSimulated: false, gate: 'runtime_probe',   dedicatedPath: true },
  { level: 'released',              rank: 7, envs: ['production'],                        allowsSimulated: false, gate: null,              dedicatedPath: true },
]);
export const LEVEL_NAMES = Object.freeze(LEVELS.map((l) => l.level));
export const ENVIRONMENTS = Object.freeze(['local', 'isolated_pg', 'ci_isolated', 'staging_signed', 'integration', 'staging', 'production']);
export const GENERIC_PROOF_LEVELS = Object.freeze(['code_built', 'isolated_test_pass', 'signed_stage_verified', 'integrated_verified']);
export const GATES = Object.freeze(['signed_gotrue', 'integration_env', 'runtime_probe', 'github_remote']);

export const isSha40 = (s) => typeof s === 'string' && /^[0-9a-f]{40}$/.test(s);
export const isSha256 = (s) => typeof s === 'string' && /^[0-9a-f]{64}$/.test(s);

export class ReadinessError extends Error {
  constructor(code, message) { super(`${code}: ${message}`); this.name = 'ReadinessError'; this.code = code; }
}

const levelDef = (name) => LEVELS.find((l) => l.level === name);

/**
 * Mirror of record_readiness_proof validation + the readiness_proofs insert guard + gate check.
 * `gates` is { signed_gotrue: bool, ... }; every gate defaults to DISABLED (fail closed).
 * Returns { ok: true } or { ok: false, code, message } using the SQL error codes.
 */
export function validateProofInput(p, { gates = {}, dedicated = false } = {}) {
  const bad = (code, message) => ({ ok: false, code, message });
  const def = levelDef(p?.level);
  if (!def || def.level === 'proposed') return bad('G3A03', 'unknown level');
  if (!dedicated && !GENERIC_PROOF_LEVELS.includes(def.level)) return bad('G3A03', 'level requires a dedicated path');
  if (!isSha40(p.commit_sha)) return bad('G3A03', 'commit sha must be 40 lowercase hex');
  if (!isSha256(p.evidence_sha256)) return bad('G3A03', 'evidence sha256 must be 64 lowercase hex');
  if (typeof p.run_ref !== 'string' || !/^[A-Za-z0-9_.:/#-]{1,128}$/.test(p.run_ref)) return bad('G3A03', 'run_ref must be an opaque reference');
  if (typeof p.simulated !== 'boolean') return bad('G3A03', 'simulated flag required');
  if (!['pass', 'fail'].includes(p.outcome)) return bad('G3A03', 'outcome must be pass|fail');
  if (typeof p.environment !== 'string') return bad('G3A03', 'environment required');
  // _f57_insert_proof gate check runs before the table guard, mirroring SQL ordering
  if (def.gate && !p.simulated && !gates[def.gate]) return bad('G3E01', `gate ${def.gate} is disabled (fail closed)`);
  if (!def.envs.includes(p.environment)) return bad('G3A03', `level ${def.level} does not accept environment ${p.environment}`);
  if (p.simulated && !def.allowsSimulated) return bad('G3C02', `simulated evidence can never satisfy ${def.level}`);
  return { ok: true };
}

/** Stale-head validator: a proof (or receipt/deployment) counts only for the CURRENT head sha. */
export function isCurrentHead(heads, sha) {
  const cur = currentHead(heads);
  return cur !== null && cur.head_sha === sha;
}
export function currentHead(heads) {
  let best = null;
  for (const h of heads ?? []) if (best === null || h.head_seq > best.head_seq) best = h;
  return best;
}

const byNewest = (a, b) => (b.audit_seq - a.audit_seq) || ((b.proof_seq ?? 0) - (a.proof_seq ?? 0));

/**
 * deriveReadiness({ featureId, heads:[{head_seq, head_sha}], proofs:[{level, commit_sha, outcome, simulated, audit_seq, proof_seq}] })
 * Returns exactly the object produced by SQL derive_readiness().
 */
export function deriveReadiness({ featureId, heads = [], proofs = [] }) {
  const head = currentHead(heads);
  const headSha = head ? head.head_sha : null;
  const sat = []; const sim = []; const mis = []; const stale = [];
  let state = 'proposed'; let rank = 1; let contig = true; let staleCi = false; let staleOther = false;

  for (const lv of LEVELS.filter((l) => l.rank >= 2)) {
    const atLevel = proofs.filter((p) => p.level === lv.level);
    let latest = null;
    if (headSha !== null) {
      latest = atLevel.filter((p) => p.commit_sha === headSha).sort(byNewest)[0] ?? null;
    }
    if (latest && latest.outcome === 'pass') {
      sat.push(lv.level);
      if (latest.simulated) sim.push(lv.level);
      if (contig) { state = lv.level; rank = lv.rank; }
    } else {
      mis.push(lv.level);
      contig = false;
      if (headSha !== null) {
        const shas = [...new Set(atLevel.filter((p) => p.commit_sha !== headSha).map((p) => p.commit_sha))].sort();
        for (const sha of shas) {
          const newest = atLevel.filter((p) => p.commit_sha === sha).sort(byNewest)[0];
          if (newest.outcome === 'pass') {
            stale.push({ level: lv.level, commit_sha: sha });
            if (lv.level === 'code_built' || lv.level === 'isolated_test_pass') staleCi = true; else staleOther = true;
          }
        }
      }
    }
  }

  const txt = [];
  if (state !== 'released') txt.push('not certified');
  if (headSha === null) txt.push('head not registered');
  if (staleCi) txt.push('stale CI');
  if (staleOther) txt.push('stale evidence');
  if (!sat.includes('isolated_test_pass') && !staleCi) txt.push('isolated tests missing');
  if (!sat.includes('signed_stage_verified')) txt.push('staging missing');
  if (!sat.includes('integrated_verified')) txt.push('integration missing');
  if (!sat.includes('deployed_verified')) txt.push('deployment unverified');
  if (!sat.includes('released')) txt.push('release not approved');
  if (sat.length > 0 && sat.every((l) => sim.includes(l))) txt.push('simulation only');

  return {
    feature_id: featureId,
    current_head_sha: headSha,
    head_seq: head ? head.head_seq : null,
    state,
    state_rank: rank,
    satisfied_levels: sat,
    missing_proofs: mis,
    stale,
    simulated_levels: sim,
    certified: state === 'released',
    text: txt,
    summary: txt.join(' / '),
  };
}
