'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {reconcileDay,assertSource}=require('../field-review/chatgpt-246/r01-money-day-ledger.cjs');
const manifest=require('../field-review/ownership-246-1000.json');
const S={tenantId:'DEMO-TENANT',businessId:'DEMO-BIZ',siteId:'DEMO-S1'};
const at=x=>({...S,...x});
function f(){
 return {scope:{...S,synthetic_only:true},
  day:at({dayRef:'DEMO-R01-001',cashbookRef:'DEMO-CASHBOOK-01',businessDate:'2026-11-23',
   drawerExpenseFree:true}),
  accountProvider:at({sourceRef:'DEMO-C02-ACCOUNTS',capability:'expense_10_2',
   hasAccounts:true,options:[
    at({accountId:'DEMO-IMPREST-ACC',sourceRef:'DEMO-ACC-OPT',role:'IMPREST_CASH',
     action:'expense_10_2',status:'ACTIVE',canExpense:true})]}),
  control:at({sourceRef:'DEMO-CONTROL-SNAPSHOT',floatControlRef:'DEMO-FLOAT-POLICY',
   imprestControlRef:'DEMO-IMP-POLICY',fixedImprestBDT:'1000',approvedFloatBDT:'500'}),
  opening:at({imprestCashBDT:'900',imprestReceiptsBDT:'100',drawerCountBDT:'500'}),
  sourceVouchers:[at({sourceRef:'DEMO-C02-DOC1',voucherRef:'DEMO-C02-1',
   dayRef:'DEMO-R01-001',cashbookRef:'DEMO-CASHBOOK-01',
   money_account_id:'DEMO-IMPREST-ACC',pay_mode:'cash',amountBDT:'200',
   drawerUntouched:true,receiptAttached:true,receiptProofRef:'DEMO-RECEIPT1',
   preparedBy:'DEMO-MAKER',checkedBy:'DEMO-CHECKER'})],
  sourceMoneyEvents:[],
  ledgerRows:[at({entryRef:'DEMO-BOOK-LINE1',sourceEventRef:'DEMO-C02-DOC1',
   cashbookRef:'DEMO-CASHBOOK-01',dayRef:'DEMO-R01-001',
   accountId:'DEMO-IMPREST-ACC',amountBDT:'200',direction:'OUT',
   enteredBy:'DEMO-CLERK',checkedBy:'DEMO-SUPERVISOR'})],
  declaredClose:at({floatSetBDT:'500',vTotalBDT:'200',advanceTakenBDT:'0',
   imprestCashBDT:'700',imprestReceiptsBDT:'300',drawerExpenseFree:true})};
}
const edit=fun=>{const v=f();fun(v);return reconcileDay(v);};
function addAdvance(v){
 v.sourceMoneyEvents.push(at({kind:'ORDER_ADVANCE',sourceRef:'DEMO-ADV-1',
  dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,orderRef:'DEMO-ORDER-12',
  accountId:'DEMO-SALES-DRAWER',amountBDT:'50',evidenceRef:'DEMO-MONEY-RECEIPT',
  makerActor:'DEMO-SELLER',checkerActor:'DEMO-CASHIER'}));
 v.ledgerRows.push(at({entryRef:'DEMO-BOOK-LINE2',sourceEventRef:'DEMO-ADV-1',
  dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,accountId:'DEMO-SALES-DRAWER',
  amountBDT:'50',direction:'IN',enteredBy:'DEMO-CLERK',checkedBy:'DEMO-SUPERVISOR'}));
 v.declaredClose.advanceTakenBDT='50';
}
test('R01 original owned expense sum, imprest, float and advance fields are pinned, no legacy execution',()=>{
 const p=assertSource();assert.equal(p.oldExecuted,false);
 assert.ok(p.fields.every(x=>[...manifest.lane_B_chatgpt.critical_86_keys,
 ...manifest.lane_B_chatgpt.mapped_150_keys,
 ...manifest.lane_B_chatgpt.reserved_next_10_keys].includes(x)));
 assert.ok(!p.fields.includes('R-01:refund'));
 assert.ok(!p.fields.includes('R-01:midday_hub'));
 const r=edit(()=>{});
 assert.equal(r.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(r.blockers));
 assert.deepEqual(r.blockers,[]);
 assert.equal(r.evidence.dailyExpenseBDT,'200.00');
 assert.equal(r.evidence.imprestCashBDT,'700.00');
 assert.equal(r.evidence.imprestReceiptsBDT,'300.00');
 assert.equal(r.evidence.fixedImprestBDT,'1000.00');
 assert.equal(r.canonicalMoneyLedgerVerified,false);assert.equal(r.canPost,false);
 assert.equal(r.evidence.sourceDigest,edit(()=>{}).evidence.sourceDigest);
});
test('R01 C02 signed account-shaped source voucher -> cashbook must match; advances stay outside imprest',()=>{
 const r=edit(addAdvance);
 assert.equal(r.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(r.blockers));
 assert.equal(r.evidence.sourceAdvanceBDT,'50.00');
 assert.equal(r.evidence.cashbookRows,2);
 assert.equal(r.evidence.imprestCashBDT,'700.00','external advances never replenish imprest');
 assert.ok(edit(v=>{addAdvance(v);v.declaredClose.advanceTakenBDT='40'})
   .blockers.includes('R01_ADVANCE_SOURCE_TO_DAILY_TOTAL_MISMATCH'));
 assert.ok(edit(v=>{addAdvance(v);v.sourceMoneyEvents[0].accountId='DEMO-IMPREST-ACC';
  v.ledgerRows[1].accountId='DEMO-IMPREST-ACC'})
 .blockers.includes('R01_ADVANCE_MUST_NOT_ENTER_IMPREST'));
});
test('R01 voucher source and ledger exceptions: amounts, missing events, wrong day and account',()=>{
 assert.ok(edit(v=>{v.declaredClose.vTotalBDT='199'})
  .blockers.includes('R01_C02_VOUCHER_TO_DAILY_TOTAL_MISMATCH'));
 assert.ok(edit(v=>{v.ledgerRows[0].amountBDT='199'})
  .blockers.includes('R01_CASHBOOK_SOURCE_AMOUNT_MISMATCH:DEMO-C02-DOC1'));
 assert.ok(edit(v=>{v.ledgerRows=[]})
  .blockers.includes('R01_CASHBOOK_SOURCE_ROW_MISSING:DEMO-C02-DOC1'));
 assert.throws(()=>edit(v=>{v.ledgerRows[0].accountId='DEMO-ANOTHER'}),/CASHBOOK_ACCOUNT_OR_DIRECTION_MISMATCH/);
 assert.throws(()=>edit(v=>{v.sourceVouchers[0].dayRef='DEMO-YESTERDAY'}),/C02_DAILY_REF_MISMATCH/);
 assert.throws(()=>edit(v=>{v.ledgerRows[0].sourceEventRef='DEMO-UNKNOWN'}),/UNBACKED_CASHBOOK_EVENT/);
 assert.throws(()=>edit(v=>{v.ledgerRows.push({...v.ledgerRows[0],entryRef:'DEMO-BOOK-LINE-DUP'})}),/DUPLICATE_POSTING_OF_SOURCE_EVENT/);
});
test('R01 cash/book integrity: accounts, drawer, multiple actors and fixed policy',()=>{
 assert.ok(edit(v=>{v.opening.drawerCountBDT='499'}).blockers.includes('R01_OPEN_DRAWER_FLOAT_DIFFERENCE'));
 assert.ok(edit(v=>{v.control.fixedImprestBDT='999'}).blockers.includes('R01_OPEN_IMPREST_NOT_BALANCED'));
 assert.ok(edit(v=>{v.declaredClose.imprestCashBDT='699'})
  .blockers.includes('R01_C02_IMPREST_CASH_RECEIPT_CONTINUITY_MISMATCH'));
 assert.ok(edit(v=>{v.declaredClose.floatSetBDT='600'})
  .blockers.includes('R01_FLOAT_SETTING_SOURCE_MISMATCH'));
 assert.ok(edit(v=>{v.sourceVouchers[0].receiptAttached=false})
  .blockers.includes('R01_C02_RECEIPT_EVIDENCE_REQUIRED:DEMO-C02-1'));
 assert.ok(edit(v=>{v.sourceVouchers[0].pay_mode='bank'})
  .blockers.includes('R01_NONCASH_C02_REQUIRES_SEPARATE_SIGNED_BOOK'));
 assert.ok(edit(v=>{v.sourceVouchers[0].checkedBy=v.sourceVouchers[0].preparedBy})
  .blockers.includes('R01_C02_INDEPENDENT_VOUCHER_ACTORS_REQUIRED:DEMO-C02-1'));
 assert.ok(edit(v=>{v.declaredClose.drawerExpenseFree=false})
  .blockers.includes('R01_SALES_DRAWER_EXPENSE_PROHIBITION_UNPROVEN'));
});
test('R01 external refund/deposit/reversal are integrity-reviewed but NOT Codex-owned R01 field calculations',()=>{
 const r=edit(v=>{addAdvance(v);
  v.sourceMoneyEvents.push(at({kind:'CUSTOMER_REFUND',sourceRef:'DEMO-REF1',
    originalAdvanceRef:'DEMO-ADV-1',dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,
    amountBDT:'20',accountId:'DEMO-SALES-DRAWER',evidenceRef:'DEMO-REFUND-RECEIPT',
    makerActor:'DEMO-MAKER',checkerActor:'DEMO-CHECKER'}));
  v.ledgerRows.push(at({entryRef:'DEMO-BOOK-LINE3',sourceEventRef:'DEMO-REF1',
   dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,amountBDT:'20',
   accountId:'DEMO-SALES-DRAWER',direction:'OUT',
   enteredBy:'DEMO-BOOK-MAKER',checkedBy:'DEMO-BOOK-CHECKER'}));});
 assert.ok(r.blockers.includes('R01_EXTERNAL_REFUND_NEEDS_SIGNED_MONEY_POLICY'));
 assert.equal(r.canPost,false);
 assert.throws(()=>edit(v=>{addAdvance(v);
  v.sourceMoneyEvents.push(at({kind:'CUSTOMER_REFUND',sourceRef:'DEMO-REFX',
   originalAdvanceRef:'DEMO-ADV-1',dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,
   amountBDT:'51',accountId:'DEMO-SALES-DRAWER',evidenceRef:'DEMO-X',
   makerActor:'DEMO-M1',checkerActor:'DEMO-M2'}));}),/REFUND_EXCEEDS_ORIGINAL_ADVANCE/);
 assert.throws(()=>edit(v=>{addAdvance(v);
  v.sourceMoneyEvents.push(at({kind:'CUSTOMER_REFUND',sourceRef:'DEMO-CROSS-ACCOUNT-REF',
   originalAdvanceRef:'DEMO-ADV-1',dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,
   amountBDT:'10',accountId:'DEMO-FOREIGN-ACCOUNT',evidenceRef:'DEMO-REF-PROOF',
   makerActor:'DEMO-M1',checkerActor:'DEMO-M2'}));}),
  /REFUND_MONEY_ACCOUNT_DIFFERS_FROM_ADVANCE/);
 const deposit=edit(v=>{v.sourceMoneyEvents.push(at({kind:'BANK_DEPOSIT',sourceRef:'DEMO-DP1',
   destinationAccountRef:'DEMO-BANK-01',dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,
   amountBDT:'40',accountId:'DEMO-SALES-DRAWER',evidenceRef:'DEMO-BANK-SLIP',
   makerActor:'DEMO-CASHIER',checkerActor:'DEMO-BANKER'}));});
 assert.ok(deposit.blockers.includes('R01_EXTERNAL_DEPOSIT_NEEDS_BANK_CONFIRMATION'));
 assert.ok(deposit.blockers.includes('R01_CASHBOOK_SOURCE_ROW_MISSING:DEMO-DP1'));
 const reversal=edit(v=>{v.sourceMoneyEvents.push(at({kind:'REVERSAL',sourceRef:'DEMO-REV1',
   originalEventRef:'DEMO-C02-DOC1',dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,
   amountBDT:'200',accountId:'DEMO-IMPREST-ACC',evidenceRef:'DEMO-REV-EVID',
   makerActor:'DEMO-MAKER',checkerActor:'DEMO-CHECKER',reason:'Duplicate submitted'}));
  v.ledgerRows.push(at({entryRef:'DEMO-BOOK-REV',sourceEventRef:'DEMO-REV1',
   dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,accountId:'DEMO-IMPREST-ACC',
   amountBDT:'200',direction:'IN',enteredBy:'DEMO-S1',checkedBy:'DEMO-S2'}));});
 assert.ok(reversal.blockers.includes('R01_REVERSAL_REQUIRES_SIGNED_APPROVAL_AND_AUDIT'));
 assert.equal(reversal.signedReversalVerified,false);
});
test('R01 invalid/replayed records, cross-tenant/source, precision and impossible cash are fail-closed',()=>{
 assert.throws(()=>edit(v=>{v.scope.synthetic_only=false}),/SYNTHETIC_ONLY/);
 assert.throws(()=>edit(v=>{v.sourceVouchers[0].tenantId='OTHER'}),/CROSS_SCOPE/);
 assert.throws(()=>edit(v=>{v.ledgerRows[0].siteId='DEMO-OTHER-SITE'}),/CROSS_SCOPE/);
 assert.throws(()=>edit(v=>{v.sourceVouchers[0].amountBDT='200.001'}),/INVALID_MONEY/);
 assert.throws(()=>edit(v=>{v.sourceVouchers[0].amountBDT='9007199254740993'}),/UNSAFE_MONEY/);
 assert.throws(()=>edit(v=>{v.sourceVouchers[0].sourceRef=v.day.dayRef}),/DUPLICATE_OR_REPLAYED_SOURCE_EVENT/);
 assert.ok(edit(v=>{v.sourceVouchers[0].amountBDT='950'})
  .blockers.includes('R01_IMPREST_CASH_OVERDRAWN'));
 assert.throws(()=>edit(v=>{v.sourceMoneyEvents.push(at({kind:'CUSTOMER_REFUND',
   sourceRef:'DEMO-UNLINKED-REF',originalAdvanceRef:'DEMO-NO-ADVANCE',
   dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,
   amountBDT:'10',accountId:'DEMO-SALES-DRAWER',evidenceRef:'DEMO-REF-PROOF',
   makerActor:'DEMO-MAKER',checkerActor:'DEMO-CHECKER'}));}),/REFUND_WITHOUT_KNOWN_ADVANCE/);
});

