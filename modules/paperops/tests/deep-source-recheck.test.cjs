'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const deep=require('../field-deep-source-recheck.cjs');
const conditional=require('../source-conditional-recheck.cjs');
const data=require('../field-review/deep-source-recheck-001-003.json');
test('all 150 rechecked from literal old original forms.js source calls, ordered in 3 nonoverlapping 50 blocks',()=>{
 const r=deep.audit();
 assert.equal(r.summary.source_field_declarations_relocated,150);
 assert.deepEqual(r.summary.forms,{'C-02':19,'C-01':16,'W-02':48,'W-03':9,'R-01':58});
 assert.equal(r.summary.conditional_required_source_count,6);
 assert.equal(r.summary.conditional_visibility_source_count,16);
 assert.equal(r.summary.required_source_count,30);
 assert.ok(r.summary.entries_referencing_calc_body>=30);
 assert.equal(r.summary.source_business_rule_parity_approved,0);
 assert.equal(r.summary.owner_accepted,0);
 assert.equal(r.source_operationally_executed,false);
 assert.equal(new Set(r.entries.map(x=>x.source_id)).size,150);
 assert.equal(r.entries.filter(x=>x.batch_number===1).length,50);
 assert.equal(r.entries.filter(x=>x.batch_number===2).length,50);
 assert.equal(r.entries.filter(x=>x.batch_number===3).length,50);
 assert.ok(r.entries.every(x=>x.source_call.startsWith('(')&&x.source_to_live_ERP_verified===false));
});
test('frozen original field declaration changes, missing required flags and missing original field abort the source recheck',()=>{
 const src=require('node:fs').readFileSync(require('node:path').resolve(__dirname,'../../../legacy/islamia-erp/forms.js'),'utf8');
 const sem=require('../field-review/semantic-triage-001-003.json');
 const bs=[1,2,3].map(n=>require('../field-review/batch-'+String(n).padStart(3,'0')+'.json'));
 assert.throws(()=>deep.redoSourceEvidence(src.replace('"Time"','"Other time"'),sem,bs),/OLD_LABEL_DRIFT/);
 const bad=structuredClone(bs);bad[0].entries[0].required_candidate='ALWAYS';
 assert.throws(()=>deep.redoSourceEvidence(src,sem,bad),/OLD_BRANCH_METADATA_DRIFT/);
 const omit=src.replace('e.forms["C-02"]','e.forms["MISSING"]');
 assert.throws(()=>deep.redoSourceEvidence(omit,sem,bs),/OLD_FORM_SOURCE_MISSING/);
});
test('all 16 true original source show expressions accounted, six are conditionally required',()=>{
 const out=conditional.audit();
 assert.equal(out.total_visible_conditions,16);
 assert.equal(out.conditional_required,6);
 assert.equal(out.source_expressions_verified,16);
 assert.equal(out.parityCertified,false);
 assert.equal(new Set(Object.keys(conditional.expr)).size,16);
});
test('source conditional required approvals and receipt reasons are visible only when triggered',()=>{
 const tests=[
  ['C-02:approved_by',{overLimit:true},{overLimit:false}],
  ['C-02:no_receipt_reason',{missingReceipt:true},{missingReceipt:false}],
  ['C-01:diff_reason',{diffNonzero:true},{diffNonzero:false}],
  ['W-02:outside_reason',{outside:'yes'},{outside:'no'}],
  ['W-03:movement_detail',{movement:'yes'},{movement:'no'}],
  ['R-01:safety_defect',{safety:'no'},{safety:'yes'}]
 ];
 for(const [id,yes,no] of tests){
  const a=conditional.decide(id,yes),b=conditional.decide(id,no),unknown=conditional.decide(id,{});
  assert.equal(a.status,'VISIBLE',id);
  assert.equal(a.required,'REQUIRED',id);
  assert.equal(b.status,'HIDDEN',id);
  assert.equal(b.required,'NOT_REQUIRED',id);
  assert.equal(unknown.status,'UNKNOWN_MUST_REVIEW',id);
  assert.equal(unknown.required,'UNKNOWN_MUST_REVIEW',id);
  assert.equal(a.sourceRuntimeParityCertified,false);
  assert.equal(a.erpPostingAuthorized,false);
 }
});
test('original optional conditional reference/amount/showroom busy day is not silently made mandatory',()=>{
 for(const [id,yes,no] of [
  ['W-02:order_no',{custOrder:'yes'},{custOrder:'no'}],
  ['W-02:cash_amount',{paymentMethod:'cash'},{paymentMethod:'bank'}],
  ['R-01:expired_informed',{expiredShown:'yes'},{expiredShown:'no'}],
  ['R-01:t2_1',{dayType:'busy'},{dayType:'normal'}],
  ['R-01:t2_2',{dayType:'busy'},{dayType:'normal'}],
  ['C-02:money_account_id',{moneySourceConnected:true,expenseAccountAvailable:true},{moneySourceConnected:false}]
 ]){
  const v=conditional.decide(id,yes),x=conditional.decide(id,no);
  assert.equal(v.status,'VISIBLE',id);
  assert.equal(x.status,'HIDDEN',id);
  assert.equal(v.required,'NOT_DECLARED_BY_SOURCE',id);
  assert.equal(x.required,'NOT_DECLARED_BY_SOURCE',id);
 }
});
test('unknown source helper O fields stay UNKNOWN even if a mock input is present',()=>{
 for(const id of ['C-02:sum_cr','C-02:imprest_text','R-01:open_diff']){
  const r=conditional.decide(id,{cashNow:'100',openCounted:'500'});
  assert.equal(r.status,'UNKNOWN_MUST_REVIEW',id);
  assert.match(r.evidence,/OLD_O_HELPER_NOT_PROVEN/);
 }
});
test('R-01 conditional imp_text tracks precheck state but never falsely certifies n() helper',()=>{
 assert.equal(conditional.decide('R-01:imp_text',{cf:false}).status,'VISIBLE');
 assert.equal(conditional.decide('R-01:imp_text',{cf:true,imprestCashIsPresent:true}).status,'VISIBLE');
 assert.equal(conditional.decide('R-01:imp_text',{cf:true,imprestCashIsPresent:false}).status,'HIDDEN');
 assert.equal(conditional.decide('R-01:imp_text',{}).status,'UNKNOWN_MUST_REVIEW');
 assert.equal(conditional.decide('R-01:imp_text',{cf:true,imprestCashIsPresent:true}).sourceRuntimeParityCertified,false);
});
test('condition gate never accepts arbitrary invented fields or unknown actor/boolean source data',()=>{
 assert.throws(()=>conditional.decide('R-01:nonexistent',{}),/NOT_AN_EXTRACTED_CONDITIONAL_FIELD/);
 assert.equal(conditional.decide('C-02:approved_by',{overLimit:'maybe'}).status,'UNKNOWN_MUST_REVIEW');
 assert.equal(conditional.decide('W-02:outside_reason',{outside:true}).status,'UNKNOWN_MUST_REVIEW');
 assert.equal(conditional.decide('C-02:money_account_id',{moneySourceConnected:true}).status,'UNKNOWN_MUST_REVIEW');
});
