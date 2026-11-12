import test from 'node:test';
import assert from 'node:assert/strict';
import { buildCsp, securityHeaders, assertStrictCsp, applySecurityHeaders, CspError } from '../../../internal/gov003/server/csp.mjs';

test('CSP contains no unsafe-inline / unsafe-eval / wildcard / data: / external origin', () => {
  const csp = buildCsp();
  assert.equal(/unsafe-inline|unsafe-eval|unsafe-hashes|strict-dynamic|\*|data:|blob:|https?:/.test(csp), false, csp);
  assert.match(csp, /default-src 'none'/);
  assert.match(csp, /script-src 'self'(;|$)/);
  assert.match(csp, /frame-ancestors 'none'/);
  assert.match(csp, /object-src 'none'/);
  assert.match(csp, /base-uri 'none'/);
  assert.match(csp, /form-action 'self'/);
  assert.equal(assertStrictCsp(csp), true);
});

test('security headers: referrer none, nosniff, no framing, no-store, DEMO label', () => {
  const h = securityHeaders();
  assert.equal(h['referrer-policy'], 'no-referrer');
  assert.equal(h['x-content-type-options'], 'nosniff');
  assert.equal(h['x-frame-options'], 'DENY');
  assert.equal(h['cache-control'], 'no-store');
  assert.equal(h['cross-origin-resource-policy'], 'same-origin');
  assert.equal(h['x-gov003-mode'], 'DEMO / NOT LIVE');
  assert.equal(Object.hasOwn(h, 'strict-transport-security'), false);
  assert.match(securityHeaders({ https: true })['strict-transport-security'], /max-age=\d+; includeSubDomains/);
  for (const v of Object.values(h)) assert.equal(/unsafe-inline|unsafe-eval/.test(v), false);
  const set = {}; applySecurityHeaders({ setHeader: (k, v) => { set[k] = v; } });
  assert.equal(set['content-security-policy'], h['content-security-policy']);
});

test('NEGATIVE: weakening the policy is refused by builder and by the assertion', () => {
  for (const x of ["'unsafe-inline'", "'unsafe-eval'", '*', 'https://cdn.example.com', 'data:', "'strict-dynamic'"]) {
    assert.throws(() => buildCsp({ extra: { 'script-src': [x] } }), CspError, x);
    assert.throws(() => buildCsp({ extra: { 'style-src': [x] } }), CspError, x);
  }
  assert.throws(() => buildCsp({ extra: { 'bogus-src': ["'self'"] } }), CspError);
  assert.throws(() => buildCsp({ reportUri: 'https://evil.example/r' }), CspError);
  for (const bad of ["default-src 'self'", "default-src 'none'; script-src 'self' 'unsafe-inline'; frame-ancestors 'none'; object-src 'none'; base-uri 'none'",
    "default-src 'none'; script-src 'self' 'unsafe-eval'; frame-ancestors 'none'; object-src 'none'; base-uri 'none'",
    "default-src 'none'; script-src 'self'; object-src 'none'; base-uri 'none'", "default-src 'none'; default-src 'none'"]) {
    assert.throws(() => assertStrictCsp(bad), CspError, bad);
  }
});

test('nonce sources are allowed only in the strict nonce shape; same-origin extras allowed', () => {
  const nonce = `'nonce-${'A'.repeat(22)}=='`;
  const csp = buildCsp({ extra: { 'script-src': [nonce], 'connect-src': ["'self'"] }, reportUri: '/csp-report' });
  assert.ok(csp.includes(nonce)); assert.ok(csp.endsWith('report-uri /csp-report'));
  assert.throws(() => buildCsp({ extra: { 'script-src': ["'nonce-short'"] } }), CspError);
});
