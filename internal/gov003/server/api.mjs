// GOV-003 LOCAL-ONLY JSON API. DEMO / NOT LIVE. Zero dependencies (node:http + the existing GOV-003 server modules).
//
// What this is: a thin, fail-closed HTTP face over the disposable PostgreSQL test bed (schema c10_gov003_demo).
// What this is NOT: a production API. It binds 127.0.0.1 only, authenticates ONLY through a SessionAdapter, and
// real signed GoTrue verification does not exist here - outside demo mode (env G3_DEMO=1) every /api request is
// rejected 401 SIGNED_SESSION_UNAVAILABLE. In demo mode the FixtureSessionAdapter maps an inert label in the
// X-Demo-Identity header to a fixture UUID. That is NOT signed evidence and the UI says so.
//
// Rules enforced here (each has a test in tests/gov003/demo):
//  * The actor comes ONLY from the SessionAdapter. Actor/role/tenant-authority/service-role claims in the body, the
//    query string or the headers are rejected 400 (never silently ignored); no request is forwarded to the DB.
//  * Reads go through role c10g3_reader (security_invoker views + RLS); writes through c10g3_backend RPCs only.
//    No SQL text is built from request data: every value travels as a psql variable (pg.mjs).
//  * Denied reads are one generic 403 (no existence/count leak). Unknown errors are one scrubbed generic 500.
//  * Every response carries the strict security headers and X-Demo-Mode: DEMO / NOT LIVE.
import http from 'node:http';
import { createHash, randomUUID } from 'node:crypto';
import { createPool, PgError } from './pg.mjs';
import { createSessionAdapter, DEMO_IDENTITIES, AdapterError } from './adapters.mjs';
import { securityHeaders } from './csp.mjs';
import { buildEnvelope, toSqlParams, assertNoAuthorityClaims, EnvelopeError } from './envelope.mjs';
import { PayloadError, scrubText } from './redact.mjs';

export const DEMO_MODE_HEADER = 'DEMO / NOT LIVE';
const S = 'c10_gov003_demo';

// ------------------------------------------------------------------------------------------------ fixture catalog
// Selectable TARGETS for the demo picker (opaque synthetic UUIDs from tests/gov003/fixtures/seed.sql). They are scope
// SELECTORS, never authority: the database decides, per call, what the session actor may do.
export const DEMO_TARGETS = Object.freeze([
  { tenant_id: '11111111-1111-4111-8111-111111111111', business_id: 'b1000000-0000-4000-8000-000000000001', label: 'Tenant One / Business A (synthetic)',
    sites: [{ site_id: '51000000-0000-4000-8000-000000000001', label: 'Site 1' }, { site_id: '51000000-0000-4000-8000-000000000002', label: 'Site 2' }] },
  { tenant_id: '11111111-1111-4111-8111-111111111111', business_id: 'b1000000-0000-4000-8000-000000000002', label: 'Tenant One / Business B (synthetic)',
    sites: [{ site_id: '51000000-0000-4000-8000-000000000003', label: 'Site 3' }] },
  { tenant_id: '22222222-2222-4222-8222-222222222222', business_id: 'b1000000-0000-4000-8000-000000000003', label: 'Tenant Two / Business C (synthetic)',
    sites: [{ site_id: '51000000-0000-4000-8000-000000000004', label: 'Site 4' }] },
]);
const LABEL_BY_ID = new Map(Object.entries(DEMO_IDENTITIES).map(([label, id]) => [id, label]));
const labelOf = (id) => LABEL_BY_ID.get(id) ?? null;

// ------------------------------------------------------------------------------------------------ errors
export class HttpError extends Error {
  constructor(status, error, message, extra = {}) { super(message); this.name = 'HttpError'; this.status = status; this.error = error; this.extra = extra; }
}
const bad = (message) => new HttpError(400, 'bad_request', message);

const GENERIC = Object.freeze({
  scope_denied: 'Access outside the permitted scope was denied.',
  internal_error: 'An internal error occurred.',
});

/** SQLSTATE (GOV-003 core) -> HTTP. Unknown -> 500 with a static body: no stack, no token, no SQL text. */
export function mapError(e) {
  if (e instanceof HttpError) return { status: e.status, body: { ok: false, error: e.error, message: e.message, ...e.extra } };
  if (e instanceof AdapterError) {
    return { status: 401, body: { ok: false, error: e.code, message: e.code === 'SIGNED_SESSION_UNAVAILABLE'
      ? 'No signed session verification is available in this local module; refusing every request (fail closed).'
      : 'Authentication failed.' } };
  }
  if (e instanceof EnvelopeError) return { status: 400, body: { ok: false, error: 'bad_request', code: e.code, message: scrubText(e.message) } };
  if (e instanceof PayloadError) return { status: 422, body: { ok: false, error: 'validation_failed', code: 'G3A03', message: scrubText(e.message) } };
  if (e instanceof PgError) {
    const d = scrubText(e.detail || '');
    switch (e.code) {
      case 'G3A01': return { status: 403, body: { ok: false, error: 'forged_actor', code: e.code, message: 'A caller-supplied actor does not match the server-derived actor.' } };
      case 'G3A02': return { status: 403, body: { ok: false, error: 'scope_denied', code: e.code, message: GENERIC.scope_denied } };
      case 'G3A05': return { status: 401, body: { ok: false, error: 'unauthenticated', code: e.code, message: 'The session actor is not a known identity.' } };
      case 'G3A06': return { status: 403, body: { ok: false, error: 'independent_review_required', code: e.code, message: 'A reviewer who is not an actor of the evidence is required.' } };
      case 'G3A03': return { status: 422, body: { ok: false, error: 'validation_failed', code: e.code, message: d } };
      case 'G3A04': return { status: 422, body: { ok: false, error: 'integrity_check_failed', code: e.code, message: d } };
      case 'G3C01': return { status: 409, body: { ok: false, error: 'idempotency_conflict', code: e.code, message: d } };
      case 'G3C02': return { status: 409, body: { ok: false, error: 'precondition_failed', code: e.code, message: d } };
      case 'G3C03': return { status: 409, body: { ok: false, error: 'baseline_missing', code: e.code, message: d } };
      case 'G3E01': return { status: 422, body: { ok: false, error: 'real_evidence_unavailable', code: e.code, message: d } };
      case 'G3H01': return { status: 409, body: { ok: false, error: 'append_only_violation', code: e.code, message: d } };
      case 'G3H02': return { status: 409, body: { ok: false, error: 'evidence_under_hold', code: e.code, message: d } };
      default: break;
    }
  }
  return { status: 500, body: { ok: false, error: 'internal_error', message: GENERIC.internal_error } };
}

