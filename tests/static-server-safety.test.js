'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {createServer} = require('./e2e/static_server');

test('browser fixture serves packaged assets and denies repository internals over HTTP', async () => {
  const server = createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = 'http://127.0.0.1:' + server.address().port;
  try {
    for (const route of ['/index.html', '/owner.html', '/v2/index.html', '/core10-crm-lifecycle.html']) {
      assert.equal((await fetch(base + route)).status, 200, route);
    }
    for (const route of ['/AGENTS.md', '/.git/config', '/internal/core10-pages-package.js', '/internal/enterprise-sql/c10_a018_demo_backend.sql', '/tests/e2e/static_server.js', '/docs/development/CURRENT_HANDOFF.md', '/setup-example.html', '/%2e%2e/AGENTS.md']) {
      assert.equal((await fetch(base + route)).status, 404, route);
    }
    assert.equal((await fetch(base + '/%ZZ')).status, 400);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
