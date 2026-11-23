'use strict';
/* R01-03 and R01-04: nonposting C02 -> R01 source/ledger reconciliation.
 * This file owns ONLY the enumerated ChatGPT 246 form field IDs. Incoming
 * refund/deposit/reversal events are EXTERNAL Money-source evidence, not
 * implementations of Codex-owned R-01 fields or historical cash formulas.
 * No persistence, credentials, approvals or signed Money/Stock/Sales calls.
 */
const {createHash}=require('node:crypto');
const frozen=require('./source-helper-conditions.cjs');
const {reviewAccountSource}=require('./c02-account-source.cjs');
const manifest=require('../ownership-246-1000.json');
const FIELDS=['R-01:vouchers','R-01:v_no','R-01:v_amt','R-01:v_total',
 'R-01:imp_cash','R-01:imp_receipts','R-01:float_set','R-01:open_diff',
 'R-01:advance_taken','C-02:money_account_id','C-02:pay_mode'];
const OWNED=new Set([...manifest.lane_B_chatgpt.critical_86_keys,
 ...manifest.lane_B_chatgpt.mapped_150_keys,...manifest.lane_B_chatgpt.reserved_next_10_keys]);
if(FIELDS.some(id=>!OWNED.has(id)))throw Error('R01_246_LANE_SCOPE_VIOLATION');
const RE=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$/;
function id(v,label){if(typeof v!=='string'||!RE.test(v))throw Error('R01_LEDGER_INVALID_REF:'+label);return v;}
function cents(v,label){
 const s=typeof v==='number'&&Number.isFinite(v)?String(v):v;
 if(typeof s!=='string'||! /^(?:0|[1-9]\d*)(?:\.\d{1,2})?$/.test(s))
  throw Error('R01_LEDGER_INVALID_MONEY:'+label);
 const [whole,dec='']=s.split('.');
 const n=BigInt(whole)*100n+BigInt(dec.padEnd(2,'0')||'0');
 if(n>BigInt(Number.MAX_SAFE_INTEGER))throw Error('R01_LEDGER_UNSAFE_MONEY:'+label);
 return n;
}
function fmt(n){return (n<0n?'-':'')+(n<0n?-n:n)/100n+'.'+String((n<0n?-n:n)%100n).padStart(2,'0');}
function scoped(r,s,label){
 if(!r||r.tenantId!==s.tenantId||r.businessId!==s.businessId||r.siteId!==s.siteId)
  throw Error('R01_LEDGER_CROSS_SCOPE:'+label);
}
function assertSource(){
 const s=frozen.readFrozen('forms');frozen.verifyEvidence();
 const p=s.indexOf('e.forms["R-01"]='),end=s.indexOf('e.forms[',p+1);
 if(p<0)throw Error('R01_LEDGER_ORIGINAL_SOURCE_MISSING');
 const block=s.slice(p,end<0?s.length:end);
 for(const q of [
  'd.v_total=s(e.rows("vouchers").map(e=>e.v_amt))',
  'd.float_set=null===l?T:l',
  'd.open_diff=r(o.open_counted)-l',
  'd.imp_text=P(e)',
  'k("vouchers",t("দৈনিক খরচ (শুধু ইমপ্রেস্ট থেকে)"',
  'c("advance_taken",t("আজ নেওয়া অ্যাডভান্স"'])
  if(!block.includes(q))throw Error('R01_LEDGER_OLD_SOURCE_DRIFT:'+q);
 return {originalBlob:frozen.PIN.forms,oldExecuted:false,fields:FIELDS};
}
function reconcileDay({scope:s,day,accountProvider,control,opening,sourceVouchers,
  sourceMoneyEvents,ledgerRows,declaredClose}={}){
 const proof=assertSource();
 if(!s||s.synthetic_only!==true||![s.tenantId,s.businessId,s.siteId].every(
  x=>typeof x==='string'&&x.startsWith('DEMO-')&&RE.test(x)))
  throw Error('R01_LEDGER_SYNTHETIC_ONLY');
 for(const [name,row] of [['DAY',day],['PROVIDER',accountProvider],
  ['CONTROL',control],['OPENING',opening],['CLOSE',declaredClose]])
  scoped(row,s,name);
 if(!Array.isArray(sourceVouchers)||sourceVouchers.length>200||
    !Array.isArray(sourceMoneyEvents)||sourceMoneyEvents.length>300||
    !Array.isArray(ledgerRows)||ledgerRows.length>600)
  throw Error('R01_LEDGER_EVENT_COLLECTION_REQUIRED');
 if(!/^\d{4}-\d{2}-\d{2}$/.test(day.businessDate||''))
  throw Error('R01_LEDGER_INVALID_BUSINESS_DATE');
 for(const name of ['dayRef','cashbookRef'])id(day[name],name);
 for(const name of ['sourceRef','floatControlRef','imprestControlRef'])
  id(control[name],name);
 if(accountProvider.capability!=='expense_10_2')
  throw Error('R01_LEDGER_WRONG_ACCOUNT_OPTION_PROVIDER');
 const blocked=[],flag=x=>{if(!blocked.includes(x))blocked.push(x);};
 if(day.drawerExpenseFree!==true||declaredClose.drawerExpenseFree!==true)
  flag('R01_SALES_DRAWER_EXPENSE_PROHIBITION_UNPROVEN');
 const openingCash=cents(opening.imprestCashBDT,'OPEN_CASH');
 const openingReceipts=cents(opening.imprestReceiptsBDT,'OPEN_RECEIPTS');
 const fixed=cents(control.fixedImprestBDT,'FIXED_IMPREST');
 if(openingCash+openingReceipts!==fixed)flag('R01_OPEN_IMPREST_NOT_BALANCED');
 const float=cents(control.approvedFloatBDT,'APPROVED_FLOAT');
 if(cents(opening.drawerCountBDT,'OPEN_DRAWER_COUNT')!==float)
  flag('R01_OPEN_DRAWER_FLOAT_DIFFERENCE');
 if(cents(declaredClose.floatSetBDT,'DECLARED_FLOAT')!==float)
  flag('R01_FLOAT_SETTING_SOURCE_MISMATCH');
 const uniqueSource=new Set([day.dayRef,day.cashbookRef,
  control.sourceRef,control.floatControlRef,control.imprestControlRef]);
 const moneyMap=new Map(),voucherMap=new Map(),ledgerRefs=new Set(),events=[];
 let expense=0n,advances=0n,spend=0n,receipts=openingReceipts;
 function putEvent(e,k,amount,accountId,direction){
  id(e.sourceRef,'SOURCE_EVENT');
  if(uniqueSource.has(e.sourceRef))throw Error('R01_DUPLICATE_OR_REPLAYED_SOURCE_EVENT');
  uniqueSource.add(e.sourceRef);
  if(moneyMap.has(e.sourceRef))throw Error('R01_DUPLICATE_SOURCE_EVENT');
  moneyMap.set(e.sourceRef,{kind:k,amount,accountId,direction});
 }
 for(const v of sourceVouchers){
  scoped(v,s,'C02');
  id(v.voucherRef,'VOUCHER');id(v.sourceRef,'C02_SOURCE');
  if(voucherMap.has(v.voucherRef))throw Error('R01_DUPLICATE_C02_VOUCHER');
  if(v.dayRef!==day.dayRef)throw Error('R01_C02_DAILY_REF_MISMATCH');
  if(v.cashbookRef!==day.cashbookRef)throw Error('R01_C02_CASHBOOK_SCOPE_MISMATCH');
  if(v.drawerUntouched!==true)flag('R01_C02_SALES_DRAWER_BREACH');
  const amount=cents(v.amountBDT,'C02_AMOUNT');
  if(amount===0n)throw Error('R01_EMPTY_C02_EXPENSE');
  const result=reviewAccountSource({scope:s,provider:accountProvider,voucher:{
   tenantId:s.tenantId,businessId:s.businessId,siteId:s.siteId,
   voucherRef:v.voucherRef,money_account_id:v.money_account_id,pay_mode:v.pay_mode,
   salesDrawerUntouched:v.drawerUntouched}});
  if(result.status==='BLOCK')
   for(const blocker of result.blockers)flag('R01_C02_ACCOUNT:'+v.voucherRef+':'+blocker);
  if(v.pay_mode!=='cash')flag('R01_NONCASH_C02_REQUIRES_SEPARATE_SIGNED_BOOK');
  if(v.receiptAttached!==true||!v.receiptProofRef||!RE.test(v.receiptProofRef))
   flag('R01_C02_RECEIPT_EVIDENCE_REQUIRED:'+v.voucherRef);
  if(!RE.test(v.preparedBy||'')||!RE.test(v.checkedBy||'')||
     v.preparedBy===v.checkedBy)flag('R01_C02_INDEPENDENT_VOUCHER_ACTORS_REQUIRED:'+v.voucherRef);
  expense+=amount;
  if(v.pay_mode==='cash'){spend+=amount;receipts+=amount;}
  voucherMap.set(v.voucherRef,amount);
  putEvent(v,'C02_EXPENSE',amount,v.money_account_id,'OUT');
 }
 const refundedByAdvance=new Map(),pendingReversal=new Set();
 for(const e of sourceMoneyEvents){
  scoped(e,s,'EXTERNAL_MONEY');
  id(e.sourceRef,'MONEY_SOURCE');
  const amount=cents(e.amountBDT,'MONEY_EVENT_AMOUNT');
  if(amount===0n)throw Error('R01_ZERO_MONEY_EVENT');
  id(e.accountId,'MONEY_ACCOUNT');id(e.evidenceRef,'MONEY_EVENT_EVIDENCE');
  if(e.dayRef!==day.dayRef||e.cashbookRef!==day.cashbookRef)
   throw Error('R01_EXTERNAL_MONEY_DAILY_REF_MISMATCH');
  if(!RE.test(e.makerActor||'')||!RE.test(e.checkerActor||'')||e.makerActor===e.checkerActor)
   flag('R01_MONEY_INDEPENDENT_REVIEW_REQUIRED');
  if(e.kind==='ORDER_ADVANCE'){
   id(e.orderRef,'ADVANCE_ORDER');
   if(e.accountId===accountProvider.options.find(o=>o.role==='IMPREST_CASH')?.accountId)
    flag('R01_ADVANCE_MUST_NOT_ENTER_IMPREST');
   advances+=amount;
   putEvent(e,e.kind,amount,e.accountId,'IN');
  }else if(e.kind==='CUSTOMER_REFUND'){
   id(e.originalAdvanceRef,'ORIGINAL_ADVANCE_REF');
   const original=moneyMap.get(e.originalAdvanceRef);
   if(!original||original.kind!=='ORDER_ADVANCE')throw Error('R01_REFUND_WITHOUT_KNOWN_ADVANCE');
   if(e.accountId!==original.accountId)throw Error('R01_REFUND_MONEY_ACCOUNT_DIFFERS_FROM_ADVANCE');
   const already=refundedByAdvance.get(e.originalAdvanceRef)||0n;
   if(already+amount>original.amount)throw Error('R01_REFUND_EXCEEDS_ORIGINAL_ADVANCE');
   refundedByAdvance.set(e.originalAdvanceRef,already+amount);
   flag('R01_EXTERNAL_REFUND_NEEDS_SIGNED_MONEY_POLICY');
   putEvent(e,e.kind,amount,e.accountId,'OUT');
  }else if(e.kind==='BANK_DEPOSIT'){
   id(e.destinationAccountRef,'DESTINATION_BANK_ACCOUNT');
   if(e.accountId===e.destinationAccountRef)
    throw Error('R01_DEPOSIT_SOURCE_EQUALS_DESTINATION');
   flag('R01_EXTERNAL_DEPOSIT_NEEDS_BANK_CONFIRMATION');
   putEvent(e,e.kind,amount,e.accountId,'OUT');
  }else if(e.kind==='REVERSAL'){
   id(e.originalEventRef,'ORIGINAL_EVENT');
   const original=moneyMap.get(e.originalEventRef);
   if(!original||original.kind==='REVERSAL')throw Error('R01_REVERSAL_UNKNOWN_OR_NESTED_EVENT');
   if(pendingReversal.has(e.originalEventRef))
    throw Error('R01_DOUBLE_REVERSAL_OR_REPLAY');
   pendingReversal.add(e.originalEventRef);
   if(amount!==original.amount||e.accountId!==original.accountId)
    throw Error('R01_REVERSAL_VALUE_OR_ACCOUNT_MISMATCH');
   if(typeof e.reason!=='string'||e.reason.trim().length<5)
    flag('R01_REVERSAL_REASON_AND_AUDIT_REQUIRED');
   flag('R01_REVERSAL_REQUIRES_SIGNED_APPROVAL_AND_AUDIT');
   putEvent(e,e.kind,amount,e.accountId,original.direction==='IN'?'OUT':'IN');
  }else throw Error('R01_UNKNOWN_EXTERNAL_MONEY_EVENT');
  events.push({kind:e.kind,sourceRef:e.sourceRef,amountBDT:fmt(amount)});
 }
 const bookedSource=new Set();
 for(const b of ledgerRows){
  scoped(b,s,'CASHBOOK_ROW');
  id(b.entryRef,'CASHBOOK_ENTRY');
  if(ledgerRefs.has(b.entryRef)||uniqueSource.has(b.entryRef))
   throw Error('R01_DUPLICATE_CASHBOOK_ENTRY');
  ledgerRefs.add(b.entryRef);
  id(b.sourceEventRef,'CASHBOOK_EVENT_REF');
  if(bookedSource.has(b.sourceEventRef))
   throw Error('R01_DUPLICATE_POSTING_OF_SOURCE_EVENT');
  bookedSource.add(b.sourceEventRef);
  if(b.cashbookRef!==day.cashbookRef||b.dayRef!==day.dayRef)
   throw Error('R01_CASHBOOK_ROW_DIFFERENT_DAY');
  const original=moneyMap.get(b.sourceEventRef);
  if(!original)throw Error('R01_UNBACKED_CASHBOOK_EVENT');
  if(b.accountId!==original.accountId||b.direction!==original.direction)
   throw Error('R01_CASHBOOK_ACCOUNT_OR_DIRECTION_MISMATCH');
  if(cents(b.amountBDT,'LEDGER_AMOUNT')!==original.amount)
   flag('R01_CASHBOOK_SOURCE_AMOUNT_MISMATCH:'+b.sourceEventRef);
  if(!RE.test(b.enteredBy||'')||!RE.test(b.checkedBy||'')||b.enteredBy===b.checkedBy)
   flag('R01_CASHBOOK_INDEPENDENT_CHECKER_REQUIRED:'+b.sourceEventRef);
 }
 if(bookedSource.size!==moneyMap.size)
  flag('R01_SOURCE_EVENTS_NOT_ALL_IN_CASHBOOK');
 for(const sourceRef of moneyMap.keys())if(!bookedSource.has(sourceRef))
  flag('R01_CASHBOOK_SOURCE_ROW_MISSING:'+sourceRef);
 if(cents(declaredClose.vTotalBDT,'R01_VTOTAL')!==expense)
  flag('R01_C02_VOUCHER_TO_DAILY_TOTAL_MISMATCH');
 if(cents(declaredClose.advanceTakenBDT,'R01_ADVANCES')!==advances)
  flag('R01_ADVANCE_SOURCE_TO_DAILY_TOTAL_MISMATCH');
 const finalCash=openingCash-spend;
 if(finalCash<0n)flag('R01_IMPREST_CASH_OVERDRAWN');
 if(cents(declaredClose.imprestCashBDT,'R01_IMP_CASH')!==finalCash||
    cents(declaredClose.imprestReceiptsBDT,'R01_IMP_RECEIPTS')!==receipts)
  flag('R01_C02_IMPREST_CASH_RECEIPT_CONTINUITY_MISMATCH');
 if(finalCash+receipts!==fixed)flag('R01_IMPREST_FIXED_BALANCE_INCONSISTENT');
 const lineage={scope:s,day,control,opening,sourceVouchers,
  sourceMoneyEvents,ledgerRows,declaredClose};
 return Object.freeze({sourceFields:proof.fields.slice(),
  status:blocked.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
  blockers:Object.freeze(blocked),evidence:Object.freeze({
   dailyExpenseBDT:fmt(expense),sourceAdvanceBDT:fmt(advances),
   imprestCashBDT:fmt(finalCash),imprestReceiptsBDT:fmt(receipts),
   fixedImprestBDT:fmt(fixed),cashbookRows:ledgerRows.length,
   sourceEvents:moneyMap.size,externalMoneyEvents:Object.freeze(events),
   sourceDigest:createHash('sha256').update(JSON.stringify(lineage)).digest('hex'),
   originalSourceBlob:proof.originalBlob}),
  sourceOnly:true,syntheticOnly:true,originalLegacyCodeExecuted:false,
  originalCashExpectedFormulaParityCertified:false,
  canonicalMoneyLedgerVerified:false,canonicalSalesVerified:false,
  canonicalAuditVerified:false,signedReversalVerified:false,
  signedAccountScopeVerified:false,ownerAccepted:false,canPost:false});
}
module.exports={reconcileDay,assertSource};
