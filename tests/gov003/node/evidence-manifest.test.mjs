// Feature 11 incident-evidence-preservation: Node manifest builder/verifier, hold evaluation, purge decision.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  MANIFEST_SPEC, ZERO_DIGEST, LEGAL_NOTICE, ManifestError, sha256Hex, itemDigest, emptyManifestDigest, buildManifest,
  verifyManifest, verifyEvidenceBytes, validateEvidenceInput, protectionReasons, purgeDecision, assertIndependent,
  holdStatus, claimsLegalCompliance, utcIso,
} from '../../../internal/gov003/server/evidence-manifest.mjs';

const CASE = 'c0000000-0000-4000-8000-000000000001';
const U1 = '1d000000-0000-4000-8000-000000000002';
const code = (fn) => { try { fn(); } catch (e) { return e.code ?? e.message; } return null; };
const mk = (i, o = {}) => ({
  evidence_ref: `ev-${i}`, kind: 'log_extract', sha256: sha256Hex(`bytes-${i}`), byte_length: 100 + i, source_ref: `src:${i}`,
  retain_until: null, added_at: `2026-11-12T10:00:0${i}.000001Z`, added_by: U1, ...o,
});
const NOW = new Date('2026-11-12T12:00:00Z');
const FUTURE = '2026-12-01T00:00:00.000000Z';
const PAST = '2026-11-01T00:00:00.000000Z';

test('manifest chain: digests are deterministic, chained, and the manifest digest is the last item digest', () => {
  const m = buildManifest(CASE, [mk(1), mk(2), mk(3)]);
  assert.equal(MANIFEST_SPEC, 'g3m1');
  assert.equal(m.itemCount, 3);
  assert.equal(m.items[0].prior_digest, ZERO_DIGEST);
  assert.equal(m.items[1].prior_digest, m.items[0].item_digest);
  assert.equal(m.manifestDigest, m.items[2].item_digest);
  assert.equal(buildManifest(CASE, [mk(1), mk(2), mk(3)]).manifestDigest, m.manifestDigest);
  assert.notEqual(buildManifest(CASE, [mk(1), mk(3), mk(2)]).manifestDigest, m.manifestDigest); // order matters
  assert.notEqual(buildManifest('c0000000-0000-4000-8000-000000000002', [mk(1), mk(2), mk(3)]).manifestDigest, m.manifestDigest);
  assert.equal(buildManifest(CASE, []).manifestDigest, emptyManifestDigest(CASE));
  assert.ok(Object.isFrozen(m.items[0]));
});

test('verifyManifest: intact chain passes; matching expected digest passes', () => {
  const m = buildManifest(CASE, [mk(1), mk(2)]);
  const v = verifyManifest(CASE, m.items, { expectedDigest: m.manifestDigest });
  assert.equal(v.ok, true); assert.equal(v.itemCount, 2); assert.equal(v.manifestDigest, m.manifestDigest);
  assert.equal(verifyManifest(CASE, []).ok, true);
});

test('verifyManifest: every field of an entry is covered (tampering is detected at that sequence)', () => {
  const m = buildManifest(CASE, [mk(1), mk(2), mk(3)]);
  const tamper = { evidence_ref: 'other', kind: 'image', sha256: 'f'.repeat(64), byte_length: 1, source_ref: 'src:x',
    retain_until: '2030-01-01T00:00:00.000000Z', added_at: '2026-11-12T10:59:59.000001Z', added_by: '1d000000-0000-4000-8000-000000000001' };
  for (const [k, v] of Object.entries(tamper)) {
    const items = m.items.map((x) => ({ ...x }));
    items[1][k] = v;
    const r = verifyManifest(CASE, items);
    assert.equal(r.ok, false, k); assert.equal(r.reason, 'item_digest_mismatch', k); assert.equal(r.firstBadSeq, 2, k);
  }
});

test('verifyManifest: removed, reordered, relinked entries and a wrong case are detected', () => {
  const m = buildManifest(CASE, [mk(1), mk(2), mk(3)]);
  assert.equal(verifyManifest(CASE, [m.items[0], m.items[2]]).reason, 'sequence_gap');
  assert.equal(verifyManifest(CASE, [{ ...m.items[0], prior_digest: 'a'.repeat(64) }, m.items[1], m.items[2]]).reason, 'prior_digest_mismatch');
  assert.equal(verifyManifest(CASE, [m.items[2], m.items[1], m.items[0]]).ok, true); // sorted by item_seq first: order of input is irrelevant
  assert.equal(verifyManifest('c0000000-0000-4000-8000-000000000009', m.items).ok, false);
});

