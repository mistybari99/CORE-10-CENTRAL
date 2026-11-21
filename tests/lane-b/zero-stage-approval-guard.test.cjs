'use strict';
// Static contract regression; disposable PG17 adversarial tests remain mandatory.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const cases = [
  ['0301_np03b_sales_commands.up.sql', 'SALES_APPROVAL_NOT_ALLOWED'],
  ['0304_np03b_draft_invoices.up.sql', 'SALES_INVOICE_APPROVAL_NOT_ALLOWED'],
];
for (const [file, error] of cases) {
  const sql = fs.readFileSync(path.join(root, 'internal/migrations', file), 'utf8');
  const guard = new RegExp("IF\\s+stages\\s*=\\s*0\\s+AND\\s+p_approval\\s+IS\\s+NOT\\s+NULL\\s+THEN\\s+RAISE\\s+EXCEPTION\\s+'" + error + "'\\s*;\\s*END\\s+IF\\s*;", 'gi');
  const matches = [...sql.matchAll(guard)];
  assert.equal(matches.length, 1, `${file}: zero-stage guard must occur exactly once`);
  const after = sql.slice(matches[0].index + matches[0][0].length);
  assert.match(after, /IF\s+stages\s*>\s*0\s+THEN/i, `${file}: positive-stage verification must remain after guard`);
  assert.match(after, /verify_approval_binding_v1\s*\(/i, `${file}: binding verification missing`);
  console.log(`PASS ${file}: guard precedes positive-stage verification`);
}
