'use strict';
// Lane B: guard the numeric migration handoff without contacting hosted services.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const reservations = JSON.parse(fs.readFileSync(path.join(root, 'docs/coordination/MIGRATION_RESERVATIONS.json'), 'utf8'));
const runner = fs.readFileSync(path.join(root, 'internal/migrations/run.sh'), 'utf8');
test('migration allocations are disjoint and cover stock, sales, finance, manufacturing', () => {
  const ranges = reservations.ranges;
  for (const r of ranges) assert.ok(Number.isInteger(r.from) && Number.isInteger(r.to) && r.from <= r.to);
  for (let i = 0; i < ranges.length; i++)
    for (let j = i + 1; j < ranges.length; j++)
      assert.ok(ranges[i].to < ranges[j].from || ranges[j].to < ranges[i].from,
        'overlapping migration allocation: ' + ranges[i].lane + ' / ' + ranges[j].lane);
  for (const [v, lane] of [[201, 'NP03A'], [305, 'NP03B'], [400, 'NP06'], [500, 'NP05A']]) {
    const matches = ranges.filter(r => r.from <= v && v <= r.to);
    assert.equal(matches.length, 1, 'unique owner for migration ' + v);
    assert.ok(matches[0].lane.includes(lane), 'expected allocation ' + lane);
  }
});
test('runner refuses out-of-order and checksum drift before applying SQL', () => {
  assert.match(runner, /CHECKSUM_DRIFT/);
  assert.match(runner, /OUT_OF_ORDER/);
  assert.match(runner, /sha256sum/);
  assert.match(runner, /\[ "\$v" -lt "\$top" \]/);
  assert.match(runner, /\$\{PSQL\[@\]\}" -1 -f "\$f"/);
  assert.ok(runner.indexOf('CHECKSUM_DRIFT') < runner.indexOf('OUT_OF_ORDER'));
  assert.ok(runner.indexOf('OUT_OF_ORDER') < runner.indexOf('applied $n'));
});
