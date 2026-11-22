'use strict';
// Mutation harness for the static Sales guard contract. Does not replace PG17 execution.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const cases = [
  ['0301_np03b_sales_commands.up.sql', 'SALES_APPROVAL_NOT_ALLOWED'],
  ['0304_np03b_draft_invoices.up.sql', 'SALES_INVOICE_APPROVAL_NOT_ALLOWED'],
];
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'core10-sales-guard-'));
try {
  const migrations = path.join(temp, 'internal', 'migrations');
  const tests = path.join(temp, 'tests', 'lane-b');
  fs.mkdirSync(migrations, { recursive: true });
  fs.mkdirSync(tests, { recursive: true });
  fs.copyFileSync(path.join(__dirname, 'zero-stage-approval-guard.test.cjs'), path.join(tests, 'zero-stage-approval-guard.test.cjs'));
  const originals = new Map();
  for (const [file] of cases) {
    const original = fs.readFileSync(path.join(root, 'internal', 'migrations', file), 'utf8');
    originals.set(file, original);
    fs.writeFileSync(path.join(migrations, file), original);
  }
  const run = () => spawnSync(process.execPath, [path.join(tests, 'zero-stage-approval-guard.test.cjs')], { encoding: 'utf8' });
  assert.equal(run().status, 0, 'baseline contract must pass');
  for (const [file, error] of cases) {
    const original = originals.get(file);
    const guard = new RegExp(" IF stages=0 AND p_approval IS NOT NULL THEN RAISE EXCEPTION '" + error + "'; END IF;\\n");
    assert.match(original, guard, file + ': expected original guard missing');
    const target = path.join(migrations, file);
    const mutated = original.replace(guard, '');
    assert.notEqual(mutated, original, 'mutation must change source');
    fs.writeFileSync(target, mutated);
    const failed = run();
    assert.notEqual(failed.status, 0, file + ': deleting guard must fail contract');
    fs.writeFileSync(target, original);
    assert.equal(run().status, 0, file + ': restored contract must pass');
    console.log('PASS mutation: deleting zero-stage guard is detected in ' + file);
  }
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
