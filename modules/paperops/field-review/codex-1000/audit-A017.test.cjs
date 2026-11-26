'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(17);
const sales=supplements['forms_sales.js'];
const factory=supplements['forms_factory.js'];
const field=key=>report.fields.find(row=>row.source_id===key);
test('A017 covers exactly the assigned 50 original IDs',()=>assert.equal(verify(report,manifest,source,17,supplements),50));
test('monthly KPIs and signed leakage retain denominator and role rules',()=>{
  assert.match(sales,/t>0\?\(e\/t\*100\)\.toFixed\(1\)/);
  assert.match(sales,/0!==m&&a\.push\(q\("leak_nonzero","yellow"/);
  assert.match(sales,/e\.c\.checked_by===o\.prepared_by/);
  assert.equal(field('A-02:rec_leak').requirements,'e=>e.v.leak_nonzero');
  assert.equal(field('A-02:checked_by').role,'"checker"');
  const ratio=(numerator,denominator)=>denominator>0?(numerator/denominator*100).toFixed(1):null;
  assert.deepEqual([ratio(3,4),ratio(3,-4),ratio(3,0)],['75.0',null,null]);
});
test('fridge ranges include endpoints and preserve missing-setting distinction',()=>{
  assert.match(factory,/T=\[1,2\]/);
  assert.match(factory,/a=e>=l&&e<=p/);
  assert.match(factory,/null===l\|\|null===p/);
  assert.match(factory,/D\(e,"fridges2","temp2_out_"/);
  const check=(value,min,max)=>value===undefined?'missing-reading':min===null||max===null?'missing-setting':value>=min&&value<=max?'in':'red';
  assert.deepEqual([check(1,1,4),check(4,1,4),check(5,1,4),check(3,null,4),check(undefined,1,4)],['in','in','red','missing-setting','missing-reading']);
});
test('factory failures and unplanned details use their separate triggers',()=>{
  assert.equal(field('F-05:scale_listed').requirements,'e=>"off"===e.d.scale');
  assert.equal(field('F-05:unplanned_what').requirements,'e=>"yes"===e.d.unplanned');
  assert.equal(field('F-05:bd_request').requirements,'e=>"yes"===e.d.breakdown');
  assert.equal(field('F-05:bd_result').requirements,'e=>"checked"===e.d.bd_product');
  assert.match(factory,/t\[e\]===t\[r\]/);
  const same=(performer,checker)=>Boolean(performer&&performer===checker);
  assert.deepEqual([same('a','b'),same('a','a'),same(undefined,undefined)],[false,true,false]);
});
