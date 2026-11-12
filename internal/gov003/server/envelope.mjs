// GOV-003 typed, versioned event envelope builder/validator. Zero dependencies. DEMO / NOT LIVE contract core.
//
// The envelope carries ONLY scope selectors and facts about the source event. It never carries an actor, role,
// permission or any tenant authority claim: the actor is derived by the trusted boundary (SQL actor_id() from the
// verified session) and any caller attempt to supply one is rejected here and again in SQL (G3A01 forged_actor).
// `ingest_time` is a reserved slot: it is assigned by the append function (clock_timestamp()) and is part of the
// event digest, so the caller can neither choose nor predict it.
import { randomUUID } from 'node:crypto';
import { canonicalJson, sha256Hex, utcIso, CanonicalError } from './canonical.mjs';
import { redactPayload, validatePayload, looksSecret, PayloadError } from './redact.mjs';

export class EnvelopeError extends Error {
  constructor(code, message) { super(message); this.name = 'EnvelopeError'; this.code = code; }
}

export const ENVELOPE_SCHEMA_VERSION = 1;
export const REASON_CATEGORIES = Object.freeze(['operational', 'security', 'compliance', 'finance', 'inventory',
  'access', 'readiness', 'export', 'incident', 'review', 'other']);

// Any of these keys (case-insensitive, also nested one level in `meta`-style objects) is an authority claim.
const FORBIDDEN_AUTHORITY = new Set([
  'actor', 'actor_id', 'actorid', 'claimed_actor', 'acting_as', 'on_behalf_of', 'user', 'user_id', 'userid',
  'identity', 'identity_id', 'sub', 'role', 'roles', 'app_role', 'tenant_role', 'business_role', 'scope_role',
  'permission', 'permissions', 'scopes', 'is_admin', 'is_owner', 'is_superuser', 'admin', 'owner', 'claims',
  'jwt', 'token', 'access_token', 'authorization', 'service_role', 'impersonate', 'tenant_owner', 'entitlements',
]);

const ALLOWED_INPUT = new Set(['event_id', 'tenant_id', 'business_id', 'legal_entity_id', 'site_id', 'source_domain',
  'source_id', 'source_version', 'action', 'event_time', 'correlation_id', 'idempotency_key', 'payload',
  'payload_sha256', 'reason_category', 'schema_version']);

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const PAT = {
  source_domain: /^[a-z][a-z0-9_.-]{1,63}$/,
  source_id: /^[A-Za-z0-9_.:/#-]{1,128}$/,
  source_version: /^[A-Za-z0-9_.:+-]{1,64}$/,
  action: /^[a-z][a-z0-9_.-]{1,63}$/,
  correlation_id: /^[A-Za-z0-9_.:-]{1,128}$/,
  idempotency_key: /^[A-Za-z0-9_.:-]{8,128}$/,
};

function reqStr(name, v) {
  if (typeof v !== 'string' || !PAT[name].test(v)) throw new EnvelopeError('ENVELOPE_FIELD', `${name} is missing or malformed`);
  return v;
}
function uuid(name, v, optional) {
  if ((v === undefined || v === null) && optional) return null;
  if (typeof v !== 'string' || !UUID.test(v.toLowerCase())) throw new EnvelopeError('ENVELOPE_FIELD', `${name} must be a UUID`);
  return v.toLowerCase();
}

/** Recursively (depth <= 6) scan an object for authority-claim keys. Throws EnvelopeError. */
export function assertNoAuthorityClaims(obj, where = 'envelope', depth = 0) {
  if (obj === null || typeof obj !== 'object' || depth > 6) return;
  for (const k of Object.keys(obj)) {
    if (FORBIDDEN_AUTHORITY.has(k.toLowerCase())) {
      throw new EnvelopeError('ENVELOPE_AUTHORITY_CLAIM',
        `caller-supplied "${k.slice(0, 40)}" in ${where} is an authority claim; actor/role/tenant authority is derived by the trusted boundary only`);
    }
  }
  for (const k of Object.keys(obj)) {
    const v = obj[k];
    if (v && typeof v === 'object') assertNoAuthorityClaims(v, `${where}.${k.slice(0, 20)}`, depth + 1);
  }
}

function deepFreeze(o) {
  if (o && typeof o === 'object' && !Object.isFrozen(o)) { Object.freeze(o); for (const v of Object.values(o)) deepFreeze(v); }
  return o;
}

/**
 * Build a validated, redacted, hashed envelope from untrusted input.
 * Throws EnvelopeError (shape/scope/authority) or PayloadError (G3A03, payload content).
 * Returned object is deep-frozen and JSON-serialisable.
 */
export function buildEnvelope(input, { newId = randomUUID, redactOptions = {} } = {}) {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) {
    throw new EnvelopeError('ENVELOPE_SHAPE', 'envelope input must be an object');
  }
  assertNoAuthorityClaims(input);
  for (const k of Object.keys(input)) {
    if (!ALLOWED_INPUT.has(k)) throw new EnvelopeError('ENVELOPE_UNKNOWN_FIELD', `unknown envelope field "${k.slice(0, 40)}"`);
  }
  if (input.schema_version !== undefined && input.schema_version !== ENVELOPE_SCHEMA_VERSION) {
    throw new EnvelopeError('ENVELOPE_SCHEMA', 'unsupported schema_version');
  }
  if (!REASON_CATEGORIES.includes(input.reason_category)) throw new EnvelopeError('ENVELOPE_FIELD', 'reason_category is not allowed');
  if (looksSecret(String(input.source_id ?? '')) || looksSecret(String(input.correlation_id ?? ''))) {
    throw new EnvelopeError('ENVELOPE_FIELD', 'source_id/correlation_id must be opaque references');
  }
  let eventTime;
  try { eventTime = utcIso(input.event_time); } catch (e) {
    if (e instanceof CanonicalError) throw new EnvelopeError('ENVELOPE_TIME', 'event_time must be ISO-8601 with an explicit offset');
    throw e;
  }
  const { payload, dropped } = redactPayload(input.payload ?? {}, redactOptions);
  const payload_sha256 = sha256Hex(canonicalJson(payload));
  if (input.payload_sha256 !== undefined && input.payload_sha256 !== payload_sha256) {
    throw new EnvelopeError('ENVELOPE_HASH_MISMATCH', 'supplied payload_sha256 does not match the redacted canonical payload');
  }
  const env = {
    schema_version: ENVELOPE_SCHEMA_VERSION,
    event_id: input.event_id === undefined ? newId() : uuid('event_id', input.event_id),
    tenant_id: uuid('tenant_id', input.tenant_id),
    business_id: uuid('business_id', input.business_id),
    legal_entity_id: uuid('legal_entity_id', input.legal_entity_id, true),
    site_id: uuid('site_id', input.site_id, true),
    source_domain: reqStr('source_domain', input.source_domain),
    source_id: reqStr('source_id', input.source_id),
    source_version: reqStr('source_version', input.source_version),
    action: reqStr('action', input.action),
    event_time: eventTime,
    ingest_time: null, // slot: assigned by the trusted append boundary, part of the event digest
    correlation_id: reqStr('correlation_id', input.correlation_id),
    idempotency_key: reqStr('idempotency_key', input.idempotency_key),
    payload,
    payload_sha256,
    reason_category: input.reason_category,
  };
  // `dropped` is diagnostic (field NAMES only). It is non-enumerable so it is never serialised or hashed.
  Object.defineProperty(env, 'redaction_dropped', { value: Object.freeze(dropped), enumerable: false });
  return deepFreeze(env);
}

