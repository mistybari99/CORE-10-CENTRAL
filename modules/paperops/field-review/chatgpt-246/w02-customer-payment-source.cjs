'use strict';
/* W02-02: pinned historical visibility rules + stricter synthetic-only
 * transfer/customer-payment source review. No signed Money/Sales provider
 * authentication, no orders or accounts created, no posting. Owner policy
 * is required to authorize stricter cash/order requirements.
 */
const {createHash}=require('node:crypto');
const source=require('./source-helper-conditions.cjs');
const manifest=require('../ownership-246-1000.json');
const FIELDS=Object.freeze(['W-02:cust_order','W-02:order_no','W-02:pay','W-02:cash_amount']);
const owned=new Set([...manifest.lane_B_chatgpt.critical_86_keys,...manifest.lane_B_chatgpt.mapped_150_keys,...manifest.lane_B_chatgpt.reserved_next_10_keys]);
if(FIELDS.some(x=>!owned.has(x)))throw Error('W02_OUTSIDE_246_LANE');
const RE=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$/;
const ref=(v,name)=>{if(typeof v!=='string'||!RE.test(v))throw Error('W02_BAD_REF:'+name);return v;};
function amount(v,name){
 const s=typeof v==='number'&&Number.isFinite(v)?String(v):v;
 if(typeof s!=='string'||! /^(?:0|[1-9]\d*)(?:\.\d{1,2})?$/.test(s))
  throw Error('W02_BAD_MONEY:'+name);
 const [a,b='']=s.split('.');
 const cents=BigInt(a)*100n+BigInt(b.padEnd(2,'0')||'0');
 if(cents>BigInt(Number.MAX_SAFE_INTEGER))throw Error('W02_UNSAFE_AMOUNT:'+name);
 return cents;
}
function sameScope(e,s,kind){
 if(!e||e.tenantId!==s.tenantId||e.businessId!==s.businessId||e.siteId!==s.siteId)
  throw Error('W02_CROSS_TENANT_BUSINESS_SITE:'+kind);
}
function assertSource(){
 const forms=source.readFrozen('forms');source.verifyEvidence();
 const at=forms.indexOf('e.forms["W-02"]='),end=forms.indexOf('e.forms[',at+1);
 if(at<0)throw Error('W02_ORIGINAL_FORM_NOT_FOUND');
 const block=forms.slice(at,end<0?forms.length:end);
 for(const proof of [
  '"cust_order",t("কাস্টমার অর্ডারের পণ্য?","Goods for a customer order?")',
  '"order_no",t("অর্ডার নং","Order no."),{show:e=>"yes"===e.d.cust_order}',
  '"pay",t("পেমেন্ট","Payment")',
  '["adv",t("অ্যাডভান্স","Advance")]',
  '["cash",t("ক্যাশ","Cash")]',
  '["credit",t("বাকি","Credit")]',
  '"cash_amount",t("ক্যাশ টাকা","Cash amount"),{show:e=>"cash"===e.d.pay}'
 ])if(!block.includes(proof))throw Error('W02_PINNED_FORM_RULE_DRIFT:'+proof);
 return Object.freeze({sourceForms:['W-02'],originalBlob:source.PIN.forms,
  orderNoSourceVisibleWhen:'cust_order=yes',cashAmountSourceVisibleWhen:'pay=cash',
  originalOrderNoRequired:false,originalCashAmountRequired:false,oldCodeExecuted:false,fields:FIELDS});
}
function reviewTransfer({scope:s,transfer,orderEvidence=null,moneyEvidence=null}={}){
 const pinned=assertSource();
 if(!s||s.synthetic_only!==true||![s.tenantId,s.businessId,s.siteId].every(x=>
  typeof x==='string'&&x.startsWith('DEMO-')&&RE.test(x)))
  throw Error('W02_SYNTHETIC_SCOPE_REQUIRED');
 sameScope(transfer,s,'TRANSFER');
 ref(transfer.sourceRef,'TRANSFER_SOURCE');ref(transfer.challanRef,'CHALLAN');
 if(!['yes','no'].includes(transfer.cust_order))throw Error('W02_CUSTOMER_ORDER_BOOLEAN_REQUIRED');
 const blocked=[],flag=k=>{if(!blocked.includes(k))blocked.push(k);};
 const orderVisible=transfer.cust_order==='yes',cashVisible=transfer.pay==='cash';
 if(![null,undefined,'','cash','adv','credit'].includes(transfer.pay))
  throw Error('W02_UNSUPPORTED_PAYMENT_MODE');
 const orderNo=transfer.order_no;
 if(orderVisible){
  if(!orderNo)flag('W02_CUSTOMER_ORDER_SOURCE_NUMBER_REQUIRED_BY_REVIEW');
  else ref(orderNo,'ORDER_NUMBER');
  if(!orderEvidence)flag('W02_CUSTOMER_ORDER_REGISTER_EVIDENCE_MISSING');
  else{
   sameScope(orderEvidence,s,'ORDER_REGISTER');
   ref(orderEvidence.sourceRef,'ORDER_SOURCE');
   if(orderEvidence.sourceRef===transfer.sourceRef)throw Error('W02_REUSED_SOURCE_PROOF');
   if(orderEvidence.orderNo!==orderNo||orderEvidence.challanRef!==transfer.challanRef)
    flag('W02_ORDER_REGISTER_CHALLAN_CROSSREF_MISMATCH');
   if(orderEvidence.status!=='AUTHORIZED_FOR_TRANSFER')
    flag('W02_SIGNED_SALES_ORDER_AUTHORITY_NOT_VERIFIED');
  }
 }else{
  if(orderNo!==null&&orderNo!==undefined&&orderNo!=='')
   flag('W02_HIDDEN_ORDER_FIELD_CARRIED_IN_SOURCE');
  if(orderEvidence)flag('W02_UNLINKED_CUSTOMER_ORDER_EVIDENCE');
 }
 if(cashVisible){
  if(transfer.cash_amount===null||transfer.cash_amount===undefined||
    transfer.cash_amount==='')flag('W02_CASH_AMOUNT_REQUIRED_BY_STRICT_REVIEW');
  else if(amount(transfer.cash_amount,'CASH_AMOUNT')===0n)
   flag('W02_ZERO_CASH_AMOUNT_REQUIRES_FINANCE_REVIEW');
 }else if(transfer.cash_amount!==undefined&&transfer.cash_amount!==null&&transfer.cash_amount!==''){
  if(amount(transfer.cash_amount,'HIDDEN_CASH_AMOUNT')!==0n)
   flag('W02_CASH_AMOUNT_WHEN_SOURCE_FIELD_HIDDEN');
 }
 const selected=transfer.pay??'';
 if(selected!==''){
  if(!moneyEvidence)flag('W02_MONEY_SOURCE_EVENT_REQUIRED');
  else{
   sameScope(moneyEvidence,s,'MONEY_EVENT');
   ref(moneyEvidence.sourceRef,'MONEY_EVENT');
   ref(moneyEvidence.accountRef,'MONEY_ACCOUNT');
   ref(moneyEvidence.receiptRef,'MONEY_RECEIPT');
   if(moneyEvidence.sourceRef===transfer.sourceRef||
      (orderEvidence&&moneyEvidence.sourceRef===orderEvidence.sourceRef)||
      moneyEvidence.receiptRef===moneyEvidence.sourceRef)
    throw Error('W02_REPLAYED_PAYMENT_PROVENANCE');
   if(moneyEvidence.challanRef!==transfer.challanRef||
      moneyEvidence.mode!==selected)flag('W02_PAYMENT_PROVENANCE_MODE_OR_CHALLAN_MISMATCH');
   if(!RE.test(moneyEvidence.maker||'')||!RE.test(moneyEvidence.checker||'')||
     moneyEvidence.maker===moneyEvidence.checker)
    flag('W02_MONEY_INDEPENDENT_CHECKER_MISSING');
   if(selected==='cash'){
    if(transfer.cash_amount!=null&&transfer.cash_amount!==''&&
      amount(transfer.cash_amount,'DECLARED_CASH')!==amount(moneyEvidence.amountBDT,'BOOK_CASH'))
      flag('W02_CASH_SOURCE_MONEY_AMOUNT_MISMATCH');
    if(moneyEvidence.accountRole!=='BUSINESS_CASH')
     flag('W02_CASH_RECEIPT_IN_WRONG_ACCOUNT_KIND');
   }else if(selected==='adv'){
    ref(moneyEvidence.originalAdvanceRef,'ADVANCE_SOURCE');
    flag('W02_ADVANCE_APPLICATION_REQUIRES_SIGNED_SALES_MONEY_LINK');
   }else{
    ref(moneyEvidence.creditPolicyRef,'CREDIT_POLICY');
    flag('W02_CREDIT_REQUIRES_SIGNED_APPROVAL_AND_RECEIVABLE');
   }
   if(moneyEvidence.salesDrawerExpense===true)
    flag('W02_SALES_DRAWER_EXPENSE_CROSS_MODULE_BREACH');
  }
 }else if(moneyEvidence)flag('W02_PAYMENT_EVENT_WITHOUT_SELECTED_MODE');
 if(selected&&transfer.salesDrawerExpenseFree!==true)
  flag('W02_SALES_DRAWER_EXPENSE_SEPARATION_NOT_ATTESTED');
 return Object.freeze({status:blocked.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
  blockers:Object.freeze(blocked),evidence:Object.freeze({
   orderNumberFieldVisibleByOldRule:orderVisible,cashAmountFieldVisibleByOldRule:cashVisible,
   provenanceDigest:createHash('sha256').update(JSON.stringify({s,transfer,orderEvidence,moneyEvidence})).digest('hex'),
   sourceBlob:pinned.originalBlob}),
  fieldIDs:pinned.fields,syntheticOnly:true,sourceOnly:true,canonicalSalesOrderVerified:false,
  canonicalMoneyVerified:false,ownerPolicyAccepted:false,originalSourceRuleApproval:false,
  authenticatedSignatures:false,canPost:false});
}
module.exports={assertSource,reviewTransfer};