test('verifyManifest: caller-supplied digest mismatch is G3A04 (stale or forged manifest claim)', () => {
  const m = buildManifest(CASE, [mk(1)]);
  assert.equal(code(() => verifyManifest(CASE, m.items, { expectedDigest: 'e'.repeat(64) })), 'G3A04');
  assert.equal(code(() => verifyManifest(CASE, [], { expectedDigest: m.manifestDigest })), 'G3A04');
});

test('item digest is stable for a known vector (format drift guard)', () => {
  const it = { ...mk(1), item_seq: 1 };
  const expected = sha256Hex(['g3m1', ZERO_DIGEST, CASE, '1', 'ev-1', 'log_extract', it.sha256, '101', 'src:1', '', '2026-11-12T10:00:01.000001Z', U1].join('|'));
  assert.equal(itemDigest(it, ZERO_DIGEST, CASE), expected);
  const r = { ...it, retain_until: FUTURE };
  assert.equal(itemDigest(r, ZERO_DIGEST, CASE), sha256Hex(['g3m1', ZERO_DIGEST, CASE, '1', 'ev-1', 'log_extract', it.sha256, '101', 'src:1', FUTURE, '2026-11-12T10:00:01.000001Z', U1].join('|')));
});

test('validateEvidenceInput: opaque refs only; secrets, PII, bad kind/hash/length rejected', () => {
  assert.equal(validateEvidenceInput(mk(1)).kind, 'log_extract');
  for (const bad of [
    { evidence_ref: 'a b' }, { evidence_ref: 'user@example.com' }, { source_ref: 'Bearer abc' }, { source_ref: 'service_role' },
    { evidence_ref: '4111111111111111' }, { kind: 'video' }, { sha256: 'ABC' }, { sha256: 'a'.repeat(63) }, { byte_length: -1 },
    { byte_length: 1.5 }, { byte_length: 2e12 }, { evidence_ref: '' }, { evidence_ref: 'x'.repeat(129) },
  ]) assert.equal(code(() => validateEvidenceInput(mk(1, bad))), 'G3A03', JSON.stringify(bad));
});

test('verifyEvidenceBytes: exact content passes, any change or length difference is G3A04', () => {
  const item = { sha256: sha256Hex('payload'), byte_length: 7 };
  assert.equal(verifyEvidenceBytes(item, 'payload'), true);
  assert.equal(verifyEvidenceBytes(item, Buffer.from('payload')), true);
  assert.equal(code(() => verifyEvidenceBytes(item, 'payloae')), 'G3A04');
  assert.equal(code(() => verifyEvidenceBytes(item, 'payload!')), 'G3A04');
  assert.equal(code(() => verifyEvidenceBytes({ ...item, byte_length: 8 }, 'payload')), 'G3A04');
});

test('protection rule matrix: hold, retention, release, scope (item vs case-wide)', () => {
  const item = { evidence_id: 'E1', retain_until: null };
  const caseHold = { evidence_id: null, retention_until: FUTURE, released: false };
  assert.deepEqual(protectionReasons({ item, holds: [], now: NOW }), []);
  assert.deepEqual(protectionReasons({ item, holds: [caseHold], now: NOW }), ['hold_active', 'hold_retention']);
  assert.deepEqual(protectionReasons({ item, holds: [{ ...caseHold, retention_until: PAST }], now: NOW }), ['hold_active']);
  assert.deepEqual(protectionReasons({ item, holds: [{ ...caseHold, released: true }], now: NOW }), ['hold_retention']);
  assert.deepEqual(protectionReasons({ item, holds: [{ ...caseHold, released: true, retention_until: PAST }], now: NOW }), []);
  assert.deepEqual(protectionReasons({ item, holds: [{ evidence_id: 'E2', retention_until: FUTURE, released: false }], now: NOW }), []); // other item
  assert.deepEqual(protectionReasons({ item, holds: [{ evidence_id: 'E1', retention_until: PAST, released: false }], now: NOW }), ['hold_active']);
  assert.deepEqual(protectionReasons({ item: { ...item, retain_until: FUTURE }, holds: [], now: NOW }), ['item_retention']);
  assert.deepEqual(protectionReasons({ item: { ...item, retain_until: PAST }, holds: [], now: NOW }), []);
});

