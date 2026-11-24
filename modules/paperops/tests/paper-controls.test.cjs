'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const gate=require('../paper-controls.js');

const handover={
 closingRef:'CLOSE-1',sealRef:'BAG-1',cashLedgerRef:'LEDGER-1',
 dispatchedCash:'120.50',receivedCash:'120.50',floatLeft:'15',
 approvedFloat:'15',sentBy:'A',receivedBy:'B'
};
const transfer={
 sourceLocation:'Factory',destinationLocation:'Showroom',challanRef:'W-02-01',
 issuedBy:'Factory keeper',receivedBy:'Showroom receiver',sentQty:'10',receivedQty:'10',
 foodGoods:true,productionDate:'2026-11-22',grade:'G1'
};
const receipt={
 poRef:'PO-1',grnRef:'GRN-1',invoiceRef:'BILL-1',orderedQty:'10',deliveredQty:'10',
 acceptedQty:'8',heldQty:'2',returnedQty:'0',receivedBy:'Storekeeper',qcBy:'QC',
 heldSegregated:true,qcPassed:true
};
const batch={
 batchRef:'B-01',recipeVersion:'RCP-1@v2',issueSlipRef:'ISSUE-1',issuedKg:'12',
 usedKg:'11',returnedKg:'1',expectedOutputKg:'16',goodOutputKg:'15',
 secondGradeKg:'0.5',wasteKg:'0.5',prestartSafetyOk:true,scaleChecked:true,
 producedBy:'Maker',yieldCheckedBy:'Independent checker',qcReleased:true,qcRef:'QC-1',
 yieldTestRef:'F-04-1'
};
const discount={
 saleRef:'SALE-1',originalAmount:'1000',discountAmount:'20',
 approvedLimit:'50',preparedBy:'Cashier'
};
const refund={
 originalSaleRef:'S-1',returnRef:'RET-1',rootCause:'Damaged packaging',
 productReturned:true,productQuarantined:true,foodIllnessReported:false,refundAmount:'30',refundLimit:'50',
 refundVoucherRef:'PAY-1',receivedBy:'Cashier',paidBy:'Accountant'
};
const order={
 totalAmount:'200',discountAmount:'10',advanceAmount:'50',
 orderRef:'ORDER-1',boardRef:'BOARD-1',deliveryDate:'2026-11-23',
 takenBy:'Cashier',boardCheckedBy:'Supervisor',advanceReceiptRef:'ADV-1',
 discountApprovalRef:'DISC-1'
};
function blocks(fn,value,code){const x=fn(value);assert.equal(x.authorized,false);
 assert.equal(x.fieldParityConfirmed,false);assert.equal(x.status,'BLOCK');
 assert.ok(x.blockers.includes(code),code+': '+JSON.stringify(x.blockers));}
