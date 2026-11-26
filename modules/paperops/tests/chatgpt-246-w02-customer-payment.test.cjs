'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {reviewTransfer,assertSource}=require('../field-review/chatgpt-246/w02-customer-payment-source.cjs');
const manifest=require('../field-review/ownership-246-1000.json');
const s={tenantId:'DEMO-TENANT-1',businessId:'DEMO-BIZ-1',siteId:'DEMO-SITE-1'};
const of=x=>({...s,...x});
function fixture(){
 return {scope:{...s,synthetic_only:true},
  transfer:of({sourceRef:'DEMO-W02-SRC',challanRef:'DEMO-CHALLAN1',
    cust_order:'yes',order_no:'DEMO-ORDER1',pay:'cash',cash_amount:'125.50',
    salesDrawerExpenseFree:true}),
  orderEvidence:of({sourceRef:'DEMO-ORDER-REG',orderNo:'DEMO-ORDER1',
    challanRef:'DEMO-CHALLAN1',status:'AUTHORIZED_FOR_TRANSFER'}),
  moneyEvidence:of({sourceRef:'DEMO-MONEY-ENTRY',receiptRef:'DEMO-RECEIPT1',
    accountRef:'DEMO-CASH-ACC',accountRole:'BUSINESS_CASH',
    challanRef:'DEMO-CHALLAN1',mode:'cash',amountBDT:'125.50',
    maker:'DEMO-CASHIER',checker:'DEMO-SUPERVISOR',salesDrawerExpense:false})};
}
function edit(fn){const x=fixture();fn(x);return reviewTransfer(x);}
test('W02 original order and cash visibility is pinned, but source has no req on either field',()=>{
 const x=assertSource();assert.equal(x.oldCodeExecuted,false);
 assert.equal(x.originalOrderNoRequired,false);
 assert.equal(x.originalCashAmountRequired,false);
 assert.deepEqual(x.fields,['W-02:cust_order','W-02:order_no','W-02:pay','W-02:cash_amount']);
 const owned=new Set([...manifest.lane_B_chatgpt.critical_86_keys,
  ...manifest.lane_B_chatgpt.mapped_150_keys,...manifest.lane_B_chatgpt.reserved_next_10_keys]);
 assert.ok(x.fields.every(k=>owned.has(k)));
 const r=edit(()=>{});
 assert.equal(r.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(r.blockers));
 assert.equal(r.evidence.orderNumberFieldVisibleByOldRule,true);
 assert.equal(r.evidence.cashAmountFieldVisibleByOldRule,true);
 assert.equal(r.evidence.provenanceDigest,edit(()=>{}).evidence.provenanceDigest);
 assert.equal(r.canPost,false);assert.equal(r.canonicalMoneyVerified,false);
});
test('W02 source-conditional hidden field and missing visible evidence fail closed',()=>{
 assert.ok(edit(x=>{x.transfer.order_no=''}).blockers.includes('W02_CUSTOMER_ORDER_SOURCE_NUMBER_REQUIRED_BY_REVIEW'));
 assert.ok(edit(x=>{x.orderEvidence=null}).blockers.includes('W02_CUSTOMER_ORDER_REGISTER_EVIDENCE_MISSING'));
 assert.ok(edit(x=>{x.transfer.cash_amount=''}).blockers.includes('W02_CASH_AMOUNT_REQUIRED_BY_STRICT_REVIEW'));
 assert.ok(edit(x=>{x.transfer.cash_amount='0'}).blockers.includes('W02_ZERO_CASH_AMOUNT_REQUIRES_FINANCE_REVIEW'));
 const noOrder=edit(x=>{x.transfer.cust_order='no';x.transfer.order_no='';x.orderEvidence=null});
 assert.equal(noOrder.evidence.orderNumberFieldVisibleByOldRule,false);
 assert.equal(noOrder.status,'REVIEW_READY_NOT_APPROVED');
 assert.ok(edit(x=>{x.transfer.cust_order='no';x.orderEvidence=null})
  .blockers.includes('W02_HIDDEN_ORDER_FIELD_CARRIED_IN_SOURCE'));
});
test('W02 incorrect money mode, source amounts, account and double-role checker hold',()=>{
 assert.ok(edit(x=>{x.moneyEvidence.amountBDT='125.51'})
  .blockers.includes('W02_CASH_SOURCE_MONEY_AMOUNT_MISMATCH'));
 assert.ok(edit(x=>{x.moneyEvidence.mode='credit'})
  .blockers.includes('W02_PAYMENT_PROVENANCE_MODE_OR_CHALLAN_MISMATCH'));
 assert.ok(edit(x=>{x.moneyEvidence.accountRole='SALES_DRAWER'})
  .blockers.includes('W02_CASH_RECEIPT_IN_WRONG_ACCOUNT_KIND'));
 assert.ok(edit(x=>{x.moneyEvidence.checker=x.moneyEvidence.maker})
  .blockers.includes('W02_MONEY_INDEPENDENT_CHECKER_MISSING'));
 assert.ok(edit(x=>{x.transfer.salesDrawerExpenseFree=false})
  .blockers.includes('W02_SALES_DRAWER_EXPENSE_SEPARATION_NOT_ATTESTED'));
 assert.ok(edit(x=>{x.moneyEvidence.salesDrawerExpense=true})
  .blockers.includes('W02_SALES_DRAWER_EXPENSE_CROSS_MODULE_BREACH'));
});
test('W02 external advance and credit are recorded as policy HOLD, not posted or cash',()=>{
 const adv=edit(x=>{x.transfer.pay='adv';x.transfer.cash_amount='';
  x.moneyEvidence.mode='adv';x.moneyEvidence.originalAdvanceRef='DEMO-ORDER-PREPAY'});
 assert.equal(adv.evidence.cashAmountFieldVisibleByOldRule,false);
 assert.ok(adv.blockers.includes('W02_ADVANCE_APPLICATION_REQUIRES_SIGNED_SALES_MONEY_LINK'));
 const credit=edit(x=>{x.transfer.pay='credit';x.transfer.cash_amount='';
  x.moneyEvidence.mode='credit';x.moneyEvidence.creditPolicyRef='DEMO-CREDIT-CTRL'});
 assert.ok(credit.blockers.includes('W02_CREDIT_REQUIRES_SIGNED_APPROVAL_AND_RECEIVABLE'));
 assert.ok(edit(x=>{x.transfer.pay='adv';x.moneyEvidence.mode='adv';x.moneyEvidence.originalAdvanceRef='DEMO-ADV'})
  .blockers.includes('W02_CASH_AMOUNT_WHEN_SOURCE_FIELD_HIDDEN'));
 assert.equal(credit.canPost,false);
});
test('W02 rejects invalid scope, cross-site book, replayed proofs, bogus modes and precision',()=>{
 assert.throws(()=>edit(x=>{x.scope.synthetic_only=false}),/W02_SYNTHETIC_SCOPE_REQUIRED/);
 assert.throws(()=>edit(x=>{x.transfer.businessId='DEMO-OTHER'}),/W02_CROSS_TENANT_BUSINESS_SITE/);
 assert.throws(()=>edit(x=>{x.moneyEvidence.tenantId='DEMO-OTHER'}),/W02_CROSS_TENANT_BUSINESS_SITE/);
 assert.throws(()=>edit(x=>{x.orderEvidence.sourceRef=x.transfer.sourceRef}),/W02_REUSED_SOURCE_PROOF/);
 assert.throws(()=>edit(x=>{x.moneyEvidence.sourceRef=x.orderEvidence.sourceRef}),/W02_REPLAYED_PAYMENT_PROVENANCE/);
 assert.throws(()=>edit(x=>{x.transfer.pay='crypto'}),/W02_UNSUPPORTED_PAYMENT_MODE/);
 assert.throws(()=>edit(x=>{x.transfer.cash_amount='12.345'}),/W02_BAD_MONEY/);
 assert.throws(()=>edit(x=>{x.transfer.cash_amount='9007199254740993'}),/W02_UNSAFE_AMOUNT/);
});
