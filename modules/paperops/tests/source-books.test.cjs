'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const books=require('../source-books.cjs');
const fixture=require('../source-books-fixture.json');
const demo=require('../source-books-demo.cjs');
const clone=x=>structuredClone(x);
function packagingEdit(fn){
 const x=clone(fixture.packaging);fn(x);return books.packagingLedger(x);
}
function expenseEdit(fn){
 const x=clone(fixture.expense);fn(x);return books.expenseCashbookReconcile(x);
}
test('source books: full synthetic W-02 crates/trays open, issue, partial return and outstanding reconciled',()=>{
 const r=books.packagingLedger(fixture.packaging);
 assert.equal(r.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(r.blockers));
 assert.equal(r.entries.length,5);
 assert.deepEqual(r.balances,[{pair:'DEMO-FACTORY-01>DEMO-SHOP-01',crates:3,trays:6}]);
 assert.deepEqual(r.entries.map(x=>x.cratesOutstanding),[2,7,5,6,3]);
 assert.deepEqual(r.entries.map(x=>x.traysOutstanding),[4,12,9,11,6]);
 assert.equal(r.erpPosted,false);
 assert.equal(r.signaturesPhysicallyVerified,false);
 assert.equal(r.sourceParityCertified,false);
 assert.equal(r.ownerAccepted,false);
});
test('source books: old handwritten W-02 crates_due/trays_due cannot disagree with calculated source movements',()=>{
 const r=packagingEdit(x=>{x.events[2].declaredOutstanding.crates='999'});
 assert.equal(r.status,'BLOCK');
 assert.ok(r.blockers.includes('W02_ORIGINAL_OUTSTANDING_MISMATCH:DEMO-PK-RET1'));
 assert.equal(r.entries[2].declaredOutstandingMatched,false);
 assert.equal(r.erpPosted,false);
});
test('source books: W-02 duplicate challans, repeated opening, over-return and wrong issue links fail closed',()=>{
 assert.throws(()=>packagingEdit(x=>{x.events[1].sourceRef=x.events[0].sourceRef}),
  /DUPLICATE_PACKAGING_EVENT_OR_CHALLAN/);
 assert.throws(()=>packagingEdit(x=>{x.events[2].crates='6'}),/RETURN_EXCEEDS_ISSUED_PACKAGING/);
 assert.throws(()=>packagingEdit(x=>{x.events[2].originalIssueId='DEMO-MISSING'}),
  /UNKNOWN_OR_CROSS_PAIR_ORIGINAL_ISSUE/);
 assert.throws(()=>packagingEdit(x=>{x.events[1].type='OPENING';x.events[1].sourceKind='SIGNED_LEGACY_OPENING_CARRY_FORWARD'}),
  /OPENING_ALREADY_RECORDED_FOR_PAIR/);
 assert.throws(()=>packagingEdit(x=>{x.events[0].declaredOutstanding=undefined}),
  /ORIGINAL_W02_OUTSTANDING_SOURCE_VALUES_REQUIRED/);
 assert.throws(()=>packagingEdit(x=>{x.events[0].crates='-1'}),
  /INVALID_QUANTITY_OR_MONEY/);
});
test('source books: W-02 enforce separate custody roles, two separate sites, evidence and tenant scope',()=>{
 assert.throws(()=>packagingEdit(x=>{x.events[0].receiverId=x.events[0].senderId}),
  /INDEPENDENT_SIGNERS_REQUIRED/);
 assert.throws(()=>packagingEdit(x=>{x.events[1].toSiteId=x.events[1].fromSiteId}),
  /INVALID_PACKAGING_SITE_PAIR/);
 assert.throws(()=>packagingEdit(x=>{x.events[1].tenantId='OTHER-TENANT'}),
  /CROSS_TENANT_OR_BUSINESS_REFERENCE/);
 assert.throws(()=>packagingEdit(x=>{x.events[1].senderProofRef=''}),
  /INVALID_SENDER_PROOF/);
 assert.throws(()=>packagingEdit(x=>{x.events[0].sourceKind='UNVERIFIED_OPENING'}),
  /SIGNED_OPENING_PROVENANCE_REQUIRED/);
});
test('source books: synthetic C-02 source vouchers -> cashbook -> R-01 daily total and imprest continuity',()=>{
 const r=books.expenseCashbookReconcile(fixture.expense);
 assert.equal(r.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(r.blockers));
 assert.equal(r.voucherCount,2);
 assert.deepEqual(r.totals,{
  originalVoucherBDT:'170.00',r01ExpenseBDT:'170.00',cashbookExpenseBDT:'170.00',
  imprestCashNowBDT:'830.00',imprestReceiptsTotalBDT:'170.00',fixedImprestBDT:'1000.00'
 });
 assert.equal(r.erpPosted,false);
 assert.equal(r.actualCashCountCertified,false);
 assert.equal(r.sourceParityCertified,false);
 assert.equal(r.ownerAccepted,false);
 assert.equal(demo.run().status,'SYNTHETIC_SOURCE_BOOKS_MATCH_NOT_APPROVED');
 assert.equal(demo.run().readyForERPPosting,false);
});
test('source books: wrong source voucher cash snapshot, receipts and daily totals block; no silent adjustments',()=>{
 let r=expenseEdit(x=>{x.vouchers[1].cashNowBDT='840'});
 assert.equal(r.status,'BLOCK');assert.ok(r.blockers.includes('C02_VOUCHER_CASH_SNAPSHOT_MISMATCH:DEMO-C02-002'));
 r=expenseEdit(x=>{x.vouchers[0].receiptsTotalBDT='110'});
 assert.ok(r.blockers.includes('C02_VOUCHER_RECEIPTS_SNAPSHOT_MISMATCH:DEMO-C02-001'));
 r=expenseEdit(x=>{x.dailyClose.vTotalBDT='160'});
 assert.ok(r.blockers.includes('R01_DAILY_TOTAL_EXPENSE_MISMATCH'));
 r=expenseEdit(x=>{x.dailyClose.imprestCashNowBDT='800'});
 assert.ok(r.blockers.includes('C02_R01_IMPREST_CONTINUITY_MISMATCH'));
});
test('source books: duplicate R-01 or cashbook refs, missing C-02 source, mismatched book amount fail closed',()=>{
 assert.throws(()=>expenseEdit(x=>{x.cashbookRows[1].sourceVoucherId=x.cashbookRows[0].sourceVoucherId}),
  /DUPLICATE_CASHBOOK_POSTING_OR_SOURCE/);
 assert.throws(()=>expenseEdit(x=>{x.dailyClose.voucherRows.push(x.dailyClose.voucherRows[0])}),
  /DUPLICATE_R01_VOUCHER_REFERENCE/);
 assert.throws(()=>expenseEdit(x=>{x.cashbookRows[0].sourceVoucherId='DEMO-UNKNOWN'}),
  /UNBACKED_CASHBOOK_EXPENSE_SOURCE/);
 const r=expenseEdit(x=>{x.cashbookRows[0].amountBDT='100'});
 assert.ok(r.blockers.includes('CASHBOOK_VOUCHER_AMOUNT_MISMATCH:DEMO-C02-001'));
 assert.ok(r.blockers.includes('DAILY_CASHBOOK_TOTAL_MISMATCH'));
});
test('source books: must not infer real accounts, signatures, receipt proof or unsanctioned financial limits',()=>{
 assert.throws(()=>expenseEdit(x=>{x.cashbookRows[0].tenantId='REAL-TENANT'}),
  /CROSS_TENANT_OR_BUSINESS_REFERENCE/);
 assert.throws(()=>expenseEdit(x=>{x.vouchers[0].paidBy=x.vouchers[0].preparedBy}),
  /INDEPENDENT_SIGNERS_REQUIRED/);
 assert.throws(()=>expenseEdit(x=>{x.vouchers[0].lines[1].receiptRef='DEMO-RECEIPT-001'}),
  /DUPLICATE_RECEIPT_PROOF_REFERENCE/);
 assert.throws(()=>expenseEdit(x=>{x.dailyClose.salesDrawerUntouched=false}),
  /SALES_DRAWER_AND_IMPREST_MUST_BE_SEPARATE/);
 assert.throws(()=>expenseEdit(x=>{x.vouchers[0].cashAccountId='DEMO-OTHER'}),
  /VOUCHER_CASH_ACCOUNT_SCOPE_MISMATCH/);
 let r=expenseEdit(x=>{x.vouchers[1].lines[0].receipt='no';delete x.vouchers[1].lines[0].receiptRef});
 assert.equal(r.status,'BLOCK');assert.ok(r.blockers.some(x=>x.includes('MISSING_RECEIPT_REQUIRES_REVIEW')));
 r=expenseEdit(x=>{x.vouchers[0].approvedExpenseMax='40'});
 assert.ok(r.blockers.some(x=>x.includes('OVER_LIMIT_EXPENSE_REQUIRES_REVIEW')));
});
test('source books: fail closed on unknown noncash branch, excess spending, precision and duplicate source voucher',()=>{
 let r=expenseEdit(x=>{x.vouchers[0].payMode='bank'});
 assert.equal(r.status,'BLOCK');
 assert.ok(r.blockers.includes('NONCASH_EXPENSE_BRANCH_NOT_YET_PROVEN:DEMO-C02-001'));
 assert.throws(()=>expenseEdit(x=>{x.vouchers[1].id=x.vouchers[0].id}),
  /DUPLICATE_EXPENSE_SOURCE_VOUCHER/);
 assert.throws(()=>expenseEdit(x=>{x.vouchers[0].lines[0].amountBDT='70.001'}),
  /INVALID_QUANTITY_OR_MONEY/);
 assert.throws(()=>expenseEdit(x=>{x.openingCashBDT='120'}),
  /OPENING_IMPREST_NOT_BALANCED/);
 assert.throws(()=>expenseEdit(x=>{x.vouchers[1].lines[0].amountBDT='9999'}),
  /SOURCE_IMPREST_CASH_EXHAUSTED/);
 const copy=clone(fixture);copy.synthetic_only=false;
 assert.throws(()=>demo.run(copy),/SYNTHETIC_FIXTURE_ONLY/);
});
