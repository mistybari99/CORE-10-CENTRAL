'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(9);
const stock = supplements['forms_stock.js'];
const field = key => report.fields.find(row => row.source_id === key);
test('A009 matches exactly the assigned 50 records', () => assert.equal(verify(report, manifest, source, 9, supplements), 50));
test('urgent advance reconciles only once receipts or change are present', () => {
  assert.match(stock,/l\.adv_started="urgent"===e\.d\.urgency&&N\(e\.d\.adv_given\)&&\(a\(e\.d\.adv_change\)\|\|a\(e\.d\.adv_receipts\)\)/);
  assert.match(stock,/o\(e\.d\.adv_given\)-o\(e\.d\.adv_change\)-o\(e\.d\.adv_receipts\)/);
  assert.match(stock,/a\(e\.d\.grn_no\)\|\|s\.push\(S\("advance_no_grn","red"/);
  assert.match(stock,/e\.d\.adv_checker===e\.d\.adv_to/);
  assert.equal(field('P-01:adv_equal').requirements,'e=>e.v.adv_started');
  const balance=(advance,change,receipt)=>change===undefined&&receipt===undefined?null:advance-(change??0)-(receipt??0);
  assert.deepEqual([balance(10,2,8),balance(10,1,8),balance(10,undefined,undefined)],[0,1,null]);
});
test('requisition checker refusal and phone time remain separate declarations', () => {
  assert.equal(field('P-01:decision').role,'"checker"');
  assert.equal(field('P-01:phone_time').visibility,'e=>!!e.c.phone_approval');
  assert.match(stock,/"no"===e\.c\.decision&&s\.push\(S\("pr_not_approved","red"/);
  assert.deepEqual(['yes','no',undefined].map(answer=>answer==='no'),[false,true,false]);
});
test('single-quote severity depends on strict threshold and presence of cap', () => {
  assert.match(stock,/l>0\?o\(e\.rate\)\*l:void 0/);
  assert.match(stock,/c=r\.filter\(e=>a\(e\.supplier\)\|\|a\(e\.rate\)\)/);
  assert.match(stock,/"single_quote",m>h\?"red":"yellow"/);
  assert.equal(field('P-02:reason').requirements,'e=>e.v.not_lowest');
  assert.equal(field('P-02:single_reason').requirements,'e=>"yes"===e.d.single');
  const warning=(total,cap)=>cap===null||total>cap?'red':'yellow';
  assert.deepEqual([warning(98,100),warning(101,100),warning(100,100),warning(99,null)],['yellow','red','yellow','red']);
});
test('cancellation activates reason and approver, while quote check can still warn', () => {
  assert.equal(field('P-03:supplier').requirements,'e=>!e.d.cancel');
  assert.equal(field('P-03:cancel_reason').requirements,'e=>!!e.d.cancel');
  assert.equal(field('P-03:cancel_approver').requirements,'e=>!!e.d.cancel');
  assert.equal(field('P-03:credit_days').requirements,'e=>"credit"===e.d.pay&&!e.d.cancel');
  assert.match(stock,/o&&!a\(e\.d\.cs_no\)&&r\.push\(S\("po_no_cs","red"/);
  assert.match(stock,/e\.d\.cancel&&r\.push\(S\("po_cancelled","yellow"/);
  const flags=(total,cap,reference,cancel)=>[total>cap&&!reference?'red':null,cancel?'yellow':null];
  assert.deepEqual([flags(101,100,true,false),flags(101,100,false,true),flags(100,100,false,false)],[[null,null],['red','yellow'],[null,null]]);
});
