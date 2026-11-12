// GOV-003 adapter INTERFACES with executable rejection implementations. Zero dependencies.
// DEMO / NOT LIVE. Nothing here performs a real integration: every external dependency is a contract plus an
// implementation that FAILS CLOSED with a stable error code, so the isolated module can never silently pass as
// integrated. Real signed GoTrue, A034 entitlement parity, the canonical CORE10 audit service, remote GitHub
// verification and real deployment probes are explicit FUTURE BLOCKERS requiring Owner approval.

export class AdapterError extends Error {
  constructor(code, message) { super(message); this.name = 'AdapterError'; this.code = code; }
}

export const DEMO_BANNER = 'DEMO / NOT LIVE';
export const DEMO_MODE_ENV = 'GOV003_DEMO_MODE';

/** Demo mode is ON only when a flag is strictly `true` or env GOV003_DEMO_MODE is exactly the string "1". */
export function isDemoModeEnabled({ demo, env = process.env } = {}) {
  return demo === true || env[DEMO_MODE_ENV] === '1';
}

/**
 * CONTRACT: SessionAdapter.authenticate(request) -> Promise<Session>
 *   request: { headers: object-like with lower-case names, ...transport specifics }
 *   Session: { actor_id: UUID, source: 'signed_gotrue'|'fixture', signed: boolean, demo: boolean,
 *              label: string|null, banner: string|null, proof: object|null }
 * Rules for any implementation:
 *  - actor_id is derived ONLY from verified evidence (signed JWT verified against the issuer's JWKS, with exp/aud/
 *    iss checks, plus A034 entitlement parity). Caller-asserted roles/tenants/actors are never evidence.
 *  - `signed: true` may only be returned by an implementation that verified a real signature.
 *  - On any doubt: throw AdapterError, never return a partial or guessed session.
 */
export class SessionAdapter {
  get kind() { return 'abstract'; }
  async authenticate(_request) { throw new AdapterError('NOT_IMPLEMENTED', 'SessionAdapter.authenticate must be implemented'); }
}

/**
 * The ONLY non-demo SessionAdapter. Real signed GoTrue verification does not exist in this isolated module, so
 * every call is rejected. Local servers outside demo mode therefore fail closed on every request.
 */
export class NoSignedSessionAdapter extends SessionAdapter {
  get kind() { return 'no_signed_session'; }
  async authenticate(_request) {
    throw new AdapterError('SIGNED_SESSION_UNAVAILABLE',
      'No signed GoTrue session verification is available in this module; refusing to authenticate (fail closed).');
  }
}

/** Inert fixture identity labels -> UUIDs (match tests/gov003/fixtures/seed.sql). NOT real identities. */
export const DEMO_IDENTITIES = Object.freeze({
  tenant_owner_t1: '1d000000-0000-4000-8000-000000000001',
  business_owner_b1: '1d000000-0000-4000-8000-000000000002',
  staff_s1: '1d000000-0000-4000-8000-000000000003',
  investor_b1: '1d000000-0000-4000-8000-000000000004',
  revoked_b1: '1d000000-0000-4000-8000-000000000005',
  tenant_owner_t2: '1d000000-0000-4000-8000-000000000006',
  support_operator: '1d000000-0000-4000-8000-000000000007',
  business_owner_b1_second: '1d000000-0000-4000-8000-000000000008',
  business_owner_b2: '1d000000-0000-4000-8000-000000000009',
});

/**
 * Demo/test ONLY. Maps a fixture identity LABEL (header `x-demo-identity` or request.demoIdentity) to an inert
 * UUID. Refuses to construct, and refuses every call, unless demo mode is explicitly on (flag demo:true or env
 * GOV003_DEMO_MODE=1). The session it returns is labelled DEMO / NOT LIVE and signed:false, proof:null -
 * downstream code must never treat it as signed GoTrue evidence.
 */
