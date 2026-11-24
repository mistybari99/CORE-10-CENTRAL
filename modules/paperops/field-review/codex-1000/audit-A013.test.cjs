'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(13);
const sales = supplements['forms_sales.js'];
const field = key => report.fields.find(row => row.source_id === key);
test('A013 matches the assigned 50 field declarations', () => assert.equal(verify(report, manifest, source, 13, supplements),50));
test('discount aggregation and limit warnings retain their rounding and scope', () => {
  assert.match(sales,/sale:A\(s\(e\.qty\)\*s\(e\.list_price\)-s\(e\.disc\)\)/);
  assert.match(sales,/d\.tot_sale=A\(d\.tot_list-d\.tot_disc\)/);
  assert.match(sales,/"discount_over_limit",r\(e\.d\.approved_by\)\?"yellow":"red"/);
  assert.match(sales,/e\.d\.approved_by===e\.d\.seller/);
  assert.equal(field('S-02:mkt_line').requirements,'e=>"offer"===e.d.reason');
  const round = value => Math.round(100 * value) / 100;
  assert.deepEqual([round(1.8-1),round(1.8-2),round(1.8-1.8)],[0.8,-0.2,0]);
});
test('illness requires reported time; product custody and refund are independent', () => {
  assert.equal(field('S-03:sick_informed').requirements,'e=>e.d.c_sick');
  assert.match(sales,/o\.c_sick&&i\.push\(q\("illness_complaint","yellow"/);
  assert.match(sales,/r\(o\.item\)&&!o\.taken_back&&i\.push\(q\("product_not_taken","red"/);
  assert.equal(field('S-03:challan_no').requirements,'e=>"factory"===e.d.p_fate');
  const red = (item,taken) => Boolean(item&&!taken);
  assert.deepEqual([red('A',true),red('A',false),red(undefined,false)],[false,true,false]);
});
test('refund limit includes explicit missing-setting and equality cases', () => {
  assert.match(sales,/!!o\.d_refund&&l>0&&\(null===d\|\|l>d\)/);
  assert.match(sales,/"refund_over_limit",r\(o\.approved_by\)\?"yellow":"red"/);
  assert.equal(field('S-03:approved_time').requirements,'e=>e.v.over_limit');
  const warning=(refund,amount,limit,approver)=>refund&&amount>0&&(limit===null||amount>limit)?approver?'yellow':'red':null;
  assert.deepEqual([warning(true,12,10,'b'),warning(true,12,10),warning(true,10,10),warning(true,1,null),warning(false,1,null)],['yellow','red',null,'red',null]);
});
