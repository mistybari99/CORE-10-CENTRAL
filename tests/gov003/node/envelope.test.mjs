import test from 'node:test';
import assert from 'node:assert/strict';
import { buildEnvelope, validateEnvelope, assertNoAuthorityClaims, toSqlParams, APPEND_EVENT_SQL, EnvelopeError, REASON_CATEGORIES } from '../../../internal/gov003/server/envelope.mjs';
import { payloadSha256, canonicalJson } from '../../../internal/gov003/server/canonical.mjs';
import { PayloadError } from '../../../internal/gov003/server/redact.mjs';
import { lintSql } from '../../../internal/gov003/server/pg.mjs';
import { T1, B1, S1, LE1 } from '../lib/ids.mjs';

const base = () => ({
  tenant_id: T1, business_id: B1, site_id: S1, legal_entity_id: LE1, source_domain: 'pos', source_id: 'sale-100', source_version: 'v1',
  action: 'sale.created', event_time: '2026-11-12T10:00:00+06:00', correlation_id: 'corr-1', idempotency_key: 'idem-key-0001',
  payload: { status: 'open', amount_minor: '1250' }, reason_category: 'operational',
});
const code = (c) => (e) => e instanceof EnvelopeError && e.code === c;

test('buildEnvelope produces a frozen, typed, hashed envelope with an empty ingest slot', () => {
  const e = buildEnvelope(base());
  assert.equal(e.schema_version, 1);
  assert.equal(e.ingest_time, null);
  assert.equal(e.event_time, '2026-11-12T04:00:00.000000Z');
  assert.match(e.event_id, /^[0-9a-f]{8}-[0-9a-f]{4}-4/);
  assert.equal(e.payload_sha256, payloadSha256({ amount_minor: '1250', status: 'open' }));
  assert.ok(Object.isFrozen(e) && Object.isFrozen(e.payload));
  assert.equal(Object.hasOwn(e, 'actor_id'), false);
  assert.equal(Object.keys(e).some((k) => /actor|role/.test(k)), false);
  assert.equal(buildEnvelope({ ...base(), site_id: undefined, legal_entity_id: null }).site_id, null);
  assert.equal(buildEnvelope({ ...base(), event_id: 'E0000000-0000-4000-8000-000000000001' }).event_id, 'e0000000-0000-4000-8000-000000000001');
  assert.deepEqual(REASON_CATEGORIES.length, 11);
});

test('buildEnvelope redacts: unknown payload fields dropped by name, never serialised', () => {
  const e = buildEnvelope({ ...base(), payload: { status: 'open', customer_email: 'a@b.com' } });
  assert.deepEqual(e.payload, { status: 'open' });
  assert.deepEqual([...e.redaction_dropped], ['customer_email']);
  assert.equal(JSON.stringify(e).includes('a@b.com'), false);
  assert.equal(JSON.stringify(e).includes('customer_email'), false);
});

test('NEGATIVE forged client actor / role / tenant authority claims are rejected', () => {
  for (const claim of [{ actor_id: '1d000000-0000-4000-8000-000000000002' }, { actor: 'owner' }, { claimed_actor: 'x' }, { role: 'tenant_owner' },
    { Roles: ['owner'] }, { is_admin: true }, { permissions: ['all'] }, { claims: { sub: 'x' } }, { jwt: 'x' }, { identity_id: 'x' }, { sub: 'x' },
    { service_role: 'x' }, { user_id: 'x' }]) {
    assert.throws(() => buildEnvelope({ ...base(), ...claim }), code('ENVELOPE_AUTHORITY_CLAIM'), JSON.stringify(claim));
  }
  assert.throws(() => buildEnvelope({ ...base(), payload: { meta: { role: 'owner' } } }), code('ENVELOPE_AUTHORITY_CLAIM'));
  assert.throws(() => assertNoAuthorityClaims({ x: { tenant_role: 'owner' } }), code('ENVELOPE_AUTHORITY_CLAIM'));
  assert.throws(() => buildEnvelope({ ...base(), tenant_owner: true }), code('ENVELOPE_AUTHORITY_CLAIM'));
});

