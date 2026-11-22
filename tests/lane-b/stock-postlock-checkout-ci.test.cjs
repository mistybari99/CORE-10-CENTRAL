'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

// CI must run against its own checkout, never a reconstructed fixture or skipped test.
const root = path.resolve(__dirname, '../..');
const dir = path.join(root, 'internal/migrations');
for (const version of ['0201', '0203', '0206']) {
  test('Stock ' + version + ' post-lock authorization source guard', () => {
    const matches = fs.readdirSync(dir).filter(name => new RegExp('^' + version + '_.*\\.up\\.sql$').test(name));
    assert.equal(matches.length, 1, 'expected one committed UP file for ' + version);
    const file = path.join(dir, matches[0]);
    const st = fs.lstatSync(file);
    assert.ok(st.isFile() && !st.isSymbolicLink(), 'unsafe migration file');
    const source = fs.readFileSync(file, 'utf8');
    const lock = /FOR\\s+(?:NO\\s+KEY\\s+)?UPDATE\\b/ig;
    const hits = [...source.matchAll(lock)];
    assert.ok(hits.length > 0, 'row lock missing');
    // Source-presence smoke guard, not a proof of control-flow dominance.
    assert.match(source.slice(hits[0].index), /auth|permission|member|scope|actor/i,
      'no authorization evidence after first row-lock token');
  });
}
