// GOV-003 feature 06 exact-commit CI receipts. Pure Node, ZERO dependencies. DEMO / NOT LIVE contract core.
//
// Mirrors sql/060_ci_receipts.sql: record_ci_receipt validation, evidence reference, verify_ci_receipt
// comparison, trust derivation and the stale-head validator.
//
// TRUST MODEL
//   * Building a receipt only PATTERN-validates the run URL. A caller-supplied URL is never certification.
//   * trust = 'unverified'            -> label `offline_fixture/unverified`
//             'simulated_verified'    -> label `offline_fixture/simulated_verified` (simulated adapter matched)
//             'verified'              -> label `remote_verified` (github_api adapter matched; needs the real adapter)
//   * No real GitHub adapter exists in this isolated package: createUnavailableGithubAdapter() fails closed.
//   * A CI receipt can back only code_built / isolated_test_pass, only for its own head sha.
import { createHash } from 'node:crypto';

export class ReceiptError extends Error {
  constructor(code, message) { super(`${code}: ${message}`); this.name = 'ReceiptError'; this.code = code; }
}
export class RemoteVerifierUnavailable extends Error {
  constructor(message = 'remote GitHub verifier is not available (fail closed)') {
    super(message); this.name = 'RemoteVerifierUnavailable'; this.code = 'G3E01';
  }
}

// ---- canonical JSON / digests (same domain as SQL canonical_json for ASCII strings, ints, null, bool) -------------
export function canonicalJson(v) {
  if (v === null) return 'null';
  switch (typeof v) {
    case 'string': return JSON.stringify(v);
    case 'boolean': return v ? 'true' : 'false';
    case 'number':
      if (!Number.isSafeInteger(v)) throw new ReceiptError('G3A03', 'canonical JSON: integers only');
      return String(v);
    case 'object': {
      if (Array.isArray(v)) return `[${v.map(canonicalJson).join(',')}]`;
      const keys = Object.keys(v).sort((a, b) => (Buffer.compare(Buffer.from(a), Buffer.from(b))));
      return `{${keys.map((k) => `${JSON.stringify(k)}:${canonicalJson(v[k])}`).join(',')}}`;
    }
    default: throw new ReceiptError('G3A03', `canonical JSON: unsupported ${typeof v}`);
  }
}
export const sha256Hex = (s) => createHash('sha256').update(Buffer.from(s, 'utf8')).digest('hex');

// ---- validation contracts -------------------------------------------------------------------------------------------
export const isSha40 = (s) => typeof s === 'string' && /^[0-9a-f]{40}$/.test(s);
export const RUN_URL_RE = /^https:\/\/github\.com\/([A-Za-z0-9][A-Za-z0-9-]{0,38})\/([A-Za-z0-9._-]{1,100})\/actions\/runs\/([0-9]{1,18})$/;
export const TRUSTED_REPOS = Object.freeze(['mistybari99/core-10-central']);
export const RUN_STATUSES = Object.freeze(['queued', 'in_progress', 'completed']);
export const CONCLUSIONS = Object.freeze(['success', 'failure', 'cancelled', 'skipped', 'neutral', 'timed_out', 'action_required']);
export const ENVIRONMENTS = Object.freeze(['local', 'isolated_pg', 'ci_isolated', 'staging_signed', 'integration', 'staging', 'production']);
export const ISOLATED_CI_ENVIRONMENTS = Object.freeze(['ci_isolated', 'isolated_pg']);

/** Parse https://github.com/<owner>/<repo>/actions/runs/<id>. Anything else (query, fragment, http, userinfo, ...) is rejected. */
export function parseRunUrl(url) {
  const m = typeof url === 'string' ? RUN_URL_RE.exec(url) : null;
  if (!m) return { ok: false, code: 'G3A03', message: 'run url does not match the GitHub Actions run pattern' };
  return { ok: true, owner: m[1], repo: m[2], repo_full: `${m[1]}/${m[2]}`.toLowerCase(), run_id: m[3] };
}

/**
 * Validate + normalize a receipt and compute its immutable evidence reference
 * (sha256 of the canonical receipt). Throws ReceiptError(G3A03) like record_ci_receipt.
 */
