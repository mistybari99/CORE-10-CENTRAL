'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { inspect, readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(18);
const factory=supplements['forms_factory.js'];
const field=key=>report.fields.find(row=>row.source_id===key);
test('A018 verifies 50 declarations and excludes shared helper outside F-02',()=>{
  assert.equal(verify(report,manifest,source,18,supplements),50);
  assert.equal(field('F-02:item').evidence.label_en,'Item code & product name');
  assert.ok(factory.includes('u("item",t("কাঁচামালের নাম ও আইটেম কোড","Raw material name & item code")'));
  assert.throws(()=>inspect(factory,'F-02:qty'),/Missing or ambiguous/);
});
test('factory custody and separation conditions are distinct',()=>{
  assert.equal(field('F-05:raw_return_by').requirements,'e=>"done"===e.d.raw_return');
  assert.equal(field('F-05:key_to').requirements,'!0');
  assert.equal(field('F-05:mgmt_checker').role,'"checker"');
  assert.match(factory,/t\.yield_approver===t\.in_charge/);
  const self=(actor,approver)=>Boolean(approver&&actor===approver);
  assert.deepEqual([self('a','b'),self('a','a'),self('a',undefined)],[false,true,false]);
});
test('an unresolved incident is counted only when it has a description',()=>{
  assert.match(factory,/a\(e\.what\)&&!e\.solved/);
  const count=rows=>rows.filter(row=>row.what&&!row.solved).length;
  assert.deepEqual([count([{what:'test',solved:true}]),count([{what:'test',solved:false}]),count([{solved:false}])],[0,1,0]);
});
test('spec card converts grams to pieces with an inclusive missing/zero guard',()=>{
  assert.match(factory,/r\(o\.g1_weight\)>0\?Math\.round\(1e3\/r\(o\.g1_weight\)\*100\)\/100:void 0/);
  assert.equal(field('F-02:pcs_calc').visibility,'e=>r(e.d.g1_weight)>0');
  assert.equal(field('F-02:photo_rej').requirements,'!0');
  const pieces=grams=>grams>0?Math.round(1000/grams*100)/100:undefined;
  assert.deepEqual([pieces(30),pieces(-5),pieces(0),pieces(undefined)],[33.33,undefined,undefined,undefined]);
});