// ------------------------------------------------------------------------------------------------ validation
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const IDEM_RE = /^[A-Za-z0-9_.:-]{8,100}$/;
const TOKEN_RE = /^[a-z][a-z0-9_.-]{1,63}$/;
const REF_RE = /^[A-Za-z0-9_.:/#-]{1,128}$/;
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$/;

const reqUuid = (v, name) => { if (typeof v !== 'string' || !UUID_RE.test(v)) throw bad(`${name} must be a UUID`); return v.toLowerCase(); };
const optUuid = (v, name) => (v === undefined || v === null || v === '' ? null : reqUuid(v, name));
const reqIdem = (v) => { if (typeof v !== 'string' || !IDEM_RE.test(v)) throw bad('idempotency_key must be 8-100 characters [A-Za-z0-9_.:-]'); return v; };
const optToken = (v, name) => { if (v === undefined || v === null || v === '') return null; if (typeof v !== 'string' || !TOKEN_RE.test(v)) throw bad(`${name} is malformed`); return v; };
const optIso = (v, name) => {
  if (v === undefined || v === null || v === '') return null;
  if (typeof v !== 'string' || !ISO_RE.test(v) || Number.isNaN(Date.parse(v))) throw bad(`${name} must be an ISO-8601 time with an explicit offset`);
  return v;
};
const intIn = (v, name, lo, hi, dflt) => {
  if (v === undefined || v === null || v === '') return dflt;
  const n = typeof v === 'number' ? v : (/^\d{1,9}$/.test(String(v)) ? Number(v) : NaN);
  if (!Number.isInteger(n) || n < lo || n > hi) throw bad(`${name} must be an integer ${lo}..${hi}`);
  return n;
};

// Authority-claim detection beyond the envelope's own list (which assertNoAuthorityClaims also applies).
const EXTRA_FORBIDDEN_KEYS = new Set(['tenant', 'tenant_name', 'business', 'business_name', 'demo_identity', 'identity_label',
  'service_key', 'apikey', 'api_key', 'x_demo_identity', 'actor_label', 'created_by', 'reviewer', 'reviewer_id', 'approved_by']);
const FORBIDDEN_HEADERS = ['x-actor', 'x-actor-id', 'x-user', 'x-user-id', 'x-role', 'x-roles', 'x-tenant-role', 'x-service-role',
  'x-claimed-actor', 'x-impersonate', 'x-on-behalf-of', 'x-forwarded-user', 'x-jwt-sub', 'x-tenant-id', 'x-business-id', 'authorization', 'apikey'];

function rejectAuthorityClaims(obj, where) {
  const walk = (o, depth) => {
    if (o === null || typeof o !== 'object' || depth > 6) return;
    for (const k of Object.keys(o)) {
      if (EXTRA_FORBIDDEN_KEYS.has(k.toLowerCase())) throw bad(`"${k.slice(0, 40)}" in the ${where} is an authority claim and is rejected; the actor is derived by the session boundary only`);
    }
    for (const v of Object.values(o)) walk(v, depth + 1);
  };
  try { assertNoAuthorityClaims(obj, where); } catch (e) {
    if (e instanceof EnvelopeError) throw bad(scrubText(e.message));
    throw e;
  }
  walk(obj, 0);
}

// ------------------------------------------------------------------------------------------------ SQL (trusted constants)
const SQL = {
  gateRead: `select ${S}.can_read_business(:'tenant_id'::uuid, :'business_id'::uuid) as ok`,
  gateReadOrSupport: `select (${S}.can_read_business(:'tenant_id'::uuid, :'business_id'::uuid)
                          or ${S}.has_support_grant(:'tenant_id'::uuid, :'business_id'::uuid)) as ok`,
  auditList: `select
      (select count(*) from ${S}.v_audit_events e where e.tenant_id = :'tenant_id'::uuid and e.business_id = :'business_id'::uuid) as total_count,
      (select count(*) from ${S}.v_audit_events e where e.tenant_id = :'tenant_id'::uuid and e.business_id = :'business_id'::uuid
          and (nullif(:'action','') is null or e.action = :'action')
          and (nullif(:'source_domain','') is null or e.source_domain = :'source_domain')
          and (nullif(:'from_ts','') is null or e.event_time >= nullif(:'from_ts','')::timestamptz)
          and (nullif(:'to_ts','') is null or e.event_time < nullif(:'to_ts','')::timestamptz)) as filtered_count,
      (select coalesce(jsonb_agg(to_jsonb(x) order by x.stream_seq desc), '[]'::jsonb) from (
          select e.event_id, e.stream_seq, e.site_id, e.source_domain, e.source_id, e.source_version, e.action, e.event_time,
                 e.ingest_time, e.actor_id, e.correlation_id, e.idempotency_key, e.payload, e.payload_sha256, e.prior_digest,
                 e.event_digest, e.reason_category, e.receipt_id, e.receipt_digest
            from ${S}.v_audit_events e
           where e.tenant_id = :'tenant_id'::uuid and e.business_id = :'business_id'::uuid
             and (nullif(:'action','') is null or e.action = :'action')
             and (nullif(:'source_domain','') is null or e.source_domain = :'source_domain')
             and (nullif(:'from_ts','') is null or e.event_time >= nullif(:'from_ts','')::timestamptz)
             and (nullif(:'to_ts','') is null or e.event_time < nullif(:'to_ts','')::timestamptz)
           order by e.stream_seq desc limit :'lim'::int offset :'off'::int) x) as events,
      (select coalesce(jsonb_agg(distinct e.action order by e.action), '[]'::jsonb) from ${S}.v_audit_events e
        where e.tenant_id = :'tenant_id'::uuid and e.business_id = :'business_id'::uuid) as actions,
      (select coalesce(jsonb_agg(distinct e.source_domain order by e.source_domain), '[]'::jsonb) from ${S}.v_audit_events e
        where e.tenant_id = :'tenant_id'::uuid and e.business_id = :'business_id'::uuid) as source_domains`,
  verifyChain: `select ok, checked, first_bad_seq, reason from ${S}.verify_chain(:'tenant_id'::uuid, :'business_id'::uuid)`,
  append: `select outcome, event_id, receipt_id, stream_seq, event_digest, receipt_digest, replayed, payload_sha256
      from ${S}.append_event_logged(:'tenant_id'::uuid, :'business_id'::uuid, nullif(:'site_id', '')::uuid, nullif(:'legal_entity_id', '')::uuid,
        :'source_domain', :'source_id', :'source_version', :'action', :'event_time'::timestamptz, :'correlation_id', :'idempotency_key',
        :'payload'::jsonb, :'payload_sha256', :'reason_category', null::uuid, :'event_id'::uuid)`,
  signals: `select s.signal_id, s.rule_id, s.signal_key, s.severity, s.disposition, s.confidence_pct, s.reason, s.source_domain,
        s.window_start, s.window_end, s.context, s.evidence_actor_ids, s.detected_at, s.receipt_id, s.status, s.review_decision,
        s.review_reason_code, s.reviewer_id, s.reviewed_at, s.review_receipt_id,
        (select coalesce(jsonb_agg(jsonb_build_object('evidence_kind', ev.evidence_kind, 'event_id', ev.event_id, 'receipt_id', ev.receipt_id,
            'log_id', ev.log_id, 'ref', ev.ref,
            'stream_seq', (select a.stream_seq from ${S}.v_audit_events a where a.event_id = ev.event_id),
            'event_digest', (select a.event_digest from ${S}.v_audit_events a where a.event_id = ev.event_id),
            'action', (select a.action from ${S}.v_audit_events a where a.event_id = ev.event_id)) order by ev.evidence_id), '[]'::jsonb)
           from ${S}.v_risk_signal_evidence ev where ev.signal_id = s.signal_id) as evidence
      from ${S}.v_risk_signals s
     where s.tenant_id = :'tenant_id'::uuid and s.business_id = :'business_id'::uuid
     order by s.detected_at desc, s.signal_id`,
  detect: `select signal_id, rule_id, signal_key, created, receipt_id
      from ${S}.run_risk_detection(:'tenant_id'::uuid, :'business_id'::uuid, nullif(:'as_of','')::timestamptz, null::uuid)`,
  review: `select review_id, signal_id, decision, reason_code, receipt_id, replayed
      from ${S}.review_signal(:'signal_id'::uuid, :'decision', :'reason_code', :'idem', null::uuid)`,
  readinessFeatures: `select f.feature_id, f.title, f.registered_at, f.readiness from ${S}.v_readiness_features f
     where f.tenant_id = :'tenant_id'::uuid and f.business_id = :'business_id'::uuid order by f.feature_id`,
  readinessHeads: `select feature_id, head_seq, head_sha, recorded_at from ${S}.v_readiness_heads
     where tenant_id = :'tenant_id'::uuid and business_id = :'business_id'::uuid order by feature_id, head_seq`,
  readinessProofs: `select proof_seq, feature_id, level, commit_sha, environment, run_ref, simulated, evidence_sha256, outcome, recorded_at, is_current_head
      from ${S}.v_readiness_proofs where tenant_id = :'tenant_id'::uuid and business_id = :'business_id'::uuid order by proof_seq`,
  incCases: `select case_id, case_ref, severity, category, opened_at, site_id, audit_receipt_id from ${S}.v_incident_cases
     where tenant_id = :'tenant_id'::uuid and business_id = :'business_id'::uuid order by opened_at`,
  incEvidence: `select c.case_ref, e.evidence_id, e.item_seq, e.evidence_ref, e.kind, e.sha256, e.byte_length, e.source_ref, e.retain_until,
        e.added_at, e.item_digest, e.audit_receipt_id, e.purged, e.purged_at
      from ${S}.v_incident_evidence e join ${S}.v_incident_cases c on c.case_id = e.case_id
     where e.tenant_id = :'tenant_id'::uuid and e.business_id = :'business_id'::uuid order by c.case_ref, e.item_seq`,
  incHolds: `select c.case_ref, h.hold_ref, h.evidence_id, h.reason_category, h.retention_until, h.placed_at, h.review_status, h.released, h.in_force
      from ${S}.v_incident_holds h join ${S}.v_incident_cases c on c.case_id = h.case_id
     where h.tenant_id = :'tenant_id'::uuid and h.business_id = :'business_id'::uuid order by h.placed_at`,
  manifest: `select ok, item_count, purged_count, manifest_digest, first_bad_seq, reason
      from ${S}.verify_manifest(:'tenant_id'::uuid, :'business_id'::uuid, :'case_ref')`,
  purge: `select outcome, error_code, protection, evidence_id, audit_receipt_id, replayed, notice
      from ${S}.purge_evidence_attempt(:'tenant_id'::uuid, :'business_id'::uuid, :'case_ref', :'evidence_ref', :'reason_code', :'idem', null::uuid)`,
  exportCsv: `select outcome, export_receipt_id, audit_receipt_id, audit_event_id, row_count, byte_length, byte_sha256, filter_sha256,
        source_version, issued_at, receipt_digest, replayed, csv_text
      from ${S}.export_audit_csv(:'tenant_id'::uuid, :'business_id'::uuid, :'idem', nullif(:'from_ts','')::timestamptz,
        nullif(:'to_ts','')::timestamptz, nullif(:'action',''), nullif(:'source_domain',''), :'max_rows'::int, null::uuid)`,
  exportVerify: `select ok, export_receipt_id, row_count, byte_length, byte_sha256, audit_receipt_id, source_version, issued_at
      from ${S}.verify_export(:'receipt_id'::uuid, :'csv')`,
  receipts: `select export_receipt_id, row_count, byte_sha256, byte_length, source_version, issued_at, audit_receipt_id
      from ${S}.v_export_receipts where tenant_id = :'tenant_id'::uuid and business_id = :'business_id'::uuid order by issued_at desc limit 10`,
  trace: `select snapshot_id, source_label, imported_at, snapshot_sha256, verdict, violations, summary, receipt_id
      from ${S}.v_trace_snapshots where tenant_id = :'tenant_id'::uuid and business_id = :'business_id'::uuid order by imported_at desc limit 5`,
  recordError: `select error_id, error_code, public_message, scrubbed_detail
      from ${S}.record_safe_error(:'tenant_id'::uuid, :'business_id'::uuid, nullif(:'site_id','')::uuid, 'INTERNAL', :'detail', :'context'::jsonb, :'correlation_id')`,
  errors: `select error_id, site_id, error_code, public_message, scrubbed_detail, correlation_id, occurred_at from ${S}.v_safe_errors
     where tenant_id = :'tenant_id'::uuid and business_id = :'business_id'::uuid order by occurred_at desc limit 20`,
  baselines: `select baseline_id, baseline_seq, snapshot_id, approved_at, inventory_sha256, receipt_id from ${S}.v_catalog_baselines
     where tenant_id = :'tenant_id'::uuid and business_id = :'business_id'::uuid order by baseline_seq desc limit 5`,
  diffs: `select diff_id, baseline_id, label, diff, diff_sha256, finding_count, max_severity, requested_at, signal_id, receipt_id
      from ${S}.v_catalog_diffs where tenant_id = :'tenant_id'::uuid and business_id = :'business_id'::uuid order by requested_at desc limit 3`,
  snapshot: `select snapshot_id, receipt_id, inventory_sha256, item_count, replayed from ${S}.take_snapshot(:'tenant_id'::uuid, :'business_id'::uuid, :'idem', null::uuid)`,
  baseline: `select baseline_id, baseline_seq, snapshot_id, receipt_id, inventory_sha256, replayed
      from ${S}.record_baseline(:'tenant_id'::uuid, :'business_id'::uuid, :'idem', null::uuid, null::uuid)`,
  diff: `select diff_id, baseline_id, snapshot_id, receipt_id, finding_count, max_severity, diff_sha256, signal_id, replayed
      from ${S}.diff_against_baseline(:'tenant_id'::uuid, :'business_id'::uuid, :'idem', null::uuid, null::uuid)`,
};

// Candidate scope rows for GET /api/me: the database answers can_read / can_write for the session actor.
const ME_SQL = (() => {
  const rows = [];
  for (const t of DEMO_TARGETS) {
    rows.push(`('${t.tenant_id}'::uuid, '${t.business_id}'::uuid, null::uuid)`);
    for (const s of t.sites) rows.push(`('${t.tenant_id}'::uuid, '${t.business_id}'::uuid, '${s.site_id}'::uuid)`);
  }
  return `select v.tenant_id, v.business_id, v.site_id, ${S}.can_read_business(v.tenant_id, v.business_id) as can_read,
      ${S}.can_write_scope(v.tenant_id, v.business_id, v.site_id) as can_write
    from (values ${rows.join(', ')}) as v(tenant_id, business_id, site_id)`;
})();

// Synthetic, secret-laden error. Assembled at runtime from fragments so that no secret-looking literal exists in
// source, and used ONLY to prove scrubbing: the raw text is never returned, logged or stored.
function syntheticSecretError() {
  const jwt = ['ey' + 'JhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9', 'ey' + 'JzdWIiOiJkZW1vLXN5bnRoZXRpYyJ9', 'c3ludGhldGljLXNpZ25hdHVyZQ'].join('.');
  const planted = {
    password: 'hunter2-' + 'synthetic',
    jwt,
    email: 'ops.demo' + '@' + 'example.test',
    connection_string: 'postgres' + '://svc_user:Pa55w0rd-synthetic@db.internal.invalid:5432/app',
    card_number: '4111' + '111111111111',
    stack_frame: '/srv/app/handlers/export.js',
  };
  const text = `Error: connection failed password=${planted.password} Authorization: Bearer ${planted.jwt} contact ${planted.email} `
    + `via ${planted.connection_string} card ${planted.card_number}\n    at handler (${planted.stack_frame}:41:9)\n    at next (/srv/app/node_modules/x/index.js:7:1)`;
  return { text, planted };
}

// ------------------------------------------------------------------------------------------------ server
const MAX_BODY_DEFAULT = 1024 * 1024;
const MAX_BODY_VERIFY = 9 * 1024 * 1024;

/**
 * createApiHandler({ pool, sessionAdapter, env, log }) -> async (req, res) => boolean
 * Handles ONLY paths beginning /api/ (returns false otherwise so a static handler can take over).
 */
export function createApiHandler(options = {}) {
  const env = options.env ?? process.env;
  const pool = options.pool ?? createPool({ env, database: options.database });
  // GOV003_DEMO_MODE is deliberately ignored: this server is armed by G3_DEMO=1 only.
  const adapter = options.sessionAdapter ?? createSessionAdapter({ demo: env.G3_DEMO === '1', env: {} });
  const log = options.log ?? (() => {});

  const rd = (ctx) => ({ role: 'c10g3_reader', actor: ctx.session.actor_id });
  const be = (ctx) => ({ role: 'c10g3_backend', actor: ctx.session.actor_id });
  const q = (ctx, role, sql, params) => pool.queryAsync(sql, params, role === 'reader' ? rd(ctx) : be(ctx));

  function scopeOf(src) {
    return { tenant_id: reqUuid(src.tenant_id, 'tenant_id'), business_id: reqUuid(src.business_id, 'business_id') };
  }
  async function gateRead(ctx, scope, support = false) {
    const [r] = await q(ctx, 'reader', support ? SQL.gateReadOrSupport : SQL.gateRead, scope);
    if (!r || r.ok !== true) throw new HttpError(403, 'scope_denied', GENERIC.scope_denied);
  }
  const withLabels = (row, keys) => { const o = { ...row }; for (const k of keys) if (o[k]) o[`${k}_label`] = labelOf(o[k]); return o; };

  // ------------------------------------------------------------ handlers
  async function me(ctx) {
    const rows = await q(ctx, 'backend', ME_SQL, {});
    const targets = DEMO_TARGETS.map((t) => {
      const biz = rows.find((r) => r.business_id === t.business_id && r.site_id === null);
      return {
        tenant_id: t.tenant_id, business_id: t.business_id, label: t.label,
        can_read: biz?.can_read === true, can_write: biz?.can_write === true,
        sites: t.sites.map((s) => ({ site_id: s.site_id, label: s.label,
          can_write: rows.find((r) => r.site_id === s.site_id)?.can_write === true })),
      };
    });
    return { status: 200, body: {
      banner: DEMO_MODE_HEADER, signed: false, session_source: ctx.session.source,
      actor: { label: ctx.session.label, actor_id: ctx.session.actor_id },
      targets,
      limitations: [
        'Fixture identity from a header: NOT a signed GoTrue session. Real signed-session and A034 parity are future blockers.',
        'A hash chain inside a mutable PostgreSQL database is tamper-evident for ordinary principals, not WORM storage.',
        'Signals and grant findings are advisory review prompts only; nothing here freezes, blocks, pays, approves or changes a role.',
      ],
    } };
  }

  async function auditList(ctx) {
    const scope = scopeOf(ctx.query);
    const params = {
      ...scope, action: optToken(ctx.query.action, 'action') ?? '', source_domain: optToken(ctx.query.source_domain, 'source_domain') ?? '',
      from_ts: optIso(ctx.query.from, 'from') ?? '', to_ts: optIso(ctx.query.to, 'to') ?? '',
      lim: intIn(ctx.query.limit, 'limit', 1, 200, 50), off: intIn(ctx.query.offset, 'offset', 0, 1000000, 0),
    };
    await gateRead(ctx, scope);
    const [r] = await q(ctx, 'reader', SQL.auditList, params);
    return { status: 200, body: {
      total_count: Number(r.total_count), filtered_count: Number(r.filtered_count), limit: params.lim, offset: params.off,
      filters: { action: params.action || null, source_domain: params.source_domain || null, from: params.from_ts || null, to: params.to_ts || null },
      actions: r.actions, source_domains: r.source_domains,
      events: r.events.map((e) => withLabels(e, ['actor_id'])),
    } };
  }

  async function auditVerify(ctx) {
    const scope = scopeOf(ctx.query);
    const [r] = await q(ctx, 'reader', SQL.verifyChain, scope);
    return { status: 200, body: { ok: r.ok === true, checked: Number(r.checked), first_bad_seq: r.first_bad_seq, reason: r.reason,
      limitation: 'Tamper-evidence for ordinary principals only; not WORM protection against a privileged DBA.' } };
  }

  async function auditAppend(ctx) {
    const b = ctx.body;
    const idem = reqIdem(b.idempotency_key);
    const input = { ...b, idempotency_key: idem };
    if (input.event_time === undefined) input.event_time = new Date().toISOString();
    if (input.correlation_id === undefined) input.correlation_id = idem;
    if (input.source_version === undefined) input.source_version = 'v1';
    if (input.reason_category === undefined) input.reason_category = 'operational';
    const env = buildEnvelope(input);
    const [r] = await q(ctx, 'backend', SQL.append, toSqlParams(env));
    if (r.outcome === 'conflict') {
      throw new HttpError(409, 'idempotency_conflict', 'This idempotency key was already used with a different payload or command; nothing was stored.');
    }
    return { status: r.replayed ? 200 : 201, body: {
      outcome: r.outcome, replayed: r.replayed === true, event_id: r.event_id, receipt_id: r.receipt_id, stream_seq: Number(r.stream_seq),
      event_digest: r.event_digest, receipt_digest: r.receipt_digest, payload_sha256: r.payload_sha256,
      note: r.replayed ? 'Exact replay: the original receipt was returned and no new effect was stored.' : 'Stored. The actor was derived by the server from the session.',
    } };
  }

  async function signalsList(ctx) {
    const scope = scopeOf(ctx.query);
    await gateRead(ctx, scope);
    const rows = await q(ctx, 'reader', SQL.signals, scope);
    return { status: 200, body: {
      advisory_notice: 'ADVISORY ONLY: signals are review prompts, not accusations. Nothing is frozen, blocked, paid, approved or changed automatically.',
      signals: rows.map((s) => ({ ...withLabels(s, ['reviewer_id']), evidence_actor_labels: (s.evidence_actor_ids || []).map(labelOf) })),
    } };
  }

  async function signalsDetect(ctx) {
    const scope = scopeOf(ctx.body);
    const asOf = optIso(ctx.body.as_of, 'as_of') ?? '';
    const rows = await q(ctx, 'backend', SQL.detect, { ...scope, as_of: asOf });
    return { status: 200, body: {
      advisory_notice: 'Detection only wrote advisory signals and their audit receipts. No stock, money, approval or role data was touched.',
      created: rows.filter((r) => r.created).length, existing: rows.filter((r) => !r.created).length, signals: rows } };
  }

  async function signalReview(ctx, [signalId]) {
    const sid = reqUuid(signalId, 'signal id');
    const decision = ctx.body.decision;
    if (decision !== 'acknowledge' && decision !== 'dismiss') throw bad('decision must be acknowledge or dismiss');
    const reason = optToken(ctx.body.reason_code, 'reason_code');
    if (!reason) throw bad('reason_code is required');
    const [r] = await q(ctx, 'backend', SQL.review, { signal_id: sid, decision, reason_code: reason, idem: reqIdem(ctx.body.idempotency_key) });
    return { status: r.replayed ? 200 : 201, body: { ...r, advisory_notice: 'Review recorded as an append-only receipt. It changes no stock, money, approval or role data.' } };
  }

  async function readiness(ctx) {
    const scope = scopeOf(ctx.query);
    await gateRead(ctx, scope);
    const [features, heads, proofs] = await Promise.all([
      q(ctx, 'reader', SQL.readinessFeatures, scope), q(ctx, 'reader', SQL.readinessHeads, scope), q(ctx, 'reader', SQL.readinessProofs, scope)]);
    return { status: 200, body: {
      levels: ['proposed', 'code_built', 'isolated_test_pass', 'signed_stage_verified', 'integrated_verified', 'deployed_verified', 'released'],
      features, heads, proofs,
      notice: 'State is derived from proof rows bound to the current head sha. Simulated or isolated proofs can never satisfy signed-session, integration, deployment or release levels.',
    } };
  }

  async function incidents(ctx) {
    const scope = scopeOf(ctx.query);
    await gateRead(ctx, scope);
    const [cases, evidence, holds] = await Promise.all([q(ctx, 'reader', SQL.incCases, scope), q(ctx, 'reader', SQL.incEvidence, scope), q(ctx, 'reader', SQL.incHolds, scope)]);
    const manifests = {};
    for (const c of cases) { const [m] = await q(ctx, 'reader', SQL.manifest, { ...scope, case_ref: c.case_ref }); manifests[c.case_ref] = m; }
    return { status: 200, body: { cases, evidence, holds, manifests,
      notice: 'Engineering control in a mutable database only. This is not a legal-hold certification; legal retention decisions are an Owner/counsel gate.' } };
  }

  async function purgeAttempt(ctx, [caseRefEnc]) {
    let caseRef;
    try { caseRef = decodeURIComponent(caseRefEnc); } catch { throw bad('case reference is malformed'); }
    if (!REF_RE.test(caseRef)) throw bad('case reference is malformed');
    const scope = scopeOf(ctx.body);
    const evidenceRef = ctx.body.evidence_ref;
    if (typeof evidenceRef !== 'string' || !REF_RE.test(evidenceRef)) throw bad('evidence_ref is malformed');
    const reasonCode = optToken(ctx.body.reason_code ?? 'retention_expiry', 'reason_code');
    const [r] = await q(ctx, 'backend', SQL.purge, { ...scope, case_ref: caseRef, evidence_ref: evidenceRef, reason_code: reasonCode, idem: reqIdem(ctx.body.idempotency_key) });
    if (r.outcome === 'refused') {
      return { status: 409, body: { ok: false, error: 'evidence_under_hold', outcome: r.outcome, code: r.error_code, protection: r.protection,
        evidence_id: r.evidence_id, audit_receipt_id: r.audit_receipt_id, replayed: r.replayed === true, notice: r.notice,
        message: 'Purge refused: the evidence is under a hold or retention rule. The refusal itself was recorded as an audit receipt.' } };
    }
    return { status: 200, body: { outcome: r.outcome, evidence_id: r.evidence_id, audit_receipt_id: r.audit_receipt_id, replayed: r.replayed === true, notice: r.notice } };
  }

  async function exportCreate(ctx) {
    const scope = scopeOf(ctx.body);
    const params = { ...scope, idem: reqIdem(ctx.body.idempotency_key), from_ts: optIso(ctx.body.from, 'from') ?? '', to_ts: optIso(ctx.body.to, 'to') ?? '',
      action: optToken(ctx.body.action, 'action') ?? '', source_domain: optToken(ctx.body.source_domain, 'source_domain') ?? '',
      max_rows: intIn(ctx.body.max_rows, 'max_rows', 1, 10000, 10000) };
    const [r] = await q(ctx, 'backend', SQL.exportCsv, params);
    const recomputed = createHash('sha256').update(Buffer.from(r.csv_text, 'utf8')).digest('hex');
    return { status: r.replayed ? 200 : 201, body: {
      outcome: r.outcome, replayed: r.replayed === true,
      receipt: { export_receipt_id: r.export_receipt_id, audit_receipt_id: r.audit_receipt_id, audit_event_id: r.audit_event_id, row_count: Number(r.row_count),
        byte_length: Number(r.byte_length), byte_sha256: r.byte_sha256, filter_sha256: r.filter_sha256, source_version: r.source_version,
        issued_at: r.issued_at, receipt_digest: r.receipt_digest },
      sha256_recomputed: recomputed, sha256_matches: recomputed === r.byte_sha256, csv_spec: 'g3csv1', csv: r.csv_text,
      note: 'The CSV is hashed as exact UTF-8 bytes; the receipt and an audit event record the hash, row count, filter and source version.' } };
  }

  async function exportVerify(ctx) {
    if (typeof ctx.body.csv !== 'string') throw bad('csv must be a string');
    const [r] = await q(ctx, 'reader', SQL.exportVerify, { receipt_id: reqUuid(ctx.body.export_receipt_id, 'export_receipt_id'), csv: ctx.body.csv });
    return { status: 200, body: { ok: r.ok === true, receipt: r } };
  }

  async function exportList(ctx) {
    const scope = scopeOf(ctx.query);
    await gateRead(ctx, scope);
    return { status: 200, body: { receipts: await q(ctx, 'reader', SQL.receipts, scope) } };
  }

  async function trace(ctx) {
    const scope = scopeOf(ctx.query);
    await gateRead(ctx, scope);
    return { status: 200, body: { snapshots: await q(ctx, 'reader', SQL.trace, scope),
      notice: 'Requirement graph snapshots are imported from safe local data; Drive history is never rewritten.' } };
  }

  async function errorsDemo(ctx) {
    const scope = scopeOf(ctx.body);
    const site = optUuid(ctx.body.site_id, 'site_id') ?? '';
    const { text, planted } = syntheticSecretError();
    const [r] = await q(ctx, 'backend', SQL.recordError, { ...scope, site_id: site, detail: text,
      context: JSON.stringify({ detail_code: 'demo_synthetic' }), correlation_id: `demo-err-${randomUUID()}` });
    const projection = { error_id: r.error_id, error_code: r.error_code, public_message: r.public_message, scrubbed_detail: r.scrubbed_detail };
    const leaked = Object.values(planted).some((v) => JSON.stringify(projection).includes(v) || JSON.stringify(projection).includes(v.slice(0, 12)));
    if (leaked) throw new Error('scrubber failed closed'); // -> generic 500, nothing returned
    return { status: 201, body: { projection, planted_marker_kinds: Object.keys(planted), raw_text_returned: false,
      note: 'A synthetic error containing secret-like markers was generated server-side. Only the allow-listed safe projection is shown; the raw text is neither returned nor stored.' } };
  }

  async function errorsList(ctx) {
    const scope = scopeOf(ctx.query);
    await gateRead(ctx, scope, true);
    return { status: 200, body: { errors: await q(ctx, 'reader', SQL.errors, scope) } };
  }

  async function grantsGet(ctx) {
    const scope = scopeOf(ctx.query);
    await gateRead(ctx, scope);
    const [baselines, diffs] = await Promise.all([q(ctx, 'reader', SQL.baselines, scope), q(ctx, 'reader', SQL.diffs, scope)]);
    const cut = diffs.map((d) => ({ ...d, diff: { ...d.diff, findings: (d.diff?.findings || []).slice(0, 200) } }));
    return { status: 200, body: { baselines, diffs: cut,
      notice: 'ADVISORY. This module only reads the permission catalog; it never runs GRANT, REVOKE or ALTER, and it takes the baseline from the owner-approved stored snapshot, never from a caller.' } };
  }
  const grantsAction = (sql) => async (ctx) => {
    const [r] = await q(ctx, 'backend', sql, { ...scopeOf(ctx.body), idem: reqIdem(ctx.body.idempotency_key) });
    return { status: r.replayed ? 200 : 201, body: { ...r, advisory_notice: 'Advisory result. No permission was changed.' } };
  };

  // ------------------------------------------------------------ routing
  const routes = [
    ['GET', /^\/api\/me$/, me],
    ['GET', /^\/api\/audit$/, auditList],
    ['GET', /^\/api\/audit\/verify$/, auditVerify],
    ['POST', /^\/api\/audit\/append$/, auditAppend],
    ['GET', /^\/api\/signals$/, signalsList],
    ['POST', /^\/api\/signals\/detect$/, signalsDetect],
    ['POST', /^\/api\/signals\/([0-9a-fA-F-]{36})\/review$/, signalReview],
    ['GET', /^\/api\/readiness$/, readiness],
    ['GET', /^\/api\/incidents$/, incidents],
    ['POST', /^\/api\/incidents\/([^/]{1,200})\/purge-attempt$/, purgeAttempt],
    ['GET', /^\/api\/export$/, exportList],
    ['POST', /^\/api\/export$/, exportCreate],
    ['POST', /^\/api\/export\/verify$/, exportVerify, MAX_BODY_VERIFY],
    ['GET', /^\/api\/trace$/, trace],
    ['GET', /^\/api\/errors$/, errorsList],
    ['POST', /^\/api\/errors\/demo$/, errorsDemo],
    ['GET', /^\/api\/grants\/diff$/, grantsGet],
    ['POST', /^\/api\/grants\/diff$/, grantsAction(SQL.diff)],
    ['POST', /^\/api\/grants\/baseline$/, grantsAction(SQL.baseline)],
    ['POST', /^\/api\/grants\/snapshot$/, grantsAction(SQL.snapshot)],
  ];

  function send(res, status, body, reqId) {
    const payload = JSON.stringify(body);
    const h = { ...securityHeaders(), 'x-demo-mode': DEMO_MODE_HEADER, 'x-request-id': reqId,
      'content-type': 'application/json; charset=utf-8', 'content-length': Buffer.byteLength(payload) };
    // an unread (oversized / rejected) request body must not poison a kept-alive connection
    if (res.req && !res.req.complete) h.connection = 'close';
    res.writeHead(status, h);
    res.end(payload);
  }

  async function readBody(req, limit) {
    const type = String(req.headers['content-type'] || '').split(';')[0].trim().toLowerCase();
    if (type !== 'application/json') throw new HttpError(415, 'unsupported_media_type', 'Content-Type must be application/json.');
    const chunks = []; let size = 0;
    for await (const c of req) {
      size += c.length;
      if (size > limit) throw new HttpError(413, 'payload_too_large', 'The request body is too large.');
      chunks.push(c);
    }
    let parsed;
    try { parsed = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw bad('body must be valid JSON'); }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) throw bad('body must be a JSON object');
    return parsed;
  }

  return async function handle(req, res) {
    const reqUrl = new URL(req.url, 'http://127.0.0.1');
    if (!reqUrl.pathname.startsWith('/api/') && reqUrl.pathname !== '/api') return false;
    const reqId = randomUUID();
    try {
      // DNS-rebinding guard: only literal loopback host names are served.
      const host = String(req.headers.host || '').toLowerCase().replace(/:\d+$/, '');
      if (host !== '127.0.0.1' && host !== 'localhost') throw new HttpError(403, 'host_not_allowed', 'This local demo only answers on 127.0.0.1.');
      // Fail closed: authentication FIRST (outside demo mode every request ends here with 401).
      const session = await adapter.authenticate({ headers: req.headers });
      const ctx = { req, res, session, query: Object.fromEntries(reqUrl.searchParams), body: null };
      for (const h of FORBIDDEN_HEADERS) {
        if (req.headers[h] !== undefined) throw bad(`header "${h}" is an authority claim and is rejected; the actor is derived by the session boundary only`);
      }
      rejectAuthorityClaims(ctx.query, 'query string');
      const route = routes.find(([m, re]) => m === req.method && re.test(reqUrl.pathname));
      if (!route) {
        const known = routes.some(([, re]) => re.test(reqUrl.pathname));
        throw new HttpError(known ? 405 : 404, known ? 'method_not_allowed' : 'not_found', known ? 'Method not allowed.' : 'Unknown endpoint.');
      }
      const [method, re, fn, limit] = route;
      if (method === 'POST') {
        ctx.body = await readBody(req, limit ?? MAX_BODY_DEFAULT);
        rejectAuthorityClaims(ctx.body, 'request body');
      }
      const out = await fn(ctx, re.exec(reqUrl.pathname).slice(1));
      send(res, out.status, { ...(out.body.ok === false ? {} : { ok: true }), demo: DEMO_MODE_HEADER, request_id: reqId, ...out.body }, reqId);
    } catch (e) {
      const mapped = mapError(e);
      if (mapped.status === 500) log(`internal error (${e && e.code ? String(e.code).slice(0, 12) : e && e.name ? String(e.name).slice(0, 24) : 'unknown'}) request=${reqId}`);
      send(res, mapped.status, { demo: DEMO_MODE_HEADER, request_id: reqId, ...mapped.body }, reqId);
    }
    return true;
  };
}

/** Local server on 127.0.0.1 only. `fallback(req,res)` serves non-/api paths (static files) when supplied. */
export async function startApiServer(options = {}) {
  const host = options.host ?? '127.0.0.1';
  if (host !== '127.0.0.1') throw new Error('GOV-003 API binds 127.0.0.1 only');
  const api = createApiHandler(options);
  const server = http.createServer((req, res) => {
    api(req, res).then((handled) => {
      if (handled) return undefined;
      if (options.fallback) return options.fallback(req, res);
      res.writeHead(404, { ...securityHeaders(), 'x-demo-mode': DEMO_MODE_HEADER, 'content-type': 'application/json; charset=utf-8' });
      return res.end(JSON.stringify({ ok: false, error: 'not_found' }));
    }).catch(() => { if (!res.headersSent) res.writeHead(500); res.end(); });
  });
  server.requestTimeout = 60000;
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(options.port ?? 0, host, resolve); });
  const { port } = server.address();
  return { server, port, url: `http://127.0.0.1:${port}`,
    close: () => new Promise((resolve) => { server.close(() => resolve()); server.closeAllConnections?.(); }) };
}
