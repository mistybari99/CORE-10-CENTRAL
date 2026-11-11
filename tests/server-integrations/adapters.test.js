'use strict';
const assert = require('assert');
const path = require('path');
const root = path.join(__dirname, '..', '..', 'server', 'integrations');
const { verifyHmac, hmacHex } = require(path.join(root, 'signature.js'));
const { envResolver } = require(path.join(root, 'secrets.js'));
const { dryRunAdapter, httpAdapter, createRegistry } = require(path.join(root, 'adapters.js'));
const { runOnce } = require(path.join(root, 'worker.js'));

let n = 0; const ok = (name) => { n++; console.log('ok -', name); };
(async () => {
  // ---- signature ----
  const secret = 'whsec_test', body = '{"id":"e1","amount":500}';
  const sig = hmacHex(secret, body);
  assert.strictEqual(verifyHmac({ secret, rawBody: body, signature: sig }), 'ok'); ok('valid signature');
  assert.strictEqual(verifyHmac({ secret, rawBody: body + ' ', signature: sig }), 'bad'); ok('tampered body is bad');
  assert.strictEqual(verifyHmac({ secret: 'other', rawBody: body, signature: sig }), 'bad'); ok('wrong secret is bad');
  assert.strictEqual(verifyHmac({ secret, rawBody: body, signature: '' }), 'missing'); ok('empty signature is missing');
  assert.strictEqual(verifyHmac({ secret, rawBody: body, signature: undefined }), 'missing'); ok('no signature is missing');
  assert.strictEqual(verifyHmac({ secret: '', rawBody: body, signature: sig }), 'missing'); ok('no secret is missing (never ok)');
  assert.strictEqual(verifyHmac({ secret, rawBody: body, signature: 'abc' }), 'bad'); ok('short signature is bad (no throw)');
  assert.strictEqual(verifyHmac({ secret, rawBody: body, signature: 'sha256=' + sig }), 'ok'); ok('sha256= prefix accepted');
  const ts = 1700000000, tsig = hmacHex(secret, ts + '.' + body);
  assert.strictEqual(verifyHmac({ secret, rawBody: body, signature: tsig, timestamp: ts, toleranceSec: 300, nowSec: ts + 10 }), 'ok'); ok('timestamped signature ok');
  assert.strictEqual(verifyHmac({ secret, rawBody: body, signature: tsig, timestamp: ts, toleranceSec: 300, nowSec: ts + 4000 }), 'bad'); ok('replayed (stale) event is bad');

  // ---- secrets ----
  const res = envResolver({ IB_101_SMS_V1: 'KEYVALUE' });
  assert.strictEqual(await res('ib_101_sms_v1'), 'KEYVALUE'); ok('secret resolved by reference');
  await assert.rejects(() => res('sk-live-ABC.def'), /secret_ref_invalid/); ok('value-looking reference rejected');
  await assert.rejects(() => res('ib_missing_v1'), (e) => e.message === 'secret_not_found' && !/KEYVALUE/.test(e.message)); ok('missing secret error has no value');

  // ---- registry: unknown providers fall back to dry-run ----
  const reg = createRegistry({});
  assert.strictEqual(reg.get('sms', 'messaging').kind, 'dry_run'); ok('unimplemented provider resolves to dry-run adapter');

  // ---- fake db + workers ----
  const mk = (rows) => {
    const reports = [];
    return { reports, async claim() { return rows; }, async report(id, ok_, tr, ref, err) { reports.push({ id, ok: ok_, tr, ref, err }); return ok_ ? (rows.find(r => r.id === id).is_dry_run ? 'dry_run_logged' : 'sent') : (tr ? 'queued' : 'failed'); } };
  };
  const fam = 'messaging';
  // OFF: never touches anything
  let db = mk([{ id: 1 }]); let called = false;
  let r = await runOnce({ db: { claim: async () => { called = true; return []; }, report: async () => 'x' }, registry: reg, resolveSecret: res, account: { id: 1, mode: 'off', provider_code: 'sms', family: fam } });
  assert.strictEqual(called, false); ok('OFF port: worker never claims');
  // dry-run: http is never provided, secret never resolved
  let httpCalled = false, secretCalled = false;
  const realish = createRegistry({ sms: httpAdapter(fam, { build: (j, s) => ({ url: 'https://example.invalid', method: 'POST', headers: { a: s }, body: '{}' }), parse: () => ({ ok: true, providerRef: 'p' }) }) });
  db = mk([{ id: 7, is_dry_run: true, template_code: 't' }]);
  r = await runOnce({ db, registry: realish, resolveSecret: async () => { secretCalled = true; return 'S'; }, http: async () => { httpCalled = true; return { status: 200 }; }, account: { id: 1, mode: 'dry_run', provider_code: 'sms', family: fam, secret_ref: 'ib_1_sms_v1' } });
  assert.strictEqual(httpCalled, false); assert.strictEqual(secretCalled, false);
  assert.strictEqual(db.reports[0].err, 'network_forbidden_in_dry_run'); ok('dry-run: no network, no secret resolution, real adapter refused');
  r = await runOnce({ db: mk([{ id: 8, is_dry_run: true, template_code: 't' }]), registry: reg, resolveSecret: res, account: { id: 1, mode: 'dry_run', provider_code: 'sms', family: fam } });
  assert.strictEqual(r.dry_run_logged, 1); ok('dry-run adapter logs the job without sending');
  // live: secret resolved, http called with the secret only inside the request
  let seen;
  db = mk([{ id: 9, is_dry_run: false, template_code: 't' }]);
  r = await runOnce({ db, registry: realish, resolveSecret: async () => 'S3CR3T', http: async (q) => { seen = q; return { status: 200 }; }, account: { id: 1, mode: 'live', provider_code: 'sms', family: fam, secret_ref: 'ib_1_sms_v1' } });
  assert.strictEqual(seen.headers.a, 'S3CR3T'); assert.strictEqual(r.sent, 1);
  assert.ok(!JSON.stringify(db.reports).includes('S3CR3T')); ok('live: secret used for the call and never reported');
  // transient 503 -> requeue; permanent 400 -> failed; network error -> transient; exception -> transient without message
  for (const [status, expect] of [[503, 'queued'], [429, 'queued'], [400, 'failed'], [401, 'failed']]) {
    db = mk([{ id: 10, is_dry_run: false, template_code: 't' }]);
    await runOnce({ db, registry: realish, resolveSecret: async () => 'S', http: async () => ({ status }), account: { id: 1, mode: 'live', provider_code: 'sms', family: fam, secret_ref: 'ib_1_sms_v1' } });
    assert.strictEqual(db.reports[0].tr, expect === 'queued'); }
  ok('5xx/429 are transient, other 4xx are permanent');
  db = mk([{ id: 11, is_dry_run: false, template_code: 't' }]);
  await runOnce({ db, registry: realish, resolveSecret: async () => 'S', http: async () => { throw new Error('connect failed token=S'); }, account: { id: 1, mode: 'live', provider_code: 'sms', family: fam, secret_ref: 'ib_1_sms_v1' } });
  assert.strictEqual(db.reports[0].err, 'network_error'); assert.ok(!JSON.stringify(db.reports).includes('token=S')); ok('network error is transient and its message is not forwarded');
  const boom = createRegistry({ sms: { family: fam, kind: 'x', async send() { throw new Error('secret=S3CR3T leaked'); } } });
  db = mk([{ id: 12, is_dry_run: false, template_code: 't' }]);
  await runOnce({ db, registry: boom, resolveSecret: async () => 'S', http: async () => ({}), account: { id: 1, mode: 'live', provider_code: 'sms', family: fam, secret_ref: 'ib_1_sms_v1' } });
  assert.strictEqual(db.reports[0].err, 'adapter_exception'); assert.ok(!JSON.stringify(db.reports).includes('S3CR3T')); ok('adapter exception message never reaches the report');
  // missing secret -> requeue, not sent
  db = mk([{ id: 13, is_dry_run: false, template_code: 't' }]);
  r = await runOnce({ db, registry: realish, resolveSecret: res, http: async () => ({ status: 200 }), account: { id: 1, mode: 'live', provider_code: 'sms', family: fam, secret_ref: 'ib_1_sms_v1' } });
  assert.strictEqual(r.requeued, 1); assert.strictEqual(r.sent, 0); ok('unresolvable secret requeues instead of sending');
  console.log('PASS server-integrations:', n, 'checks');
})().catch((e) => { console.error('FAIL', e); process.exit(1); });
