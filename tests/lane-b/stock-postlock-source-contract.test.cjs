'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

// Execute only on an exact-head checkout; no database credentials are needed.
// CORE10_REPO=/path/to/checkout node --test tests/lane-b/stock-postlock-source-contract.test.cjs
const root = process.env.CORE10_REPO;
const versions = ['0201', '0203', '0206'];

test('stock command, purchase order and receipt migrations retain lock/auth source evidence', { skip: !root && 'CORE10_REPO checkout required' }, () => {
  const dir = path.join(root, 'internal/migrations');
  for (const version of versions) {
    const files = fs.readdirSync(dir).filter(f => new RegExp('^' + version + '_.*\\.up\\.sql$').test(f));
    assert.equal(files.length, 1, 'exactly one UP migration expected for ' + version);
    const full = path.join(dir, files[0]);
    const stat = fs.lstatSync(full);
    assert.ok(stat.isFile() && !stat.isSymbolicLink(), 'unsafe migration source: ' + files[0]);
    const sql = fs.readFileSync(full, 'utf8');
    assert.match(sql, /FOR\\s+UPDATE/i, 'missing row lock in ' + files[0]);
    const afterFirstLock = sql.slice(sql.search(/FOR\\s+UPDATE/i));
    assert.match(afterFirstLock, /auth|permission|member|scope|actor/i, 'post-lock authorization evidence missing: ' + files[0]);
  }
});
