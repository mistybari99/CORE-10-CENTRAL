'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(16);
const sales=supplements['forms_sales.js'];
const field=key=>report.fields.find(row=>row.source_id===key);
test('A016 verifies 50 keys while retaining both name declarations',()=>{
  assert.equal(verify(report,manifest,source,16,supplements),50);
  assert.equal(field('A-02:name').evidence.label_en,'Location · brand');
  assert.equal(field('A-02:name').alternate_evidence.label_en,'Raw material');
  const broken=structuredClone(report);
  delete broken.fields.find(row=>row.source_id==='A-02:name').alternate_evidence;
  assert.throws(()=>verify(broken,manifest,source,16,supplements));
});
test('weekly split and decision rules do not infer voucher data',()=>{
  assert.equal(field('A-01:split_in_decisions').requirements,'e=>"yes"===e.d.split');
  assert.equal(field('A-01:deadline').requirements,'e=>r(e.row.what)');
  assert.equal(field('A-01:prev_reason').requirements,'e=>s(e.d.prev_open)>0');
  assert.match(sales,/A\(s\(t\.prev_done\)\+s\(t\.prev_open\)\)!==A\(s\(t\.prev_total\)\)/);
  const mismatch=(total,done,open)=>[total,done,open].every(value=>value!==undefined)&&done+open!==total;
  assert.deepEqual([mismatch(2,1,1),mismatch(2,0,1),mismatch(2,undefined,1)],[false,true,false]);
});
test('P&L rounding permits signed reinvestment and negative COGS',()=>{
  assert.match(sales,/A\(s\(o\.open_stock\)\+s\(o\.purchases\)-s\(o\.close_stock\)\)/);
  assert.match(sales,/n\.reinvest=A\(p\*s\(o\.reinvest_pct\)\/100\)/);
  const toFund=(net,pct)=>Math.round(net*pct)/100;
  assert.deepEqual([toFund(100,20),toFund(-100,20),toFund(-100,0)],[20,-20,-0]);
  const cogs=(opening,purchase,closing)=>opening+purchase-closing;
  assert.deepEqual([cogs(5,1,2),cogs(5,1,7),cogs(5,1,6)],[4,-1,0]);
});
test('monthly date format does not establish month bounds',()=>{
  assert.match(sales,/new Date\(Number\(t\[1\]\),Number\(t\[2\]\),0\)\.getDate\(\)/);
  const parseMonth=month=>{const match=/^(\d{4})-(\d{1,2})$/.exec(month);return match?new Date(Number(match[1]),Number(match[2]),0).getDate():null;};
  assert.deepEqual([parseMonth('2024-02'),parseMonth('2024-13'),parseMonth('2024-x')],[29,31,null]);
});
test('sales subtotal, signed leakage and raw material completeness are separate',()=>{
  assert.match(sales,/f>0&&r\(o\.sales\)&&f!==d/);
  assert.match(sales,/A\(s\(o\.cash_short\)\+s\(o\.gm_unexplained\)\+s\(o\.count_short\)\)/);
  assert.match(sales,/chg:r\(e\.p_start\)&&r\(e\.p_end\)\?/);
  const warn=(subtotal,total)=>subtotal>0&&total!==undefined&&subtotal!==total;
  assert.deepEqual([warn(9,9),warn(9,10),warn(0,10)],[false,true,false]);
});
