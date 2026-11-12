// GOV-003 approved-field redaction, secret/PII detection and error scrubbing. Zero dependencies.
// Mirrors SQL looks_secret / validate_payload (020_audit_core.sql) and scrub_text (040_observability.sql).
// Parity is proven by tests/gov003/sql/parity_canonical_redact.test.mjs against a real PostgreSQL.
//
// Whitespace note: SQL uses POSIX [[:space:]], whose members are locale-defined. SP below is the set used by
// glibc C.UTF-8/en_US.UTF-8 (ASCII whitespace + U+1680, U+2000-2006, U+2008-200A, U+2028, U+2029, U+205F,
// U+3000; NOT NBSP, U+0085, U+2007, U+202F). A database on a different libc locale could differ for exotic
// Unicode whitespace only; ASCII behaviour is identical everywhere.
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const SPC = '\\t\\n\\v\\f\\r \\u1680\\u2000-\\u2006\\u2008-\\u200a\\u2028\\u2029\\u205f\\u3000';
const SP = `[${SPC}]`;
const NSP = `[^${SPC}]`;

export class PayloadError extends Error {
  constructor(message, code = 'G3A03') { super(message); this.name = 'PayloadError'; this.code = code; }
}

const cpLen = (s) => { let n = 0; for (const _ of s) n++; return n; }; // eslint-disable-line no-unused-vars
const cpLeft = (s, n) => { let out = ''; let i = 0; for (const ch of s) { if (i++ >= n) break; out += ch; } return out; };

// ---- allowlist (exact copy of SQL payload_allowlist) -----------------------------------------------------------
const rawAllow = JSON.parse(readFileSync(join(here, '..', 'shared', 'payload_allowlist.json'), 'utf8'));
export const PAYLOAD_ALLOWLIST = Object.freeze(new Map(rawAllow.fields.map((f) => [f.field_name, f.kind])));
export const ALLOWLIST_FIELDS = Object.freeze(rawAllow.fields.map((f) => Object.freeze({ ...f })));

// ---- looks_secret -----------------------------------------------------------------------------------------------
const RE_JWT = /eyJ[A-Za-z0-9_-]{8,}/;
const RE_SECRET_WORD = new RegExp(`(bearer${SP}|service[_-]?role|passw(or)?d|secret|api[_-]?key|token|private[_-]?key|authorization)`, 'i');
const RE_EMAIL_DETECT = new RegExp(`${NSP.replace(']', '@]')}+@${NSP.replace(']', '@]')}+\\.[A-Za-z]{2,}`);
const RE_CARDISH = /(^|[^0-9A-Za-z-])[0-9]{13,19}($|[^0-9A-Za-z-])/;
const RE_LONG_DIGITS = /^[0-9]{9,}$/;
const RE_STACK = new RegExp(`\\n${SP}+at `);

/** Mirror of SQL looks_secret(text). */
export function looksSecret(p) {
  const s = String(p ?? '');
  return RE_JWT.test(s) || RE_SECRET_WORD.test(s) || RE_EMAIL_DETECT.test(s) || RE_CARDISH.test(s)
    || RE_LONG_DIGITS.test(s) || RE_STACK.test(s);
}

