'use strict';
// Mutation test for Sales approval stage range enforcement. Static only; PG17 required.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const cases = [
  ['0301_np03b_sales_commands.up.sql', 'SALES_APPROVAL_STAGES_INVALID'],
  ['0304_np03b_draft_invoices.up.sql', 'SALES_INVOICE_APPROVAL_STAGES_INVALID'],
];
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'core10-stage-range-'));
try {
  const migrations = path.join(tmp, 'internal', 'migrations');
  const tests = path.join(tmp, 'tests', 'lane-b');
  fs.mkdirSync(migrations, { recursive: true });
  fs.mkdirSync(tests, { recursive: true });
  fs.copyFileSync(path.join(__dirname, 'approval-stage-range.test.cjs'), path.join(tests, 'approval-stage-range.test.cjs'));
  const originals = new Map();
  for (const [file] of cases) {
    const source = fs.readFileSync(path.join(root, 'internal', 'migrations', file), 'utf8');
    originals.set(file, source);
    fs.writeFileSync(path.join(migrations, file), source);
  }
  const run = () => spawnSync(process.execPath, [path.join(tests, 'approval-stage-range.test.cjs')], { encoding: 'utf8' });
  assert.equal(run().status, 0, 'baseline stage-range contract must pass');
  for (const [file, error] of cases) {
    const source = originals.get(file);
    const guard = "IF stages IS NULL OR stages NOT BETWEEN 0 AND 5 THEN RAISE EXCEPTION '" + error + "'; END IF;";
    assert.equal(source.split(guard).length - 1, 1, file + ': unique guard required');
    const target = path.join(migrations, file);
    for (const [label, mutation] of [
      ['remove guard', ''],
      ['permit null', guard.replace('stages IS NULL OR ', '')],
      ['permit stage 6', guard.replace('BETWEEN 0 AND 5', 'BETWEEN 0 AND 6')],
      ['move guard after approval branch', null],
    ]) {
      let changed;
      if (mutation !== null) changed = source.replace(guard, mutation);
      else {
        const branch = 'IF stages>0 THEN';
        assert.ok(source.indexOf(branch, source.indexOf(guard)) > source.indexOf(guard), file + ': expected approval branch');
        changed = source.replace(guard, '').replace(branch, branch + '\n ' + guard);
      }
      assert.notEqual(changed, source, file + ': ' + label + ' must mutate source');
      fs.writeFileSync(target, changed);
      const result = run();
      assert.notEqual(result.status, 0, file + ': ' + label + ' must fail contract');
      fs.writeFileSync(target, source);
      assert.equal(run().status, 0, file + ': restoration must pass');
      console.log('PASS mutation: ' + file + ' / ' + label);
    }
  }
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
