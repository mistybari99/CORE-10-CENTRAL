'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { inspect, readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(7);
const stock = supplements['forms_stock.js'];
const cash = supplements['forms_cash.js'];
const field = key => report.fields.find(row => row.source_id === key);
const validate = batch => verify(batch, manifest, source, 7, supplements);

test('A007 source evidence and corrected manifest slot', () => {
  assert.equal(validate(report), 50);
  assert.equal(report.fields[3].source_id, 'R-01:cashier');
  const regression = structuredClone(report);
  regression.fields[3].source_id = 'S-04:cashier';
  assert.throws(() => validate(regression));
});
test('cashier constructor must be appended to R-01 with an idempotence guard', () => {
  assert.deepEqual(inspect(cash, 'R-01:cashier'), field('R-01:cashier').evidence);
  assert.throws(() => inspect(cash, 'S-04:cashier'), /belongs to R-01/);
  assert.throws(() => inspect(cash.replace('e.forms["R-01"].head.push', 'e.forms["S-04"].head.push'), 'R-01:cashier'), /Missing or ambiguous/);
  const shouldAdd = form => Boolean(form?.head && !form.head.some(item => item.id === 'cashier'));
  assert.deepEqual([shouldAdd({head: []}), shouldAdd({head: [{id:'cashier'}]}), shouldAdd(undefined)], [true, false, false]);
});
test('purchase and payment references follow the declared branches', () => {
  assert.equal(field('P-04:pr_no').requirements, 'e=>"pr"===e.d.paper');
  assert.equal(field('P-04:cash_amount').requirements, 'e=>"cash"===e.d.pay');
  assert.equal(field('P-04:pay_other').requirements, 'e=>"other"===e.d.pay');
  assert.equal(field('P-04:ledger_line').visibility, 'e=>a(e.d.pay)&&"credit"!==e.d.pay');
  const ledgerRefVisible = pay => Boolean(pay && pay !== 'credit');
  assert.deepEqual(['cash','credit',undefined].map(ledgerRefVisible), [true,false,false]);
});
test('GRN separates signed differences, shortages and excess', () => {
  assert.match(stock, /var:r&&a\(t\.memo\)\?o\(t\.counted\)-o\(t\.memo\):void 0/);
  assert.match(stock, /amt:r&&a\(t\.rate\)\?o\(t\.counted\)\*o\(t\.rate\):void 0/);
  const variance = (counted, memo) => counted === undefined || memo === undefined ? undefined : counted - memo;
  assert.deepEqual([[8,5],[3,5],[5,5],[undefined,5]].map(args => variance(...args)), [3,-2,0,undefined]);
  assert.equal(Math.max(0, -variance(3,5)), 2);
  assert.equal(Math.max(0, variance(8,5)), 3);
});
test('reduced rate requires independent approval and hold requires separation', () => {
  assert.equal(field('P-04:new_rate').requirements, 'e=>e.v.has_reduced');
  assert.match(stock, /s\.has_reduced=t\.some\(e=>"reduced"===e\.quality\)/);
  assert.match(stock, /e\.d\.rate_approver===e\.d\.receiver&&r\.push\(S\("rate_approver_is_receiver","red"/);
  assert.match(stock, /e\.d\.held_apart\|\|r\.push\(S\("hold_not_apart","red"/);
  const warning = (reduced, approver, receiver) => Boolean(reduced && approver && receiver && approver === receiver);
  assert.deepEqual([warning(true,'a','b'), warning(true,'a','a'), warning(true,undefined,'b')], [false,true,false]);
});
test('weekly reviewer and GRN checker are source role declarations', () => {
  for (const key of ['S-04:checked_by','S-04:reviewed_by','P-04:mgmt_checked']) assert.equal(field(key).role, '"checker"');
  assert.equal(field('S-04:reviewed_by').requirements, 'NOT_DECLARED');
});
test('overnight returns and excessive return quantities preserve warning behavior', () => {
  assert.match(stock, /i=!e\.d\.not_overnight/);
  assert.match(stock, /o\(t\.issued\)-\(i\?0:o\(t\.ret\)\)/);
  assert.match(stock, /o\(e\.ret\)>o\(e\.issued\)\)\&\&r\.push\(S\("return_exceeds","red"/);
  const use = (issued, returned, notOvernight) => issued - (notOvernight ? returned : 0);
  assert.deepEqual([use(5,3,true),use(5,3,false),use(5,5,true),use(5,6,true)], [2,5,0,-1]);
  assert.match(stock, /"staff"===e\.d\.purpose\?\(r\.push\(S\("issue_staff","yellow"/);
});