// ---- validate_payload / redact ---------------------------------------------------------------------------------
const KIND_RE = {
  money: /^-?[0-9]{1,18}$/,
  count: /^-?[0-9]{1,15}$/,
  ts: /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$/,
  enum: /^[a-z0-9_.:-]{1,64}$/,
  ref: /^[A-Za-z0-9_.:/#-]{1,128}$/,
};
const KIND_MSG = {
  money: 'must be integer minor units',
  count: 'must be an integer',
  ts: 'must be UTC ISO time',
  enum: 'must be an enum token',
  ref: 'is not an opaque reference',
};

const isPlainObject = (o) => o !== null && typeof o === 'object' && !Array.isArray(o)
  && (Object.getPrototypeOf(o) === Object.prototype || Object.getPrototypeOf(o) === null);

function checkField(k, v, kind) {
  const t = v === null ? 'null' : Array.isArray(v) ? 'array' : typeof v;
  if (t === 'number' || t === 'bigint') {
    throw new PayloadError(`payload_not_allowed: field "${k}" must be a string (decimals/ints travel as strings)`);
  }
  if (!['string', 'boolean', 'null'].includes(t)) {
    throw new PayloadError(`payload_not_allowed: field "${k}" must be scalar`);
  }
  if (t !== 'string') return; // SQL only validates string values; booleans/nulls pass
  if (v.includes('\u0000')) throw new PayloadError(`payload_not_allowed: field "${k}" contains NUL`);
  if (cpLen(v) > 256) throw new PayloadError(`payload_not_allowed: field "${k}" too long`);
  if (kind === 'ref') {
    if (!KIND_RE.ref.test(v) || looksSecret(v)) throw new PayloadError(`payload_not_allowed: field "${k}" ${KIND_MSG.ref}`);
  } else if (kind === 'text') {
    if (looksSecret(v)) throw new PayloadError(`payload_not_allowed: field "${k}" looks sensitive`);
  } else if (!KIND_RE[kind].test(v)) {
    throw new PayloadError(`payload_not_allowed: field "${k}" ${KIND_MSG[kind]}`);
  }
}

/** Exact mirror of SQL validate_payload(jsonb): rejects (throws PayloadError, code G3A03), never silently drops. */
export function validatePayload(p) {
  if (!isPlainObject(p)) throw new PayloadError('payload_not_allowed: payload must be an object');
  for (const k of Object.keys(p)) {
    const kind = PAYLOAD_ALLOWLIST.get(k);
    if (kind === undefined) throw new PayloadError(`payload_not_allowed: field "${cpLeft(k, 40)}" is not approved`);
    checkField(k, p[k], kind);
  }
  return p;
}

/**
 * Approved-field redaction. Unknown fields are DROPPED (and reported by name, never by value); known fields are
 * validated exactly like validate_payload. By default an invalid KNOWN field throws (fail closed); with
 * { onInvalid: 'drop' } it is dropped and reported instead. { coerceIntegers: true } turns safe integers/BigInt into
 * decimal strings (the SQL contract only accepts strings). The result always passes SQL validate_payload.
 */
export function redactPayload(input, { onInvalid = 'throw', coerceIntegers = false } = {}) {
  if (!isPlainObject(input)) throw new PayloadError('payload_not_allowed: payload must be an object');
  const payload = {}; const dropped = []; const rejected = [];
  for (const k of Object.keys(input)) {
    const kind = PAYLOAD_ALLOWLIST.get(k);
    if (kind === undefined) { dropped.push(cpLeft(k, 40)); continue; }
    let v = input[k];
    if (coerceIntegers && ((typeof v === 'number' && Number.isSafeInteger(v)) || typeof v === 'bigint')) v = String(v);
    try { checkField(k, v, kind); } catch (e) {
      if (onInvalid === 'drop') { rejected.push(k); continue; }
      throw e;
    }
    payload[k] = v;
  }
  return { payload, dropped, rejected };
}

// ---- scrub_text ------------------------------------------------------------------------------------------------
const RE_S_JWT = /eyJ[A-Za-z0-9_-]{8,}(\.[A-Za-z0-9_-]+){0,2}/g;
const RE_S_BEARER = new RegExp(`bearer${SP}+[A-Za-z0-9._~+/=-]+`, 'gi');
const RE_S_URL = new RegExp(`(postgres(?:ql)?|mysql|mongodb|redis|https?):\\/\\/${NSP}+`, 'gi');
const RE_S_ASSIGN = new RegExp(`(password|passwd|secret|api[_-]?key|token|service[_-]?role|authorization)${SP}*[=:]${SP}*[^${SPC},;]+`, 'gi');
const RE_S_EMAIL = new RegExp(`${NSP.replace(']', '@]')}+@${NSP.replace(']', '@]')}+\\.[A-Za-z]{2,}`, 'g');
const RE_S_NUMBER = /\+?[0-9][0-9 -]{7,}[0-9]/g;
const RE_S_FRAME = /(?<![\p{L}\p{N}\p{M}_])at [A-Za-z0-9_.$<>]+ \([^)]*\)/giu;