export function buildReceipt(input, { trustedRepos = TRUSTED_REPOS } = {}) {
  const bad = (m) => { throw new ReceiptError('G3A03', m); };
  const i = input ?? {};
  if (typeof i.feature_id !== 'string' || !/^[A-Za-z0-9_.:/#-]{1,128}$/.test(i.feature_id)) bad('feature_id must be an opaque reference');
  if (!isSha40(i.head_sha)) bad('head sha must be 40 lowercase hex');
  if (typeof i.run_id !== 'string' || !/^[0-9]{1,18}$/.test(i.run_id)) bad('run id must be numeric');
  if (typeof i.workflow !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9 _.()/-]{0,99}$/.test(i.workflow)) bad('workflow name');
  const conclusion = i.conclusion ?? null;
  if (!RUN_STATUSES.includes(i.run_status) || (i.run_status === 'completed') !== (conclusion !== null)
      || (conclusion !== null && !CONCLUSIONS.includes(conclusion))) bad('run status/conclusion');
  if (!ENVIRONMENTS.includes(i.environment)) bad('environment');
  const attempt = i.run_attempt ?? 1;
  if (!Number.isInteger(attempt) || attempt < 1 || attempt > 999) bad('run attempt');
  const u = parseRunUrl(i.run_url);
  if (!u.ok) bad(u.message);
  if (u.run_id !== i.run_id) bad('run url id does not match run id');
  if (!trustedRepos.includes(u.repo_full)) bad('repository is not a trusted source for this module');
  const receipt = {
    conclusion, environment: i.environment, feature_id: i.feature_id, head_sha: i.head_sha, repo: u.repo_full,
    run_attempt: String(attempt), run_id: i.run_id, run_status: i.run_status, run_url: i.run_url, workflow: i.workflow,
  };
  return { receipt, evidence_sha256: sha256Hex(canonicalJson(receipt)), trust: 'unverified', trust_label: trustLabel('unverified') };
}

// ---- trust ----------------------------------------------------------------------------------------------------------
export const VERIFIER_KINDS = Object.freeze(['simulated_fixture', 'github_api']);
export function receiptTrust(verifications = []) {
  if (verifications.some((v) => v.verifier_kind === 'github_api')) return 'verified';
  if (verifications.some((v) => v.verifier_kind === 'simulated_fixture')) return 'simulated_verified';
  return 'unverified';
}
export function trustLabel(trust) {
  return trust === 'verified' ? 'remote_verified'
    : trust === 'simulated_verified' ? 'offline_fixture/simulated_verified'
      : 'offline_fixture/unverified';
}
/** A caller-supplied URL (or any receipt without a matching verification record) never certifies. */
export const certifies = (trust) => trust === 'verified';

// ---- stale-head validator -------------------------------------------------------------------------------------------
/** { current, stale, code } — an old SHA pass is never reused for a new SHA. */
export function validateReceiptHead(receiptHeadSha, currentHeadSha) {
  if (!isSha40(receiptHeadSha) || !(currentHeadSha === null || isSha40(currentHeadSha))) {
    return { current: false, stale: true, code: 'G3A03' };
  }
  const current = currentHeadSha !== null && receiptHeadSha === currentHeadSha;
  return { current, stale: !current, code: current ? null : 'G3C01' };
}
export function assertCurrentHead(receiptHeadSha, currentHeadSha) {
  const r = validateReceiptHead(receiptHeadSha, currentHeadSha);
  if (!r.current) throw new ReceiptError(r.code ?? 'G3C01', 'stale head: receipt sha is not the current head');
  return r;
}

// ---- remote verifier adapter contract -------------------------------------------------------------------------------
// An adapter is { kind: 'simulated_fixture'|'github_api', fetchRun({ repo, run_id }) -> Promise<Observation> }.
// Observation = { repo, run_id, run_url, head_sha, workflow, run_status, conclusion|null, observed_at(ISO UTC) }.
export const OBSERVATION_FIELDS = Object.freeze(['repo', 'run_id', 'run_url', 'head_sha', 'workflow', 'run_status', 'conclusion', 'observed_at']);

export function assertRemoteVerifierAdapter(adapter) {
  if (!adapter || typeof adapter.fetchRun !== 'function') throw new ReceiptError('G3A03', 'adapter must expose fetchRun()');
  if (!VERIFIER_KINDS.includes(adapter.kind)) throw new ReceiptError('G3A03', 'adapter kind must be simulated_fixture|github_api');
  return adapter;
}
export function validateObservation(o) {
  if (o === null || typeof o !== 'object' || Array.isArray(o)) throw new ReceiptError('G3A03', 'observation must be an object');
  for (const k of Object.keys(o)) if (!OBSERVATION_FIELDS.includes(k)) throw new ReceiptError('G3A03', 'unexpected observation field');
  if (!isSha40(o.head_sha)) throw new ReceiptError('G3A03', 'observation head sha');
  if (typeof o.run_id !== 'string' || !/^[0-9]{1,18}$/.test(o.run_id)) throw new ReceiptError('G3A03', 'observation run id');
  if (typeof o.observed_at !== 'string' || !/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$/.test(o.observed_at)) throw new ReceiptError('G3A03', 'observation time');
  if (!RUN_STATUSES.includes(o.run_status)) throw new ReceiptError('G3A03', 'observation run status');
  return o;
}
/** Mismatch codes, in the exact order used by SQL verify_ci_receipt. Empty array = match. */
export function compareReceiptToObservation(receipt, o) {
  const m = [];
  if (String(o.repo ?? '').toLowerCase() !== receipt.repo) m.push('repo_mismatch');
  if (o.run_id !== receipt.run_id) m.push('run_id_mismatch');
  if ((o.run_url ?? null) !== receipt.run_url) m.push('run_url_mismatch');
  if (o.head_sha !== receipt.head_sha) m.push('head_sha_mismatch');
  if ((o.workflow ?? null) !== receipt.workflow) m.push('workflow_mismatch');
  if (o.run_status !== receipt.run_status) m.push('run_status_mismatch');
  if ((o.conclusion ?? null) !== (receipt.conclusion ?? null)) m.push('conclusion_mismatch');
  return m;
}
/**
 * Ask a remote adapter about a receipt. NEVER trusts receipt.run_url as proof: the adapter's own observation is
 * compared with the receipt. Any mismatch or malformed observation REJECTS (ok:false); adapter failure fails closed.
 */
export async function verifyReceiptWithAdapter(receipt, adapter) {
  assertRemoteVerifierAdapter(adapter);
  let obs;
  try {
    obs = await adapter.fetchRun({ repo: receipt.repo, run_id: receipt.run_id });
    validateObservation(obs);
  } catch (e) {
    if (e instanceof RemoteVerifierUnavailable) return { ok: false, kind: adapter.kind, rejected: 'unavailable', mismatches: [] };
    if (e instanceof ReceiptError) return { ok: false, kind: adapter.kind, rejected: 'malformed_observation', mismatches: [] };
    return { ok: false, kind: adapter.kind, rejected: 'adapter_error', mismatches: [] };
  }
  const mismatches = compareReceiptToObservation(receipt, obs);
  if (mismatches.length) return { ok: false, kind: adapter.kind, rejected: 'mismatch', mismatches, observation: obs };
  return {
    ok: true, kind: adapter.kind, mismatches: [], observation: obs,
    remote_payload_sha256: sha256Hex(canonicalJson(obs)),
    trust: adapter.kind === 'github_api' ? 'verified' : 'simulated_verified',
  };
}

/** Simulated adapter over fixed fixtures keyed by run id. Always kind simulated_fixture: never real certification. */
export function createSimulatedGithubAdapter(fixtures) {
  return {
    kind: 'simulated_fixture',
    async fetchRun({ run_id }) {
      const f = fixtures?.[run_id];
      if (!f) throw new ReceiptError('G3A03', 'no fixture for run');
      return { ...f };
    },
  };
}
/** Placeholder for the future real adapter: fails closed until a real, owner-approved integration exists. */
export function createUnavailableGithubAdapter() {
  return { kind: 'github_api', async fetchRun() { throw new RemoteVerifierUnavailable(); } };
}

/** Which readiness proofs a receipt may back. Mirrors bind_ci_receipt_to_readiness. */
export function proofsForReceipt(receipt, trust, evidenceSha256) {
  if (receipt.run_status !== 'completed') throw new ReceiptError('G3C02', 'queued or in-progress CI is not evidence');
  if (!ISOLATED_CI_ENVIRONMENTS.includes(receipt.environment)) throw new ReceiptError('G3C02', 'a CI receipt can only back isolated levels');
  if (trust === 'unverified') throw new ReceiptError('G3C02', 'an offline_fixture/unverified receipt is not certification');
  const simulated = trust !== 'verified';
  const outcome = receipt.conclusion === 'success' ? 'pass' : 'fail';
  const base = { commit_sha: receipt.head_sha, environment: receipt.environment, run_ref: `gh-run-${receipt.run_id}`, simulated, evidence_sha256: evidenceSha256 };
  const out = [];
  if (outcome === 'pass') out.push({ ...base, level: 'code_built', outcome });
  out.push({ ...base, level: 'isolated_test_pass', outcome });
  return out;
}