/** Re-validate an envelope-shaped object (e.g. before sending it to the DB or after reading a queue). */
export function validateEnvelope(env) {
  const rebuilt = buildEnvelope({
    ...Object.fromEntries(Object.entries(env).filter(([k]) => k !== 'ingest_time')),
  });
  if (env.ingest_time !== null && env.ingest_time !== undefined) {
    throw new EnvelopeError('ENVELOPE_INGEST_SLOT', 'ingest_time is assigned by the trusted append boundary, not by callers');
  }
  if (canonicalJson(rebuilt.payload) !== canonicalJson(env.payload)) {
    throw new EnvelopeError('ENVELOPE_NOT_REDACTED', 'payload contains fields that redaction would alter');
  }
  validatePayload(env.payload);
  return rebuilt;
}

/** Named SQL parameters for APPEND_EVENT_SQL (psql variables; never interpolated into SQL text). */
export function toSqlParams(env) {
  return {
    tenant_id: env.tenant_id,
    business_id: env.business_id,
    site_id: env.site_id,
    legal_entity_id: env.legal_entity_id,
    source_domain: env.source_domain,
    source_id: env.source_id,
    source_version: env.source_version,
    action: env.action,
    event_time: env.event_time,
    correlation_id: env.correlation_id,
    idempotency_key: env.idempotency_key,
    payload: canonicalJson(env.payload),
    payload_sha256: env.payload_sha256,
    reason_category: env.reason_category,
    event_id: env.event_id,
  };
}

/**
 * Trusted append call. null params are passed as '' and mapped back with nullif(). p_claimed_actor is ALWAYS null:
 * the actor comes only from the server-derived session (request.jwt.claim.sub via SET), never from the caller.
 */
export const APPEND_EVENT_SQL = `select outcome, event_id, receipt_id, stream_seq, event_digest, receipt_digest, replayed, payload_sha256
  from c10_gov003_demo.append_event(
    :'tenant_id'::uuid, :'business_id'::uuid, nullif(:'site_id', '')::uuid, nullif(:'legal_entity_id', '')::uuid,
    :'source_domain', :'source_id', :'source_version', :'action',
    :'event_time'::timestamptz, :'correlation_id', :'idempotency_key',
    :'payload'::jsonb, :'payload_sha256', :'reason_category',
    null::uuid, :'event_id'::uuid)`;

export { PayloadError };
