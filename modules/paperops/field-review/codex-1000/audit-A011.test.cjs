'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(11);
const stock = supplements['forms_stock.js'];
const sales = supplements['forms_sales.js'];
const field = key => report.fields.find(row => row.source_id === key);
test('A011 matches the 50 original records and source hashes', () => assert.equal(verify(report, manifest, source, 11, supplements), 50));
test('supplier prevention checks distinguish verification, change, and holder scope', () => {
  assert.match(stock,/t\.some\(e=>o\(e\.pay\)>0\)&&!a\(e\.d\.verifier\)/);
  assert.match(stock,/e\.d\.verifier===e\.d\.keeper&&r\.push\(S\("verifier_is_keeper","red"/);
  assert.match(stock,/e\.d\.chg_approver===e\.d\.keeper&&r\.push\(S\("change_approver_is_keeper","red"/);
  assert.equal(field('P-06:chg_approver').requirements,'e=>a(e.d.chg_new)');
  assert.equal(field('P-06:verify_other').visibility,'e=>"other"===e.d.verify_how');
  assert.equal(field('P-06:m_other_text').visibility,'e=>!!e.d.m_other');
  const warning=(pay,verifier)=>pay>0&&!verifier;
  assert.deepEqual([warning(7,'auditor'),warning(7,undefined),warning(0,undefined)],[false,true,false]);
});
test('AP running balance flags negative intermediate movement and master sums independent balances', () => {
  assert.match(stock,/i\+=o\(e\.bill\)-o\(e\.debit\)-o\(e\.pay\)/);
  assert.match(stock,/e\.bal<0\)&&r\.push\(S\("overpaid","yellow"/);
  assert.match(stock,/s\.master_total=n\(e\.rows\("master"\)\.map\(e=>e\.m_due\)\)/);
  assert.equal(field('P-06:mgmt_checked').role,'"checker"');
  assert.equal(field('P-06:master_posted').requirements,'NOT_DECLARED');
  const balances=(start,lines)=>lines.map(([bill,debit,pay])=>(start+=bill-debit-pay));
  assert.deepEqual(balances(0,[[6,1,3],[0,0,4],[8,0,0]]),[2,-2,6]);
  assert.deepEqual(balances(0,[[4,1,3]]),[0]);
  assert.deepEqual(balances(12,[]),[]);
});
test('order choices, custom refund and same-maker review are distinct', () => {
  assert.equal(field('S-01:channel_other').visibility,'e=>"other"===e.d.channel');
  assert.equal(field('S-01:online_other').visibility,'e=>"other"===e.d.online');
  assert.equal(field('S-01:cust_phone').requirements,'!0');
  assert.match(sales,/"custom"===o\.order_type&&"refund"===o\.adv_fate/);
  assert.match(sales,/o\.board_checker===o\.taker&&i\.push\(q\("board_checker_is_maker","yellow"/);
  const warns=(type,fate)=>type==='custom'&&fate==='refund';
  assert.deepEqual([warns('custom','refund'),warns('normal','refund'),warns('custom',undefined)],[true,false,false]);
});
