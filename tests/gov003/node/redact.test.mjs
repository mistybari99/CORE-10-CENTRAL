import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  PAYLOAD_ALLOWLIST, ALLOWLIST_FIELDS, looksSecret, validatePayload, redactPayload, scrubText, projectSafeError, PayloadError,
  ERROR_CATALOG,
} from '../../../internal/gov003/server/redact.mjs';
import { NoSignedSessionAdapter, createSessionAdapter } from '../../../internal/gov003/server/adapters.mjs';

const JWT = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';

test('allowlist JSON is well formed and has the 40 approved fields', () => {
  const j = JSON.parse(readFileSync(new URL('../../../internal/gov003/shared/payload_allowlist.json', import.meta.url), 'utf8'));
  assert.equal(j.fields.length, 40);
  assert.equal(PAYLOAD_ALLOWLIST.size, 40);
  assert.equal(ALLOWLIST_FIELDS.length, 40);
  for (const f of j.fields) assert.match(f.kind, /^(enum|ref|money|count|ts|text)$/);
  assert.equal(PAYLOAD_ALLOWLIST.get('amount_minor'), 'money');
  assert.equal(PAYLOAD_ALLOWLIST.get('password'), undefined);
});

test('validatePayload accepts approved fields of every kind', () => {
  validatePayload({ amount_minor: '-1250', currency: 'bdt', item_ref: 'sku:1/a#2', quantity_milli: '1500', count: '3',
    window_start: '2026-11-12T10:00:00Z', commit_sha: 'a1b2c3d4', status: 'open', note_code: null, severity: true });
});

test('validatePayload rejects (never drops): unknown, wrong kind, numbers, nested, long, secret-like', () => {
  const bad = [
    { unknown_field: 'x' }, { password: 'x' }, { amount_minor: '12.5' }, { amount_minor: 12 }, { count: '1e3' },
    { window_start: '2026-11-12 10:00' }, { status: 'Has Space' }, { status: 'UPPER' }, { item_ref: 'has space' },
    { item_ref: JWT }, { item_ref: 'user@example.com' }, { item_ref: 'token-abc' }, { item_ref: 'x'.repeat(257) },
    { item_ref: 'x'.repeat(129) }, { status: { a: 1 } }, { status: ['a'] }, { count: 5n },
  ];
  for (const p of bad) assert.throws(() => validatePayload(p), (e) => e instanceof PayloadError && e.code === 'G3A03', String(JSON.stringify(p, (_k, v) => (typeof v === 'bigint' ? `${v}n` : v))));
  for (const p of [null, undefined, [], 'x', 3]) assert.throws(() => validatePayload(p), PayloadError);
});

test('looksSecret detectors', () => {
  for (const s of [JWT, 'Bearer abc', 'service_role', 'my password', 'API-KEY', 'a@b.co', '1234567890123456', '123456789',
    'x\n   at foo (file.js:1:1)', 'TOKEN', 'private_key', 'Authorization', '1234567890123456789012']) assert.equal(looksSecret(s), true, s);
  for (const s of ['sale-1', 'open', '12345678', 'a@b', 'invoice:2026/11#7']) assert.equal(looksSecret(s), false, s);
});

test('redactPayload drops unknown fields by name only and validates known ones', () => {
  const r = redactPayload({ status: 'open', email: 'a@b.com', note: 'free text', count: '2' });
  assert.deepEqual(r.payload, { status: 'open', count: '2' });
  assert.deepEqual(r.dropped, ['email', 'note']);
  assert.equal(JSON.stringify(r).includes('a@b.com'), false, 'dropped VALUES must not appear anywhere');
  assert.throws(() => redactPayload({ item_ref: JWT }), PayloadError);
  const d = redactPayload({ item_ref: JWT, status: 'ok' }, { onInvalid: 'drop' });
  assert.deepEqual(d.payload, { status: 'ok' });
  assert.deepEqual(d.rejected, ['item_ref']);
  assert.throws(() => redactPayload({ count: 3 }), PayloadError);
  assert.deepEqual(redactPayload({ count: 3, amount_minor: 10n }, { coerceIntegers: true }).payload, { count: '3', amount_minor: '10' });
  assert.deepEqual(redactPayload({ __proto__x: 1, constructor: 'x' }).payload, {});
  assert.throws(() => redactPayload([]), PayloadError);
  assert.doesNotThrow(() => validatePayload(redactPayload({ status: 'ok', junk: 1 }).payload));
});

