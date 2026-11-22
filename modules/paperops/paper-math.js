/* CORE-10 PaperOps pure calculation prototypes; NO accounting posting, no approvals granted.
 * Original sweetness formulas are source-derived; all policy limits are external, required where indicated.
 * Decimal monetary inputs use integer paisa internally to avoid binary float equality errors.
 */
(function(root,factory){
  'use strict';
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;
  if(root)root.CORE10_PAPER_MATH=api;
})(typeof globalThis==='object'?globalThis:this,function(){
  'use strict';
  function decimal(value,name,scale=2,nonNegative=true){
    const raw=typeof value==='number'&&Number.isFinite(value)?String(value):value;
    if(typeof raw!=='string'||!/^-?\d+(?:\.\d+)?$/.test(raw.trim()))throw Error('NUMBER_REQUIRED:'+name);
    const s=raw.trim();
    if(!new RegExp('^-?\\d+(?:\\.\\d{1,'+scale+'})?$').test(s))throw Error('INVALID_PRECISION:'+name);
    const n=Number(s),factor=10**scale,scaled=n*factor;
    if(!Number.isSafeInteger(Math.round(scaled))||Math.abs(Math.round(scaled)-scaled)>0.00001)
      throw Error('UNSAFE_NUMBER:'+name);
    if(nonNegative&&n<0)throw Error('NEGATIVE_NOT_ALLOWED:'+name);
    return Math.round(scaled);
  }
  function money(v,name){return decimal(v,name,2);}
  function qty(v,name){return decimal(v,name,4);}
  function fromMoney(n){if(!Number.isSafeInteger(n))throw Error('OVERFLOW');return(n/100).toFixed(2);}
  function fromQty(n){if(!Number.isSafeInteger(n))throw Error('OVERFLOW');return(n/10000).toFixed(4);}
  function hasOwn(o,k){return Object.prototype.hasOwnProperty.call(o,k);}
  function roundedRatio(n,d,dp=4){return Math.round((n/d)*10**dp)/10**dp;}
  function flags(ok,code){return ok?[]:[code];}
  function stockBalance(v){
    const open=qty(v.opening,'opening'),inc=qty(v.received,'received'),returnIn=qty(v.returnedIn,'returnedIn');
    const issue=qty(v.issued,'issued'),sale=qty(v.sold,'sold'),waste=qty(v.wasted,'wasted');
    const out=qty(v.returnedOut,'returnedOut'),count=qty(v.physicalClose,'physicalClose');
    const expected=open+inc+returnIn-issue-sale-waste-out;
    if(expected<0)return {status:'BLOCK',reason:['NEGATIVE_BOOK_STOCK'],expected:fromQty(expected),counted:fromQty(count)};
    const diff=count-expected;
    return {status:diff===0?'MATCH':'BLOCK',expected:fromQty(expected),counted:fromQty(count),
      variance:fromQty(diff),reason:flags(diff===0,'STOCK_COUNT_VARIANCE'),
      adjustmentAuthorized:false};
  }
  function cashClosing(v){
    const opening=money(v.openingFloat,'openingFloat'),sales=money(v.cashSales,'cashSales'),other=money(v.receipts,'receipts');
    const expense=money(v.approvedExpenses,'approvedExpenses'),refunds=money(v.refunds,'refunds');
    const deposit=money(v.bankDeposits,'bankDeposits'),handover=money(v.handovers,'handovers');
    const close=money(v.countedClose,'countedClose');
    const expected=opening+sales+other-expense-refunds-deposit-handover;
    const mismatch=close-expected;
    return {status:expected<0?'BLOCK':mismatch===0?'MATCH':'BLOCK',expected:fromMoney(expected),
      actual:fromMoney(close),variance:fromMoney(mismatch),
      reason:expected<0?['NEGATIVE_EXPECTED_CASH']:flags(mismatch===0,'CASH_DIFFERENCE'),
      transferIsEvidenceOnly:true};
  }
  function threeWay(v){
    const refs=['poRef','grnRef','billRef'].map(k=>{
      if(typeof v[k]!=='string'||!v[k].trim())throw Error('SOURCE_REFERENCE_REQUIRED:'+k);
      return v[k].trim();
    });
    const po=money(v.poAmount,'poAmount'),grn=money(v.acceptedAmount,'acceptedAmount'),bill=money(v.invoiceAmount,'invoiceAmount');
    const payment=money(v.paymentProposed,'paymentProposed');
    const mismatch=po!==grn||grn!==bill;
    const approved=typeof v.approvedBy==='string'&&v.approvedBy.trim()&&
      typeof v.preparedBy==='string'&&v.preparedBy.trim()&&v.approvedBy.trim()!==v.preparedBy.trim();
    const blockers=[];
    if(mismatch)blockers.push('PO_GRN_BILL_MISMATCH');
    if(mismatch&&payment>0)blockers.push('PAYMENT_REQUEST_WITH_MISMATCH');
    if(payment>0&&!approved)blockers.push('INDEPENDENT_APPROVAL_MISSING');
    return {sourceRefs:refs,amounts:{po:fromMoney(po),grn:fromMoney(grn),bill:fromMoney(bill)},
      proposedPayment:fromMoney(payment),status:blockers.length?'BLOCK':'MATCHED_FOR_PAPER_REVIEW',
      reasons:blockers,readyForERPPosting:false};
  }
  function digitalSettlement(v){
    const paper=money(v.paperRecorded,'paperRecorded'),statement=money(v.statementGross,'statementGross');
    const fee=money(v.processingFee,'processingFee'),bank=money(v.bankReceived,'bankReceived');
    const paperGap=statement-paper,bankGap=bank-(statement-fee);
    const reasons=[];
    if(paperGap!==0)reasons.push('PAPER_STATEMENT_MISMATCH');
    if(bankGap!==0)reasons.push('BANK_NET_SETTLEMENT_MISMATCH');
    if(fee>statement)reasons.push('FEE_EXCEEDS_GROSS');
    if(v.personalAccount===true)reasons.push('PERSONAL_ACCOUNT_ESCALATION');
    return {status:reasons.length?'BLOCK':'MATCH',paperGap:fromMoney(paperGap),
      bankGap:fromMoney(bankGap),netExpected:fromMoney(statement-fee),reasons};
  }
  function receivableAging(v){
    const total=money(v.totalDue,'totalDue'),d30=money(v.days0to30,'days0to30'),
      d60=money(v.days31to60,'days31to60'),older=money(v.daysOver60,'daysOver60');
    const diff=total-d30-d60-older,missingPolicy=!hasOwn(v,'creditLimit');
    const limit=missingPolicy?null:money(v.creditLimit,'creditLimit');
    const over=limit!==null&&total>limit;
    const reasons=[];
    if(diff!==0)reasons.push('AGING_BUCKET_MISMATCH');
    if(missingPolicy)reasons.push('CREDIT_LIMIT_POLICY_REQUIRED');
    if(over&&!v.creditStopped)reasons.push('CREDIT_EXCEEDS_LIMIT_NOT_STOPPED');
    if(older>0)reasons.push('OVER_60_REVIEW_REQUIRED');
    return {total:fromMoney(total),bucketVariance:fromMoney(diff),
      creditOverLimit:over,missingPolicy,reviewRequired:older>0,
      status:reasons.length?'REVIEW':'MATCH',reasons};
  }
  function quoteSelection(v){
    if(!Array.isArray(v.quotes)||v.quotes.length<1||v.quotes.length>100)throw Error('INVALID_QUOTES');
    const quoteMap=new Map();
    for(const q of v.quotes){
      if(typeof q.supplier!=='string'||!q.supplier.trim())throw Error('SUPPLIER_REQUIRED');
      if(quoteMap.has(q.supplier.trim()))throw Error('DUPLICATE_SUPPLIER');
      quoteMap.set(q.supplier.trim(),money(q.rate,'rate:'+q.supplier));
    }
    if(typeof v.selectedSupplier!=='string'||!quoteMap.has(v.selectedSupplier.trim()))
      throw Error('SELECTED_SUPPLIER_NOT_QUOTED');
    const lowest=Math.min(...quoteMap.values()),selected=quoteMap.get(v.selectedSupplier.trim());
    const reasons=[];
    if(selected>lowest)reasons.push('NOT_LOWEST_RATE');
    if(quoteMap.size===1)reasons.push('SINGLE_QUOTE_REVIEW_REQUIRED');
    if(!hasOwn(v,'comparisonThreshold'))reasons.push('COMPARISON_POLICY_REQUIRED');
    else money(v.comparisonThreshold,'comparisonThreshold');
    if(reasons.length&&(!v.selectionReason||!v.independentApprover||v.independentApprover===v.collectedBy))
      reasons.push('EXCEPTION_APPROVAL_REQUIRED');
    return {lowestRate:fromMoney(lowest),selectedRate:fromMoney(selected),
      extraPerUnit:fromMoney(selected-lowest),status:reasons.length?'REVIEW':'MATCH',reasons};
  }
  function jalebiYield(v){
    const issued=qty(v.flourIssuedKg,'flourIssuedKg'),openDough=qty(v.openDoughKg,'openDoughKg'),
      closeDough=qty(v.closeDoughKg,'closeDoughKg');
    const pct=decimal(v.approvedBaseConversionPercent,'approvedBaseConversionPercent',4);
    const yieldKg=qty(v.approvedKgPerKgFlour,'approvedKgPerKgFlour');
    const salePaisa=money(v.jalebiSales,'jalebiSales'),price=money(v.approvedPricePerKg,'approvedPricePerKg');
    const unsold=qty(v.unsoldKg,'unsoldKg'),samples=qty(v.samplesKg,'samplesKg');
    const iOil=qty(v.oilIssuedL,'oilIssuedL'),oOil=qty(v.openOilL,'openOilL'),cOil=qty(v.closeOilL,'closeOilL');
    const iSyr=qty(v.syrupReceivedL,'syrupReceivedL'),oSyr=qty(v.openSyrupL,'openSyrupL'),cSyr=qty(v.closeSyrupL,'closeSyrupL');
    if(pct<=0||price<=0||yieldKg<=0)throw Error('APPROVED_CONVERSION_YIELD_PRICE_REQUIRED');
    const flourUsed=issued+(openDough-closeDough)*1000000/pct; // original R-02: dough delta × 100 / approved base %
    const expected=flourUsed*yieldKg/10000;
    const soldKg=salePaisa*10000/price;
    const actual=soldKg+unsold+samples;
    const diff=actual-expected;
    const oilUsed=iOil+oOil-cOil,syrUsed=iSyr+oSyr-cSyr;
    const reasons=[];
    if(flourUsed<0||oilUsed<0||syrUsed<0)reasons.push('NEGATIVE_CONSUMPTION');
    if(!v.measuredBy||!v.producedBy||v.measuredBy===v.producedBy)reasons.push('INDEPENDENT_MEASURER_REQUIRED');
    if(v.scaleChecked!==true)reasons.push('SCALE_CHECK_REQUIRED');
    if(!v.issueSlipRef)reasons.push('MATERIAL_ISSUE_SLIP_REQUIRED');
    if(unsold>0&&!v.unsoldDecision)reasons.push('UNSOLD_DISPOSITION_REQUIRED');
    const hasPct=hasOwn(v,'approvedTolerancePercent'),hasKg=hasOwn(v,'approvedToleranceKg');
    if(!hasPct&&!hasKg)reasons.push('TOLERANCE_POLICY_REQUIRED');
    else{
      const tolerances=[];
      if(hasPct){
        const p=decimal(v.approvedTolerancePercent,'approvedTolerancePercent',4);
        tolerances.push(expected>0?Math.abs(diff)*100/expected<=p:Math.abs(diff)<0.0000001);
      }
      if(hasKg)tolerances.push(Math.abs(diff)<=qty(v.approvedToleranceKg,'approvedToleranceKg')+0.0000001);
      if(!tolerances.some(Boolean))reasons.push('YIELD_OUTSIDE_APPROVED_TOLERANCE');
    }
    const roundQty=x=>fromQty(Math.round(x));
    return {flourUsedKg:roundQty(flourUsed),expectedOutputKg:roundQty(expected),
      actualOutputKg:roundQty(actual),soldKg:roundQty(soldKg),varianceKg:roundQty(diff),
      oilUsedL:roundQty(oilUsed),syrupUsedL:roundQty(syrUsed),
      status:reasons.length?'REVIEW':'FORMULA_MATCH_REVIEW_SIGNOFF_REQUIRED',reasons,source:'legacy R-02 (proposed parity)'};
  }
  function monthlyProfit(v){
    const sales=money(v.sales,'sales'),opening=money(v.openStock,'openStock'),
      purchases=money(v.purchases,'purchases'),closing=money(v.closeStock,'closeStock');
    const expense=money(v.operatingExpenses,'operatingExpenses'),payroll=money(v.payroll,'payroll'),
      bank=money(v.bankCharges,'bankCharges');
    const cogs=opening+purchases-closing,gross=sales-cogs,net=gross-expense-payroll-bank;
    const reasons=[];
    if(cogs<0)reasons.push('NEGATIVE_COGS_CHECK_STOCK');
    if(!hasOwn(v,'receivables')||!hasOwn(v,'payables'))reasons.push('AR_AP_NOT_RECONCILED');
    else{money(v.receivables,'receivables');money(v.payables,'payables');}
    if(!v.checkedBy||!v.preparedBy||v.checkedBy===v.preparedBy)reasons.push('INDEPENDENT_REVIEW_REQUIRED');
    if(net<0)reasons.push('NET_LOSS_REVIEW');
    return {cogs:fromMoney(cogs),gross:fromMoney(gross),net:fromMoney(net),
      status:reasons.length?'REVIEW':'PAPER_SUMMARY_MATCH',reasons,
      postingAuthorized:false};
  }
  return Object.freeze({stockBalance,cashClosing,threeWay,digitalSettlement,receivableAging,quoteSelection,jalebiYield,monthlyProfit});
});
