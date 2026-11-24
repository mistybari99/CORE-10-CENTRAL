'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { inspect, hash, readBatch, verify } = require('./audit.cjs');
const partial = require('./A019-partial.json');
const issue = require('./issues-A019.json').find(row => row.issue_id === 'A019-F008');
const { manifest, source, supplements } = readBatch(18);
const factory = supplements['forms_factory.js'];
test('A019 preserves 47 source records while a partial batch fails closed',()=>{
  assert.equal(partial.fields.length,47);
  const keys=manifest.lane_A_codex.ownership_keys.slice(900,950);
  assert.deepEqual(partial.fields.map(row=>row.source_id),keys.filter(key=>!partial.unverified_fields.includes(key)&&!issue.actual_candidates.includes(key)));
  for(const row of partial.fields) assert.deepEqual(inspect(factory,row.source_id),row.evidence);
  assert.throws(()=>verify(partial,manifest,source,19,supplements));
});
test('F-03 ingredient helper is outside F-02 and used by all three recipe sections',()=>{
  assert.equal(hash(factory),issue.source_sha256);
  const endOfSpec=factory.indexOf(';const F=[');
  const startOfRecipe=factory.indexOf('e.forms["F-03"]={');
  const endOfRecipe=factory.indexOf('e.forms["F-04"]={');
  assert.ok(issue.helper.offset_utf16>endOfSpec&&issue.helper.offset_utf16<startOfRecipe);
  assert.equal(factory.slice(issue.helper.offset_utf16,issue.helper.offset_utf16+issue.helper.text.length),issue.helper.text);
  for(const use of issue.consumers){
    assert.ok(use.offset_utf16>=startOfRecipe&&use.offset_utf16<endOfRecipe);
    assert.equal(factory.slice(use.offset_utf16,use.offset_utf16+use.text.length),use.text);
  }
  for(const key of issue.source_ids) assert.throws(()=>inspect(factory,key),/Missing or ambiguous/);
});
test('verified recipe and spec rules retain explicit branches',()=>{
  assert.match(factory,/o\.craft_incharge===o\.factory_incharge/);
  assert.match(factory,/calc:e=>\(\{v:\{\},flags:\[\],needs:\[\]\}\)/);
  assert.match(factory,/new Set\(d\)\.size<d\.length/);
  assert.match(factory,/R=\(e,t\)=>r\(t\)>0&&a\(e\)\?Math\.round\(r\(e\)\/r\(t\)\*1e4\)\/100:void 0/);
  const conversion=(base,input)=>base===undefined||input<=0?undefined:Math.round(base/input*10000)/100;
  assert.deepEqual([conversion(3,4),conversion(3,0),conversion(0,4),conversion(undefined,4)],[75,undefined,0,undefined]);
});
