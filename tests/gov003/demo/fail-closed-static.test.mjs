// GOV-003 local demo: fail-closed behaviour, static serving, CSP, and the browser-less HTML contract. DEMO / NOT LIVE.
// These tests never reach the database (every request here is refused or static before a query), so they use rebuild:false and
// do not touch g3_demo_test, which api.test.mjs owns. node:test runs the files in parallel.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { startDemoServer } from '../../../internal/gov003/server/demo-server.mjs';
import { startApiServer } from '../../../internal/gov003/server/api.mjs';

const DB = 'g3_demo_test';
const root = new URL('../../../internal/gov003/', import.meta.url);
const read = (p) => readFileSync(new URL(p, root), 'utf8');
let srv; let closed;

before(async () => { srv = await startDemoServer({ env: { ...process.env, G3_DEMO: '1' }, database: DB, rebuild: false }); });
after(async () => { await closed?.close(); await srv?.close(); });

test('the demo server refuses to start unless G3_DEMO=1', async () => {
  for (const env of [{}, { G3_DEMO: '0' }, { G3_DEMO: 'true' }, { GOV003_DEMO_MODE: '1' }]) {
    await assert.rejects(() => startDemoServer({ env, database: DB }), /G3_DEMO=1/);
  }
  await assert.rejects(() => startDemoServer({ env: { G3_DEMO: '1' }, database: 'postgres' }), /g3_demo/);
});

test('fail closed: without G3_DEMO the API has no session adapter and every call is 401 SIGNED_SESSION_UNAVAILABLE', async () => {
  closed = await startApiServer({ env: {}, database: DB, port: 0, log: () => {} });
  for (const [path, headers] of [['/api/me', { 'x-demo-identity': 'business_owner_b1' }], ['/api/audit', {}], ['/api/readiness', { 'x-demo-identity': 'tenant_owner_t1' }]]) {
    const r = await fetch(closed.url + path, { headers });
    assert.equal(r.status, 401, path);
    const j = await r.json();
    assert.equal(j.error, 'SIGNED_SESSION_UNAVAILABLE');
    assert.ok(!('events' in j) && !('total_count' in j));
    assert.equal(r.headers.get('x-demo-mode'), 'DEMO / NOT LIVE');
    assert.ok(r.headers.get('content-security-policy'));
  }
  // the alternate env flag does not arm the fixture adapter either
  const alt = await startApiServer({ env: { GOV003_DEMO_MODE: '1' }, database: DB, port: 0, log: () => {} });
  try { assert.equal((await fetch(alt.url + '/api/me', { headers: { 'x-demo-identity': 'business_owner_b1' } })).status, 401); } finally { await alt.close(); }
});

test('with G3_DEMO=1 an unknown, missing or malformed identity label is 401, never a default identity', async () => {
  for (const headers of [{}, { 'x-demo-identity': 'root' }, { 'x-demo-identity': '1d000000-0000-4000-8000-000000000002' }, { 'x-demo-identity': '../../etc' }]) {
    const r = await fetch(srv.url + '/api/me', { headers });
    assert.equal(r.status, 401, JSON.stringify(headers));
  }
});

test('methods and paths: only documented routes exist; wrong method is 405; oversized or non-JSON bodies are refused', async () => {
  const H = { 'x-demo-identity': 'business_owner_b1' };
  assert.equal((await fetch(srv.url + '/api/me', { method: 'POST', headers: H })).status, 405);
  assert.equal((await fetch(srv.url + '/api/audit', { method: 'DELETE', headers: H })).status, 405);
  assert.equal((await fetch(srv.url + '/api/unknown', { headers: H })).status, 404);
  const notJson = await fetch(srv.url + '/api/audit/append', { method: 'POST', headers: { ...H, 'content-type': 'text/plain' }, body: 'x' });
  assert.ok([400, 415].includes(notJson.status));
  const badJson = await fetch(srv.url + '/api/audit/append', { method: 'POST', headers: { ...H, 'content-type': 'application/json' }, body: '{nope' });
  assert.equal(badJson.status, 400);
  const huge = await fetch(srv.url + '/api/audit/append', { method: 'POST', headers: { ...H, 'content-type': 'application/json' }, body: JSON.stringify({ x: 'a'.repeat(1_200_000) }) }).catch(() => null);
  if (huge) assert.ok([400, 413].includes(huge.status));
});

test('static files: only the whitelist is served, with the strict CSP and no-store; traversal and unknown paths are 404', async () => {
  for (const [path, type] of [['/', /text\/html/], ['/index.html', /text\/html/], ['/app.js', /javascript/], ['/app.css', /text\/css/], ['/favicon.svg', /image\/svg/], ['/client/api-client.js', /javascript/]]) {
    const r = await fetch(srv.url + path);
    assert.equal(r.status, 200, path);
    assert.match(r.headers.get('content-type'), type);
    const csp = r.headers.get('content-security-policy');
    assert.match(csp, /default-src 'none'/);
    assert.match(csp, /script-src 'self'/);
    assert.doesNotMatch(csp, /unsafe-inline|unsafe-eval|\*|https?:/);
    assert.equal(r.headers.get('x-demo-mode'), 'DEMO / NOT LIVE');
    assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
    assert.match(r.headers.get('cache-control'), /no-store/);
    await r.arrayBuffer();
  }
  for (const path of ['/app.js.map', '/../package.json', '/%2e%2e/package.json', '/client/../server/api.mjs', '/server/api.mjs', '/internal/gov003/server/pg.mjs', '/README.md', '/.env', '//etc/passwd', '/client/']) {
    const r = await fetch(srv.url + path);
    assert.ok([400, 404].includes(r.status), `${path} -> ${r.status}`);
    await r.arrayBuffer();
  }
  assert.equal((await fetch(srv.url + '/', { method: 'POST' })).status, 405);
  const idx = await (await fetch(srv.url + '/')).text();
  assert.equal(idx, read('demo/index.html'));
});

