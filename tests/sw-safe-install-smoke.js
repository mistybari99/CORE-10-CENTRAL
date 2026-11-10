// Regression checks for safe service-worker update. Run: node tests/sw-safe-install-smoke.js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '..', 'sw.js'), 'utf8');
async function scenario(fail) {
  const handlers = {}, cache = new Map(), deleted = [];
  let skipped = false, claimed = false;
  const scope = 'https://example.test/erp/';
  const response = (url) => ({
    ok: !(fail === 'shell' && url.includes('index.html')) && !(fail === 'asset' && url.includes('core.js')),
    type: 'basic',
    clone() { return this; },
    async text() { return '<script src="core.js?v=58937687db"></script>'; }
  });
  const context = {
    URL, Set, Promise, Error,
    self: { location: { origin: 'https://example.test' }, registration: { scope },
      addEventListener(name, fn) { handlers[name] = fn; },
      async skipWaiting() { skipped = true; },
      clients: { async claim() { claimed = true; } } },
    caches: {
      async open(name) { if (!cache.has(name)) cache.set(name, new Map()); const store = cache.get(name);
        return { async put(k, v) { store.set(String(k), v); }, async match(k) { return store.get(String(k)); } }; },
      async keys() { return ['bos-sw-previous', ...cache.keys()]; },
      async delete(k) { deleted.push(k); return true; }
    },
    async fetch(u) { return response(String(u)); }
  };
  vm.runInNewContext(source, context, { filename: 'sw.js' });
  let pending;
  handlers.install({ waitUntil(p) { pending = p; } });
  if (fail) await assert.rejects(pending, /Offline (shell|asset) download failed/);
  else await pending;
  assert.equal(skipped, !fail, 'skipWaiting must only run after a complete install');
  assert.equal(deleted.length, 0, 'failed install must never delete prior caches');
  assert.equal(claimed, false, 'activate must not happen during install');
}
(async () => {
  await scenario('shell');
  await scenario('asset');
  await scenario(null);
  console.log('PASS: failed shell, failed asset and successful install');
})().catch(e => { console.error(e); process.exitCode = 1; });
