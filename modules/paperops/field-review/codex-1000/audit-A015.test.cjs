'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(15);
const sales=supplements['forms_sales.js'];
const field=key=>report.fields.find(row=>row.source_id===key);
test('A015 covers exactly the assigned 50 records',()=>assert.equal(verify(report,manifest,source,15,supplements),50));
test('goods check result and two-person estimate approval are independent',()=>{
  assert.equal(field('M-01:goods_result').requirements,'e=>"checked"===e.d.goods_state');
  assert.match(sales,/t\.approved_by!==t\.reported_by&&t\.approved_by!==t\.requested_by/);
  const warning=(approver,reporter,requester)=>Boolean(approver&&(approver===reporter||approver===requester));
  assert.deepEqual([warning('c','a','b'),warning('a','a','b'),warning(undefined,'a','b')],[false,true,false]);
});
test('repair cap uses strict comparison and missing setting requests data',()=>{
  assert.match(sales,/"imprest"===t\.pay&&s\(t\.actual_cost\)>0&&\(null===n\?i\.push\("expense_max"\):s\(t\.actual_cost\)>n/);
  assert.equal(field('M-01:voucher_no').visibility,'e=>"imprest"===e.d.pay');
  const cap=(method,amount,max)=>method==='imprest'&&amount>0?(max===null?'missing':amount>max?'yellow':null):null;
  assert.deepEqual([cap('imprest',10,10),cap('imprest',11,10),cap('imprest',11,null),cap('bank',11,10)],[null,'yellow','missing',null]);
});
test('weekly date rule rejects reversal and permits equal dates',()=>{
  assert.match(sales,/r\(t\.week_from\)&&r\(t\.week_to\)&&t\.week_to<t\.week_from/);
  assert.equal(field('A-01:week_from').requirements,'!0');
  assert.equal(field('A-01:week_to').requirements,'!0');
  const reversed=(from,to)=>Boolean(from&&to&&to<from);
  assert.deepEqual([reversed('2026-11-20','2026-11-21'),reversed('2026-11-21','2026-11-20'),reversed('2026-11-21','2026-11-21'),reversed('2026-11-21',undefined)],[false,true,false,false]);
});
test('weekly projection declares showroom and factory groupings',()=>{
  assert.match(sales,/"showroom"===e\.kind&&!1!==e\.is_active/);
  assert.equal(field('A-01:sales').collection,'show');
  assert.equal(field('A-01:open_adv').collection,'fac');
  const eligible=loc=>loc.kind==='showroom'&&loc.is_active!==false&&['live','setting_up',null,undefined].includes(loc.status);
  assert.deepEqual([{kind:'showroom',status:'live'},{kind:'showroom',status:'live',is_active:false},{kind:'showroom'}].map(eligible),[true,false,true]);
});
