/* CORE-10 PaperOps first 50 source fields: C-02 expense, C-01 cash count, W-02 transfer.
 * Source candidates derived from preserved historical JS; no old app execution, no ERP writes.
 * These evidence gates can BLOCK or request paper review, never approve/settle/post.
 */
(function(root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.CORE10_PAPER_BATCH001_CHECKS = api;
})(typeof globalThis === 'object' ? globalThis : this, function() {
  'use strict';
  const present=v=>typeof v==='string'&&v.trim().length>0;
  function integerScaled(value, key, digits, positiveOnly=false) {
    const s=typeof value==='number'&&Number.isFinite(value)?String(value):value;
    const re=digits===0?/^\\d+$/:new RegExp('^\\d+(?:\\.\\d{1,'+digits+'})?
    if(typeof s!=='string'||!re.test(s.trim())) throw Error('INVALID_DECIMAL:'+key);
    const parts=s.trim().split('.'),factor=10**digits;
    const n=Number(parts[0])*factor+Number((parts[1]||'').padEnd(digits,'0'));
    if(!Number.isSafeInteger(n)||(positiveOnly&&n===0)) throw Error('UNSAFE_OR_ZERO:'+key);
    return n;
  }
  function money(v,k){return integerScaled(v,k,2);}
  function qty(v,k){return integerScaled(v,k,4);}
  function amount(n){return(n/100).toFixed(2);}
  function quantity(n){return(n/10000).toFixed(4);}
  function result(blockers, evidence, source) {
    return Object.freeze({source,status:blockers.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
      blockers:Object.freeze(blockers),evidence:Object.freeze(evidence),
      authorized:false,fieldParityConfirmed:false,erpPosted:false});
  }
  function expenseVoucher(input) {
    const v=input||{},reasons=[],source='C-02';
    if(!Array.isArray(v.lines)||v.lines.length===0||v.lines.length>100)
      throw Error('INVALID_EXPENSE_LINES');
    if(!present(v.voucherRef)||!present(v.sheetNo)) reasons.push('EXPENSE_SOURCE_REFERENCE_REQUIRED');
    if(!present(v.preparedBy)||!present(v.paidBy)) reasons.push('EXPENSE_ROLE_EVIDENCE_REQUIRED');
    if(v.drawerUntouched!==true)reasons.push('SALES_DRAWER_NOT_CONFIRMED_UNTOUCHED');
    if(!['cash','bank','mobile','card'].includes(v.payMode))
      reasons.push('EXPENSE_PAYMENT_MODE_REQUIRED');
    if(v.payMode!=='cash'&&(!present(v.moneyAccountId)||!present(v.accountProofRef)))
      reasons.push('NONCASH_SOURCE_ACCOUNT_PROOF_REQUIRED');
    const sourcePolicy=v.approvedExpenseMax===undefined?null:money(v.approvedExpenseMax,'approvedExpenseMax');
    const imprest=v.approvedImprest===undefined?null:money(v.approvedImprest,'approvedImprest');
    if(sourcePolicy===null||!present(v.expenseLimitPolicyRef))
      reasons.push('EXPENSE_MAX_POLICY_REQUIRED');
    if(imprest===null||!present(v.imprestPolicyRef))
      reasons.push('IMPREST_POLICY_REQUIRED');
    const cash=money(v.cashNow,'cashNow'),receipts=money(v.receiptsTotal,'receiptsTotal');
    const sumCR=cash+receipts;
    if(imprest!==null&&sumCR!==imprest) reasons.push('IMPREST_MISMATCH');
    let total=0,missingReceipt=0,overLimit=0;
    for(let i=0;i<v.lines.length;i++){
      const row=v.lines[i];if(!row||typeof row!=='object')throw Error('INVALID_EXPENSE_ROW:'+i);
      const paid=money(row.amount,'lines['+i+'].amount');
      if(!present(row.head)||!present(row.to))reasons.push('EXPENSE_LINE_IDENTITY_MISSING:'+i);
      if(!['yes','no'].includes(row.receipt))reasons.push('RECEIPT_STATUS_UNKNOWN:'+i);
      if(row.receipt==='yes'&&!present(row.receiptRef))
        reasons.push('RECEIPT_PROOF_REFERENCE_REQUIRED:'+i);
      if(row.receipt==='no'&&paid>0)missingReceipt+=paid;
      if(sourcePolicy!==null&&paid>sourcePolicy)overLimit++;
      if(!Number.isSafeInteger(total+paid))throw Error('EXPENSE_TOTAL_OVERFLOW');
      total+=paid;
    }
    if(missingReceipt>0&&!present(v.noReceiptReason))
      reasons.push('RECEIPT_REASON_MISSING');
    if(missingReceipt>0) reasons.push('MISSING_RECEIPT_REQUIRES_REVIEW');
    if(overLimit>0&&(!present(v.approvedBy)||!present(v.approvalRef)||
      (present(v.preparedBy)&&v.preparedBy.trim()===v.approvedBy?.trim())||
      (present(v.paidBy)&&v.paidBy.trim()===v.approvedBy?.trim())))
      reasons.push('OVER_LIMIT_INDEPENDENT_APPROVAL_MISSING');
    if(overLimit>0)reasons.push('OVER_LIMIT_EXPENSE_REQUIRES_REVIEW');
    return result(reasons,{expenseTotalBDT:amount(total),cashPlusReceiptsBDT:amount(sumCR),
      missingReceiptBDT:amount(missingReceipt),overLimitCount:overLimit,
      ruleRefs:['expense_max','imprest'],controlVersion:'BATCH-001-DRAFT'},source);
  }
  function cashDenominations(v) {
    v=v||{};const reasons=[];
    if(!Array.isArray(v.denominations)||v.denominations.length===0||v.denominations.length>30)
      throw Error('INVALID_DENOMINATIONS');
    if(!present(v.closingRef)||!present(v.sealRef)||!present(v.ledgerRef))
      reasons.push('CASH_SOURCE_DOCUMENT_MISSING');
    if(!present(v.carrier)||!present(v.sentBy)||!present(v.receivedBy)||
      v.sentBy===v.receivedBy)reasons.push('INDEPENDENT_CASH_COUNT_ROLES_REQUIRED');
    if(v.sheetAttached!==true)reasons.push('ORIGINAL_SHOWROOM_SHEET_MISSING');
    const leave=money(v.floatLeft,'floatLeft');
    const fixed=v.approvedFloat===undefined?null:money(v.approvedFloat,'approvedFloat');
    if(fixed===null)reasons.push('DRAWER_FLOAT_POLICY_MISSING');
    else if(leave!==fixed)reasons.push('DRAWER_FLOAT_DIFFERS_FROM_POLICY');
    let counted=0,hub=0;
    const values=new Set();
    for(let i=0;i<v.denominations.length;i++){
      const row=v.denominations[i],denom=money(row?.denomination,'denomination['+i+']');
      const sent=integerScaled(row?.sentCount,'sentCount['+i+']',0);
      const recount=integerScaled(row?.hubCount,'hubCount['+i+']',0);
      if(denom<=0||values.has(denom))throw Error('DUPLICATE_OR_ZERO_DENOMINATION');
      values.add(denom);
      counted+=denom*sent;hub+=denom*recount;
      if(!Number.isSafeInteger(counted)||!Number.isSafeInteger(hub))throw Error('CASH_DENOMINATION_OVERFLOW');
    }
    const dispatched=counted-leave,difference=hub-dispatched;
    if(dispatched<0)reasons.push('FLOAT_GREATER_THAN_COUNTED_CASH');
    if(difference!==0)reasons.push('HUB_INDEPENDENT_RECOUNT_MISMATCH');
    if(difference!==0&&!present(v.differenceReason))
      reasons.push('DIFFERENCE_REASON_REQUIRED');
    if(v.sealIntact!==true)reasons.push('SEAL_INTACT_NOT_CONFIRMED');
    if(!present(v.ledgerLine))reasons.push('CASH_BANK_LEDGER_LINE_REQUIRED');
    return result(reasons,{countedTotalBDT:amount(counted),handoverBDT:amount(dispatched),
      hubReceivedBDT:amount(hub),differenceBDT:amount(difference),
      sourceFormula:'counted_total - leave_float = handover; hub_count - handover = diff'},'C-01');
  }
  function transferLines(v) {
    v=v||{};const reasons=[];
    if(!Array.isArray(v.lines)||v.lines.length===0||v.lines.length>100)
      throw Error('INVALID_TRANSFER_LINES');
    if(!present(v.challanRef)||!present(v.fromLocation)||!present(v.toLocation))
      reasons.push('TRANSFER_ID_OR_LOCATIONS_MISSING');
    if(present(v.fromLocation)&&v.fromLocation===v.toLocation)
      reasons.push('SAME_LOCATION_TRANSFER_BLOCKED');
    if(!present(v.sentBy)||!present(v.receivedBy)||v.sentBy===v.receivedBy)
      reasons.push('INDEPENDENT_RECEIVER_REQUIRED');
    if(v.productionDatesWritten!==true||v.gradesWritten!==true)
      reasons.push('FOOD_DATE_GRADE_MARKING_MISSING');
    if(v.outsideDemand===true){
      reasons.push('OUTSIDE_DEMAND_REQUIRES_REVIEW');
      if(!present(v.outsideReason))reasons.push('OUTSIDE_DEMAND_REASON_REQUIRED');
    }else if(v.outsideDemand!==false)reasons.push('OUTSIDE_DEMAND_STATUS_UNKNOWN');
    if(v.customerOrder===true&&!present(v.customerOrderRef))reasons.push('CUSTOMER_ORDER_REFERENCE_REQUIRED');
    if(v.customerOrder!==true&&v.customerOrder!==false)
      reasons.push('CUSTOMER_ORDER_STATUS_UNKNOWN');
    let shortage=0,excess=0,overDemand=0;
    const keys=new Set();
    for(let i=0;i<v.lines.length;i++){
      const row=v.lines[i];if(!row||typeof row!=='object')throw Error('INVALID_TRANSFER_LINE:'+i);
      if(!present(row.item)||!present(row.productionDate)||!present(row.grade))
        reasons.push('ITEM_DATE_GRADE_REQUIRED:'+i);
      const key=[row.item,row.productionDate,row.grade].join('|');
      if(keys.has(key))reasons.push('DUPLICATE_ITEM_LOT_ON_CHALLAN:'+i);
      keys.add(key);
      const sent=qty(row.sentQty,'sent['+i+']'),received=qty(row.receivedQty,'received['+i+']');
      if(sent>received)shortage+=sent-received;
      if(received>sent)excess+=received-sent;
      if(row.demandQty!==undefined){
        const demand=qty(row.demandQty,'demand['+i+']');
        if(sent>demand)overDemand+=sent-demand;
      }
    }
    if(shortage>0)reasons.push('TRANSFER_SHORTAGE_REQUIRES_REVIEW');
    if(excess>0)reasons.push('TRANSFER_EXCESS_REQUIRES_REVIEW');
    if(overDemand>0)reasons.push('OVER_DEMAND_REQUIRES_REVIEW');
    return result(reasons,{shortage:quantity(shortage),excess:quantity(excess),
      overDemand:quantity(overDemand),reconciledLines:v.lines.length},'W-02');
  }
  return Object.freeze({expenseVoucher,cashDenominations,transferLines});
});
);
    if(typeof s!=='string'||!re.test(s.trim())) throw Error('INVALID_DECIMAL:'+key);
    const parts=s.trim().split('.'),factor=10**digits;
    const n=Number(parts[0])*factor+Number((parts[1]||'').padEnd(digits,'0'));
    if(!Number.isSafeInteger(n)||(positiveOnly&&n===0)) throw Error('UNSAFE_OR_ZERO:'+key);
    return n;
  }
  function money(v,k){return integerScaled(v,k,2);}
  function qty(v,k){return integerScaled(v,k,4);}
  function amount(n){return(n/100).toFixed(2);}
  function quantity(n){return(n/10000).toFixed(4);}
  function result(blockers, evidence, source) {
    return Object.freeze({source,status:blockers.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
      blockers:Object.freeze(blockers),evidence:Object.freeze(evidence),
      authorized:false,fieldParityConfirmed:false,erpPosted:false});
  }
  function expenseVoucher(input) {
    const v=input||{},reasons=[],source='C-02';
    if(!Array.isArray(v.lines)||v.lines.length===0||v.lines.length>100)
      throw Error('INVALID_EXPENSE_LINES');
    if(!present(v.voucherRef)||!present(v.sheetNo)) reasons.push('EXPENSE_SOURCE_REFERENCE_REQUIRED');
    if(!present(v.preparedBy)||!present(v.paidBy)) reasons.push('EXPENSE_ROLE_EVIDENCE_REQUIRED');
    if(v.drawerUntouched!==true)reasons.push('SALES_DRAWER_NOT_CONFIRMED_UNTOUCHED');
    if(!['cash','bank','mobile','card'].includes(v.payMode))
      reasons.push('EXPENSE_PAYMENT_MODE_REQUIRED');
    if(v.payMode!=='cash'&&(!present(v.moneyAccountId)||!present(v.accountProofRef)))
      reasons.push('NONCASH_SOURCE_ACCOUNT_PROOF_REQUIRED');
    const sourcePolicy=v.approvedExpenseMax===undefined?null:money(v.approvedExpenseMax,'approvedExpenseMax');
    const imprest=v.approvedImprest===undefined?null:money(v.approvedImprest,'approvedImprest');
    if(sourcePolicy===null||!present(v.expenseLimitPolicyRef))
      reasons.push('EXPENSE_MAX_POLICY_REQUIRED');
    if(imprest===null||!present(v.imprestPolicyRef))
      reasons.push('IMPREST_POLICY_REQUIRED');
    const cash=money(v.cashNow,'cashNow'),receipts=money(v.receiptsTotal,'receiptsTotal');
    const sumCR=cash+receipts;
    if(imprest!==null&&sumCR!==imprest) reasons.push('IMPREST_MISMATCH');
    let total=0,missingReceipt=0,overLimit=0;
    for(let i=0;i<v.lines.length;i++){
      const row=v.lines[i];if(!row||typeof row!=='object')throw Error('INVALID_EXPENSE_ROW:'+i);
      const paid=money(row.amount,'lines['+i+'].amount');
      if(!present(row.head)||!present(row.to))reasons.push('EXPENSE_LINE_IDENTITY_MISSING:'+i);
      if(!['yes','no'].includes(row.receipt))reasons.push('RECEIPT_STATUS_UNKNOWN:'+i);
      if(row.receipt==='yes'&&!present(row.receiptRef))
        reasons.push('RECEIPT_PROOF_REFERENCE_REQUIRED:'+i);
      if(row.receipt==='no'&&paid>0)missingReceipt+=paid;
      if(sourcePolicy!==null&&paid>sourcePolicy)overLimit++;
      if(!Number.isSafeInteger(total+paid))throw Error('EXPENSE_TOTAL_OVERFLOW');
      total+=paid;
    }
    if(missingReceipt>0&&!present(v.noReceiptReason))
      reasons.push('RECEIPT_REASON_MISSING');
    if(missingReceipt>0) reasons.push('MISSING_RECEIPT_REQUIRES_REVIEW');
    if(overLimit>0&&(!present(v.approvedBy)||!present(v.approvalRef)||
      (present(v.preparedBy)&&v.preparedBy.trim()===v.approvedBy?.trim())||
      (present(v.paidBy)&&v.paidBy.trim()===v.approvedBy?.trim())))
      reasons.push('OVER_LIMIT_INDEPENDENT_APPROVAL_MISSING');
    if(overLimit>0)reasons.push('OVER_LIMIT_EXPENSE_REQUIRES_REVIEW');
    return result(reasons,{expenseTotalBDT:amount(total),cashPlusReceiptsBDT:amount(sumCR),
      missingReceiptBDT:amount(missingReceipt),overLimitCount:overLimit,
      ruleRefs:['expense_max','imprest'],controlVersion:'BATCH-001-DRAFT'},source);
  }
  function cashDenominations(v) {
    v=v||{};const reasons=[];
    if(!Array.isArray(v.denominations)||v.denominations.length===0||v.denominations.length>30)
      throw Error('INVALID_DENOMINATIONS');
    if(!present(v.closingRef)||!present(v.sealRef)||!present(v.ledgerRef))
      reasons.push('CASH_SOURCE_DOCUMENT_MISSING');
    if(!present(v.carrier)||!present(v.sentBy)||!present(v.receivedBy)||
      v.sentBy===v.receivedBy)reasons.push('INDEPENDENT_CASH_COUNT_ROLES_REQUIRED');
    if(v.sheetAttached!==true)reasons.push('ORIGINAL_SHOWROOM_SHEET_MISSING');
    const leave=money(v.floatLeft,'floatLeft');
    const fixed=v.approvedFloat===undefined?null:money(v.approvedFloat,'approvedFloat');
    if(fixed===null)reasons.push('DRAWER_FLOAT_POLICY_MISSING');
    else if(leave!==fixed)reasons.push('DRAWER_FLOAT_DIFFERS_FROM_POLICY');
    let counted=0,hub=0;
    const values=new Set();
    for(let i=0;i<v.denominations.length;i++){
      const row=v.denominations[i],denom=money(row?.denomination,'denomination['+i+']');
      const sent=integerScaled(row?.sentCount,'sentCount['+i+']',0);
      const recount=integerScaled(row?.hubCount,'hubCount['+i+']',0);
      if(denom<=0||values.has(denom))throw Error('DUPLICATE_OR_ZERO_DENOMINATION');
      values.add(denom);
      counted+=denom*sent;hub+=denom*recount;
      if(!Number.isSafeInteger(counted)||!Number.isSafeInteger(hub))throw Error('CASH_DENOMINATION_OVERFLOW');
    }
    const dispatched=counted-leave,difference=hub-dispatched;
    if(dispatched<0)reasons.push('FLOAT_GREATER_THAN_COUNTED_CASH');
    if(difference!==0)reasons.push('HUB_INDEPENDENT_RECOUNT_MISMATCH');
    if(difference!==0&&!present(v.differenceReason))
      reasons.push('DIFFERENCE_REASON_REQUIRED');
    if(v.sealIntact!==true)reasons.push('SEAL_INTACT_NOT_CONFIRMED');
    if(!present(v.ledgerLine))reasons.push('CASH_BANK_LEDGER_LINE_REQUIRED');
    return result(reasons,{countedTotalBDT:amount(counted),handoverBDT:amount(dispatched),
      hubReceivedBDT:amount(hub),differenceBDT:amount(difference),
      sourceFormula:'counted_total - leave_float = handover; hub_count - handover = diff'},'C-01');
  }
  function transferLines(v) {
    v=v||{};const reasons=[];
    if(!Array.isArray(v.lines)||v.lines.length===0||v.lines.length>100)
      throw Error('INVALID_TRANSFER_LINES');
    if(!present(v.challanRef)||!present(v.fromLocation)||!present(v.toLocation))
      reasons.push('TRANSFER_ID_OR_LOCATIONS_MISSING');
    if(present(v.fromLocation)&&v.fromLocation===v.toLocation)
      reasons.push('SAME_LOCATION_TRANSFER_BLOCKED');
    if(!present(v.sentBy)||!present(v.receivedBy)||v.sentBy===v.receivedBy)
      reasons.push('INDEPENDENT_RECEIVER_REQUIRED');
    if(v.productionDatesWritten!==true||v.gradesWritten!==true)
      reasons.push('FOOD_DATE_GRADE_MARKING_MISSING');
    if(v.outsideDemand===true){
      reasons.push('OUTSIDE_DEMAND_REQUIRES_REVIEW');
      if(!present(v.outsideReason))reasons.push('OUTSIDE_DEMAND_REASON_REQUIRED');
    }else if(v.outsideDemand!==false)reasons.push('OUTSIDE_DEMAND_STATUS_UNKNOWN');
    if(v.customerOrder===true&&!present(v.customerOrderRef))reasons.push('CUSTOMER_ORDER_REFERENCE_REQUIRED');
    if(v.customerOrder!==true&&v.customerOrder!==false)
      reasons.push('CUSTOMER_ORDER_STATUS_UNKNOWN');
    let shortage=0,excess=0,overDemand=0;
    const keys=new Set();
    for(let i=0;i<v.lines.length;i++){
      const row=v.lines[i];if(!row||typeof row!=='object')throw Error('INVALID_TRANSFER_LINE:'+i);
      if(!present(row.item)||!present(row.productionDate)||!present(row.grade))
        reasons.push('ITEM_DATE_GRADE_REQUIRED:'+i);
      const key=[row.item,row.productionDate,row.grade].join('|');
      if(keys.has(key))reasons.push('DUPLICATE_ITEM_LOT_ON_CHALLAN:'+i);
      keys.add(key);
      const sent=qty(row.sentQty,'sent['+i+']'),received=qty(row.receivedQty,'received['+i+']');
      if(sent>received)shortage+=sent-received;
      if(received>sent)excess+=received-sent;
      if(row.demandQty!==undefined){
        const demand=qty(row.demandQty,'demand['+i+']');
        if(sent>demand)overDemand+=sent-demand;
      }
    }
    if(shortage>0)reasons.push('TRANSFER_SHORTAGE_REQUIRES_REVIEW');
    if(excess>0)reasons.push('TRANSFER_EXCESS_REQUIRES_REVIEW');
    if(overDemand>0)reasons.push('OVER_DEMAND_REQUIRES_REVIEW');
    return result(reasons,{shortage:quantity(shortage),excess:quantity(excess),
      overDemand:quantity(overDemand),reconciledLines:v.lines.length},'W-02');
  }
  return Object.freeze({expenseVoucher,cashDenominations,transferLines});
});
