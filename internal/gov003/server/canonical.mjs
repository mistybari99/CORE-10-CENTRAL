// GOV-003 canonical JSON + digests. Zero dependencies (node:crypto only). DEMO / NOT LIVE contract core.
//
// Contract: output is BYTE-IDENTICAL to SQL c10_gov003_demo.canonical_json(jsonb) and g3_sha256(text) for the
// supported value domain:
//   object  -> keys sorted bytewise on their UTF-8 encoding (SQL: ORDER BY key COLLATE "C"), no whitespace
//   array   -> element order preserved
//   string  -> JSON string, escapes exactly as PostgreSQL jsonb output (", \, \b \f \n \r \t, other C0 as \u00xx
//              lowercase; DEL, U+2028/2029 and non-ASCII are NOT escaped). NUL and lone surrogates are rejected
//              (PostgreSQL jsonb cannot hold them either).
//   number  -> integers ONLY (safe integer Number, or BigInt). Decimals travel as strings. Floats/NaN/Infinity/
//              unsafe integers/undefined/functions/symbols/Date/Map/class instances are rejected (fail closed).
//   boolean / null as-is.
// Digest formats for events and receipts replicate event_digest_of / receipt_digest_of in 030_append_event.sql
// ('g3e1|...' and 'g3r1|...', concat_ws('|'), UTC microsecond ISO timestamps).
import { createHash } from 'node:crypto';

export class CanonicalError extends Error {
  constructor(code, message) { super(message); this.name = 'CanonicalError'; this.code = code; }
}

export const GENESIS_DIGEST = '0'.repeat(64);
const MAX_DEPTH = 64;

export function sha256Hex(input) {
  if (typeof input === 'string') return createHash('sha256').update(Buffer.from(input, 'utf8')).digest('hex');
  if (input instanceof Uint8Array) return createHash('sha256').update(input).digest('hex');
  throw new CanonicalError('CANON_BAD_INPUT', 'sha256Hex expects a string or bytes');
}

const hasLoneSurrogate = (s) => {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) {
      const n = s.charCodeAt(i + 1);
      if (n >= 0xdc00 && n <= 0xdfff) { i++; continue; }
      return true;
    }
    if (c >= 0xdc00 && c <= 0xdfff) return true;
  }
  return false;
};

function quote(s) {
  if (s.includes('\u0000')) throw new CanonicalError('CANON_NUL', 'NUL is not representable (PostgreSQL jsonb rejects it)');
  if (hasLoneSurrogate(s)) throw new CanonicalError('CANON_SURROGATE', 'lone surrogate is not valid Unicode text');
  return JSON.stringify(s);
}

const isPlain = (o) => {
  const p = Object.getPrototypeOf(o);
  return p === Object.prototype || p === null;
};

function enc(v, depth) {
  if (depth > MAX_DEPTH) throw new CanonicalError('CANON_DEPTH', 'value nested too deeply');
  if (v === null) return 'null';
  switch (typeof v) {
    case 'string': return quote(v);
    case 'boolean': return v ? 'true' : 'false';
    case 'bigint': return v.toString();
    case 'number':
      if (!Number.isFinite(v)) throw new CanonicalError('CANON_NUMBER', 'NaN/Infinity not allowed');
      if (!Number.isInteger(v)) throw new CanonicalError('CANON_FLOAT', 'non-integer number not allowed (use a decimal string)');
      if (!Number.isSafeInteger(v)) throw new CanonicalError('CANON_UNSAFE_INT', 'unsafe integer not allowed (use BigInt or a string)');
      return String(v === 0 ? 0 : v); // normalises -0
    case 'undefined': throw new CanonicalError('CANON_UNDEFINED', 'undefined is not representable');
    case 'object': {
      if (Array.isArray(v)) {
        const out = new Array(v.length);
        for (let i = 0; i < v.length; i++) {
          if (!(i in v)) throw new CanonicalError('CANON_SPARSE', 'sparse array not allowed');
          out[i] = enc(v[i], depth + 1);
        }
        return '[' + out.join(',') + ']';
      }
      if (!isPlain(v)) throw new CanonicalError('CANON_TYPE', 'only plain objects/arrays are supported');
      const keys = Object.keys(v).map((k) => ({ k, b: Buffer.from(k, 'utf8') }));
      keys.sort((a, b) => Buffer.compare(a.b, b.b));
      const parts = [];
      for (const { k } of keys) {
        if (v[k] === undefined) throw new CanonicalError('CANON_UNDEFINED', `undefined at key "${k.slice(0, 40)}"`);
        parts.push(quote(k) + ':' + enc(v[k], depth + 1));
      }
      return '{' + parts.join(',') + '}';
    }
    default: throw new CanonicalError('CANON_TYPE', `unsupported type ${typeof v}`);
  }
}

