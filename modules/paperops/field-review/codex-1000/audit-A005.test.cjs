'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(5);
const cash = supplements['forms_cash.js'];
const field = key => report.fields.find(row => row.source_id === key);
test('A005 exact 50 field records', () => assert.equal(verify(report, manifest, source, 5, supplements), 50));
test('same maker and measuring actor triggers red before attestation fallback', () => {
  assert.match(cash, /r\(o\.produced_by\)&&o\.produced_by===o\.measured_by\?s\.push\(A\("producer_is_measurer","red"/);
  const level = (maker, measurer, marked) => maker && maker === measurer ? 'red' : marked ? 'yellow' : null;
  assert.deepEqual([level('a','b',false), level('a','a',false), level('','',true)], [null,'red','yellow']);
});
test('marketing branches and checker role match source', () => {
  assert.equal(field('C-03:amt').requirements, 'e=>!r(e.row.nonpay)');
  assert.equal(field('C-03:brand_other').visibility, 'e=>"other"===e.d.brand');
  assert.equal(field('C-03:over_approver').requirements, 'e=>e.v.any_over');
  assert.equal(field('C-03:owner_by').role, '"checker"');
  assert.match(cash, /Number\.isFinite\(d\)\?d:S\(o,"mkt_limit_"\+i\)/);
  const limit = (running, cap) => cap === null ? 'missing' : running > cap ? 'over' : 'within';
  assert.deepEqual([limit(9,10),limit(11,10),limit(10,10),limit(11,null)], ['within','over','within','missing']);
});
test('marketing match can treat one absent comparison as zero', () => {
  assert.match(cash, /null===g&&null===b\?"—":0===\(g\|\|0\)&&0===\(b\|\|0\)/);
  const matches = (ledger, statement) => ledger === null && statement === null ? null : (ledger || 0) === 0 && (statement || 0) === 0;
  assert.deepEqual([matches(0,0),matches(0,1),matches(null,0),matches(null,null)], [true,false,true,null]);
});
test('wholesale rolling balance and rounded credit limit', () => {
  assert.match(cash, /n=T\(n\+a\(e\.inv\)-a\(e\.ret\)-a\(e\.coll\)\)/);
  assert.match(cash, /m=null!==h&&T\(n-h\)>0/);
  const round = n => Math.round(n * 100) / 100;
  const balance = (opening, rows) => rows.reduce((n, [invoice, returned, collected]) => round(n + invoice - returned - collected), opening);
  assert.equal(balance(100, [[50,10,5],[0,0,15]]), 120);
  assert.equal(balance(0, [[0,0,10]]), -10);
  assert.equal(balance(25, []), 25);
  assert.deepEqual([119.99,120,120.01].map(n => round(n-120)>0),[false,false,true]);
});