test('R01 repeated C02 voucher receipts and duplicate external Money evidence cannot masquerade as independent proof',()=>{
 assert.throws(()=>edit(v=>{
  v.sourceVouchers.push(at({...v.sourceVouchers[0],
   sourceRef:'DEMO-C02-DOC2',voucherRef:'DEMO-C02-2',receiptProofRef:'DEMO-RECEIPT1'}));
 }),/R01_REPLAYED_C02_RECEIPT_PROOF/);
 assert.throws(()=>edit(v=>{
  addAdvance(v);
  v.sourceMoneyEvents.push(at({kind:'BANK_DEPOSIT',sourceRef:'DEMO-DUP-PROOF-DP',
   destinationAccountRef:'DEMO-BANK',dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,
   amountBDT:'10',accountId:'DEMO-SALES-DRAWER',
   evidenceRef:'DEMO-MONEY-RECEIPT',makerActor:'DEMO-MAKER',checkerActor:'DEMO-CHECKER'}));
 }),/R01_DUPLICATE_EXTERNAL_MONEY_EVIDENCE/);
 assert.throws(()=>edit(v=>{
  v.sourceMoneyEvents.push(at({kind:'ORDER_ADVANCE',sourceRef:'DEMO-A1',
   dayRef:v.day.dayRef,cashbookRef:v.day.cashbookRef,orderRef:'DEMO-O1',
   accountId:'DEMO-SALES-DRAWER',amountBDT:'1',
   evidenceRef:'DEMO-RECEIPT1',makerActor:'DEMO-MAKER',checkerActor:'DEMO-CHECKER'}));
 }),/R01_DUPLICATE_EXTERNAL_MONEY_EVIDENCE/);
});
