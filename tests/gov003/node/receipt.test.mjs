import test from 'node:test';
import assert from 'node:assert/strict';
import { buildEnvelope } from '../../../internal/gov003/server/envelope.mjs';
import { chainEvent, verifyChain, verifyReceipt, replayMatchesReceipt, verifyExportBytes, countCsvRows, recomputeEventDigest } from '../../../internal/gov003/server/receipt.mjs';
import { sha256Hex, GENESIS_DIGEST } from '../../../internal/gov003/server/canonical.mjs';
import { T1, B1, S1, U } from '../lib/ids.mjs';

const mk = (i) => buildEnvelope({ tenant_id: T1, business_id: B1, site_id: S1, source_domain: 'pos', source_id: `sale-${i}`, source_version: 'v1',
  action: 'sale.created', event_time: '2026-11-12T10:00:00Z', correlation_id: `corr-${i}`, idempotency_key: `idem-key-000${i}`,
  payload: { status: 'open', count: String(i) }, reason_category: 'operational' });

function chain(n) {
  let head = null; const events = []; const receipts = [];
  for (let i = 1; i <= n; i++) {
    const r = chainEvent(mk(i), { actorId: U.bizOwnerB1, head, ingestTime: `2026-11-12T10:00:0${i}.123456Z`, receiptId: `c0000000-0000-4000-8000-00000000000${i}` });
    events.push(r.event); receipts.push(r.receipt); head = r.head;
  }
  return { events, receipts, head };
}
const clone = (x) => JSON.parse(JSON.stringify(x));

test('chainEvent builds a valid linked chain starting at the genesis digest', () => {
  const { events, receipts } = chain(3);
  assert.equal(events[0].prior_digest, GENESIS_DIGEST);
  assert.equal(events[1].prior_digest, events[0].event_digest);
  assert.deepEqual(verifyChain(events, receipts), { ok: true, checked: 3, first_bad_seq: null, reason: null });
  assert.deepEqual(verifyChain([], []), { ok: true, checked: 0, first_bad_seq: null, reason: null });
  for (let i = 0; i < 3; i++) assert.equal(verifyReceipt(events[i], receipts[i]).ok, true);
});

test('verifyChain detects every tamper class with the SQL reason strings', () => {
  const { events, receipts } = chain(3);
  const t = (mut, reason, seq) => {
    const e = clone(events); const r = clone(receipts); mut(e, r);
    const v = verifyChain(e, r);
    assert.equal(v.ok, false); assert.equal(v.reason, reason); assert.equal(v.first_bad_seq, seq);
  };
  t((e) => { e.splice(1, 1); }, 'sequence_gap', 3);
  t((e) => { e[1].prior_digest = 'f'.repeat(64); }, 'prior_digest_mismatch', 2);
  t((e) => { e[1].payload.status = 'closed'; }, 'payload_hash_mismatch', 2);
  t((e) => { e[1].action = 'sale.deleted'; }, 'event_digest_mismatch', 2);
  t((e) => { e[0].actor_id = '1d000000-0000-4000-8000-000000000001'; }, 'event_digest_mismatch', 1);
  t((e) => { e[2].ingest_time = '2026-11-12T10:00:09.000001Z'; }, 'event_digest_mismatch', 3);
  t((e, r) => { r.splice(2, 1); }, 'receipt_missing', 3);
  t((e, r) => { r[0].receipt_digest = 'f'.repeat(64); }, 'receipt_digest_mismatch', 1);
  t((e, r) => { r[1].issued_at = '2026-11-12T10:00:59Z'; }, 'receipt_digest_mismatch', 2);
  // a consistent rewrite of one event + its digests breaks the NEXT link (tamper-evident)
  const e = clone(events); const r = clone(receipts);
  e[0].payload = { status: 'forged' }; e[0].payload_sha256 = sha256Hex('{"status":"forged"}');
  e[0].event_digest = recomputeEventDigest(e[0]);
  assert.equal(verifyChain(e, r).ok, false);
});

test('verifyReceipt reports precise reasons and never throws on tampered data', () => {
  const { events, receipts } = chain(1);
  const e = clone(events[0]); const r = clone(receipts[0]);
  assert.equal(verifyReceipt(null, r).reasons[0], 'event_missing');
  assert.equal(verifyReceipt(e, null).reasons[0], 'receipt_missing');
  assert.ok(verifyReceipt({ ...e, payload: { status: 'x' } }, r).reasons.includes('payload_hash_mismatch'));
  assert.ok(verifyReceipt({ ...e, event_id: 'garbage' }, r).reasons.includes('event_digest_mismatch'));
  assert.ok(verifyReceipt(e, { ...r, receipt_id: 'c0000000-0000-4000-8000-0000000000ff' }).reasons.includes('receipt_digest_mismatch'));
  assert.ok(verifyReceipt(e, { ...r, idempotency_key: 'idem-other-key' }).reasons.includes('receipt_fields_mismatch'));
});

test('idempotency evidence: exact replay must return the original receipt', () => {
  const { receipts } = chain(1);
  assert.equal(replayMatchesReceipt({ ...receipts[0] }, receipts[0]), true);
  assert.equal(replayMatchesReceipt({ ...receipts[0], receipt_digest: 'f'.repeat(64) }, receipts[0]), false);
  assert.equal(replayMatchesReceipt({ ...receipts[0], receipt_id: 'c0000000-0000-4000-8000-0000000000ff' }, receipts[0]), false);
  assert.equal(replayMatchesReceipt(null, receipts[0]), false);
});

test('countCsvRows is quote aware (CR/LF inside quotes are data)', () => {
  assert.equal(countCsvRows('a,b\r\n1,2\r\n3,4\r\n'), 2);
  assert.equal(countCsvRows('a,b\n1,"x\ny"\n3,4'), 2);
  assert.equal(countCsvRows('a,b\n'), 0);
  assert.equal(countCsvRows(''), 0);
  assert.equal(countCsvRows('a\n"q""\n"\n', { header: false }), 2);
});

test('verifyExportBytes: exact hash/size/row match; mismatch, missing receipt and missing hash all FAIL', () => {
  const csv = 'id,n\r\n1,a\r\n2,b\r\n';
  const receipt = { content_sha256: sha256Hex(csv), byte_count: Buffer.byteLength(csv), row_count: 2 };
  assert.equal(verifyExportBytes(csv, receipt).ok, true);
  assert.equal(verifyExportBytes(Buffer.from(csv), receipt).ok, true);
  assert.equal(verifyExportBytes(csv, { byte_sha256: receipt.content_sha256 }).ok, true);
  assert.deepEqual(verifyExportBytes(csv + ' ', receipt).reasons, ['content_hash_mismatch', 'byte_count_mismatch', 'row_count_mismatch']);
  assert.deepEqual(verifyExportBytes(csv, { ...receipt, row_count: 3 }).reasons, ['row_count_mismatch']);
  assert.deepEqual(verifyExportBytes(csv, null).reasons, ['receipt_missing']);
  assert.deepEqual(verifyExportBytes(csv, {}).reasons, ['receipt_hash_missing']);
  assert.deepEqual(verifyExportBytes(csv, { content_sha256: 'A'.repeat(64) }).reasons, ['receipt_hash_missing']);
  assert.deepEqual(verifyExportBytes(42, receipt).reasons, ['bytes_invalid']);
  assert.equal(verifyExportBytes(csv, receipt).actual.row_count, 2);
});
