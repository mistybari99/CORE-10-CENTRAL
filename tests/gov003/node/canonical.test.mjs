import test from 'node:test';
import assert from 'node:assert/strict';
import {
  canonicalJson, sha256Hex, payloadSha256, strictJsonParse, utcIso, parseTimestampMicros, decimalToMinorUnits,
  minorUnitsToDecimal, eventDigestOf, receiptDigestOf, GENESIS_DIGEST, CanonicalError,
} from '../../../internal/gov003/server/canonical.mjs';

const throwsCode = (fn, code) => assert.throws(fn, (e) => e instanceof CanonicalError && e.code === code, `expected ${code}`);

test('canonical: sorted keys bytewise on UTF-8, no whitespace, nested', () => {
  assert.equal(canonicalJson({ b: 1, a: { z: [1, { y: null, x: true }], c: 'q' } }),
    '{"a":{"c":"q","z":[1,{"x":true,"y":null}]},"b":1}');
  // U+FFFF (EF BF BF) sorts BEFORE U+1F600 (F0 9F 98 80) bytewise although UTF-16 order is the opposite.
  assert.equal(canonicalJson({ '\u{1F600}': 1, '￿': 2 }), '{"￿":2,"\u{1F600}":1}');
  assert.equal(canonicalJson({}), '{}');
  assert.equal(canonicalJson([]), '[]');
  assert.equal(canonicalJson({ B: 1, a: 2, _: 3 }), '{"B":1,"_":3,"a":2}');
});

test('canonical: string escapes match PostgreSQL jsonb output', () => {
  assert.equal(canonicalJson('\u0001\u001f\b\f\n\r\t"\\'), '"\\u0001\\u001f\\b\\f\\n\\r\\t\\"\\\\"');
  assert.equal(canonicalJson('\u007f é/'), '"\u007f é/"');
  assert.equal(canonicalJson('\u{1F600}'), '"\u{1F600}"');
});

test('canonical: integers, BigInt, negative zero', () => {
  assert.equal(canonicalJson([0, -0, 1, -5, 9007199254740991, 12345678901234567890n]), '[0,0,1,-5,9007199254740991,12345678901234567890]');
});

test('canonical negatives: floats, NaN, Infinity, unsafe ints, undefined, exotic types, NUL, surrogates', () => {
  throwsCode(() => canonicalJson(1.5), 'CANON_FLOAT');
  throwsCode(() => canonicalJson(NaN), 'CANON_NUMBER');
  throwsCode(() => canonicalJson(Infinity), 'CANON_NUMBER');
  throwsCode(() => canonicalJson(2 ** 53), 'CANON_UNSAFE_INT');
  throwsCode(() => canonicalJson(undefined), 'CANON_UNDEFINED');
  throwsCode(() => canonicalJson({ a: undefined }), 'CANON_UNDEFINED');
  throwsCode(() => canonicalJson([1, , 3]), 'CANON_SPARSE'); // eslint-disable-line no-sparse-arrays
  throwsCode(() => canonicalJson(new Date()), 'CANON_TYPE');
  throwsCode(() => canonicalJson(new Map()), 'CANON_TYPE');
  throwsCode(() => canonicalJson(() => 1), 'CANON_TYPE');
  throwsCode(() => canonicalJson(Symbol('x')), 'CANON_TYPE');
  throwsCode(() => canonicalJson('a\u0000b'), 'CANON_NUL');
  throwsCode(() => canonicalJson('\ud800'), 'CANON_SURROGATE');
  throwsCode(() => canonicalJson({ '\udc00': 1 }), 'CANON_SURROGATE');
  let deep = {}; const root = deep; for (let i = 0; i < 80; i++) { deep.n = {}; deep = deep.n; }
  throwsCode(() => canonicalJson(root), 'CANON_DEPTH');
});

