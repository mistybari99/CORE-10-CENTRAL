// GOV-003 feature 11 incident-evidence-preservation: evidence manifest builder/verifier, hold evaluation and the
// purge-block decision. Pure, zero-dependency. DEMO / NOT LIVE contract code.
//
// Mirrors internal/gov003/sql/110_incident.sql (inc_item_digest_of, verify_manifest, _inc_protection,
// purge_evidence_attempt). The parity tests in tests/gov003/sql/f11_incident.test.mjs prove identical digests and
// identical purge decisions.
//
// LEGAL LIMIT (deliberate): a hold flag in a mutable database is an engineering control. It is NOT a legal-hold
// certification and NOT WORM storage. Whether evidence must be kept, and when a hold can be lifted, is an
// Owner / legal counsel decision gate outside this code. Nothing here may be presented as legal compliance.
import { createHash } from 'node:crypto';

export const MANIFEST_SPEC = 'g3m1';
export const ZERO_DIGEST = '0'.repeat(64);
export const LEGAL_NOTICE =
  'Engineering control in a mutable database only. This is not a legal-hold certification; legal retention decisions are an Owner/counsel gate.';
export const EVIDENCE_KINDS = Object.freeze(['log_extract', 'document', 'image', 'export_csv', 'db_snapshot_ref', 'other']);
export const HOLD_REASONS = Object.freeze(['security_incident', 'fraud_review', 'owner_directive', 'counsel_request', 'regulatory_inquiry', 'other']);

export class ManifestError extends Error {
  constructor(code, message) { super(`${code}: ${message}`); this.code = code; this.detail = message; }
}

export const sha256Hex = (input) =>
  createHash('sha256').update(typeof input === 'string' ? Buffer.from(input, 'utf8') : input).digest('hex');

const MICRO_ISO = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$/;
export function utcIso(value) {
  if (typeof value === 'string' && MICRO_ISO.test(value)) return value;
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) throw new ManifestError('G3A03', 'not a timestamp');
  return d.toISOString().replace('Z', '000Z');
}

