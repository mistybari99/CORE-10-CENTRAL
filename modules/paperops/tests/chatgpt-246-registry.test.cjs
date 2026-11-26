'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const owned=require('../field-review/ownership-246-1000.json');
const report=require('../field-review/chatgpt-246/closure-evidence.json');
const issues=require('../field-review/chatgpt-246/issue-registry.json');
const deep=require('../field-review/deep-source-recheck-001-003.json');
const gaps=require('../field-review/functional-gaps-001-003.json');
const trace=require('../control-trace.json');
const helpers=require('../field-review/chatgpt-246/source-helper-conditions.cjs');
const ids=[...owned.lane_B_chatgpt.critical_86_keys,
 ...owned.lane_B_chatgpt.mapped_150_keys,
 ...owned.lane_B_chatgpt.reserved_next_10_keys];
test('all and ONLY the original 246 IDs appear in complete lane B evidence, in frozen owner order',()=>{
 assert.equal(report.fields.length,246);
 assert.deepEqual(report.fields.map(x=>x.source_id),ids);
 assert.deepEqual(report.fields.reduce((s,x)=>(s[x.lane]=(s[x.lane]||0)+1,s),{}),
  {CRITICAL_86:86,MAPPED_150:150,RESERVED_R01_10:10});
 assert.equal(new Set(report.fields.map(x=>x.source_id)).size,246);
 const excluded=new Set(owned.lane_A_codex.ownership_keys);
 assert.equal(owned.lane_A_codex.ownership_keys.length,1000);
 assert.ok(report.fields.every(x=>!excluded.has(x.source_id)));
 assert.ok(report.fields.every(x=>x.owner_accepted===false&&x.canonical_runtime_integrated===false&&
  x.signed_tested===false&&x.release_authorized===false&&x.erp_post_authorized===false));
 assert.equal(report.owner_approved_fields,0);
 assert.equal(report.canonical_runtime_signed_postings,0);
});
test('first mapped 150 retain literal old field proofs, not formula or Owner parity',()=>{
 const x=new Map(deep.entries.map(e=>[e.source_id,e]));
 for(const f of report.fields.filter(f=>f.lane==='MAPPED_150')){
  assert.equal(f.source_constructor_proof,x.get(f.source_id).source_call);
  assert.equal(f.source_rule_verified,false);
  assert.equal(f.owner_accepted,false);
 }
});
test('all ten new R-01 old source calls, aliases, Bangla-English labels and calc absence are pinned',()=>{
 const original=fs.existsSync(path.resolve(__dirname,'../../../legacy/islamia-erp/forms.js'))?
  fs.readFileSync(path.resolve(__dirname,'../../../legacy/islamia-erp/forms.js'),'utf8'):
  fs.readFileSync(path.resolve(__dirname,'../../../forms.js'),'utf8');
 helpers.verifyEvidence();
 const proofs=report.reserved_r01_original_declarations;
 assert.deepEqual(proofs.map(x=>x.source_id),owned.lane_B_chatgpt.reserved_next_10_keys);
 assert.deepEqual(proofs.map(x=>x.constructor_type),
  ['checkbox','number','text','checkbox','checkbox','number','text','number','number','money']);
 for(const p of proofs){
  assert.ok(original.includes(p.source_exact_call),p.source_id);
  assert.ok(p.label_bn&&p.label_en);
  assert.equal(p.source_required,'NOT_DECLARED');
  assert.equal(p.source_visibility,'NOT_DECLARED');
  assert.equal(p.source_calc_mentions,false);
  assert.equal(p.source_to_signed_ERP_verified,false);
  assert.equal(p.original_source_operationally_executed,false);
 }
});
test('11 functional gaps and 20 obligations are cross-linked without duplicate issue counting',()=>{
 assert.equal(issues.total_original_gaps,11);
 assert.equal(issues.total_high_risk_obligations,20);
 assert.deepEqual(issues.functional_gaps.map(x=>x.id),gaps.gaps.map(x=>x.id));
 assert.deepEqual(issues.high_risk_obligations.map(x=>x.id),trace.records.map(x=>x.obligation_id));
 const indexed=new Map(report.fields.map(x=>[x.source_id,x]));
 for(const g of issues.functional_gaps){
  assert.equal(g.status,'OPEN_WITH_BLOCKER');assert.equal(g.signed_tested,false);
  for(const id of g.field_ids)assert.ok(indexed.get(id)?.original_gap_ids.includes(g.id));
 }
 for(const o of issues.high_risk_obligations){
  assert.equal(o.status,'OPEN_WITH_BLOCKER');assert.equal(o.canonical_runtime_integrated,false);
  for(const id of o.field_ids)assert.ok(indexed.get(id)?.critical_obligation_ids.includes(o.id));
 }
 const overlapping=report.fields.filter(x=>x.critical_obligation_ids.length+x.original_gap_ids.length>1).map(x=>x.source_id);
 assert.deepEqual(issues.intersecting_field_ids,overlapping);
 const affected=report.fields.filter(x=>x.critical_obligation_ids.length||x.original_gap_ids.length).map(x=>x.source_id);
 assert.deepEqual(issues.distinct_field_ids_with_any_finding,affected);
});
test('helper evidence stays an explicitly partial, synthetic-only R01-02 correction',()=>{
 const g=issues.functional_gaps.find(x=>x.id==='R01-02');
 assert.match(g.local_correction,/PINNED_OLD_N_O_SOURCE_HELPERS_IMPLEMENTED/);
 assert.equal(g.status,'OPEN_WITH_BLOCKER');
 assert.equal(report.helper_correction.signed_authorization_proven,false);
 assert.equal(issues.no_owner_acceptance,true);
 assert.equal(report.status,'ALL_246_ENUMERATED__PARITY_NOT_APPROVED');
});