test('cash custody requires two people, source/ledger references, independent recount and approved float',()=>{
 assert.equal(gate.cashHandover(handover).status,'REVIEW_READY_NOT_APPROVED');
 blocks(gate.cashHandover,{...handover,receivedCash:'119.50'},'HUB_RECOUNT_DIFFERS');
 blocks(gate.cashHandover,{...handover,receivedBy:'A'},'INDEPENDENT_RECIPIENT_REQUIRED');
 blocks(gate.cashHandover,{...handover,approvedFloat:undefined},'DRAWER_FLOAT_POLICY_REQUIRED');
 blocks(gate.cashHandover,{...handover,cashLedgerRef:''},'CASH_LEDGER_REFERENCE_MISSING');
});
test('goods transfer rejects same location, one-person count, food lot omissions and damage dispute',()=>{
 assert.equal(gate.stockTransfer(transfer).status,'REVIEW_READY_NOT_APPROVED');
 blocks(gate.stockTransfer,{...transfer,receivedQty:'9'},'TRANSFER_QUANTITY_VARIANCE');
 blocks(gate.stockTransfer,{...transfer,destinationLocation:'Factory'},'INVALID_SOURCE_DESTINATION');
 blocks(gate.stockTransfer,{...transfer,receivedBy:transfer.issuedBy},'INDEPENDENT_RECEIVER_REQUIRED');
 blocks(gate.stockTransfer,{...transfer,grade:''},'FOOD_BATCH_DATE_AND_GRADE_REQUIRED');
 blocks(gate.stockTransfer,{...transfer,damageReported:true},'DAMAGE_AND_LIABILITY_EVIDENCE_REQUIRED');
});
test('GRN cannot release unaccounted stock, hold without quarantine, or accept own rate approval',()=>{
 assert.equal(gate.goodsReceived(receipt).status,'REVIEW_READY_NOT_APPROVED');
 blocks(gate.goodsReceived,{...receipt,acceptedQty:'7'},'DELIVERED_ACCEPTED_HELD_RETURN_MISMATCH');
 blocks(gate.goodsReceived,{...receipt,heldSegregated:false},'HELD_STOCK_NOT_SEGREGATED');
 blocks(gate.goodsReceived,{...receipt,rateChanged:true,rateApprovedBy:'Storekeeper',rateApprovalRef:'A-1'},
  'INDEPENDENT_RATE_CHANGE_APPROVAL_REQUIRED');
 blocks(gate.goodsReceived,{...receipt,qcBy:'Storekeeper'},'INDEPENDENT_QC_REQUIRED');
 blocks(gate.goodsReceived,{...receipt,qcPassed:false},'QC_RELEASE_MISSING');
 blocks(gate.goodsReceived,{...receipt,deliveredQty:'9'},'PO_DELIVERY_VARIANCE_REVIEW');
});
test('factory batch must reconcile input and multi-grade output, plus different checker and QC',()=>{
 assert.equal(gate.factoryBatch(batch).status,'REVIEW_READY_NOT_APPROVED');
 blocks(gate.factoryBatch,{...batch,returnedKg:'0'},'RAW_MATERIAL_ISSUE_NOT_RECONCILED');
 blocks(gate.factoryBatch,{...batch,goodOutputKg:'14'},'YIELD_OUTPUT_VARIANCE_REVIEW');
 blocks(gate.factoryBatch,{...batch,yieldCheckedBy:batch.producedBy},'INDEPENDENT_YIELD_CHECKER_REQUIRED');
 blocks(gate.factoryBatch,{...batch,prestartSafetyOk:false},'FACTORY_PRESTART_SAFETY_MISSING');
 blocks(gate.factoryBatch,{...batch,recipeVersion:''},'BATCH_RECIPE_ISSUE_REFERENCES_REQUIRED');
 blocks(gate.factoryBatch,{...batch,qcReleased:false},'BATCH_QC_RELEASE_MISSING');
});
test('discount cannot bypass approved limit, source evidence or independent approver',()=>{
 assert.equal(gate.discountApproval(discount).status,'REVIEW_READY_NOT_APPROVED');
 blocks(gate.discountApproval,{...discount,approvedLimit:undefined},'DISCOUNT_POLICY_MISSING');
 blocks(gate.discountApproval,{...discount,discountAmount:'80'},'ABOVE_LIMIT_INDEPENDENT_APPROVAL_REQUIRED');
 blocks(gate.discountApproval,{...discount,discountAmount:'80',approvedBy:'Cashier',approvalRef:'APP-1'},
  'ABOVE_LIMIT_INDEPENDENT_APPROVAL_REQUIRED');
 assert.equal(gate.discountApproval({...discount,discountAmount:'80',approvedBy:'Boss',approvalRef:'APP-1'}).status,
  'REVIEW_READY_NOT_APPROVED');
 blocks(gate.discountApproval,{...discount,discountAmount:'2000'},'DISCOUNT_EXCEEDS_TOTAL');
});
test('return quarantines unsafe goods, escalates illness and never silently authorizes refund',()=>{
 assert.equal(gate.returnRefund(refund).status,'REVIEW_READY_NOT_APPROVED');
 blocks(gate.returnRefund,{...refund,productQuarantined:false},'RETURNED_GOODS_NOT_QUARANTINED');
 blocks(gate.returnRefund,{...refund,foodIllnessReported:true},'FOOD_ILLNESS_ESCALATION_MISSING');
 blocks(gate.returnRefund,{...refund,refundLimit:undefined},'REFUND_POLICY_MISSING');
 blocks(gate.returnRefund,{...refund,refundAmount:'80',approvedBy:'Cashier',approvalRef:'APP-1'},
   'INDEPENDENT_REFUND_APPROVAL_REQUIRED');
 blocks(gate.returnRefund,{...refund,refundVoucherRef:''},'REFUND_PAYMENT_EVIDENCE_MISSING');
});
test('customer order reconciles advance and discount and prevents self-approved order board',()=>{
 const x=gate.customerOrder(order);
 assert.equal(x.evidence.balancePaisa,14000);
 assert.equal(x.status,'REVIEW_READY_NOT_APPROVED');
 blocks(gate.customerOrder,{...order,advanceAmount:'220'},'DISCOUNT_ADVANCE_EXCEED_ORDER_TOTAL');
 blocks(gate.customerOrder,{...order,boardCheckedBy:'Cashier'},'INDEPENDENT_ORDER_BOARD_CHECK_REQUIRED');
 blocks(gate.customerOrder,{...order,notCollected:true},'UNCOLLECTED_ORDER_DECISION_REQUIRED');
 blocks(gate.customerOrder,{...order,advanceReceiptRef:''},'ADVANCE_RECEIPT_MISSING');
});
test('all gates reject invalid amounts instead of guessing or rounding',()=>{
 assert.throws(()=>gate.cashHandover({...handover,receivedCash:'nan'}),/INVALID_MONEY/);
 assert.throws(()=>gate.stockTransfer({...transfer,sentQty:'1.12345'}),/INVALID_QUANTITY/);
 assert.throws(()=>gate.goodsReceived({...receipt,heldQty:'-1'}),/INVALID_QUANTITY/);
 assert.throws(()=>gate.discountApproval({...discount,discountAmount:'99999999999999999'}),/UNSAFE_MONEY/);
});