const REF = /^[A-Za-z0-9_.:/#-]{1,128}$/;
// Same patterns as c10_gov003_demo.looks_secret, so an evidence reference can never smuggle a secret/PII.
const SECRET_RES = [
  /eyJ[A-Za-z0-9_-]{8,}/,
  /(bearer\s|service[_-]?role|passw(or)?d|secret|api[_-]?key|token|private[_-]?key|authorization)/i,
  /[^\s@]+@[^\s@]+\.[A-Za-z]{2,}/,
  /(^|[^0-9A-Za-z-])[0-9]{13,19}($|[^0-9A-Za-z-])/,
  /^[0-9]{9,}$/,
  /\n\s+at /,
];
const looksSecret = (s) => SECRET_RES.some((re) => re.test(s));

/** Validate one evidence item input (same rules as add_evidence). Returns a normalized copy. */
export function validateEvidenceInput(i) {
  const bad = (m, code = 'G3A03') => { throw new ManifestError(code, m); };
  for (const f of ['evidence_ref', 'source_ref']) {
    if (typeof i[f] !== 'string' || !REF.test(i[f]) || looksSecret(i[f])) bad(`${f} must be an opaque reference`);
  }
  if (!EVIDENCE_KINDS.includes(i.kind)) bad('evidence kind');
  if (typeof i.sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(i.sha256)) bad('sha256 must be 64 lowercase hex characters');
  const len = typeof i.byte_length === 'bigint' ? Number(i.byte_length) : Number(i.byte_length);
  if (!Number.isInteger(len) || len < 0 || len > 1_000_000_000_000) bad('byte_length');
  return { ...i, byte_length: len, retain_until: i.retain_until == null ? null : utcIso(i.retain_until) };
}

// ------------------------------------------------------------------------------------------------ manifest chain
/** Digest of one manifest entry, chained to the previous entry's digest. */
export function itemDigest(item, priorDigest, caseId) {
  return sha256Hex([
    MANIFEST_SPEC, priorDigest, caseId, String(item.item_seq), item.evidence_ref, item.kind, item.sha256,
    String(item.byte_length), item.source_ref, item.retain_until == null ? '' : utcIso(item.retain_until),
    utcIso(item.added_at), item.added_by,
  ].join('|'));
}

export const emptyManifestDigest = (caseId) => sha256Hex(`${MANIFEST_SPEC}|empty|${caseId}`);

/** Build a fresh manifest from items in order (item_seq assigned 1..n). Items are never mutated. */
export function buildManifest(caseId, items) {
  let prior = ZERO_DIGEST; const out = [];
  items.forEach((raw, idx) => {
    const norm = validateEvidenceInput(raw);
    const it = { ...norm, item_seq: idx + 1, added_at: utcIso(norm.added_at), prior_digest: prior };
    it.item_digest = itemDigest(it, prior, caseId);
    prior = it.item_digest;
    out.push(Object.freeze(it));
  });
  return { caseId, items: out, itemCount: out.length, manifestDigest: out.length ? prior : emptyManifestDigest(caseId) };
}

/**
 * Recompute the chain from stored items and compare. Returns {ok, reason, firstBadSeq, manifestDigest}.
 * `expectedDigest` mismatch throws G3A04 (same as SQL verify_manifest); internal tampering returns ok:false.
 */
export function verifyManifest(caseId, items, { expectedDigest = null } = {}) {
  let prior = ZERO_DIGEST; let n = 0;
  const sorted = [...items].sort((a, b) => a.item_seq - b.item_seq);
  for (const it of sorted) {
    n += 1;
    if (it.item_seq !== n) return { ok: false, reason: 'sequence_gap', firstBadSeq: it.item_seq, itemCount: n, manifestDigest: prior };
    if (it.prior_digest !== prior) return { ok: false, reason: 'prior_digest_mismatch', firstBadSeq: it.item_seq, itemCount: n, manifestDigest: prior };
    if (itemDigest(it, it.prior_digest, caseId) !== it.item_digest) {
      return { ok: false, reason: 'item_digest_mismatch', firstBadSeq: it.item_seq, itemCount: n, manifestDigest: prior };
    }
    prior = it.item_digest;
  }
  if (n === 0) prior = emptyManifestDigest(caseId);
  if (expectedDigest !== null && expectedDigest !== prior) {
    throw new ManifestError('G3A04', 'manifest_digest_mismatch: supplied manifest digest does not match the recomputed digest');
  }
  return { ok: true, reason: null, firstBadSeq: null, itemCount: n, manifestDigest: prior };
}

/** Evidence bytes vs manifest entry (hash and optional length). Mismatch is G3A04. */
export function verifyEvidenceBytes(item, content) {
  const bytes = typeof content === 'string' ? Buffer.from(content, 'utf8') : Buffer.from(content);
  if (sha256Hex(bytes) !== item.sha256 || bytes.length !== Number(item.byte_length)) {
    throw new ManifestError('G3A04', 'evidence_hash_mismatch: supplied content does not match the manifest entry');
  }
  return true;
}

// ------------------------------------------------------------------------------------------------ holds + purge rule
const T = (v) => (v instanceof Date ? v.getTime() : Date.parse(v));

/**
 * Reasons evidence may not be purged now (same rule as SQL _inc_protection):
 *   item_retention : item.retain_until in the future
 *   hold_active    : a covering hold (case-wide: evidence_id == null, or this item) has no release
 *   hold_retention : a covering hold's retention_until is still in the future (even if released)
 * holds: [{evidence_id|null, retention_until, released: boolean}]
 */
export function protectionReasons({ item, holds, now = new Date() }) {
  const at = T(now); const reasons = [];
  if (item.retain_until != null && T(item.retain_until) > at) reasons.push('item_retention');
  const covering = holds.filter((h) => h.evidence_id == null || h.evidence_id === item.evidence_id);
  if (covering.some((h) => !h.released)) reasons.push('hold_active');
  if (covering.some((h) => T(h.retention_until) > at)) reasons.push('hold_retention');
  return reasons;
}

/**
 * Purge decision. Refusal carries error code G3H02. Allowed purge only means "append a tombstone":
 * history, the manifest entry and the recorded SHA-256 are never edited or removed.
 */
export function purgeDecision({ item, holds, now = new Date(), tombstoned = false }) {
  if (tombstoned) return { outcome: 'already_purged', allowed: false, errorCode: null, reasons: [], action: 'none', notice: LEGAL_NOTICE };
  const reasons = protectionReasons({ item, holds, now });
  if (reasons.length) return { outcome: 'refused', allowed: false, errorCode: 'G3H02', reasons, action: 'audit_refusal', notice: LEGAL_NOTICE };
  return { outcome: 'tombstoned', allowed: true, errorCode: null, reasons: [], action: 'append_tombstone', notice: LEGAL_NOTICE };
}

/** Independence rule shared by review and release: the reviewer must differ from the hold placer. */
export function assertIndependent(placedBy, actor) {
  if (!placedBy || !actor || placedBy === actor) {
    throw new ManifestError('G3A02', 'independent_review_required: the hold placer cannot review or release their own hold');
  }
  return true;
}

/** Hold status as the scoped view shows it. */
export function holdStatus({ hold, review = null, release = null, now = new Date() }) {
  return {
    review_status: review ? review.decision : 'pending',
    released: Boolean(release),
    in_force: !release || T(hold.retention_until) > T(now),
  };
}

/** Wording guard used by UI/doc tests: legal-compliance promises are forbidden in hold copy. */
export function claimsLegalCompliance(text) {
  return /\b(legally\s+(compliant|binding|certified)|legal[- ]hold\s+(certified|compliant|guaranteed)|court[- ]proof|wo?rm\s+(compliant|certified)|guarantees?\s+(admissib|compliance))/i.test(String(text));
}