test('purgeDecision: refusal is G3H02 and audited; allowed purge means tombstone only; double purge is a no-op', () => {
  const item = { evidence_id: 'E1', retain_until: null };
  const held = purgeDecision({ item, holds: [{ evidence_id: null, retention_until: FUTURE, released: false }], now: NOW });
  assert.equal(held.outcome, 'refused'); assert.equal(held.allowed, false); assert.equal(held.errorCode, 'G3H02'); assert.equal(held.action, 'audit_refusal');
  const free = purgeDecision({ item, holds: [], now: NOW });
  assert.equal(free.outcome, 'tombstoned'); assert.equal(free.allowed, true); assert.equal(free.errorCode, null); assert.equal(free.action, 'append_tombstone');
  assert.equal(purgeDecision({ item, holds: [], now: NOW, tombstoned: true }).outcome, 'already_purged');
  for (const d of [held, free]) assert.equal(d.notice, LEGAL_NOTICE);
});

test('independence: placer cannot review or release; missing identities fail closed', () => {
  assert.equal(assertIndependent(U1, '1d000000-0000-4000-8000-000000000008'), true);
  assert.equal(code(() => assertIndependent(U1, U1)), 'G3A02');
  assert.equal(code(() => assertIndependent(null, U1)), 'G3A02');
  assert.equal(code(() => assertIndependent(U1, undefined)), 'G3A02');
});

test('holdStatus: pending until reviewed; release keeps in_force while retention_until is in the future', () => {
  const hold = { retention_until: FUTURE };
  assert.deepEqual(holdStatus({ hold, now: NOW }), { review_status: 'pending', released: false, in_force: true });
  assert.deepEqual(holdStatus({ hold, review: { decision: 'rejected' }, now: NOW }), { review_status: 'rejected', released: false, in_force: true });
  assert.deepEqual(holdStatus({ hold, release: {}, now: NOW }), { review_status: 'pending', released: true, in_force: true });
  assert.deepEqual(holdStatus({ hold: { retention_until: PAST }, release: {}, now: NOW }), { review_status: 'pending', released: true, in_force: false });
});

test('no false legal-hold compliance promise: notice, wording guard, and the shipped SQL/JS comments', () => {
  assert.ok(/not a legal-hold certification/i.test(LEGAL_NOTICE) && /Owner\/counsel gate/.test(LEGAL_NOTICE));
  assert.equal(claimsLegalCompliance(LEGAL_NOTICE), false);
  for (const bad of ['This hold is legally compliant', 'legal hold certified', 'court-proof evidence', 'guarantees compliance', 'WORM compliant storage']) {
    assert.equal(claimsLegalCompliance(bad), true, bad);
  }
  for (const rel of ['../../../internal/gov003/sql/110_incident.sql', '../../../internal/gov003/server/evidence-manifest.mjs']) {
    const src = readFileSync(new URL(rel, import.meta.url), 'utf8');
    assert.equal(claimsLegalCompliance(src), false, rel);
    assert.ok(/ENGINEERING CONTROL/i.test(src), rel);
    assert.ok(/NOT a legal-hold certification/i.test(src), rel);
    assert.ok(/counsel/i.test(src), rel);
  }
});

test('utcIso normalizes Date and rejects garbage; module imports only node:crypto', () => {
  assert.equal(utcIso(new Date('2026-11-12T10:00:00Z')), '2026-11-12T10:00:00.000000Z');
  assert.equal(code(() => utcIso('nope')), 'G3A03');
  const src = readFileSync(new URL('../../../internal/gov003/server/evidence-manifest.mjs', import.meta.url), 'utf8');
  assert.deepEqual([...src.matchAll(/^import .* from '([^']+)'/gm)].map((m) => m[1]), ['node:crypto']);
  assert.ok(new ManifestError('G3A04', 'x') instanceof Error);
});