export function canonicalJson(value) { return enc(value, 0); }
export function payloadSha256(payload) { return sha256Hex(canonicalJson(payload)); }

/**
 * Strict JSON text parser for untrusted request bodies: rejects numbers that are not safe integers
 * (so 1.5, 1e3, 12345678901234567890 can never silently change meaning) and duplicate keys.
 */
export function strictJsonParse(text) {
  let bad = null;
  const dupCheck = (t) => {
    // Detect duplicate keys cheaply: re-scan with a tiny tokenizer only over object key positions.
    let i = 0; const n = t.length;
    const skipStr = () => { i++; while (i < n && t[i] !== '"') { if (t[i] === '\\') i++; i++; } i++; };
    const stack = [];
    while (i < n) {
      const c = t[i];
      if (c === '"') {
        const start = i; skipStr();
        let j = i; while (j < n && /\s/.test(t[j])) j++;
        const top = stack[stack.length - 1];
        if (top && top.type === 'o' && t[j] === ':' && top.expectKey) {
          const key = JSON.parse(t.slice(start, i));
          if (top.keys.has(key)) bad = bad || `duplicate key "${key.slice(0, 40)}"`;
          top.keys.add(key); top.expectKey = false;
        }
        continue;
      }
      if (c === '{') stack.push({ type: 'o', keys: new Set(), expectKey: true });
      else if (c === '[') stack.push({ type: 'a' });
      else if (c === '}' || c === ']') stack.pop();
      else if (c === ',') { const top = stack[stack.length - 1]; if (top && top.type === 'o') top.expectKey = true; }
      i++;
    }
  };
  const value = JSON.parse(text, function reviver(_k, v, ctx) {
    if (typeof v === 'number') {
      const src = ctx && typeof ctx.source === 'string' ? ctx.source : String(v);
      if (!/^-?(0|[1-9][0-9]*)$/.test(src)) bad = bad || 'non-integer number';
      else if (!Number.isSafeInteger(v)) bad = bad || 'unsafe integer';
    }
    return v;
  });
  dupCheck(text);
  if (bad) throw new CanonicalError('CANON_STRICT_JSON', bad);
  return value;
}

// ---- time: exact UTC microseconds ---------------------------------------------------------------------------

const TS_RE = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}(?::?\d{2})?)$/;