export class FixtureSessionAdapter extends SessionAdapter {
  #identities; #opts;
  constructor({ demo, env = process.env, identities = DEMO_IDENTITIES } = {}) {
    super();
    this.#opts = { demo, env };
    if (!isDemoModeEnabled(this.#opts)) {
      throw new AdapterError('DEMO_MODE_REQUIRED', 'FixtureSessionAdapter refuses to run unless demo mode is explicitly enabled');
    }
    this.#identities = Object.freeze({ ...identities });
  }
  get kind() { return 'fixture'; }
  async authenticate(request) {
    if (!isDemoModeEnabled(this.#opts)) throw new AdapterError('DEMO_MODE_REQUIRED', 'demo mode is not enabled');
    const h = (request && request.headers) || {};
    const label = (request && request.demoIdentity) ?? h['x-demo-identity'];
    if (typeof label !== 'string' || !Object.hasOwn(this.#identities, label)) {
      throw new AdapterError('FIXTURE_IDENTITY_UNKNOWN', 'unknown or missing demo identity label');
    }
    return Object.freeze({
      actor_id: this.#identities[label], source: 'fixture', signed: false, demo: true,
      label, banner: DEMO_BANNER, proof: null,
    });
  }
}

/** Server factory: demo mode on -> FixtureSessionAdapter, otherwise NoSignedSessionAdapter (fail closed). */
export function createSessionAdapter({ demo, env = process.env } = {}) {
  return isDemoModeEnabled({ demo, env }) ? new FixtureSessionAdapter({ demo, env }) : new NoSignedSessionAdapter();
}

/**
 * CONTRACT: CanonicalAuditAdapter - the one canonical CORE10 audit service (not built here).
 *   appendEvent(envelope, session) -> { receipt_id, event_digest, replayed }
 *   getReceipt(receipt_id, session) -> receipt row
 *   verifyChain(tenant_id, business_id, session) -> { ok, checked, first_bad_seq, reason }
 * The disposable c10_gov003_demo schema is a contract/test bed ONLY; adoption must be reconciled with that service.
 */
export class CanonicalAuditAdapter {
  get integrated() { return false; }
  async appendEvent() { throw new AdapterError('INTEGRATION_PENDING', 'Canonical CORE10 audit service integration is pending Owner approval'); }
  async getReceipt() { throw new AdapterError('INTEGRATION_PENDING', 'Canonical CORE10 audit service integration is pending Owner approval'); }
  async verifyChain() { throw new AdapterError('INTEGRATION_PENDING', 'Canonical CORE10 audit service integration is pending Owner approval'); }
}

/**
 * CONTRACT: GitHubVerifierAdapter - remote verification of commits and CI runs (never trusts caller-supplied URLs).
 *   verifyCommit({ repo, sha }) -> { exists, head_sha, is_ancestor_of_head }
 *   verifyCheckRun({ repo, sha, run_id }) -> { conclusion, head_sha, workflow, completed_at }
 * Until implemented, offline fixtures are SIMULATIONS and must never be reported as certification.
 */
export class GitHubVerifierAdapter {
  get integrated() { return false; }
  async verifyCommit() { throw new AdapterError('INTEGRATION_PENDING', 'Remote GitHub verification is not integrated; offline fixtures are simulations only'); }
  async verifyCheckRun() { throw new AdapterError('INTEGRATION_PENDING', 'Remote GitHub verification is not integrated; offline fixtures are simulations only'); }
}

/**
 * CONTRACT: DeployProbeAdapter - runtime smoke/health probe of a DEPLOYED artifact.
 *   probe({ environment, expected_artifact_sha256 }) -> { reachable, runtime_sha256, healthy, probed_at }
 * A queued CI job or a preview branch is never a deployment; only a real probe result can say "deployed".
 */
export class DeployProbeAdapter {
  get integrated() { return false; }
  async probe() { throw new AdapterError('INTEGRATION_PENDING', 'Real deployment probing is not integrated; no deployment is claimed'); }
}

export const ADAPTER_STATUS = Object.freeze({
  signed_gotrue_session: 'FUTURE_BLOCKER',
  a034_entitlement_parity: 'FUTURE_BLOCKER',
  canonical_audit_service: 'INTEGRATION_PENDING',
  github_remote_verification: 'INTEGRATION_PENDING',
  deploy_runtime_probe: 'INTEGRATION_PENDING',
});