/** Mirror of SQL scrub_text(text): first line only, secrets/PII/frames replaced, 300 code points max. */
export function scrubText(p) {
  let s = p === null || p === undefined ? '' : String(p);
  s = s.split('\n')[0];
  s = s.replace(RE_S_JWT, '[redacted-jwt]');
  s = s.replace(RE_S_BEARER, 'bearer [redacted]');
  s = s.replace(RE_S_URL, '[redacted-url]');
  s = s.replace(RE_S_ASSIGN, '$1=[redacted]');
  s = s.replace(RE_S_EMAIL, '[redacted-email]');
  s = s.replace(RE_S_NUMBER, '[redacted-number]');
  s = s.replace(RE_S_FRAME, '[frame]');
  return cpLeft(s, 300);
}

// ---- safe error projection ---------------------------------------------------------------------------------------
/** Mirror of SQL error_catalog. */
export const ERROR_CATALOG = Object.freeze({
  SOURCE_STALE: { public_message: 'The source feed is stale.', severity: 'warning', http_status: 409 },
  COMMAND_REJECTED: { public_message: 'A command was rejected.', severity: 'error', http_status: 422 },
  SCOPE_DENIED: { public_message: 'Access outside the permitted scope was denied.', severity: 'warning', http_status: 403 },
  RECEIPT_MISMATCH: { public_message: 'A receipt did not match the recorded evidence.', severity: 'error', http_status: 409 },
  EXPORT_FAILED: { public_message: 'A report export failed.', severity: 'error', http_status: 500 },
  INTERNAL: { public_message: 'An internal error occurred.', severity: 'error', http_status: 500 },
});

// SQLSTATEs raised by the GOV-003 SQL core -> catalog code. Everything else is INTERNAL with NO raw detail.
const CODE_MAP = {
  G3A01: 'COMMAND_REJECTED', G3A02: 'SCOPE_DENIED', G3A03: 'COMMAND_REJECTED', G3A04: 'RECEIPT_MISMATCH',
  G3A05: 'SCOPE_DENIED', G3C01: 'COMMAND_REJECTED', G3H01: 'COMMAND_REJECTED',
  SIGNED_SESSION_UNAVAILABLE: 'SCOPE_DENIED', INTEGRATION_PENDING: 'COMMAND_REJECTED',
};
const CORR_RE = /^[A-Za-z0-9_.:-]{1,128}$/;

/**
 * Project ANY thrown value into a support-safe object: catalog code + public message + scrubbed one-line detail.
 * Never returns stack traces, raw stderr, SQL text or non-GOV-003 database messages (those may echo parameter
 * values), and never the caller's object identity. Detail is only retained for codes raised by our own core.
 */
export function projectSafeError(err, { correlationId } = {}) {
  const rawCode = err && typeof err === 'object' && typeof err.code === 'string' ? err.code : '';
  const code = Object.hasOwn(ERROR_CATALOG, rawCode) ? rawCode : (Object.hasOwn(CODE_MAP, rawCode) ? CODE_MAP[rawCode] : 'INTERNAL');
  const cat = ERROR_CATALOG[code];
  let detail = '';
  if (Object.hasOwn(CODE_MAP, rawCode) && err) {
    const d = typeof err.detail === 'string' ? err.detail : typeof err.message === 'string' ? err.message : '';
    detail = scrubText(d);
  }
  const corr = typeof correlationId === 'string' && CORR_RE.test(correlationId) ? correlationId : `err-${randomUUID()}`;
  return {
    error_code: code,
    public_message: cat.public_message,
    severity: cat.severity,
    http_status: cat.http_status,
    scrubbed_detail: detail,
    correlation_id: corr,
  };
}
