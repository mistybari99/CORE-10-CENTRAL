'use strict';
/* C-01 original-source cash handover and cashbook cross-reference guard.
 * Synthetic, deterministic, no credentials/network/storage/signatures/posting.
 * C-01 calc(e): handover = showroom count - float; diff = hub count -
 * handover; original hub_diff is red ONLY if hub count > 0.
 * This stricter preview holds zero/missing recounts and requires independent
 * evidence; none of those new conditions claims historical formula parity.
 */
const {createHash}=require('node:crypto');
const source=require('./source-helper-conditions.cjs');
const ownership=require('../ownership-246-1000.json');
const C01_KEYS=['sheet_no','carrier','seal_no','send_time','count','counted_total',
 'leave_float','handover','words','with_sheet','vouchers_count','other_docs',
 'rcount','received_total','diff','diff_reason','ledger_date','ledger_line',
 'seal_ok','copy_returned'].map(k=>'C-01:'+k);
const OWNED=new Set([...ownership.lane_B_chatgpt.critical_86_keys,
 ...ownership.lane_B_chatgpt.mapped_150_keys,...ownership.lane_B_chatgpt.reserved_next_10_keys]);
if(C01_KEYS.some(x=>!OWNED.has(x)))throw Error('C01_OWNER_SCOPE_DRIFT');
const ID=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$/;
function ref(x,label){if(typeof x!=='string'||!ID.test(x))throw Error('C01_INVALID_REF:'+label);return x;}
function scaled(x,label,places=2){
 const s=typeof x==='number'&&Number.isFinite(x)?String(x):x;
 const re=places===2?/^(?:0|[1-9]\d*)(?:\.\d{1,2})?$/:/^(?:0|[1-9]\d*)$/;
 if(typeof s!=='string'||!re.test(s))throw Error('C01_INVALID_NUMBER:'+label);
 const parts=s.split('.'),factor=10**places;
 const n=BigInt(parts[0])*BigInt(factor)+BigInt((parts[1]||'').padEnd(places,'0')||0);
 if(n>BigInt(Number.MAX_SAFE_INTEGER))throw Error('C01_NUMBER_OVERFLOW:'+label);
 return Number(n);
}
function bdt(x){return (x/100).toFixed(2);}
function assertSource(){
 const s=source.readFrozen('forms');
 source.verifyEvidence();
 const start=s.indexOf('e.forms["C-01"]=');
 const end=s.indexOf('e.forms[',start+1);
 if(start<0)throw Error('C01_ORIGINAL_FORM_MISSING');
 const form=s.slice(start,end<0?s.length:end);
 for(const q of ['const t=e.den("count"),o=r(e.d.leave_float),s=t-o',
   'const c=e.denC("rcount"),l=c-s','c>0&&0!==l&&a.push(x("hub_diff","red"',
   'null==d&&i.push("drawer_float")','diff_nonzero:c>0&&0!==l',
   '"ledger_line",t(','"rcount",t('])
  if(!form.includes(q))throw Error('C01_ORIGINAL_SOURCE_RULE_DRIFT:'+q);
 return Object.freeze({sourceBlob:source.PIN.forms,form:'C-01',oldExecuted:false});
}
function scope(row,s,type){
 if(!row||row.tenantId!==s.tenantId||row.businessId!==s.businessId||
    row.siteId!==s.siteId)throw Error('C01_CROSS_TENANT_BUSINESS_SITE:'+type);
}
function reconcileCashCustody({synthetic_only,scope:s,dispatch,hub,ledger,policy,corrections=[]}={}){
 const pinned=assertSource();
 if(synthetic_only!==true||!s||![s.tenantId,s.businessId,s.siteId].every(
   x=>typeof x==='string'&&x.startsWith('DEMO-')&&ID.test(x)))
  throw Error('C01_SYNTHETIC_SCOPE_ONLY');
 scope(dispatch,s,'DISPATCH');scope(hub,s,'HUB');scope(ledger,s,'CASHBOOK');
 if(!policy||!Array.isArray(dispatch.denominations)||!Array.isArray(hub.denominations))
  throw Error('C01_POLICY_AND_INDEPENDENT_COUNTS_REQUIRED');
 if(!Array.isArray(dispatch.voucherRefs)||!Array.isArray(ledger.voucherRefs)||
    !Array.isArray(corrections)||corrections.length>100)
  throw Error('C01_SOURCE_LINKED_VOUCHERS_AND_CORRECTIONS_REQUIRED');
 const blocks=[],fail=m=>{if(!blocks.includes(m))blocks.push(m);};
 const seenRefs=new Set();
 function unique(x,label){
  const v=ref(x,label);
  if(seenRefs.has(v))throw Error('C01_DUPLICATE_OR_REPLAYED_SOURCE_REF:'+label);
  seenRefs.add(v);return v;
 }
 unique(dispatch.handoverRef,'HANDOVER');
 unique(dispatch.sheetRef,'SHEET');
 unique(dispatch.sealRef,'SEAL');
 unique(dispatch.sendEvidenceRef,'SENDER_PROOF');
 unique(hub.hubEvidenceRef,'HUB_PROOF');
 unique(ledger.sourceLedgerRef,'LEDGER');
 unique(policy.controlRef,'FLOAT_CONTROL_REF');
 const sender=ref(dispatch.senderActor,'SENDER'),carrier=ref(dispatch.carrierActor,'CARRIER'),
   receiver=ref(hub.receiverActor,'RECEIVER');
 if(new Set([sender,carrier,receiver]).size!==3)
  fail('C01_INDEPENDENT_SENDER_CARRIER_RECEIVER_REQUIRED');
 if(hub.handoverRef!==dispatch.handoverRef||ledger.handoverRef!==dispatch.handoverRef)
  throw Error('C01_HANDOVER_SOURCE_REF_MISMATCH');
 if(ledger.dailySourceRef!==dispatch.sheetRef)
  throw Error('C01_CASHBOOK_DAILY_SOURCE_MISMATCH');
 if(hub.sealRef!==dispatch.sealRef)fail('C01_SEAL_NUMBER_MISMATCH');
 if(hub.sealIntact!==true)fail('C01_SEAL_INTEGRITY_NOT_PROVED');
 if(dispatch.originalSheetEnclosed!==true)fail('C01_ORIGINAL_DAILY_SHEET_NOT_ENCLOSED');
 if(hub.returnCopyAcknowledged!==true)fail('C01_RETURNED_COPY_UNCONFIRMED');
 const t1=Date.parse(dispatch.sentAt),t2=Date.parse(hub.countedAt),t3=Date.parse(ledger.bookedAt);
 if(![dispatch.sentAt,hub.countedAt,ledger.bookedAt].every(v=>typeof v==='string'&&
    /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z$/.test(v))||
    ![t1,t2,t3].every(Number.isFinite))
  throw Error('C01_TIMESTAMP_FORMAT_INVALID');
 if(t2<t1||t3<t2)fail('C01_CUSTODY_TO_LEDGER_TIME_ORDER_INVALID');
 const expectedFloat=scaled(policy.approvedDrawerFloatBDT,'APPROVED_FLOAT'),
    declaredFloat=scaled(dispatch.leaveFloatBDT,'LEFT_FLOAT');
 if(declaredFloat!==expectedFloat)fail('C01_APPROVED_FLOAT_MISMATCH');
 const byDenom=(rows,label)=>{
  if(rows.length===0||rows.length>40)throw Error('C01_DENOMINATION_ROWS_REQUIRED:'+label);
  const by=new Map();let total=0;
  for(const r of rows){
   const denom=scaled(r?.denominationBDT,label+'_DENOM');
   const quantity=scaled(r?.count,label+'_COUNT',0);
   if(!denom||by.has(denom))throw Error('C01_ZERO_OR_DUPLICATE_DENOMINATION:'+label);
   const line=BigInt(denom)*BigInt(quantity);
   if(line>BigInt(Number.MAX_SAFE_INTEGER)||BigInt(total)+line>BigInt(Number.MAX_SAFE_INTEGER))
    throw Error('C01_DENOMINATION_OVERFLOW:'+label);
   by.set(denom,quantity);total+=Number(line);
  }return {by,total};
 };
 const sent=byDenom(dispatch.denominations,'DISPATCH'),
   received=byDenom(hub.denominations,'HUB');
 if([...sent.by.keys()].some(k=>!received.by.has(k))||
   [...received.by.keys()].some(k=>!sent.by.has(k)))
  fail('C01_HUB_DENOMINATION_SET_INCOMPLETE');
 if(declaredFloat>sent.total)fail('C01_FLOAT_EXCEEDS_COUNTED_CASH');
 const expectedHandover=sent.total-declaredFloat;
 const diff=received.total-expectedHandover;
 if(!Number.isSafeInteger(diff))throw Error('C01_DIFFERENCE_OVERFLOW');
 if(received.total===0)fail('C01_ZERO_HUB_RECOUNT_NOT_SAFE_TO_CLEAR');
 if(diff!==0){
  fail('C01_RECOUNT_DIFFERENCE_REQUIRES_INDEPENDENT_REVIEW');
  if(typeof hub.differenceReason!=='string'||!hub.differenceReason.trim())
   fail('C01_DIFFERENCE_REASON_MISSING');
 }
 // The old C-01 warning is red when c>0 and l!==0; zero hub count
 // does NOT produce this original warning, but the new guard rejects it.
 const originalWarnings=[];
 if(received.total>0&&diff!==0)originalWarnings.push({code:'hub_diff',severity:'red'});
 if(!ledger.ledgerLineRef||!ID.test(ledger.ledgerLineRef))
  fail('C01_CANONICAL_CASHBOOK_LINE_REFERENCE_MISSING');
 if(ledger.entryDirection!=='CASH_RECEIPT')fail('C01_UNKNOWN_CASHBOOK_DIRECTION');
 const declaredLedger=scaled(ledger.amountBDT,'LEDGER_AMOUNT');
 if(diff===0&&declaredLedger!==received.total)
  fail('C01_CASHBOOK_AMOUNT_MISMATCH');
 if(diff!==0)fail('C01_CASHBOOK_RECONCILIATION_ON_HOLD');
 const declaredVoucherCount=scaled(dispatch.vouchersCount,'VOUCHERS_COUNT',0);
 const vouchers=new Set();
 for(const x of dispatch.voucherRefs){const v=ref(x,'VOUCHER');if(vouchers.has(v))throw Error('C01_DUPLICATE_C02_VOUCHER');vouchers.add(v);}
 if(vouchers.size!==declaredVoucherCount)fail('C01_EXPENSE_VOUCHER_ATTACHMENT_COUNT_MISMATCH');
 if(ledger.voucherRefs.length!==vouchers.size||
    ledger.voucherRefs.some(v=>!vouchers.has(v)))
  fail('C01_CASHBOOK_VOUCHER_SOURCE_REFERENCE_MISMATCH');
 const reversalIds=new Set();
 for(const row of corrections){
  scope(row,s,'CORRECTION');
  const x=unique(row.reversalSourceRef,'REVERSAL');
  if(reversalIds.has(x))throw Error('C01_DUPLICATE_CORRECTION');reversalIds.add(x);
  if(row.originalHandoverRef!==dispatch.handoverRef||
     row.originalLedgerRef!==ledger.sourceLedgerRef)
    throw Error('C01_CORRECTION_ORIGINAL_REF_MISMATCH');
  if(!ref(row.makerActor,'CORRECTION_MAKER')||!ref(row.approverActor,'CORRECTION_APPROVER'))throw Error('C01_CORRECTION_ACTOR_INVALID');
  if(row.makerActor===row.approverActor)fail('C01_CORRECTION_SELF_APPROVAL');
  if(typeof row.reason!=='string'||!row.reason.trim())fail('C01_CORRECTION_REASON_MISSING');
  fail('C01_CORRECTION_REQUIRES_SIGNED_AUDIT_AND_REVERSAL');
 }
 const lineage={scope:s,dispatch,hub,ledger,policy,corrections};
 return Object.freeze({source_ids:C01_KEYS.slice(),status:blocks.length?'BLOCK':'SOURCE_RECONCILED_NOT_APPROVED',
  blockers:Object.freeze(blocks),sourceWarnings:Object.freeze(originalWarnings),
  evidence:Object.freeze({countedBDT:bdt(sent.total),leaveFloatBDT:bdt(declaredFloat),
    handoverBDT:bdt(expectedHandover),hubBDT:bdt(received.total),
    varianceBDT:bdt(diff),bookedBDT:bdt(declaredLedger),vouchers:vouchers.size,
    sourceDigest:createHash('sha256').update(JSON.stringify(lineage)).digest('hex'),
    oldSourceBlob:pinned.sourceBlob}),
  sourceRuleVerified:true,syntheticOnly:true,oldSourceExecuted:false,physicalSignaturesVerified:false,
  canonicalSignedMoneyVerified:false,canonicalControlVerified:false,
  signedAuditVerified:false,ownerAccepted:false,canPost:false});
}
module.exports={reconcileCashCustody,assertSource};
