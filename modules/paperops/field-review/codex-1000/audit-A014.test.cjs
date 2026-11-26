'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(14);
const sales = supplements['forms_sales.js'];
const field = key => report.fields.find(row => row.source_id === key);
test('A014 covers exactly the assigned 50 declarations',()=>assert.equal(verify(report,manifest,source,14,supplements),50));
test('complaint closure flag depends on checker context and resolved state',()=>{
  assert.match(sales,/void 0!==e\.c\.resolved&&e\.c\.resolved\|\|Object\.values\(e\.c\)\.some\(r\)/);
  assert.equal(field('S-03:resolved_date').visibility,'e=>e.c.resolved');
  const warn=(hasCheck,resolved)=>hasCheck&&!resolved;
  assert.deepEqual([warn(true,true),warn(true,false),warn(false,undefined)],[false,true,false]);
});
test('invoice totals and guarded approval versus quote',()=>{
  assert.match(sales,/E=e=>"invoice"===e\.d\.doc/);
  assert.match(sales,/d\.all_due=A\(s\(t\.prev_dues\)\+d\.inv_due\)/);
  assert.match(sales,/"credit_outside",r\(t\.approved_by\)\?"yellow":"red"/);
  assert.equal(field('S-05:posted_ledger').requirements,'E');
  const credit=(doc,marked,due,cap)=>doc==='invoice'&&marked==='inside'&&(cap===undefined||due>cap);
  assert.deepEqual([credit('quote','inside',11,10),credit('invoice','inside',11,10),credit('invoice','inside',10,10),credit('invoice','inside',0,undefined)],[false,true,false,true]);
});
test('invoice cash and previous balance use signed arithmetic',()=>{
  assert.match(sales,/d\.inv_total=A\(d\.grand-s\(t\.discount\)\),d\.inv_due=A\(d\.inv_total-s\(t\.cash_today\)\)/);
  assert.match(sales,/s\(t\.cash_today\)>d\.inv_total/);
  assert.equal(field('S-05:cash_other').visibility,'e=>s(e.d.cash_today)>0&&"other"===e.d.cash_mode');
  const due=(total,discount,cash,previous)=>previous+total-discount-cash;
  assert.deepEqual([due(100,10,90,10),due(100,10,91,0),due(0,0,0,0)],[10,-1,0]);
});
test('repair duration allows zero and warns on a negative finite interval',()=>{
  assert.match(sales,/Math\.round\(10\*s\)\/10/);
  assert.match(sales,/Number\.isFinite\(s\)&&s<0&&o\.push\(q\("done_before_found","red"/);
  const hours=(found,done)=>Math.round((done-found)/360000)/10;
  assert.deepEqual([hours(0,3600000),hours(3600000,0),hours(0,0)],[1,-1,0]);
});
