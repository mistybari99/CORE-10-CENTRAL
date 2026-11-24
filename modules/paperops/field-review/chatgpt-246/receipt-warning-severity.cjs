'use strict';
/* C-02 receipt warning severity is sourced from frozen forms.js calc(e).
 * This is a READ-ONLY synthetic warning preview, not a payout, exception
 * approval, change to the stricter expenseVoucher gate or ERP journal post.
 */
const source=require('./source-helper-conditions.cjs');
const PREDICATE='o.filter(e=>"no"===e.receipt&&r(e.amount)>0)';
const YELLOW='x("no_receipt","yellow"';
const RED='x("receipt_reason_missing","red"';
function attestSource(){
 const forms=source.readFrozen('forms');
 source.verifyEvidence();
 if(!forms.includes(PREDICATE)||!forms.includes(YELLOW)||!forms.includes(RED))
  throw Error('C02_ORIGINAL_RECEIPT_WARNING_SOURCE_DRIFT');
 return true;
}
function cents(v,label){
 const s=typeof v==='number'&&Number.isFinite(v)?String(v):v;
 if(typeof s!=='string'||! /^(?:0|[1-9]\d*)(?:\.\d{1,2})?$/.test(s))
  throw Error('C02_INVALID_MONEY:'+label);
 const p=s.split('.'),n=Number(p[0])*100+Number((p[1]||'').padEnd(2,'0'));
 if(!Number.isSafeInteger(n))throw Error('C02_UNSAFE_MONEY:'+label);
 return n;
}
function assessMissingReceipts({synthetic_only,lines,noReceiptReason}={}){
 attestSource();
 if(synthetic_only!==true)throw Error('C02_SYNTHETIC_ONLY');
 if(!Array.isArray(lines)||!lines.length||lines.length>100)
  throw Error('C02_RECEIPT_SOURCE_LINES_REQUIRED');
 const refs=new Set();
 let subtotal=0;
 for(const row of lines){
  if(!row||typeof row!=='object'||typeof row.voucherLineRef!=='string'||
    !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$/.test(row.voucherLineRef))
    throw Error('C02_IMMUTABLE_VOUCHER_LINE_REF_REQUIRED');
  if(refs.has(row.voucherLineRef))throw Error('C02_DUPLICATE_VOUCHER_LINE_REF');
  refs.add(row.voucherLineRef);
  if(row.receipt!=='yes'&&row.receipt!=='no')throw Error('C02_UNKNOWN_RECEIPT_STATUS');
  const money=cents(row.amount,'amount');
  if(row.receipt==='no'&&money>0){
   if(!Number.isSafeInteger(subtotal+money))throw Error('C02_RECEIPT_MONEY_OVERFLOW');
   subtotal+=money;
  }
 }
 const flags=[];
 if(subtotal>0){
  flags.push(Object.freeze({code:'no_receipt',severity:'yellow',amountBDT:(subtotal/100).toFixed(2)}));
  if(!source.legacyHas(noReceiptReason))
   flags.push(Object.freeze({code:'receipt_reason_missing',severity:'red',amountBDT:(subtotal/100).toFixed(2)}));
 }
 return Object.freeze({
  source_ids:['C-02:receipt','C-02:no_receipt_reason'],
  flags:Object.freeze(flags),
  status:subtotal>0?'MISSING_RECEIPT_POLICY_EXCEPTION_REQUIRED':'SOURCE_WARNING_PREVIEW_CLEAR',
  missingReceiptAmountBDT:(subtotal/100).toFixed(2),
  sourceSeverityRecovered:true,sourceCalcInputShapeApproximated:true,
  legacyExecuted:false,signedMoneyAuthorized:false,ownerPolicyAccepted:false,canPost:false
 });
}
module.exports={assessMissingReceipts,attestSource};
