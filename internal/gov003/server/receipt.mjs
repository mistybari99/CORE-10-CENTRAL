// GOV-003 receipt generation/verification helpers. Zero dependencies. DEMO / NOT LIVE contract core.
//
// These helpers RECOMPUTE digests from stored fields and compare. They never trust a stored digest.
// LIMITATION (stated on purpose): a hash chain inside a mutable PostgreSQL database is tamper-EVIDENT against
// ordinary principals, not a legal WORM guarantee against a privileged DBA/superuser who can rewrite the chain
// AND recompute every digest. Independent anchoring of chain heads outside the database is a future owner gate.
import { timingSafeEqual } from 'node:crypto';
import { randomUUID } from 'node:crypto';
import {
  GENESIS_DIGEST, eventDigestOf, receiptDigestOf, payloadSha256, sha256Hex, utcIso, CanonicalError,
} from './canonical.mjs';

const eqHex = (a, b) => typeof a === 'string' && typeof b === 'string' && a.length === b.length
  && timingSafeEqual(Buffer.from(a), Buffer.from(b));

const safe = (fn) => { try { return fn(); } catch (e) { if (e instanceof CanonicalError) return null; throw e; } };

/** Recompute the digest of a stored audit_events row. Returns null if the row is structurally unusable. */
export const recomputeEventDigest = (event) => safe(() => eventDigestOf(event));
/** Recompute the digest of a stored audit_receipts row (needs its event_digest/payload_sha256 columns). */
export const recomputeReceiptDigest = (receipt) => safe(() => receiptDigestOf(receipt));

/** Verify one event+receipt pair. Never throws for tampered data; returns reasons. */
export function verifyReceipt(event, receipt) {
  const reasons = [];
  if (!event || !receipt) return { ok: false, reasons: [!event ? 'event_missing' : 'receipt_missing'] };
  let ps = null;
  try { ps = payloadSha256(event.payload); } catch { /* unrepresentable payload */ }
  if (ps === null || !eqHex(ps, event.payload_sha256)) reasons.push('payload_hash_mismatch');
  if (!eqHex(recomputeEventDigest(event), event.event_digest)) reasons.push('event_digest_mismatch');
  if (receipt.event_id !== event.event_id) reasons.push('receipt_event_link_mismatch');
  if (receipt.event_digest !== event.event_digest || receipt.payload_sha256 !== event.payload_sha256
      || receipt.idempotency_key !== event.idempotency_key) reasons.push('receipt_fields_mismatch');
  if (!eqHex(recomputeReceiptDigest(receipt), receipt.receipt_digest)) reasons.push('receipt_digest_mismatch');
  return { ok: reasons.length === 0, reasons };
}

/**
 * Verify a whole hash chain for ONE (tenant, business) stream from rows read out of the database.
 * Same check order and reason strings as SQL verify_chain(): sequence_gap, prior_digest_mismatch,
 * payload_hash_mismatch, event_digest_mismatch, receipt_missing, receipt_digest_mismatch.
 * Returns { ok, checked, first_bad_seq, reason }.
 */
export function verifyChain(events, receipts, { genesis = GENESIS_DIGEST } = {}) {
  const byEvent = new Map((receipts || []).map((r) => [r.event_id, r]));
  const sorted = [...events].sort((a, b) => (BigInt(a.stream_seq) < BigInt(b.stream_seq) ? -1 : BigInt(a.stream_seq) > BigInt(b.stream_seq) ? 1 : 0));
  let prior = genesis; let expSeq = 1n; let n = 0;
  const bad = (seq, reason) => ({ ok: false, checked: n, first_bad_seq: Number(seq), reason });
  for (const e of sorted) {
    n++;
    if (BigInt(e.stream_seq) !== expSeq) return bad(e.stream_seq, 'sequence_gap');
    if (e.prior_digest !== prior) return bad(e.stream_seq, 'prior_digest_mismatch');
    let ps = null; try { ps = payloadSha256(e.payload); } catch { /* fallthrough */ }
    if (ps !== e.payload_sha256) return bad(e.stream_seq, 'payload_hash_mismatch');
    if (recomputeEventDigest(e) !== e.event_digest) return bad(e.stream_seq, 'event_digest_mismatch');
    const r = byEvent.get(e.event_id);
    if (!r) return bad(e.stream_seq, 'receipt_missing');
    if (recomputeReceiptDigest(r) !== r.receipt_digest || r.event_digest !== e.event_digest || r.payload_sha256 !== e.payload_sha256) {
      return bad(e.stream_seq, 'receipt_digest_mismatch');
    }
    prior = e.event_digest; expSeq += 1n;
  }
  return { ok: true, checked: n, first_bad_seq: null, reason: null };
}

/**
 * Offline simulation of the append boundary (tests/demo only; the database is authoritative).
 * Produces the next chained event row + receipt row from an envelope, the server-derived actor id and a head.
 */