test('sha256Hex known vectors and bytes/string equivalence', () => {
  assert.equal(sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assert.equal(sha256Hex(Buffer.from('abc')), sha256Hex('abc'));
  assert.equal(payloadSha256({ a: '1' }), sha256Hex('{"a":"1"}'));
  throwsCode(() => sha256Hex(5), 'CANON_BAD_INPUT');
});

test('strictJsonParse rejects floats, exponents, unsafe ints, duplicate keys', () => {
  assert.deepEqual(strictJsonParse('{"a":{"b":1},"c":{"b":2},"d":["x",-3]}'), { a: { b: 1 }, c: { b: 2 }, d: ['x', -3] });
  for (const bad of ['{"a":1.5}', '{"a":1e3}', '{"a":12345678901234567890}', '{"a":1,"a":2}', '{"x":{"k":1,"k":2}}']) {
    throwsCode(() => strictJsonParse(bad), 'CANON_STRICT_JSON');
  }
  assert.deepEqual(strictJsonParse('{"a":"k\\":1,\\"k\\":2"}'), { a: 'k":1,"k":2' }); // escaped quotes are not keys
});

test('utcIso: exact UTC microsecond formatting, offsets, rounding, ranges', () => {
  assert.equal(utcIso('2026-11-12T10:00:00Z'), '2026-11-12T10:00:00.000000Z');
  assert.equal(utcIso('2026-11-12T10:00:00.5+00:00'), '2026-11-12T10:00:00.500000Z');
  assert.equal(utcIso('2026-11-12T10:00:00.123456+05:30'), '2026-11-12T04:30:00.123456Z');
  assert.equal(utcIso('2026-11-12 10:00:00.1234565-0100'), '2026-11-12T11:00:00.123457Z');
  assert.equal(utcIso('2026-11-12T23:59:59.9999996Z'), '2026-11-13T00:00:00.000000Z');
  assert.equal(utcIso('2024-02-29T00:00:00+02'), '2024-02-28T22:00:00.000000Z');
  assert.equal(utcIso(new Date(Date.UTC(2026, 0, 2, 3, 4, 5, 678))), '2026-01-02T03:04:05.678000Z');
  assert.equal(utcIso(1700000000123456n), '2023-11-14T22:13:20.123456Z');
  assert.equal(parseTimestampMicros('1970-01-01T00:00:00Z'), 0n);
  assert.equal(utcIso('0099-01-01T00:00:00Z'), '0099-01-01T00:00:00.000000Z');
  for (const bad of ['2026-11-12T10:00:00', '2026-02-29T00:00:00Z', '2026-13-01T00:00:00Z', '2026-11-12T24:00:00Z',
    '2026-11-12T10:00:60Z', 'yesterday', '', 12345, null, undefined, {}, new Date('x')]) {
    assert.throws(() => utcIso(bad), (e) => e instanceof CanonicalError, `should reject ${String(bad)}`);
  }
});

test('decimals are exact (BigInt minor units), never floats', () => {
  assert.equal(decimalToMinorUnits('12.34', 2), 1234n);
  assert.equal(decimalToMinorUnits('12', 2), 1200n);
  assert.equal(decimalToMinorUnits('-0.05', 2), -5n);
  assert.equal(decimalToMinorUnits('0.1', 2) + decimalToMinorUnits('0.2', 2), decimalToMinorUnits('0.3', 2));
  assert.equal(minorUnitsToDecimal(-5n, 2), '-0.05');
  assert.equal(minorUnitsToDecimal(1234, 2), '12.34');
  assert.equal(minorUnitsToDecimal(7n, 0), '7');
  for (const bad of ['1.234', '1e2', '+1', '01', '1.', '.5', '', ' 1']) assert.throws(() => decimalToMinorUnits(bad, 2), CanonicalError);
  assert.throws(() => decimalToMinorUnits(1.5, 2), CanonicalError);
});

const EV = {
  prior_digest: GENESIS_DIGEST, event_id: 'e0000000-0000-4000-8000-000000000001', tenant_id: '11111111-1111-4111-8111-111111111111',
  business_id: 'b1000000-0000-4000-8000-000000000001', site_id: null, stream_seq: 1, source_domain: 'pos', source_id: 'sale-1',
  source_version: 'v1', action: 'sale.created', event_time: '2026-11-12T10:00:00Z', ingest_time: '2026-11-12T10:00:01.5Z',
  actor_id: '1d000000-0000-4000-8000-000000000002', correlation_id: 'corr-1', idempotency_key: 'idem-key-0001',
  payload_sha256: 'a'.repeat(64), reason_category: 'operational', schema_version: 1,
};

test('eventDigestOf follows the g3e1 concat_ws format', () => {
  const manual = sha256Hex(['g3e1', GENESIS_DIGEST, EV.event_id, EV.tenant_id, EV.business_id, '', '1', 'pos', 'sale-1', 'v1',
    'sale.created', '2026-11-12T10:00:00.000000Z', '2026-11-12T10:00:01.500000Z', EV.actor_id, 'corr-1', 'idem-key-0001',
    'a'.repeat(64), 'operational', '1'].join('|'));
  assert.equal(eventDigestOf(EV), manual);
  // timestamps in any offset / precision hash identically; uppercase UUIDs normalise
  assert.equal(eventDigestOf({ ...EV, event_time: '2026-11-12T15:00:00+05:00', event_id: EV.event_id.toUpperCase(), stream_seq: 1n }), manual);
  assert.notEqual(eventDigestOf({ ...EV, site_id: '51000000-0000-4000-8000-000000000001' }), manual);
});

test('eventDigestOf rejects structurally unusable input instead of guessing', () => {
  for (const patch of [{ prior_digest: 'x' }, { event_id: 'nope' }, { action: 'a|b' }, { source_id: '' }, { stream_seq: 1.5 },
    { payload_sha256: 'A'.repeat(64) }, { event_time: 'bad' }, { actor_id: null }]) {
    assert.throws(() => eventDigestOf({ ...EV, ...patch }), CanonicalError, JSON.stringify(patch));
  }
});

test('receiptDigestOf follows the g3r1 concat_ws format', () => {
  const R = { receipt_id: 'c0000000-0000-4000-8000-000000000001', event_id: EV.event_id, event_digest: 'b'.repeat(64),
    payload_sha256: 'a'.repeat(64), idempotency_key: 'idem-key-0001', issued_at: '2026-11-12T10:00:01.5Z' };
  assert.equal(receiptDigestOf(R), sha256Hex(['g3r1', R.receipt_id, R.event_id, R.event_digest, R.payload_sha256, R.idempotency_key,
    '2026-11-12T10:00:01.500000Z'].join('|')));
  assert.notEqual(receiptDigestOf({ ...R, idempotency_key: 'idem-key-0002' }), receiptDigestOf(R));
});
