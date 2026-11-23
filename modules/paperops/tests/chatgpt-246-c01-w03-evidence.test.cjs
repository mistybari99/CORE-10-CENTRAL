'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const registry=require('../field-review/chatgpt-246/issue-registry.json');
const closure=require('../field-review/chatgpt-246/closure-evidence.json');
const manifest=require('../field-review/ownership-246-1000.json');
const source=require('../field-review/chatgpt-246/source-helper-conditions.cjs');
const {assertSource:cashSource}=require('../field-review/chatgpt-246/c01-cash-custody.cjs');
const {assertSource:countSource}=require('../field-review/chatgpt-246/w03-stock-count-freeze.cjs');
test('C01/W03 local corrections have actual source gates and remain ORIGINAL GAPS OPEN',()=>{
 for(const [id,sourceFile,testFile] of [
  ['C01-01','c01-cash-custody.cjs','chatgpt-246-c01-cash-custody.test.cjs'],
  ['W03-01','w03-stock-count-freeze.cjs','chatgpt-246-w03-stock-count.test.cjs']
 ]){
  const gap=registry.functional_gaps.find(g=>g.id===id);
  assert.equal(gap.status,'OPEN_WITH_BLOCKER');
  assert.equal(gap.canonical_runtime_integrated,false);
  assert.equal(gap.signed_tested,false);
  assert.equal(gap.owner_policy_accepted,false);
  assert.match(gap.local_evidence,new RegExp(sourceFile.replace('.','\\.')));
  assert.match(gap.local_evidence,new RegExp(testFile.replace('.','\\.')));
 }
 assert.equal(registry.remaining_open_original_gaps,11);
 assert.equal(registry.total_original_gaps,11);
 assert.equal(registry.total_high_risk_obligations,20);
 assert.equal(registry.local_corrections_count,8);
 assert.equal(closure.owner_approved_fields,0);
 assert.equal(closure.canonical_runtime_signed_postings,0);
 assert.equal(closure.local_nonposting_source_logic.field_approved_for_live_use,0);
});
test('exactly 9 critical C01/W03 fields have now recovered frozen constructor labels, not Owner parity',()=>{
 const proofs=closure.fields.filter(f=>f.critical_source_declaration_recovered);
 assert.equal(proofs.length,9);
 assert.deepEqual(proofs.map(f=>f.source_id),[
  'C-01:seal_no','C-01:counted_total','C-01:received_total','C-01:diff',
  'W-03:count','W-03:book','W-03:var','W-03:reason','W-03:witness']);
 const src=source.readFrozen('forms');
 source.verifyEvidence();
 for(const p of proofs){
  assert.equal(p.lane,'CRITICAL_86');
  assert.ok(src.includes(p.source_constructor_proof));
  assert.ok(p.critical_source_labels.bn && p.critical_source_labels.en);
  assert.equal(p.source_rule_verified,false);
  assert.equal(p.owner_accepted,false);
  assert.equal(p.signed_tested,false);
 }
 assert.equal(cashSource().oldExecuted,false);
 assert.equal(countSource().oldExecuted,false);
});
test('C01 and W03 controls never edit the separate Codex 1000 ownership lane',()=>{
 const codex=new Set(manifest.lane_A_codex.ownership_keys);
 const assigned=closure.fields.filter(f=>f.local_nonposting_correction&&
  /C01_PINNED|W03_FROZEN/.test(f.local_nonposting_correction));
 assert.ok(assigned.length>=34);
 assert.ok(assigned.every(f=>
  !codex.has(f.source_id)&&/^(C-01|W-03):/.test(f.source_id)&&f.canPost!==true&&
  f.canonical_runtime_integrated===false&&f.release_authorized===false));
});