test('NEGATIVE shape, scope and field validation', () => {
  const bads = [
    [{ tenant_id: undefined }, 'ENVELOPE_FIELD'], [{ business_id: 'not-a-uuid' }, 'ENVELOPE_FIELD'], [{ site_id: 'zzz' }, 'ENVELOPE_FIELD'],
    [{ source_domain: 'POS' }, 'ENVELOPE_FIELD'], [{ source_id: 'has space' }, 'ENVELOPE_FIELD'], [{ source_id: 'a@b.com' }, 'ENVELOPE_FIELD'],
    [{ source_version: '' }, 'ENVELOPE_FIELD'], [{ action: '1bad' }, 'ENVELOPE_FIELD'], [{ idempotency_key: 'short' }, 'ENVELOPE_FIELD'],
    [{ correlation_id: 'has|pipe' }, 'ENVELOPE_FIELD'], [{ reason_category: 'because' }, 'ENVELOPE_FIELD'], [{ event_time: '2026-11-12T10:00:00' }, 'ENVELOPE_TIME'],
    [{ event_time: 1700000000 }, 'ENVELOPE_TIME'], [{ schema_version: 2 }, 'ENVELOPE_SCHEMA'], [{ extra_field: 1 }, 'ENVELOPE_UNKNOWN_FIELD'],
    [{ payload_sha256: 'f'.repeat(64) }, 'ENVELOPE_HASH_MISMATCH'],
  ];
  for (const [patch, c] of bads) assert.throws(() => buildEnvelope({ ...base(), ...patch }), code(c), JSON.stringify(patch));
  assert.throws(() => buildEnvelope(null), code('ENVELOPE_SHAPE'));
  assert.throws(() => buildEnvelope([]), code('ENVELOPE_SHAPE'));
  assert.throws(() => buildEnvelope({ ...base(), payload: { count: 1.5 } }), PayloadError);
  assert.throws(() => buildEnvelope({ ...base(), payload: { item_ref: 'user@example.com' } }), PayloadError);
});

test('supplied payload_sha256 is accepted only if it matches the redacted canonical payload', () => {
  const ok = buildEnvelope({ ...base(), payload_sha256: payloadSha256({ amount_minor: '1250', status: 'open' }) });
  assert.equal(ok.payload_sha256, payloadSha256({ status: 'open', amount_minor: '1250' }));
});

test('validateEnvelope re-validates and rejects tampered or caller-set ingest_time', () => {
  const e = buildEnvelope(base());
  assert.doesNotThrow(() => validateEnvelope({ ...e }));
  assert.throws(() => validateEnvelope({ ...e, ingest_time: '2026-11-12T10:00:00Z' }), code('ENVELOPE_INGEST_SLOT'));
  assert.throws(() => validateEnvelope({ ...e, payload: { ...e.payload, status: 'closed' } }), code('ENVELOPE_HASH_MISMATCH'));
  assert.throws(() => validateEnvelope({ ...e, actor_id: 'x' }), code('ENVELOPE_AUTHORITY_CLAIM'));
  assert.throws(() => validateEnvelope({ ...e, payload: { status: 'open', amount_minor: '1250', junk: 'x' }, payload_sha256: e.payload_sha256 }), code('ENVELOPE_NOT_REDACTED'));
});

test('toSqlParams / APPEND_EVENT_SQL are psql-parameterised and never carry an actor', () => {
  const e = buildEnvelope(base());
  const p = toSqlParams(e);
  assert.equal(p.payload, canonicalJson(e.payload));
  assert.equal(Object.keys(p).some((k) => /actor|role/.test(k)), false);
  const refs = lintSql(APPEND_EVENT_SQL);
  for (const r of refs) assert.ok(Object.hasOwn(p, r), `unsupplied ref ${r}`);
  for (const k of Object.keys(p)) assert.ok(refs.has(k), `param ${k} unused`);
  assert.match(APPEND_EVENT_SQL, /null::uuid, :'event_id'::uuid\)/); // p_claimed_actor is always NULL
});
