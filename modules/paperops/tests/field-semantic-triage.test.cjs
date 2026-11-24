'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {generate,semanticTriage,audit}=require('../field-semantic-triage.cjs');
const original=require('../legacy-rule-candidates.json');
const batches=[1,2,3].map(n=>require('../field-review/batch-'+String(n).padStart(3,'0')+'.json'));
test('150 source field keys classified by semantics, never only 150 new mandatory inputs',()=>{
 const result=audit();
 assert.equal(result.summary.fields_triaged,150);
 assert.equal(result.summary.batches,3);
 assert.equal(new Set(result.fields.map(x=>x.source_id)).size,150);
 assert.equal(result.summary.remaining_source_first_pass,1010);
 assert.equal(result.summary.parity_approved,0);
 assert.equal(result.summary.owner_accepted,0);
 assert.equal(result.status,'SEMANTIC_TRIAGE_ONLY__NOT_BUSINESS_RULE_PARITY');
 assert.ok(result.summary.high_risk>=70);
 assert.ok(result.summary.by_data_origin.CALCULATED_OR_DISPLAY__RECOMPUTE_WITH_PROVEN_SOURCE_RULE>=15);
 assert.ok(result.summary.by_data_origin.CONTROL_EVIDENCE__NEVER_ASSUME_TRUE>=20);
 assert.ok(result.summary.by_data_origin.REFERENCE__USE_SIGNED_BUSINESS_SCOPE_IF_IN_ERP>=20);
});
test('computed original field keys are not automatically demanded as handwritten input',()=>{
 const report=generate(),field=id=>report.fields.find(x=>x.source_id===id);
 for(const id of ['C-02:total','C-02:sum_cr','C-01:handover','W-02:tag',
  'R-01:float_set','R-01:open_diff','R-01:temp_ok','R-01:v_total']){
  const f=field(id);assert.ok(f,id);
  assert.equal(f.proposed_ERP_data_origin,'CALCULATED_OR_DISPLAY__RECOMPUTE_WITH_PROVEN_SOURCE_RULE',id);
  assert.equal(f.calculated_result_equivalence,'NOT_PROVEN');
  assert.equal(f.duplicate_data_entry_permitted,false);
  assert.equal(f.next_required_check,'REPLAY_HISTORICAL_FORMULA_WITH_VALID_NEGATIVE_AND_BOUNDARY_DATA');
 }
});
test('original source conditions and required fields remain high-priority unresolved evidence',()=>{
 const report=generate();
 assert.equal(report.summary.source_explicit_always_required,30);
 assert.equal(report.summary.source_explicit_conditional_required,6);
 assert.equal(report.summary.source_conditional_visibility,16);
 const byId=id=>report.fields.find(x=>x.source_id===id);
 const c02=byId('C-02:approved_by');
 assert.equal(c02.source_field_required_syntax,'CONDITIONAL');
 assert.equal(c02.source_visibility_syntax,'CONDITIONAL');
 assert.equal(c02.next_required_check,'TRACE_CONDITIONAL_VISIBILITY_AND_REQUIREDNESS_EXPRESSION');
 assert.equal(c02.owner_accepted,false);
 const w02=byId('W-02:cash_amount');
 assert.equal(w02.source_visibility_syntax,'CONDITIONAL');
 assert.equal(w02.next_required_check,'TRACE_CONDITIONAL_VISIBILITY_AND_REQUIREDNESS_EXPRESSION');
 assert.equal(byId('R-01:temp').source_requirement_evidence,'SOURCE_SYNTACTIC_ALWAYS_REQUIRED_CANDIDATE');
 assert.equal(byId('R-01:expired_shown').review_risk,'HIGH_RISK_BUSINESS_CONTROL');
});
test('expense source lines, returnable packaging and shop close voucher references point at reusable books',()=>{
 const x=generate().fields;
 const get=id=>x.find(r=>r.source_id===id);
 assert.equal(get('R-01:vouchers').proposed_semantic_class,'LINKED_EXPENSE_VOUCHER_COLLECTION');
 assert.equal(get('R-01:v_no').proposed_semantic_class,'LINKED_EXPENSE_VOUCHER_REFERENCE');
 assert.equal(get('W-02:crates_due').proposed_semantic_class,'RETURNABLE_PACKAGING_OUTSTANDING_LEDGER');
 assert.equal(get('W-02:trays_due').proposed_semantic_class,'RETURNABLE_PACKAGING_OUTSTANDING_LEDGER');
 assert.equal(get('W-03:movement').proposed_semantic_class,'COUNT_FREEZE_MOVEMENT_ATTESTATION');
 assert.equal(get('R-01:expired_informed').proposed_semantic_class,'FOOD_EXPIRY_ESCALATION_EVIDENCE');
 assert.equal(get('C-01:rcount').proposed_semantic_class,'RECEIVER_INDEPENDENT_DENOMINATION_SCHEDULE');
});
test('fail closed on unknown original fields, invalid constructor aliases and source field tampering',()=>{
 const bad=structuredClone(batches),bad2=structuredClone(original);
 bad[1].entries[0].source_id='W-02:INVENTED';
 assert.throws(()=>semanticTriage(original,bad),/UNKNOWN_ORIGINAL_FIELD/);
 const f=bad2.forms.find(x=>x.legacy_code==='C-02').fields.find(x=>x.key==='time');
 f.constructor_alias='UNKNOWN';
 assert.throws(()=>semanticTriage(bad2,batches),/UNRECOGNIZED_FIELD_CONSTRUCTOR/);
});
