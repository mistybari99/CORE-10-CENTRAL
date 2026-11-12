// GOV-003 feature 07 deployment provenance. Pure Node, ZERO dependencies. DEMO / NOT LIVE contract core.
//
// Mirrors sql/070_deployment.sql: record_deployment validation, record_runtime_probe verdict computation and
// certify_deployment preconditions. A deployed proof is SEPARATE from built/tested proof, and a preview, queued,
// failed or simulated deployment can never certify. The real runtime probe is a CONTRACT here; no real runtime exists.
import { canonicalJson, sha256Hex, isSha40 } from './ci-receipt.mjs';

export { isSha40 };
export const isSha256 = (s) => typeof s === 'string' && /^[0-9a-f]{64}$/.test(s);
export class DeployError extends Error {
  constructor(code, message) { super(`${code}: ${message}`); this.name = 'DeployError'; this.code = code; }
}

export const DEPLOY_ENVIRONMENTS = Object.freeze(['preview', 'staging', 'production']);
export const DEPLOY_MODES = Object.freeze(['real', 'simulated']);
export const DEPLOY_STATUSES = Object.freeze(['queued', 'building', 'deployed', 'failed']);
export const PROBE_HEALTH = Object.freeze(['ok', 'degraded', 'down']);
/** Mismatch codes in the exact order SQL evaluates them. */
export const PROBE_CODES = Object.freeze(['probe_before_deploy', 'source_commit_mismatch', 'artifact_hash_mismatch', 'version_mismatch', 'health_not_ok', 'http_status_not_200']);

const REF = /^[A-Za-z0-9_.:/#-]{1,128}$/;
const VERSION = /^[A-Za-z0-9_.:+-]{1,64}$/;
const bad = (m) => { throw new DeployError('G3A03', m); };

/** Validate a typed deployment record exactly like record_deployment. `gates.runtime_probe` defaults to DISABLED. */
export function buildDeployment(i, { gates = {}, now = new Date() } = {}) {
  if (typeof i?.feature_id !== 'string' || !REF.test(i.feature_id)) bad('feature_id');
  if (typeof i.build_ref !== 'string' || !REF.test(i.build_ref)) bad('build_ref');
  if (i.branch_ref != null && !REF.test(i.branch_ref)) bad('branch_ref');
  if (!DEPLOY_ENVIRONMENTS.includes(i.environment) || !DEPLOY_MODES.includes(i.mode) || !DEPLOY_STATUSES.includes(i.deploy_status)) bad('environment, mode and deploy status');
  if (!isSha40(i.source_commit) || !isSha256(i.artifact_sha256)) bad('source commit (40 hex) and artifact sha256 (64 hex) required');
  const health = i.expected_health ?? 'ok';
  if (typeof i.expected_version !== 'string' || !VERSION.test(i.expected_version) || health !== 'ok') bad('expected version / health');
  const deployedAt = i.deployed_at ?? null;
  if ((i.deploy_status === 'deployed') !== (deployedAt !== null)) bad('deployed_at is required exactly when status is deployed');
  if (deployedAt !== null && new Date(deployedAt).getTime() > now.getTime() + 5 * 60_000) bad('deployed_at is in the future');
  if (i.mode === 'real' && !gates.runtime_probe) throw new DeployError('G3E01', 'no real runtime in this isolated bed (fail closed)');
  return {
    feature_id: i.feature_id, environment: i.environment, mode: i.mode, deploy_status: i.deploy_status,
    source_commit: i.source_commit, artifact_sha256: i.artifact_sha256, build_ref: i.build_ref,
    branch_ref: i.branch_ref ?? null, deployed_at: deployedAt, expected_version: i.expected_version, expected_health: health,
  };
}

/** Microsecond UTC ISO like SQL utc_iso(): YYYY-MM-DDTHH:MM:SS.ffffffZ (ms precision from JS Date). */
export const utcIso = (d) => new Date(d).toISOString().replace('Z', '000Z');

/** Immutable evidence reference of a probe observation (== SQL record_runtime_probe evidence_sha256). */
export function probeEvidenceSha256(deploymentId, mode, o) {
  return sha256Hex(canonicalJson({
    deployment_id: deploymentId, http_status: String(o.http_status), mode,
    observed_artifact_sha256: o.observed_artifact_sha256, observed_at: utcIso(o.observed_at),
    observed_health: o.observed_health, observed_source_commit: o.observed_source_commit, observed_version: o.observed_version,
  }));
}

/**
 * Runtime probe contract: expected source hash / version / health vs observation. Verdict is COMPUTED here
 * (never caller supplied). Returns { result: 'pass'|'fail', mismatch_codes }.
 */
export function evaluateProbe(deployment, o) {
  if (!DEPLOY_MODES.includes(o?.mode) || !isSha40(o.observed_source_commit) || !isSha256(o.observed_artifact_sha256)
      || typeof o.observed_version !== 'string' || !VERSION.test(o.observed_version)
      || !PROBE_HEALTH.includes(o.observed_health) || !Number.isInteger(o.http_status) || o.http_status < 100 || o.http_status > 599
      || o.observed_at == null || Number.isNaN(new Date(o.observed_at).getTime())) bad('probe observation');
  if (deployment.deploy_status !== 'deployed') throw new DeployError('G3C02', `a ${deployment.deploy_status} deployment cannot be smoke-probed as deployed`);
  if (o.mode !== deployment.mode) throw new DeployError('G3C02', 'probe mode must equal the deployment mode');
  const codes = [];
  if (new Date(o.observed_at).getTime() < new Date(deployment.deployed_at).getTime()) codes.push('probe_before_deploy');
  if (o.observed_source_commit !== deployment.source_commit) codes.push('source_commit_mismatch');
  if (o.observed_artifact_sha256 !== deployment.artifact_sha256) codes.push('artifact_hash_mismatch');
  if (o.observed_version !== deployment.expected_version) codes.push('version_mismatch');
  if (o.observed_health !== deployment.expected_health) codes.push('health_not_ok');
  if (o.http_status !== 200) codes.push('http_status_not_200');
  return { result: codes.length === 0 ? 'pass' : 'fail', mismatch_codes: codes };
}

/**
 * Preconditions of certify_deployment, in SQL order. Throws DeployError with SQL error codes; returns the
 * deployed_verified proof shape on success. `gates.runtime_probe` defaults to DISABLED (fail closed).
 */
export function certifyDeployment({ deployment, probe, currentHeadSha, gates = {} }) {
  if (!probe) throw new DeployError('G3C02', 'a runtime smoke probe record is required');
  if (deployment.environment === 'preview') throw new DeployError('G3C02', 'a preview deployment is not deployed/healthy proof');
  if (deployment.deploy_status !== 'deployed') throw new DeployError('G3C02', `${deployment.deploy_status} is not deployed`);
  if (deployment.mode !== 'real' || probe.mode !== 'real') throw new DeployError('G3C02', 'simulated deployment evidence never certifies');
  if (!gates.runtime_probe) throw new DeployError('G3E01', 'runtime probe gate is disabled (fail closed)');
  if (probe.result !== 'pass') throw new DeployError('G3C02', `probe not passing: ${(probe.mismatch_codes ?? []).join(',')}`);
  if (currentHeadSha !== deployment.source_commit) throw new DeployError('G3C01', 'deployed source commit is not the current head');
  return {
    level: 'deployed_verified', commit_sha: deployment.source_commit, environment: deployment.environment,
    run_ref: deployment.build_ref, simulated: false, evidence_sha256: probe.evidence_sha256, outcome: 'pass',
  };
}
