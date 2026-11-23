'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const gaps=require('../field-review/chatgpt-246/issue-registry.json');
const fields=require('../field-review/chatgpt-246/closure-evidence.json');
const own=require('../field-review/ownership-246-1000.json');
const c02=require('../field-review/chatgpt-246/c02-account-source.cjs');
const r01=require('../field-review/chatgpt-246/r01-money-day-ledger.cjs');
const selected=['C-02:pay_mode','C-02:money_account_id','R-01:vouchers',
 'R-01:v_no','R-01:v_amt','R-01:v_total','R-01:float_set',
 'R-01:open_diff','R-01:imp_cash','R-01:imp_receipts','R-01:advance_taken'];
test('C02 and R01 actual source corrections remain explicitly OPEN signed/runtime gaps',()=>{
 assert.equal(gaps.local_corrections_count,8);
 assert.equal(gaps.total_original_gaps,11);
 assert.equal(gaps.remaining_open_original_gaps,11);
 assert.equal(gaps.total_high_risk_obligations,20);
 for(const name of ['C02-01','C02-03','R01-03','R01-04']){
  const g=gaps.functional_gaps.find(x=>x.id===name);
  assert.equal(g.status,'OPEN_WITH_BLOCKER');
  assert.equal(g.signed_tested,false);assert.equal(g.owner_policy_accepted,false);
  assert.equal(g.canonical_runtime_integrated,false);
  assert.match(g.local_correction,/C02|R01|MONEYSRC|BLANK/);
  assert.match(g.local_evidence,/chatgpt-246/);
  assert.ok(typeof g.remaining_dependency==='string'&&g.remaining_dependency.length>20);
  assert.ok(gaps.next_signed_dependencies[name]);
 }
 assert.ok(gaps.functional_gaps.every(x=>x.status==='OPEN_WITH_BLOCKER'));
 assert.ok(gaps.high_risk_obligations.every(x=>x.status==='OPEN_WITH_BLOCKER'));
});
test('only the eleven actual owned C02/R01 field IDs are marked with these local gates',()=>{
 const theirs=new Set(own.lane_A_codex.ownership_keys);
 assert.equal(fields.fields.length,246);
 assert.equal(new Set(selected).size,11);
 for(const id of selected){
  const row=fields.fields.find(x=>x.source_id===id);
  assert.ok(row,id);assert.equal(theirs.has(id),false,id);
  assert.match(row.local_nonposting_correction,/C02|R01/);
  assert.equal(row.signed_tested,false);
  assert.equal(row.canonical_runtime_integrated,false);
  assert.equal(row.owner_accepted,false);
  assert.equal(row.release_authorized,false);
  assert.equal(row.erp_post_authorized,false);
 }
 assert.equal(fields.canonical_runtime_signed_postings,0);
 assert.equal(fields.owner_approved_fields,0);
 assert.equal(fields.local_nonposting_source_logic.signed_money_api_invoked,false);
 assert.equal(fields.local_nonposting_source_logic.field_approved_for_live_use,0);
 assert.deepEqual(c02.assertSource().sourceFields,['C-02:money_account_id','C-02:pay_mode']);
 assert.deepEqual(r01.assertSource().fields,
  ['R-01:vouchers','R-01:v_no','R-01:v_amt','R-01:v_total',
   'R-01:imp_cash','R-01:imp_receipts','R-01:float_set','R-01:open_diff',
   'R-01:advance_taken','C-02:money_account_id','C-02:pay_mode']);
});