test('HTML contract: same-origin assets only, DEMO / NOT LIVE banner, language attributes, labelled controls, landmarks', () => {
  const html = read('demo/index.html');
  assert.match(html, /^<!doctype html>/i);
  assert.match(html, /<html lang="bn"/);
  assert.match(html, /<meta name="viewport" content="width=device-width, initial-scale=1">/);
  assert.match(html, /DEMO \/ NOT LIVE/);
  assert.match(html, /role="note"/);
  // every src / href is a same-origin absolute path or an in-page anchor; nothing external
  const refs = [...html.matchAll(/\b(?:src|href|action)="([^"]*)"/g)].map((m) => m[1]);
  assert.ok(refs.length >= 4);
  for (const r of refs) assert.match(r, /^(\/[A-Za-z0-9._\/-]*|#[A-Za-z0-9_-]+)$/, `reference ${r}`);
  assert.doesNotMatch(html, /https?:\/\/|\/\/[a-z0-9.-]+\.[a-z]{2,}/i);
  assert.doesNotMatch(html, /<script(?![^>]*\ssrc=)[^>]*>/i, 'no inline script');
  assert.doesNotMatch(html, /\sstyle=|<style|\son[a-z]+=/i, 'no inline style or event handler attributes');
  assert.doesNotMatch(html, /service[_-]?role/i);
  // landmarks
  for (const re of [/<header[^>]*role="banner"/, /<nav[^>]*aria-label=/, /<main[^>]*id="main"/, /<footer[^>]*role="contentinfo"/, /class="skip" href="#main"/, /role="tablist"/, /role="tabpanel"/, /aria-live="polite"/]) assert.match(html, re);
  // every form control has a programmatic label
  const controls = [...html.matchAll(/<(select|input|textarea)\b[^>]*\bid="([^"]+)"/g)].map((m) => m[2]);
  assert.ok(controls.includes('identity') && controls.includes('target'));
  for (const id of controls) assert.match(html, new RegExp(`<label[^>]*for="${id}"`), `label for #${id}`);
  // language toggle exposes both languages with their own lang attribute and a pressed state
  assert.match(html, /id="lang-bn"[^>]*lang="bn"[^>]*aria-pressed/);
  assert.match(html, /id="lang-en"[^>]*lang="en"[^>]*aria-pressed/);
  assert.match(html, /<title>[^<]*DEMO \/ NOT LIVE<\/title>/);
});

test('client and demo code contain no external URL, no service-role reference, no innerHTML/eval and store only the language choice', () => {
  for (const f of ['client/api-client.js', 'demo/app.js', 'demo/app.css', 'demo/index.html', 'demo/favicon.svg']) {
    const src = read(f);
    const urls = [...src.matchAll(/https?:\/\/[^\s"')`]+/g)].map((m) => m[0]);
    // the only non-local string allowed is the inert SVG XML namespace identifier (never fetched)
    for (const u of urls) assert.match(u, /^(https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?|http:\/\/www\.w3\.org\/2000\/svg)/, `${f} references ${u}`);
    assert.doesNotMatch(src, /service[_-]?role/i, `${f} names the service role`);
    if (f.endsWith('.js')) {
      const code = src.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
      assert.doesNotMatch(code, /\binnerHTML\b|\bouterHTML\b|insertAdjacentHTML|document\.write|\beval\s*\(|new Function\(|sessionStorage|document\.cookie/, f);
      // the only per-viewer convenience stored in the browser is the language choice
      for (const m of code.matchAll(/localStorage\.(?:get|set)Item\(\s*'([^']+)'/g)) assert.equal(m[1], 'g3lang', f);
      assert.ok(!/localStorage\.(?:remove|clear|key)/.test(code));
    }
    assert.doesNotMatch(src, /@import|url\(\s*['"]?https?:/i, f);
  }
  // the browser adapter has no way to send an actor, role or tenant claim
  const client = read('client/api-client.js');
  assert.doesNotMatch(client, /x-actor|x-role|authorization|bearer|apikey|x-tenant/i);
});

test('UI dictionary is complete for both languages and the Bangla copy is not a placeholder', () => {
  const app = read('demo/app.js');
  assert.match(app, /lang-bn|'bn'/);
  assert.match(app, /lang-en|'en'/);
  assert.ok(/[ঀ-৿]{3,}/.test(app), 'Bangla text present');
  for (const view of ['audit', 'signals', 'incidents', 'readiness', 'export', 'errors', 'grants']) assert.ok(app.includes(`'${view}'`) || app.includes(`${view}:`), `view ${view}`);
  for (const phrase of ['not certified', 'stale CI', 'staging missing', 'deployment unverified']) assert.ok(app.includes(phrase), `English copy for "${phrase}"`);
});
