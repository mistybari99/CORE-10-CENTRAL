'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {reconcileCashCustody,assertSource}=require('../field-review/chatgpt-246/c01-cash-custody.cjs');
const own=require('../field-review/ownership-246-1000.json');
const S={tenantId:'DEMO-T1',businessId:'DEMO-B1',siteId:'DEMO-S1'};
function datum(v={}){return {...S,...v};}
function fixture(){
 return {synthetic_only:true,scope:{...S},
  dispatch:datum({handoverRef:'DEMO-C01-88',sheetRef:'DEMO-R01-1',sealRef:'DEMO-SEAL-88',
   sendEvidenceRef:'DEMO-SEND-PROOF',senderActor:'DEMO-SEND',carrierActor:'DEMO-CARRIER',
   sentAt:'2026-11-23T00:01:00Z',denominations:[
    {denominationBDT:'1000',count:2},{denominationBDT:'500',count:1}],
   leaveFloatBDT:'500',originalSheetEnclosed:true,vouchersCount:2,
   voucherRefs:['DEMO-C02-1','DEMO-C02-2']}),
  hub:datum({handoverRef:'DEMO-C01-88',sealRef:'DEMO-SEAL-88',hubEvidenceRef:'DEMO-HUB-PROOF',
   receiverActor:'DEMO-RECEIVER',countedAt:'2026-11-23T00:02:00Z',
   denominations:[{denominationBDT:'1000',count:2},{denominationBDT:'500',count:0}],
   sealIntact:true,returnCopyAcknowledged:true}),
  ledger:datum({handoverRef:'DEMO-C01-88',dailySourceRef:'DEMO-R01-1',
   sourceLedgerRef:'DEMO-MONEY-EVENT',ledgerLineRef:'DEMO-CB-LINE-1',
   entryDirection:'CASH_RECEIPT',amountBDT:'2000',
   bookedAt:'2026-11-23T00:03:00Z',voucherRefs:['DEMO-C02-1','DEMO-C02-2']}),
  policy:{controlRef:'DEMO-FLOAT-SETTING-V1',approvedDrawerFloatBDT:'500'},
  corrections:[]};
}
const edit=fn=>{const x=fixture();fn(x);return reconcileCashCustody(x);};
test('C01 source exact original count minus float, hub variance, and cashbook backref',()=>{
 assert.equal(assertSource().oldExecuted,false);
 const a=edit(()=>{});
 assert.equal(a.status,'SOURCE_RECONCILED_NOT_APPROVED');
 assert.equal(a.evidence.countedBDT,'2500.00');
 assert.equal(a.evidence.handoverBDT,'2000.00');
 assert.equal(a.evidence.hubBDT,'2000.00');
 assert.equal(a.evidence.varianceBDT,'0.00');
 assert.equal(a.evidence.vouchers,2);
 assert.equal(a.canPost,false);
 assert.equal(a.canonicalSignedMoneyVerified,false);
 assert.equal(a.physicalSignaturesVerified,false);
 assert.ok(a.source_ids.every(id=>[...own.lane_B_chatgpt.critical_86_keys,...own.lane_B_chatgpt.mapped_150_keys].includes(id)));
 assert.equal(a.evidence.sourceDigest,edit(()=>{}).evidence.sourceDigest);
});
test('C01 red original hub_diff warning remains separate from stricter review hold',()=>{
 const x=edit(o=>{o.hub.denominations[0].count=1});
 assert.deepEqual(x.sourceWarnings,[{code:'hub_diff',severity:'red'}]);
 assert.equal(x.status,'BLOCK');
 assert.ok(x.blockers.includes('C01_RECOUNT_DIFFERENCE_REQUIRES_INDEPENDENT_REVIEW'));
 assert.ok(x.blockers.includes('C01_DIFFERENCE_REASON_MISSING'));
 assert.ok(x.blockers.includes('C01_CASHBOOK_RECONCILIATION_ON_HOLD'));
 const z=edit(o=>{o.hub.denominations[0].count=0});
 assert.equal(z.sourceWarnings.length,0,'original zero-hub runtime suppresses legacy flag');
 assert.ok(z.blockers.includes('C01_ZERO_HUB_RECOUNT_NOT_SAFE_TO_CLEAR'));
});
test('C01 ledger source, float policy and independent roles cannot silently diverge',()=>{
 assert.throws(()=>edit(o=>{o.ledger.dailySourceRef='DEMO-WRONG'}),/CASHBOOK_DAILY_SOURCE_MISMATCH/);
 assert.throws(()=>edit(o=>{o.hub.handoverRef='OTHER-C01'}),/HANDOVER_SOURCE_REF_MISMATCH/);
 const floatMismatch=edit(o=>{o.policy.approvedDrawerFloatBDT='1000'});
 assert.ok(floatMismatch.blockers.includes('C01_APPROVED_FLOAT_MISMATCH'));
 assert.deepEqual(floatMismatch.sourceWarnings,[{code:'float_mismatch',severity:'yellow'}]);
 assert.ok(edit(o=>{o.hub.receiverActor=o.dispatch.senderActor}).blockers.includes('C01_INDEPENDENT_SENDER_CARRIER_RECEIVER_REQUIRED'));
 assert.ok(edit(o=>{o.ledger.amountBDT='1900'}).blockers.includes('C01_CASHBOOK_AMOUNT_MISMATCH'));
 assert.ok(edit(o=>{o.hub.sealIntact=false}).blockers.includes('C01_SEAL_INTEGRITY_NOT_PROVED'));
 assert.ok(edit(o=>{o.ledger.voucherRefs=['DEMO-C02-1']}).blockers.includes('C01_CASHBOOK_VOUCHER_SOURCE_REFERENCE_MISMATCH'));
 assert.ok(edit(o=>{o.hub.countedAt='2026-11-22T23:58:00Z'}).blockers.includes('C01_CUSTODY_TO_LEDGER_TIME_ORDER_INVALID'));
});
test('C01 rejects duplicate/replay, cross-tenant, precision, extra voucher refs and missing proof',()=>{
 assert.throws(()=>edit(o=>{o.hub.tenantId='DEMO-T2'}),/CROSS_TENANT_BUSINESS_SITE/);
 assert.throws(()=>edit(o=>{o.ledger.siteId='DEMO-S2'}),/CROSS_TENANT_BUSINESS_SITE/);
 assert.throws(()=>edit(o=>{o.dispatch.voucherRefs.push('DEMO-C02-1')}),/DUPLICATE_C02_VOUCHER/);
 assert.throws(()=>edit(o=>{o.dispatch.denominations[0].count='2.1'}),/INVALID_NUMBER/);
 assert.throws(()=>edit(o=>{o.dispatch.denominations[0].count='9007199254740993'}),/NUMBER_OVERFLOW/);
 assert.throws(()=>edit(o=>{o.dispatch.denominations[1].denominationBDT='1000'}),/ZERO_OR_DUPLICATE_DENOMINATION/);
 assert.throws(()=>edit(o=>{o.hub.hubEvidenceRef=o.dispatch.sendEvidenceRef}),/DUPLICATE_OR_REPLAYED_SOURCE_REF/);
 assert.throws(()=>edit(o=>{o.ledger.ledgerLineRef=o.ledger.sourceLedgerRef}),/DUPLICATE_OR_REPLAYED_SOURCE_REF/);
 assert.throws(()=>edit(o=>{o.synthetic_only=false}),/SYNTHETIC_SCOPE_ONLY/);
});
test('C01 correction is a proposed controlled reversal, never an unlogged direct edit',()=>{
 const revised=edit(o=>{o.corrections=[datum({reversalSourceRef:'DEMO-REV1',
  originalHandoverRef:o.dispatch.handoverRef,originalLedgerRef:o.ledger.sourceLedgerRef,
  makerActor:'DEMO-MAKER',approverActor:'DEMO-APPROVER',reason:'Synthetic recount dispute'})]});
 assert.ok(revised.blockers.includes('C01_CORRECTION_REQUIRES_SIGNED_AUDIT_AND_REVERSAL'));
 assert.equal(revised.canPost,false);
 assert.ok(edit(o=>{o.corrections=[datum({reversalSourceRef:'DEMO-REV2',
 originalHandoverRef:o.dispatch.handoverRef,originalLedgerRef:o.ledger.sourceLedgerRef,
 makerActor:'DEMO-SAME',approverActor:'DEMO-SAME',reason:'test'})]})
 .blockers.includes('C01_CORRECTION_SELF_APPROVAL'));
 assert.throws(()=>edit(o=>{o.corrections=[datum({reversalSourceRef:'DEMO-REV3',
 originalHandoverRef:'WRONG',originalLedgerRef:o.ledger.sourceLedgerRef,
 makerActor:'DEMO-OTHER',approverActor:'DEMO-APPROVER',reason:'test'})]}),/CORRECTION_ORIGINAL_REF_MISMATCH/);
});
