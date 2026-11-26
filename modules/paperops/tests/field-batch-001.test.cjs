'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const checks=require('../field-batch-001-checks.js');
const expense={
 voucherRef:'EXP-001',sheetNo:'R01-001',preparedBy:'Cashier',paidBy:'Keeper',
 drawerUntouched:true,payMode:'cash',approvedExpenseMax:'100',expenseLimitPolicyRef:'EXP-POL-01',
 approvedImprest:'1000',imprestPolicyRef:'IMP-01',cashNow:'880',receiptsTotal:'120',
 lines:[{head:'Cleaning',to:'Supply shop',receipt:'yes',receiptRef:'RCPT-001',amount:'70'},
  {head:'Packaging',to:'Stationery',receipt:'yes',receiptRef:'RCPT-002',amount:'50'}]
};
const cash={
 closingRef:'R01-001',sealRef:'BAG-001',ledgerRef:'CASH-LEDGER-1',ledgerLine:'L01',
 carrier:'Driver',sentBy:'Cashier',receivedBy:'Hub checker',sheetAttached:true,
 floatLeft:'500',approvedFloat:'500',sealIntact:true,
 denominations:[{denomination:'1000',sentCount:'2',hubCount:'2'},
  {denomination:'500',sentCount:'1',hubCount:'0'}]
};
const transfer={
 challanRef:'W02-001',fromLocation:'Factory',toLocation:'Showroom',
 sentBy:'Factory keeper',receivedBy:'Shop receiver',productionDatesWritten:true,
 gradesWritten:true,outsideDemand:false,customerOrder:false,
 lines:[{item:'Rasgulla',productionDate:'2026-11-22',grade:'G1',
   sentQty:'15',receivedQty:'15',demandQty:'15'}]
};
function hasFlag(fn,input,expected){
 const v=fn(input);
 assert.equal(v.status,'BLOCK');
 assert.equal(v.authorized,false);
 assert.equal(v.fieldParityConfirmed,false);
 assert.ok(v.blockers.includes(expected),expected+' not in '+JSON.stringify(v.blockers));
}
test('source C-02 expense matches allowed limit and imprest precisely',()=>{
 const r=checks.expenseVoucher(expense);
 assert.equal(r.source,'C-02');assert.equal(r.status,'REVIEW_READY_NOT_APPROVED');
 assert.deepEqual(r.blockers,[]);
 assert.equal(r.evidence.expenseTotalBDT,'120.00');
 assert.equal(r.evidence.cashPlusReceiptsBDT,'1000.00');
 assert.equal(r.erpPosted,false);
});
test('C-02 all five source flag categories: limit, approver, missing receipt/reason, imprest',()=>{
 hasFlag(checks.expenseVoucher,{...expense,lines:[{head:'Packaging',to:'Vendor',receipt:'yes',receiptRef:'R',amount:'101'}]},
  'OVER_LIMIT_EXPENSE_REQUIRES_REVIEW');
 hasFlag(checks.expenseVoucher,{...expense,lines:[{head:'Packaging',to:'Vendor',receipt:'yes',receiptRef:'R',amount:'101'}]},
  'OVER_LIMIT_INDEPENDENT_APPROVAL_MISSING');
 hasFlag(checks.expenseVoucher,{...expense,lines:[{head:'Packaging',to:'Vendor',receipt:'no',amount:'50'}]},
  'MISSING_RECEIPT_REQUIRES_REVIEW');
 hasFlag(checks.expenseVoucher,{...expense,lines:[{head:'Packaging',to:'Vendor',receipt:'no',amount:'50'}]},
  'RECEIPT_REASON_MISSING');
 hasFlag(checks.expenseVoucher,{...expense,cashNow:'870'},'IMPREST_MISMATCH');
});
test('C-02 never silently invents expense_max, imprest, account or a sales-drawer exception',()=>{
 const {approvedExpenseMax,...noMax}=expense;
 hasFlag(checks.expenseVoucher,noMax,'EXPENSE_MAX_POLICY_REQUIRED');
 const {approvedImprest,...noImprest}=expense;
 hasFlag(checks.expenseVoucher,noImprest,'IMPREST_POLICY_REQUIRED');
 hasFlag(checks.expenseVoucher,{...expense,drawerUntouched:false},'SALES_DRAWER_NOT_CONFIRMED_UNTOUCHED');
 hasFlag(checks.expenseVoucher,{...expense,payMode:'bank',moneyAccountId:'BANK-01'},'NONCASH_SOURCE_ACCOUNT_PROOF_REQUIRED');
 hasFlag(checks.expenseVoucher,{...expense,lines:[{head:'Travel',to:'Driver',receipt:'yes',amount:'50'}]},'RECEIPT_PROOF_REFERENCE_REQUIRED:0');
 const extra={...expense,approvedBy:'Boss',approvalRef:'APR-01',lines:[{head:'X',to:'Vendor',receipt:'yes',receiptRef:'R',amount:'101'}]};
 // Even an independently authorized over-limit expense remains flagged for manual review.
 assert.equal(checks.expenseVoucher(extra).status,'BLOCK');
});
test('C-01 derives sender float, counted total, handover and independently counted hub cash',()=>{
 const r=checks.cashDenominations(cash);
 assert.equal(r.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(r.blockers));
 assert.equal(r.evidence.countedTotalBDT,'2500.00');
 assert.equal(r.evidence.handoverBDT,'2000.00');
 assert.equal(r.evidence.hubReceivedBDT,'2000.00');
 assert.equal(r.evidence.differenceBDT,'0.00');
});
test('C-01 source float-mismatch and hub-difference flags, checker separation and original docs',()=>{
 hasFlag(checks.cashDenominations,{...cash,approvedFloat:'300'},'DRAWER_FLOAT_DIFFERS_FROM_POLICY');
 hasFlag(checks.cashDenominations,{...cash,denominations:[
  {denomination:'1000',sentCount:'2',hubCount:'1'},
  {denomination:'500',sentCount:'1',hubCount:'0'}]},'HUB_INDEPENDENT_RECOUNT_MISMATCH');
 hasFlag(checks.cashDenominations,{...cash,receivedBy:'Cashier',sentBy:'Cashier'},'INDEPENDENT_CASH_COUNT_ROLES_REQUIRED');
 hasFlag(checks.cashDenominations,{...cash,ledgerLine:''},'CASH_BANK_LEDGER_LINE_REQUIRED');
 hasFlag(checks.cashDenominations,{...cash,sheetAttached:false},'ORIGINAL_SHOWROOM_SHEET_MISSING');
 assert.throws(()=>checks.cashDenominations({...cash,denominations:[
  {denomination:'1000',sentCount:'1',hubCount:'1'},
  {denomination:'1000',sentCount:'1',hubCount:'1'}]}),/DUPLICATE_OR_ZERO_DENOMINATION/);
});
test('W-02 row-by-row transfer balance matches both signed locations and demand',()=>{
 const x=checks.transferLines(transfer);
 assert.equal(x.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(x.blockers));
 assert.equal(x.evidence.shortage,'0.0000');
 assert.equal(x.evidence.excess,'0.0000');
 assert.equal(x.evidence.overDemand,'0.0000');
});
test('W-02 original five candidate flags: shortage/excess/outside/over-demand/same location',()=>{
 hasFlag(checks.transferLines,{...transfer,lines:[{...transfer.lines[0],receivedQty:'14'}]},
  'TRANSFER_SHORTAGE_REQUIRES_REVIEW');
 hasFlag(checks.transferLines,{...transfer,lines:[{...transfer.lines[0],receivedQty:'16'}]},
  'TRANSFER_EXCESS_REQUIRES_REVIEW');
 hasFlag(checks.transferLines,{...transfer,outsideDemand:true,outsideReason:'Supplier shortage'},
  'OUTSIDE_DEMAND_REQUIRES_REVIEW');
 hasFlag(checks.transferLines,{...transfer,lines:[{...transfer.lines[0],demandQty:'12'}]},
  'OVER_DEMAND_REQUIRES_REVIEW');
 hasFlag(checks.transferLines,{...transfer,toLocation:'Factory'},'SAME_LOCATION_TRANSFER_BLOCKED');
});
test('W-02 conditional outside reason, customer order ref, dates, grade and separate receipt are enforced',()=>{
 hasFlag(checks.transferLines,{...transfer,outsideDemand:true},'OUTSIDE_DEMAND_REASON_REQUIRED');
 hasFlag(checks.transferLines,{...transfer,customerOrder:true},'CUSTOMER_ORDER_REFERENCE_REQUIRED');
 hasFlag(checks.transferLines,{...transfer,customerOrder:undefined},'CUSTOMER_ORDER_STATUS_UNKNOWN');
 hasFlag(checks.transferLines,{...transfer,productionDatesWritten:false},'FOOD_DATE_GRADE_MARKING_MISSING');
 hasFlag(checks.transferLines,{...transfer,receivedBy:'Factory keeper'},'INDEPENDENT_RECEIVER_REQUIRED');
 hasFlag(checks.transferLines,{...transfer,lines:[{...transfer.lines[0],grade:''}]},'ITEM_DATE_GRADE_REQUIRED:0');
});
test('all three checks fail closed on decimal precision/unsafe amounts and missing lists',()=>{
 assert.throws(()=>checks.expenseVoucher({...expense,lines:[{head:'X',to:'Y',receipt:'yes',amount:'1.234'}]}),/INVALID_DECIMAL/);
 assert.throws(()=>checks.cashDenominations({...cash,denominations:[{denomination:'1000',sentCount:'-1',hubCount:'1'}]}),/INVALID_DECIMAL/);
 assert.throws(()=>checks.transferLines({...transfer,lines:[{...transfer.lines[0],sentQty:'1.12345'}]}),/INVALID_DECIMAL/);
 assert.throws(()=>checks.transferLines({...transfer,lines:[]}),/INVALID_TRANSFER_LINES/);
});
