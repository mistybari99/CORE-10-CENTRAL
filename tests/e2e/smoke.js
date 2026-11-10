// Browser smoke test (Playwright, mobile viewport) against the local static server.
const fs = require('fs'), path = require('path');
const { chromium } = require('playwright');
const { createServer } = require('./static_server');
const ROOT = path.resolve(__dirname, '..', '..');
const SHOTS = path.join(__dirname, 'screenshots');
let failures = 0;
const check = (ok, msg) => { console.log((ok ? 'PASS ' : 'FAIL ') + msg); if (!ok) failures++; };

(async () => {
  const server = createServer();
  await new Promise(r => server.listen(Number(process.env.PORT || 0), '127.0.0.1', r));
  const base = 'http://127.0.0.1:' + server.address().port;
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  const page = await context.newPage();
  const pageErrors = [], badRequests = [];
  page.on('pageerror', e => pageErrors.push(e.message));
  page.on('response', r => { if (r.url().startsWith(base) && r.status() >= 400) badRequests.push(r.status() + ' ' + r.url()); });
  page.on('requestfailed', r => { if (r.url().startsWith(base)) badRequests.push('failed ' + r.url()); });
  try {
    await page.goto(base + '/index.html', { waitUntil: 'load' });
    check((await page.title()).includes('ISLAMIYA'), 'title contains ISLAMIYA: ' + await page.title());
    const inputs = page.locator('input');
    await inputs.first().waitFor({ timeout: 20000 }).catch(() => {});
    const n = await inputs.count();
    const pin = await page.locator('input[type=password], input[inputmode=numeric], input[autocomplete="current-password"]').count();
    check(n >= 2, 'login has >=2 inputs (staff id + PIN), found ' + n);
    check(pin >= 1, 'PIN-style input present');
    await page.waitForTimeout(1500);
    check(pageErrors.length === 0, '0 pageerror' + (pageErrors.length ? ': ' + pageErrors.join(' | ') : ''));
    check(badRequests.length === 0, '0 failed same-origin requests' + (badRequests.length ? ': ' + badRequests.join(' | ') : ''));

    // every local script/link referenced by the three entry pages resolves 200
    for (const f of ['index.html', 'owner.html', 'business.html']) {
      const html = fs.readFileSync(path.join(ROOT, f), 'utf8');
      const refs = [...new Set([...html.matchAll(/<(?:script|link)\b[^>]*?\b(?:src|href)=["']([^"']+)["']/gi)].map(m => m[1])
        .filter(u => !/^(https?:|\/\/|data:|#)/i.test(u)))];
      const bad = [];
      for (const u of refs) {
        const r = await context.request.get(new URL(u, base + '/' + f).href);
        if (r.status() !== 200) bad.push(r.status() + ' ' + u);
      }
      check(bad.length === 0, f + ': ' + refs.length + ' local refs resolve 200' + (bad.length ? ' BAD: ' + bad.join(', ') : ''));
    }

    // manifest
    const mr = await context.request.get(base + '/manifest.json');
    let mok = false;
    try { const j = await mr.json(); mok = mr.status() === 200 && !!(j.name || j.short_name); } catch (e) {}
    check(mok, 'manifest.json parses');

    // service worker (the app's swreg only registers on https; localhost is a secure context, so register directly)
    const sw = await page.evaluate(async () => {
      if (!('serviceWorker' in navigator)) return 'unsupported';
      await navigator.serviceWorker.register('sw.js');
      await navigator.serviceWorker.ready;
      return 'ok';
    }).catch(e => 'error ' + e.message);
    check(sw === 'ok', 'service worker registers and activates (' + sw + ')');

    // offline reload from cache
    await page.reload({ waitUntil: 'load' });
    await page.waitForTimeout(2500);
    await context.setOffline(true);
    let offOk = false, offTitle = '';
    try { await page.reload({ waitUntil: 'load', timeout: 20000 }); offTitle = await page.title(); offOk = offTitle.includes('ISLAMIYA'); }
    catch (e) { offTitle = 'ERR ' + e.message.split('\n')[0]; }
    check(offOk, 'offline reload served from cache (' + offTitle + ')');
    await context.setOffline(false);
  } catch (e) {
    check(false, 'unexpected error: ' + e.message);
  }
  if (failures) { fs.mkdirSync(SHOTS, { recursive: true }); await page.screenshot({ path: path.join(SHOTS, 'failure.png'), fullPage: true }).catch(() => {}); }
  await browser.close(); server.close();
  console.log(failures ? 'SMOKE FAILED (' + failures + ')' : 'SMOKE PASSED');
  process.exit(failures ? 1 : 0);
})();
