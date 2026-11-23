'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(10);
const stock = supplements['forms_stock.js'];
const field = key => report.fields.find(row => row.source_id === key);
test('A010 matches the 50 assigned source records', () => assert.equal(verify(report, manifest, source, 10, supplements), 50));
test('PO totals and checker approval are governed separately', () => {
  assert.match(stock,/total:a\(t\.qty\)&&a\(t\.rate\)\?o\(t\.qty\)\*o\(t\.rate\)/);
  assert.equal(field('P-03:po_approved').role,'"checker"');
  assert.equal(field('P-03:po_approved').requirements,'e=>!e.d.cancel');
  assert.equal(field('P-03:accepted_name').visibility,'e=>!!e.d.accepted');
  const total=(qty,rate)=>qty===undefined||rate===undefined?undefined:qty*rate;
  assert.deepEqual([total(2,10),total(2,undefined),total(0,10)],[20,undefined,0]);
});
test('bill match skips incomplete rows and normalizes the first row as text', () => {
  assert.match(stock,/if\(!\(a\(n\.po\)&&a\(n\.grn\)&&a\(n\.bill\)\)\)return\{ok:""\}/);
  assert.match(stock,/0===e\?l\(n\.po\)===l\(n\.grn\)&&l\(n\.grn\)===l\(n\.bill\)/);
  const normalize=value=>String(value).trim().toLowerCase();
  const textMatch=(...values)=>values.includes(undefined)?undefined:new Set(values.map(normalize)).size===1;
  assert.deepEqual([textMatch(' A ','a','A'),textMatch('A','B','A'),textMatch('A','A',undefined)],[true,false,undefined]);
});
test('bill warning severity and unauthorized payment remain separate', () => {
  assert.match(stock,/"bill_mismatch",t\?"yellow":"red"/);
  assert.match(stock,/N\(e\.d\.pay_amount\)&&n\.push\(S\("pay_on_mismatch","red"/);
  assert.equal(field('P-05:only_matched').requirements,'!0');
  const flags=(mismatch,held,pay)=>mismatch?[held?'yellow':'red',pay!==0?'red':null]:[];
  assert.deepEqual([flags(false,false,9),flags(true,false,9),flags(true,true,0)],[[],['red','red'],['yellow',null]]);
});
test('debit reference requirements and supplier payment verification', () => {
  assert.equal(field('P-05:debit_no').requirements,'e=>"yes"===e.d.short||"yes"===e.d.returned');
  assert.equal(field('P-06:kind_other').visibility,'e=>"other"===e.d.kind');
  assert.match(stock,/o\(e\.pay\)>0\)&&!a\(e\.d\.verifier\)&&r\.push\(S\("pay_before_verify","red"/);
  const shouldWarn=(amount,verifier)=>amount>0&&!verifier;
  assert.deepEqual([shouldWarn(1,'reviewer'),shouldWarn(1,undefined),shouldWarn(0,undefined)],[false,true,false]);
});
