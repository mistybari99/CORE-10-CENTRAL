/* PaperOps draft control gates recovered from old sweets forms. No network, no posting.
 * A PASS means candidate paper checks passed, never authorisation or field-parity signoff.
 */
(function(root,factory){
  'use strict';
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;
  if(root)root.CORE10_PAPER_CONTROLS=api;
})(typeof globalThis==='object'?globalThis:this,function(){
  'use strict';
  function present(value){return typeof value==='string'&&value.trim().length>0;}
  function same(a,b){return present(a)&&present(b)&&a.trim()===b.trim();}
  function money(v,key){
    const s=typeof v==='number'&&Number.isFinite(v)?String(v):v;
    if(typeof s!=='string'||!/^\d+(?:\.\d{1,2})?$/.test(s.trim()))throw Error('INVALID_MONEY:'+key);
    const [whole,frac='']=s.trim().split('.');
    const cents=Number(whole)*100+Number(frac.padEnd(2,'0'));
    if(!Number.isSafeInteger(cents))throw Error('UNSAFE_MONEY:'+key);
    return cents;
  }
  function quantity(v,key){
    const s=typeof v==='number'&&Number.isFinite(v)?String(v):v;
    if(typeof s!=='string'||!/^\d+(?:\.\d{1,4})?$/.test(s.trim()))throw Error('INVALID_QUANTITY:'+key);
    const [whole,frac='']=s.trim().split('.');
    const units=Number(whole)*10000+Number(frac.padEnd(4,'0'));
    if(!Number.isSafeInteger(units))throw Error('UNSAFE_QUANTITY:'+key);
    return units;
  }
  function end(reasons,evidence){
    return Object.freeze({status:reasons.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
      blockers:Object.freeze(reasons),evidence:Object.freeze(evidence||{}),
      authorized:false,fieldParityConfirmed:false});
  }
  function requireUniqueActors(reasons,who,check,code){
    if(!present(who)||!present(check)||same(who,check))reasons.push(code);
  }
  function cashHandover(v){
    const reasons=[];
    const dispatch=money(v.dispatchedCash,'dispatchedCash'),
      received=money(v.receivedCash,'receivedCash'),
      leftFloat=money(v.floatLeft,'floatLeft');
    if(!present(v.closingRef))reasons.push('SOURCE_CLOSING_MISSING');
    if(!present(v.sealRef))reasons.push('SEALED_BAG_OR_EXCEPTION_REF_MISSING');
    if(!present(v.cashLedgerRef))reasons.push('CASH_LEDGER_REFERENCE_MISSING');
    requireUniqueActors(reasons,v.sentBy,v.receivedBy,'INDEPENDENT_RECIPIENT_REQUIRED');
    if(dispatch!==received)reasons.push('HUB_RECOUNT_DIFFERS');
    if(v.approvedFloat===undefined)reasons.push('DRAWER_FLOAT_POLICY_REQUIRED');
    else if(leftFloat!==money(v.approvedFloat,'approvedFloat'))reasons.push('DRAWER_FLOAT_MISMATCH');
    return end(reasons,{differencePaisa:received-dispatch});
  }
  function stockTransfer(v){
    const reasons=[];
    const sent=quantity(v.sentQty,'sentQty'),received=quantity(v.receivedQty,'receivedQty');
    if(!present(v.sourceLocation)||!present(v.destinationLocation)||
      same(v.sourceLocation,v.destinationLocation))reasons.push('INVALID_SOURCE_DESTINATION');
    if(!present(v.challanRef))reasons.push('CHALLAN_REFERENCE_REQUIRED');
    requireUniqueActors(reasons,v.issuedBy,v.receivedBy,'INDEPENDENT_RECEIVER_REQUIRED');
    if(sent!==received)reasons.push('TRANSFER_QUANTITY_VARIANCE');
    if(v.foodGoods===true&&(!present(v.productionDate)||!present(v.grade)))
      reasons.push('FOOD_BATCH_DATE_AND_GRADE_REQUIRED');
    if(v.outsideApprovedDemand===true&&(!present(v.demandExceptionRef)||!present(v.approvedBy)))
      reasons.push('OUTSIDE_DEMAND_APPROVAL_REQUIRED');
    if(v.damageReported===true&&(!present(v.damageRef)||!present(v.liabilityDecision)))
      reasons.push('DAMAGE_AND_LIABILITY_EVIDENCE_REQUIRED');
    return end(reasons,{sentUnits:sent,receivedUnits:received,differenceUnits:sent-received});
  }
  function goodsReceived(v){
    const reasons=[];
    const ordered=quantity(v.orderedQty,'orderedQty'),delivered=quantity(v.deliveredQty,'deliveredQty'),
      accepted=quantity(v.acceptedQty,'acceptedQty'),held=quantity(v.heldQty,'heldQty'),
      returned=quantity(v.returnedQty,'returnedQty');
    if(!present(v.poRef)||!present(v.grnRef)||!present(v.invoiceRef))
      reasons.push('PURCHASE_SOURCE_REFERENCES_REQUIRED');
    requireUniqueActors(reasons,v.receivedBy,v.qcBy,'INDEPENDENT_QC_REQUIRED');
    if(accepted+held+returned!==delivered)reasons.push('DELIVERED_ACCEPTED_HELD_RETURN_MISMATCH');
    if(delivered!==ordered)reasons.push('PO_DELIVERY_VARIANCE_REVIEW');
    if(held>0&&v.heldSegregated!==true)reasons.push('HELD_STOCK_NOT_SEGREGATED');
    if(v.rateChanged===true&&(!present(v.rateApprovalRef)||!present(v.rateApprovedBy)||
      same(v.rateApprovedBy,v.receivedBy)))reasons.push('INDEPENDENT_RATE_CHANGE_APPROVAL_REQUIRED');
    if(v.qcPassed!==true)reasons.push('QC_RELEASE_MISSING');
    return end(reasons,{orderedUnits:ordered,deliveredUnits:delivered,
      acceptedUnits:accepted,heldUnits:held,returnedUnits:returned});
  }
  function factoryBatch(v){
    const reasons=[];
    const issued=quantity(v.issuedKg,'issuedKg'),used=quantity(v.usedKg,'usedKg'),
      returned=quantity(v.returnedKg,'returnedKg'),expected=quantity(v.expectedOutputKg,'expectedOutputKg'),
      good=quantity(v.goodOutputKg,'goodOutputKg'),seconds=quantity(v.secondGradeKg,'secondGradeKg'),
      waste=quantity(v.wasteKg,'wasteKg');
    if(!present(v.batchRef)||!present(v.recipeVersion)||!present(v.issueSlipRef))
      reasons.push('BATCH_RECIPE_ISSUE_REFERENCES_REQUIRED');
    if(v.prestartSafetyOk!==true||v.scaleChecked!==true)reasons.push('FACTORY_PRESTART_SAFETY_MISSING');
    requireUniqueActors(reasons,v.producedBy,v.yieldCheckedBy,'INDEPENDENT_YIELD_CHECKER_REQUIRED');
    if(used+returned!==issued)reasons.push('RAW_MATERIAL_ISSUE_NOT_RECONCILED');
    if(v.qcReleased!==true||!present(v.qcRef))reasons.push('BATCH_QC_RELEASE_MISSING');
    if(!present(v.yieldTestRef))reasons.push('APPROVED_YIELD_SOURCE_MISSING');
    if(expected!==good+seconds+waste)reasons.push('YIELD_OUTPUT_VARIANCE_REVIEW');
    return end(reasons,{issueVarianceUnits:issued-used-returned,outputVarianceUnits:good+seconds+waste-expected});
  }
  function discountApproval(v){
    const reasons=[];
    const total=money(v.originalAmount,'originalAmount'),discount=money(v.discountAmount,'discountAmount');
    if(discount>total)reasons.push('DISCOUNT_EXCEEDS_TOTAL');
    if(v.approvedLimit===undefined)reasons.push('DISCOUNT_POLICY_MISSING');
    else if(discount>money(v.approvedLimit,'approvedLimit')&&
      (!present(v.approvalRef)||!present(v.approvedBy)||same(v.approvedBy,v.preparedBy)))
      reasons.push('ABOVE_LIMIT_INDEPENDENT_APPROVAL_REQUIRED');
    if(!present(v.saleRef))reasons.push('SOURCE_SALE_MISSING');
    return end(reasons,{discountPaisa:discount,netPaisa:total-discount});
  }
  function returnRefund(v){
    const reasons=[];
    const refund=money(v.refundAmount,'refundAmount');
    if(!present(v.originalSaleRef)||!present(v.returnRef))reasons.push('ORIGINAL_SALE_AND_RETURN_REF_REQUIRED');
    if(!present(v.rootCause))reasons.push('ROOT_CAUSE_REQUIRED');
    if(v.productReturned===true&&v.productQuarantined!==true)reasons.push('RETURNED_GOODS_NOT_QUARANTINED');
    if(v.foodIllnessReported===true&&v.managementEscalated!==true)reasons.push('FOOD_ILLNESS_ESCALATION_MISSING');
    if(v.refundLimit===undefined)reasons.push('REFUND_POLICY_MISSING');
    else if(refund>money(v.refundLimit,'refundLimit')&&
      (!present(v.approvalRef)||!present(v.approvedBy)||same(v.approvedBy,v.receivedBy)||
      same(v.approvedBy,v.paidBy)))reasons.push('INDEPENDENT_REFUND_APPROVAL_REQUIRED');
    if(refund>0&&(!present(v.refundVoucherRef)||!present(v.paidBy)))reasons.push('REFUND_PAYMENT_EVIDENCE_MISSING');
    return end(reasons,{refundPaisa:refund});
  }
  function customerOrder(v){
    const reasons=[];
    const total=money(v.totalAmount,'totalAmount'),discount=money(v.discountAmount,'discountAmount'),
      advance=money(v.advanceAmount,'advanceAmount');
    const balance=total-discount-advance;
    if(balance<0)reasons.push('DISCOUNT_ADVANCE_EXCEED_ORDER_TOTAL');
    if(!present(v.orderRef)||!present(v.boardRef))reasons.push('ORDER_AND_BOARD_REF_REQUIRED');
    if(!present(v.deliveryDate)||!/\d{4}-\d{2}-\d{2}/.test(v.deliveryDate))
      reasons.push('DELIVERY_DATE_REQUIRED');
    requireUniqueActors(reasons,v.takenBy,v.boardCheckedBy,'INDEPENDENT_ORDER_BOARD_CHECK_REQUIRED');
    if(advance>0&&!present(v.advanceReceiptRef))reasons.push('ADVANCE_RECEIPT_MISSING');
    if(discount>0&&!present(v.discountApprovalRef))reasons.push('DISCOUNT_APPROVAL_REF_MISSING');
    if(v.notCollected===true&&!present(v.uncollectedDecisionRef))reasons.push('UNCOLLECTED_ORDER_DECISION_REQUIRED');
    return end(reasons,{balancePaisa:balance});
  }
  return Object.freeze({cashHandover,stockTransfer,goodsReceived,factoryBatch,
    discountApproval,returnRefund,customerOrder});
});
