'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(3);
const cash = supplements['forms_cash.js'];
const field = key => report.fields.find(row => row.source_id === key);
test('A003 matches all 50 IDs and all three cash forecast declarations', () => {
  assert.equal(verify(report, manifest, source, 3, supplements), 50);
  const corrupted = structuredClone(report);
  corrupted.fields.find(row => row.source_id === 'C-06:date').additional_evidence.pop();
  assert.throws(() => verify(corrupted, manifest, source, 3, supplements));
});
test('statement settlement and one-sided exceptions', () => {
  assert.match(cash, /T\(o\[t\+"b"\]-o\[t\+"chg"\]-o\[t\+"c"\]\)/);
  const delta = (statement, charge, received) => Math.round((statement - charge - received) * 100) / 100;
  assert.deepEqual([delta(10, 1, 9), delta(10, 1, 10), delta(0, 0, 0)], [0, -1, 0]);
  assert.match(cash, /a\(e\.d\.only_st_amt\)>0/);
  assert.match(cash, /a\(e\.d\.only_us_amt\)>0/);
  assert.deepEqual([5, -5, 0].map(amount => amount > 0), [true, false, false]);
});
test('personal-number escalation and maker/checker declarations', () => {
  assert.equal(field('C-04:personal_amt').requirements, 'e=>"yes"===e.d.personal');
  assert.match(cash, /"yes"===e\.d\.personal&&t\.push\(A\("personal_number","red"/);
  assert.equal(field('C-04:checked_by').role, '"checker"');
  assert.deepEqual(['yes', 'no', undefined].map(answer => answer === 'yes'), [true, false, false]);
});
test('cash ceiling, minimum and signed forecast budget', () => {
  assert.match(cash, /l\.hub_over=a\(o\.hub_cash\)>d/);
  assert.match(cash, /T\(l\.A\+l\.Bt-l\.Ct-c\)/);
  assert.match(cash, /e<0&&i\.push\(A\("budget_negative","yellow"/);
  const over = (amount, limit) => limit === null ? 'missing' : amount > limit;
  assert.deepEqual([over(11, 10), over(10, 10), over(10, null)], [true, false, 'missing']);
  const budget = (cash, incoming, outgoing, minimum) =>
    minimum === null ? undefined : Math.round((cash + incoming - outgoing - minimum) * 100) / 100;
  assert.deepEqual([budget(10, 2, 5, 3), budget(10, 2, 9, 4), budget(10, 2, 9, 3), budget(10, 2, 9, null)], [4, -1, 0, undefined]);
});
test('shortage is conditional and checker approval is independent in declarations', () => {
  assert.equal(field('C-06:shortage_date').requirements, 'e=>"yes"===e.d.shortage');
  assert.equal(field('C-06:mgmt_informed').requirements, field('C-06:shortage_date').requirements);
  assert.equal(field('C-06:approver').role, '"checker"');
  assert.deepEqual(['yes', 'no', ''].map(answer => answer === 'yes'), [true, false, false]);
});
test('aging balances, advance status and credit warnings', () => {
  assert.match(cash, /T\(a\(e\.total\)-a\(e\.a30\)-a\(e\.a60\)-a\(e\.a60p\)\)/);
  const agingGap = (total, buckets) => Math.round((total - buckets.reduce((sum, amount) => sum + amount, 0)) * 100) / 100;
  assert.deepEqual([agingGap(100, [30, 50, 20]), agingGap(100, [30, 50, 10]), agingGap(0, [0, 0, 0])], [0, 10, 0]);
  assert.match(cash, /"given"!==e\.status&&"refunded"!==e\.status/);
  const open = status => status !== 'given' && status !== 'refunded';
  assert.deepEqual(['pending', 'given', 'refunded', undefined].map(open), [true, false, false, true]);
  assert.match(cash, /"yes"!==e\.d\.over_credit\|\|e\.d\.credit_stopped\|\|i\.push\(A\("credit_not_stopped","red"/);
  const stopWarning = (answer, stopped) => answer === 'yes' && !stopped;
  assert.deepEqual([stopWarning('yes', false), stopWarning('yes', true), stopWarning(undefined, false)], [true, false, false]);
});
