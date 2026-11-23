'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const ownership=require('../field-review/ownership-246-1000.json');
const issues=require('../field-review/chatgpt-246/issue-registry.json');
const closure=require('../field-review/chatgpt-246/closure-evidence.json');
const W=require('../field-review/chatgpt-246/w02-customer-payment-source.cjs');
const R=require('../field-review/chatgpt-246/r01-food-safety-review.cjs');
test('new W02-02 and R01-01 source-review gates remain original gaps OPEN, never Owner signed',()=>{
 assert.equal(issues.total_original_gaps,11);
 assert.equal(issues.remaining_open_original_gaps,11);
 assert.equal(issues.total_high_risk_obligations,20);
 assert.equal(issues.local_corrections_count,11);
 assert.equal(issues.functional_gaps.filter(x=>x.local_correction!==null).length,11);
 for(const [id,file] of [['W02-02','w02-customer-payment-source.cjs'],['R01-01','r01-food-safety-review.cjs']]){
  const g=issues.functional_gaps.find(x=>x.id===id);
  assert.equal(g.status,'OPEN_WITH_BLOCKER');
  assert.equal(g.signed_tested,false);
  assert.equal(g.canonical_runtime_integrated,false);
  assert.equal(g.owner_policy_accepted,false);
  assert.match(g.local_evidence,new RegExp(file.replace('.','\\.')));
  assert.ok(issues.next_signed_dependencies[id]);
 }
 assert.ok(issues.functional_gaps.every(x=>x.status==='OPEN_WITH_BLOCKER'));
 assert.ok(issues.high_risk_obligations.every(x=>x.status==='OPEN_WITH_BLOCKER'));
 assert.equal(closure.canonical_runtime_signed_postings,0);
 assert.equal(closure.owner_approved_fields,0);
});
test('all new source field overlays stay exclusively ChatGPT 246 and cannot post',()=>{
 const p=[...W.assertSource().fields,...R.assertSource().fields];
 const own=new Set([...ownership.lane_B_chatgpt.critical_86_keys,
  ...ownership.lane_B_chatgpt.mapped_150_keys,...ownership.lane_B_chatgpt.reserved_next_10_keys]);
 const codex=new Set(ownership.lane_A_codex.ownership_keys);
 assert.equal(new Set(p).size,p.length);
 assert.equal(p.length,14);
 for(const id of p){
  assert.ok(own.has(id),id);
  assert.equal(codex.has(id),false,id);
  const e=closure.fields.find(x=>x.source_id===id);
  assert.ok(e,id);
  assert.match(e.local_nonposting_correction,/W02|R01/);
  assert.equal(e.canonical_runtime_integrated,false);
  assert.equal(e.owner_accepted,false);
  assert.equal(e.signed_tested,false);
  assert.equal(e.release_authorized,false);
  assert.equal(e.erp_post_authorized,false);
 }
 assert.equal(closure.fields.length,246);
 assert.equal(closure.local_nonposting_source_logic.field_approved_for_live_use,0);
 assert.equal(closure.local_nonposting_source_logic.signed_money_api_invoked,false);
});
