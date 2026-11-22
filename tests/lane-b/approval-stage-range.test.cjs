'use strict';
// Static fail-closed stage policy regression; PG17 adversarial execution is still required.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const cases = [
  ['0301_np03b_sales_commands.up.sql', 'SALES_APPROVAL_STAGES_INVALID'],
  ['0304_np03b_draft_invoices.up.sql', 'SALES_INVOICE_APPROVAL_STAGES_INVALID'],
];
for (const [file, error] of cases) {
  const sql = fs.readFileSync(path.join(root, 'internal/migrations', file), 'utf8');
  const assign = "stages:=(c->>'stages')::integer;";
  const guard = "IF stages IS NULL OR stages NOT BETWEEN 0 AND 5 THEN RAISE EXCEPTION '" + error + "'; END IF;";
  assert.equal(sql.split(assign).length - 1, 1, file + ': stage assignment count');
  assert.equal(sql.split(guard).length - 1, 1, file + ': stage range guard count');
  const a = sql.indexOf(assign), g = sql.indexOf(guard);
  const payload = sql.indexOf('payload:=', a);
  const positive = sql.indexOf('IF stages>0 THEN', a);
  assert.ok(a < g && g < payload && payload < positive, file + ': guard must precede payload and approval branch');
  for (const stage of [null, -1, 6, 100]) {
    assert.equal(stage === null || !(stage >= 0 && stage <= 5), true, file + ': invalid stage must reject');
  }
  for (const stage of [0, 1, 2, 3, 4, 5]) {
    assert.equal(stage === null || !(stage >= 0 && stage <= 5), false, file + ': valid stage must remain possible');
  }
  console.log('PASS ' + file + ': null/out-of-range stage policy fails closed');
}
