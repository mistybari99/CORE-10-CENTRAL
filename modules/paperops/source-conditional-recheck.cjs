'use strict';
/* Explicit, fail-closed 150-field source-condition candidates. No historical code execution.
 * Inferred normalized inputs must be independently verified against the frozen source.
 */
const deep=require('./field-review/deep-source-recheck-001-003.json');
const oldHelper=require('./field-review/chatgpt-246/source-helper-conditions.cjs');
const expr={
 'C-02:money_account_id':'!(!e.moneySrc||!e.moneySrc.hasAccounts("expense_10_2"))',
 'C-02:approved_by':'e.v.over_limit',
 'C-02:no_receipt_reason':'e.v.no_receipt',
 'C-02:sum_cr':'O("cash_now")',
 'C-02:imprest_text':'O("cash_now")',
 'C-01:diff_reason':'e.v.diff_nonzero',
 'W-02:outside_reason':'"yes"===e.d.outside',
 'W-02:order_no':'"yes"===e.d.cust_order',
 'W-02:cash_amount':'"cash"===e.d.pay',
 'W-03:movement_detail':'"yes"===e.d.movement',
 'R-01:safety_defect':'"no"===e.d.safety',
 'R-01:open_diff':'O("open_counted")',
 'R-01:imp_text':'!e.cf||n(e.d.imp_cash)',
 'R-01:expired_informed':'"yes"===e.d.expired_shown',
 'R-01:t2_1':'"busy"===e.d.day_type',
 'R-01:t2_2':'"busy"===e.d.day_type'
};
const requiredIfVisible=new Set([
 'C-02:approved_by','C-02:no_receipt_reason','C-01:diff_reason',
 'W-02:outside_reason','W-03:movement_detail','R-01:safety_defect'
]);
function getValue(data,key){
 if(!data||typeof data!=='object'||!Object.prototype.hasOwnProperty.call(data,key))
  return {known:false,value:null};
 const x=data[key];
 return {known:typeof x==='string'&&x.length>0||typeof x==='boolean',value:x};
}
function same(data,key,want){
 const got=getValue(data,key);
 if(!got.known)return null;
 if(typeof got.value!=='string')return null;
 return got.value===want;
}
function boolean(data,key){
 const got=getValue(data,key);
 if(!got.known||typeof got.value!=='boolean')return null;
 return got.value;
}
function decide(id,input){
 if(!Object.hasOwn(expr,id))throw Error('NOT_AN_EXTRACTED_CONDITIONAL_FIELD:'+id);
 const d=input||{};
 let value=null,reason='EXPLICIT_SOURCE_BRANCH_RECHECK_REQUIRED';
 if(id==='C-02:approved_by')value=boolean(d,'overLimit');
 else if(id==='C-02:no_receipt_reason')value=boolean(d,'missingReceipt');
 else if(id==='C-01:diff_reason')value=boolean(d,'diffNonzero');
 else if(id==='C-02:money_account_id'){
  const enabled=boolean(d,'moneySourceConnected'),has=boolean(d,'expenseAccountAvailable');
  value=enabled===false?false:enabled===true?has:null;
 }
 else if(id==='W-02:outside_reason')value=same(d,'outside','yes');
 else if(id==='W-02:order_no')value=same(d,'custOrder','yes');
 else if(id==='W-02:cash_amount')value=same(d,'paymentMethod','cash');
 else if(id==='W-03:movement_detail')value=same(d,'movement','yes');
 else if(id==='R-01:safety_defect')value=same(d,'safety','no');
 else if(id==='R-01:expired_informed')value=same(d,'expiredShown','yes');
 else if(id==='R-01:t2_1'||id==='R-01:t2_2')value=same(d,'dayType','busy');
 else if(id==='C-02:sum_cr'||id==='C-02:imprest_text'||
         id==='R-01:open_diff'||id==='R-01:imp_text'){
  // Original forms.js: O=e=>t=>!t.cf||n(t.d[e]); entry.js:
  // $=e=>!(null==e||""===e||!1===e), t.has=$. Pinned and NOT executed.
  oldHelper.verifyEvidence();
  const field=id==='C-02:sum_cr'||id==='C-02:imprest_text'?'cash_now':
    id==='R-01:open_diff'?'open_counted':'imp_cash';
  const result=oldHelper.oldO(field,d);
  value=result.visible;
  reason='ORIGINAL_N_AND_O_HELPER_RECOVERED__'+result.why;
  // Historical test compatibility only: an externally computed presence hint
  // is NOT equivalent to a raw original field. Prefer sourceData.imp_cash.
  if(id==='R-01:imp_text'&&value===null&&d.cf===true&&
      typeof d.imprestCashIsPresent==='boolean'){
    value=d.imprestCashIsPresent;
    reason='UNVERIFIED_NORMALIZED_PRESENCE_HINT__NO_RUNTIME_PARITY';
  }
 }
 if(!['C-02:sum_cr','C-02:imprest_text','R-01:open_diff','R-01:imp_text'].includes(id))
  reason='SOURCE_EXPRESSION_RECONSTRUCTED__RUNTIME_PARITY_NOT_PROVEN';
 const status=value===null?'UNKNOWN_MUST_REVIEW':value?'VISIBLE':'HIDDEN';
 return Object.freeze({source_id:id,source_expression:expr[id],status,
  required:requiredIfVisible.has(id)?value===true?'REQUIRED':value===false?'NOT_REQUIRED':'UNKNOWN_MUST_REVIEW':'NOT_DECLARED_BY_SOURCE',
  evidence:reason,erpPostingAuthorized:false,ownerAccepted:false,
  sourceRuntimeParityCertified:false});
}
function audit(){
 const source=new Map(deep.entries.map(x=>[x.source_id,x]));
 const conditional=deep.entries.filter(x=>x.field_visibility_source==='CONDITIONAL');
 if(conditional.length!==16||Object.keys(expr).length!==16)throw Error('CONDITIONAL_SOURCE_COVERAGE_CHANGED');
 for(const [id,expression] of Object.entries(expr)){
  const f=source.get(id);
  if(!f||!f.source_call.includes(expression))throw Error('ORIGINAL_EXPRESSION_CHANGED:'+id);
  if(requiredIfVisible.has(id)&&f.field_required_source!=='CONDITIONAL')
   throw Error('REQUIRED_CONDITION_SOURCE_DRIFT:'+id);
  if(!requiredIfVisible.has(id)&&f.field_required_source==='CONDITIONAL')
   throw Error('UNMAPPED_REQUIRED_SOURCE_CONDITION:'+id);
 }
 if(requiredIfVisible.size!==6)throw Error('MISSING_REQUIRED_SOURCE_BRANCH');
 return {total_visible_conditions:conditional.length,conditional_required:requiredIfVisible.size,
  source_expressions_verified:16,helper_dependent_conditions:['C-02:sum_cr','C-02:imprest_text','R-01:open_diff','R-01:imp_text'],
  parityCertified:false,allConditionalRulesApproved:false,
  old_helpers_source_verified:oldHelper.verifyEvidence().sourceRuleVerified,
  signed_erp_posting_authorized:false};
}
if(require.main===module)console.log(JSON.stringify(audit(),null,2));
module.exports={decide,audit,expr};
