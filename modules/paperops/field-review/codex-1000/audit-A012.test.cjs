'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(12);
const sales = supplements['forms_sales.js'];
const field = key => report.fields.find(row => row.source_id === key);
test('A012 matches exactly the 50 manifest rows', () => assert.equal(verify(report, manifest, source, 12, supplements), 50));
test('delivery and item presence are separate requirements', () => {
  assert.equal(field('S-01:address').requirements,'e=>"home"===e.d.deliv_mode');
  assert.equal(field('S-01:qty').requirements,'!0');
  assert.match(sales,/r\(o\.deliv_date\)&&o\.deliv_date<e\.date/);
  assert.match(sales,/O=e=>!e\.some\(e=>r\(e\.item\)\)/);
  const before=(order,delivery)=>Boolean(delivery&&delivery<order);
  assert.deepEqual(['2026-11-23','2026-11-24',undefined].map(date=>before('2026-11-24',date)),[true,false,false]);
});
test('discount and advance follow signed rounding and slip-sensitive severity', () => {
  assert.match(sales,/d=A\(s\(o\.total\)-s\(o\.discount\)-s\(o\.advance\)\)/);
  assert.match(sales,/"discount_over",r\(o\.disc_slip\)\?"yellow":"red"/);
  assert.equal(field('S-01:adv_other').visibility,'e=>s(e.d.advance)>0&&"other"===e.d.adv_mode');
  const warning=(discount,cap,slip)=>discount>0&&(cap===null||discount>cap)?(slip?'yellow':'red'):null;
  assert.deepEqual([warning(10,10),warning(11,10),warning(11,10,true),warning(0,null),warning(1,null)],[null,'red','yellow',null,'red']);
});
test('handover differs from cancellation and requires a representative name only on release', () => {
  assert.match(sales,/L=e=>e\.d\.not_collected,M=e=>!e\.d\.not_collected/);
  assert.equal(field('S-01:cust_signed').requirements,'M');
  assert.equal(field('S-01:rep_name').requirements,'e=>"rep"===e.d.received_by&&M(e)');
  assert.equal(field('S-01:adv_fate').requirements,'e=>e.d.not_collected&&s(e.d.advance)>0');
  const requires=(notCollected,mode)=>!notCollected&&mode==='rep';
  assert.deepEqual([requires(false,'rep'),requires(true,'rep'),requires(false,'self')],[true,false,false]);
});
test('board checker warning is independent of meaningful factory and receipt links', () => {
  assert.match(sales,/r\(o\.board_checker\)&&o\.board_checker===o\.taker/);
  assert.equal(field('S-01:on_board').requirements,'!0');
  assert.equal(field('S-02:memo_no').requirements,'NOT_DECLARED');
  const same=(maker,checker)=>Boolean(checker&&maker===checker);
  assert.deepEqual([same('a','b'),same('a','a'),same(undefined,undefined)],[false,true,false]);
});