function daysFromCivil(y, m, d) {
  y -= m <= 2 ? 1 : 0;
  const era = Math.floor(y / 400);
  const yoe = y - era * 400;
  const doy = Math.floor((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
  const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
  return era * 146097 + doe - 719468;
}
function civilFromDays(z) {
  z += 719468;
  const era = Math.floor(z / 146097);
  const doe = z - era * 146097;
  const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524) - Math.floor(doe / 146096)) / 365);
  const y = yoe + era * 400;
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
  const mp = Math.floor((5 * doy + 2) / 153);
  const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
  const m = mp + (mp < 10 ? 3 : -9);
  return { y: y + (m <= 2 ? 1 : 0), m, d };
}
const isLeap = (y) => (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
const DIM = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

const MIN_MICROS = BigInt(daysFromCivil(1, 1, 1)) * 86400000000n;
const MAX_MICROS = (BigInt(daysFromCivil(9999, 12, 31)) + 1n) * 86400000000n - 1n;

/** Parse ISO-8601 with explicit offset (or Date, or BigInt microseconds) to BigInt microseconds since epoch. */
export function parseTimestampMicros(input) {
  if (typeof input === 'bigint') {
    if (input < MIN_MICROS || input > MAX_MICROS) throw new CanonicalError('TS_RANGE', 'timestamp out of range');
    return input;
  }
  if (input instanceof Date) {
    const ms = input.getTime();
    if (!Number.isFinite(ms)) throw new CanonicalError('TS_INVALID', 'invalid Date');
    return parseTimestampMicros(BigInt(ms) * 1000n);
  }
  if (typeof input !== 'string') throw new CanonicalError('TS_TYPE', 'timestamp must be an ISO string with offset, Date or BigInt micros');
  const m = TS_RE.exec(input.trim());
  if (!m) throw new CanonicalError('TS_FORMAT', 'timestamp must be ISO-8601 with an explicit Z/offset');
  const [, ys, mos, ds, hs, mis, ss, frac = '', tz] = m;
  const y = +ys; const mo = +mos; const d = +ds; const h = +hs; const mi = +mis; const s = +ss;
  if (mo < 1 || mo > 12 || d < 1 || d > DIM[mo - 1] + (mo === 2 && isLeap(y) ? 1 : 0) || y < 1 || h > 23 || mi > 59 || s > 59) {
    throw new CanonicalError('TS_INVALID', 'timestamp field out of range');
  }
  let micros = BigInt(frac.padEnd(6, '0').slice(0, 6));
  if (frac.length > 6 && frac.charCodeAt(6) >= 53) micros += 1n; // PostgreSQL rounds to the nearest microsecond
  let off = 0;
  if (tz !== 'Z') {
    const sign = tz[0] === '-' ? -1 : 1;
    const digits = tz.slice(1).replace(':', '');
    const oh = +digits.slice(0, 2); const om = digits.length > 2 ? +digits.slice(2, 4) : 0;
    if (oh > 15 || om > 59) throw new CanonicalError('TS_INVALID', 'offset out of range');
    off = sign * (oh * 3600 + om * 60);
  }
  const secs = BigInt(daysFromCivil(y, mo, d)) * 86400n + BigInt(h * 3600 + mi * 60 + s - off);
  return parseTimestampMicros(secs * 1000000n + micros);
}

const p2 = (n) => String(n).padStart(2, '0');
/** Exactly SQL utc_iso(): YYYY-MM-DD"T"HH24:MI:SS.US"Z" (always 6 fractional digits). */
export function utcIso(input) {
  const micros = parseTimestampMicros(input);
  let days = micros / 86400000000n;
  let rem = micros % 86400000000n;
  if (rem < 0n) { rem += 86400000000n; days -= 1n; }
  const { y, m, d } = civilFromDays(Number(days));
  const secs = Number(rem / 1000000n);
  const us = Number(rem % 1000000n);
  return `${String(y).padStart(4, '0')}-${p2(m)}-${p2(d)}T${p2(Math.floor(secs / 3600))}:${p2(Math.floor((secs % 3600) / 60))}:${p2(secs % 60)}.${String(us).padStart(6, '0')}Z`;
}

// ---- exact decimals ----------------------------------------------------------------------------------------

/** "12.34" + scale 2 -> 1234n. Rejects exponents, extra scale, signs other than leading '-', floats typed as Number. */
export function decimalToMinorUnits(text, scale = 2) {
  if (typeof text !== 'string') throw new CanonicalError('DEC_TYPE', 'decimal must be a string');
  if (!Number.isInteger(scale) || scale < 0 || scale > 9) throw new CanonicalError('DEC_SCALE', 'bad scale');
  const m = /^(-?)(0|[1-9][0-9]{0,17})(?:\.([0-9]+))?$/.exec(text);
  if (!m) throw new CanonicalError('DEC_FORMAT', 'invalid decimal');
  const frac = m[3] || '';
  if (frac.length > scale) throw new CanonicalError('DEC_PRECISION', 'more fractional digits than the currency scale');
  const v = BigInt(m[2] + frac.padEnd(scale, '0'));
  return m[1] ? -v : v;
}
export function minorUnitsToDecimal(minor, scale = 2) {
  const v = typeof minor === 'bigint' ? minor : BigInt(minor);
  const neg = v < 0n; let s = (neg ? -v : v).toString();
  if (scale > 0) { s = s.padStart(scale + 1, '0'); s = `${s.slice(0, -scale)}.${s.slice(-scale)}`; }
  return (neg ? '-' : '') + s;
}

// ---- digests (replicate SQL concat_ws formats) -------------------------------------------------------------

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const HEX64 = /^[0-9a-f]{64}$/;
const uuidText = (v, name) => {
  if (typeof v !== 'string' || !UUID_RE.test(v)) throw new CanonicalError('DIGEST_FIELD', `${name} must be a UUID`);
  return v.toLowerCase();
};
const textField = (v, name) => {
  if (typeof v !== 'string' || v === '') throw new CanonicalError('DIGEST_FIELD', `${name} must be a non-empty string`);
  if (v.includes('|') || v.includes('\u0000')) throw new CanonicalError('DIGEST_FIELD', `${name} contains a forbidden character`);
  return v;
};
const hexField = (v, name) => {
  if (typeof v !== 'string' || !HEX64.test(v)) throw new CanonicalError('DIGEST_FIELD', `${name} must be 64 lowercase hex chars`);
  return v;
};
const intText = (v, name) => {
  if (typeof v === 'bigint') return v.toString();
  if (typeof v === 'number' && Number.isSafeInteger(v)) return String(v);
  if (typeof v === 'string' && /^-?[0-9]{1,18}$/.test(v)) return String(BigInt(v));
  throw new CanonicalError('DIGEST_FIELD', `${name} must be an integer`);
};

/** Inputs use the SAME snake_case names as audit_events columns, so a DB row can be passed directly. */
export function eventDigestOf(e) {
  return sha256Hex([
    'g3e1',
    hexField(e.prior_digest, 'prior_digest'),
    uuidText(e.event_id, 'event_id'),
    uuidText(e.tenant_id, 'tenant_id'),
    uuidText(e.business_id, 'business_id'),
    e.site_id === null || e.site_id === undefined ? '' : uuidText(e.site_id, 'site_id'),
    intText(e.stream_seq, 'stream_seq'),
    textField(e.source_domain, 'source_domain'),
    textField(e.source_id, 'source_id'),
    textField(e.source_version, 'source_version'),
    textField(e.action, 'action'),
    utcIso(e.event_time),
    utcIso(e.ingest_time),
    uuidText(e.actor_id, 'actor_id'),
    textField(e.correlation_id, 'correlation_id'),
    textField(e.idempotency_key, 'idempotency_key'),
    hexField(e.payload_sha256, 'payload_sha256'),
    textField(e.reason_category, 'reason_category'),
    intText(e.schema_version, 'schema_version'),
  ].join('|'));
}

/** Inputs: receipt_id, event_id, event_digest, payload_sha256, idempotency_key, issued_at (audit_receipts columns). */
export function receiptDigestOf(r) {
  return sha256Hex([
    'g3r1',
    uuidText(r.receipt_id, 'receipt_id'),
    uuidText(r.event_id, 'event_id'),
    hexField(r.event_digest, 'event_digest'),
    hexField(r.payload_sha256, 'payload_sha256'),
    textField(r.idempotency_key, 'idempotency_key'),
    utcIso(r.issued_at),
  ].join('|'));
}