test('scrubText removes jwt, bearer, urls, assignments, emails, numbers, frames and keeps one line', () => {
  const s = scrubText(`fail user=bob@example.com token=abc123 ${JWT} Bearer abcdef.ghi postgres://u:p@h/db call +8801712345678 at foo (/srv/app.js:1:2)\n   at bar (x.js:1:1)`);
  for (const leak of ['bob@example.com', 'abc123', 'eyJ', 'abcdef.ghi', 'u:p@h', '8801712345678', 'app.js', 'bar (']) assert.equal(s.includes(leak), false, leak);
  assert.match(s, /\[redacted-jwt\]/); assert.match(s, /bearer \[redacted\]/); assert.match(s, /\[redacted-url\]/);
  assert.match(s, /\[redacted-email\]/); assert.match(s, /\[redacted-number\]/); assert.match(s, /\[frame\]/);
  assert.equal(s.includes('\n'), false);
  assert.equal(scrubText(null), '');
  assert.equal([...scrubText('é'.repeat(500))].length, 300);
  assert.equal(scrubText('Password: hunter2 then'), 'Password=[redacted] then');
});

test('projectSafeError: catalog code, public message, scrubbed detail, never stack or foreign db text', () => {
  const e = Object.assign(new Error('scope_denied at /srv/x.js'), { code: 'G3A02', detail: 'scope_denied for user a@b.com' });
  const p = projectSafeError(e, { correlationId: 'corr-9' });
  assert.equal(p.error_code, 'SCOPE_DENIED');
  assert.equal(p.http_status, 403);
  assert.equal(p.correlation_id, 'corr-9');
  assert.equal(p.scrubbed_detail.includes('a@b.com'), false);
  assert.deepEqual(Object.keys(p).sort(), ['correlation_id', 'error_code', 'http_status', 'public_message', 'scrubbed_detail', 'severity']);
  const internal = projectSafeError(Object.assign(new Error(`boom password=hunter2 ${JWT}`), { code: '22P02' }));
  assert.equal(internal.error_code, 'INTERNAL');
  assert.equal(internal.scrubbed_detail, '', 'unclassified errors carry no raw detail at all');
  assert.match(internal.correlation_id, /^err-/);
  assert.equal(projectSafeError('string thrown').error_code, 'INTERNAL');
  assert.equal(projectSafeError(null).error_code, 'INTERNAL');
  assert.equal(Object.keys(ERROR_CATALOG).length, 6);
});

test('SYNTHETIC DEBUGGING EXAMPLE: token, PII and stack are removed; no signed GoTrue proof is claimed', async () => {
  const syn = new Error(
    `Command failed for customer ritu.rahman@example.com phone +8801712345678 card 4111111111111111\n` +
    `    at Object.handler (/srv/gov003/app.js:88:13)\n    at async Router.dispatch (/srv/gov003/router.js:12:5)\n` +
    `Authorization: Bearer ${JWT}\nconnection postgres://svc:s3cret@db.internal:5432/prod service_role=sbp_live_abc`);
  syn.stack = `Error: ${syn.message}\n    at Object.handler (/srv/gov003/app.js:88:13)`;
  syn.code = 'G3A03';
  const safe = projectSafeError(syn, { correlationId: 'dbg-example-1' });
  const blob = JSON.stringify(safe);
  for (const leak of ['ritu', 'example.com', '8801712345678', '4111111111111111', 'eyJ', 's3cret', 'postgres://', 'sbp_live', 'app.js',
    'router.js', 'at Object', 'Router.dispatch', 'service_role=sbp']) assert.equal(blob.includes(leak), false, `leaked: ${leak}`);
  assert.equal(safe.scrubbed_detail.includes('\n'), false);
  assert.ok(safe.scrubbed_detail.includes('[redacted'));
  // The same event payload attempt is refused by redaction: PII/secret fields can never reach an audit event.
  const r = redactPayload({ status: 'failed', customer_email: 'ritu@example.com', phone: '+880171', card: '4111111111111111', token: JWT });
  assert.deepEqual(r.payload, { status: 'failed' });
  assert.equal(JSON.stringify(r).includes('ritu'), false);
  // No signed GoTrue proof is available anywhere in this module: authentication fails closed.
  await assert.rejects(new NoSignedSessionAdapter().authenticate({ headers: { authorization: `Bearer ${JWT}` } }),
    (e) => e.code === 'SIGNED_SESSION_UNAVAILABLE');
  await assert.rejects(createSessionAdapter({ env: {} }).authenticate({ headers: { authorization: `Bearer ${JWT}` } }),
    (e) => e.code === 'SIGNED_SESSION_UNAVAILABLE');
});