export function chainEvent(envelope, { actorId, head, ingestTime, receiptId = randomUUID(), issuedAt } = {}) {
  const prior_digest = head ? head.last_digest : GENESIS_DIGEST;
  const stream_seq = (head ? BigInt(head.last_seq) : 0n) + 1n;
  const ing = utcIso(ingestTime);
  const event = {
    event_id: envelope.event_id, tenant_id: envelope.tenant_id, business_id: envelope.business_id,
    legal_entity_id: envelope.legal_entity_id, site_id: envelope.site_id, stream_seq: Number(stream_seq),
    source_domain: envelope.source_domain, source_id: envelope.source_id, source_version: envelope.source_version,
    action: envelope.action, event_time: envelope.event_time, ingest_time: ing, actor_id: actorId,
    correlation_id: envelope.correlation_id, idempotency_key: envelope.idempotency_key, payload: envelope.payload,
    payload_sha256: envelope.payload_sha256, prior_digest, reason_category: envelope.reason_category, schema_version: 1,
  };
  event.event_digest = eventDigestOf(event);
  const receipt = {
    receipt_id: receiptId, event_id: event.event_id, tenant_id: event.tenant_id, business_id: event.business_id,
    idempotency_key: event.idempotency_key, payload_sha256: event.payload_sha256, event_digest: event.event_digest,
    issued_at: utcIso(issuedAt ?? ingestTime),
  };
  receipt.receipt_digest = receiptDigestOf(receipt);
  return { event, receipt, head: { last_seq: Number(stream_seq), last_digest: event.event_digest } };
}

/**
 * Idempotency evidence: an exact replay must return the ORIGINAL receipt. Compares a replay result to the stored
 * receipt by identity AND digest; any difference is a mismatch (never silently accepted).
 */
export function replayMatchesReceipt(replay, stored) {
  return !!replay && !!stored && replay.receipt_id === stored.receipt_id && replay.event_id === stored.event_id
    && eqHex(replay.receipt_digest, stored.receipt_digest);
}

// ---- export bytes ------------------------------------------------------------------------------------------------

const toBytes = (b) => {
  if (b instanceof Uint8Array) return b;
  if (typeof b === 'string') return Buffer.from(b, 'utf8');
  throw new CanonicalError('EXPORT_BYTES', 'bytes must be a string or Uint8Array');
};

/** Count CSV records (RFC 4180 quoting aware: CR, LF, CRLF inside quotes are data). Header excluded by default. */
export function countCsvRows(bytes, { header = true } = {}) {
  const t = Buffer.from(toBytes(bytes)).toString('utf8');
  let records = 0; let inQ = false; let any = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (inQ) { if (c === '"') { if (t[i + 1] === '"') i++; else inQ = false; } any = true; continue; }
    if (c === '"') { inQ = true; any = true; continue; }
    if (c === '\r' || c === '\n') { if (c === '\r' && t[i + 1] === '\n') i++; if (any) records++; any = false; continue; }
    any = true;
  }
  if (any) records++;
  return Math.max(0, records - (header && records > 0 ? 1 : 0));
}

const pick = (o, names) => { for (const n of names) if (o[n] !== undefined && o[n] !== null) return o[n]; return undefined; };

/**
 * Verify exact export bytes against an export receipt. Accepts receipt field names
 * content_sha256 | byte_sha256 | sha256 (required), byte_count | bytes | size_bytes (optional), row_count (optional).
 * Returns { ok, reasons, actual: { sha256, byte_count, row_count } }; a missing hash is a FAILURE, not a pass.
 */
export function verifyExportBytes(bytes, receipt, { header = true } = {}) {
  const reasons = [];
  let b;
  try { b = toBytes(bytes); } catch { return { ok: false, reasons: ['bytes_invalid'], actual: null }; }
  const actual = { sha256: sha256Hex(b), byte_count: b.length, row_count: null };
  if (!receipt || typeof receipt !== 'object') return { ok: false, reasons: ['receipt_missing'], actual };
  const expected = pick(receipt, ['content_sha256', 'byte_sha256', 'sha256']);
  if (typeof expected !== 'string' || !/^[0-9a-f]{64}$/.test(expected)) reasons.push('receipt_hash_missing');
  else if (!eqHex(expected, actual.sha256)) reasons.push('content_hash_mismatch');
  const bc = pick(receipt, ['byte_count', 'bytes', 'size_bytes']);
  if (bc !== undefined && String(bc) !== String(actual.byte_count)) reasons.push('byte_count_mismatch');
  const rc = pick(receipt, ['row_count']);
  if (rc !== undefined) {
    actual.row_count = countCsvRows(b, { header });
    if (String(rc) !== String(actual.row_count)) reasons.push('row_count_mismatch');
  }
  return { ok: reasons.length === 0, reasons, actual };
}
