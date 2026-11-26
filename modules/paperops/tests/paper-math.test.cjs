'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const math=require('../paper-math.js');
const goodJalebi={
 flourIssuedKg:'10',openDoughKg:'2',closeDoughKg:'1',
 approvedBaseConversionPercent:'80',approvedKgPerKgFlour:'1.5',
 jalebiSales:'2000',approvedPricePerKg:'200',unsoldKg:'6.875',samplesKg:'0',
 oilIssuedL:'3',openOilL:'2',closeOilL:'1',
 syrupReceivedL:'5',openSyrupL:'1',closeSyrupL:'2',
 producedBy:'Cook',measuredBy:'Checker',scaleChecked:true,issueSlipRef:'ISSUE-1',
 unsoldDecision:'DATE_TAG',approvedToleranceKg:'0.05'
};
test('sweets R-02 source formula: 10 + 1×100/80 flour; expected and actual Jalebi match',()=>{
 const x=math.jalebiYield(goodJalebi);
 assert.equal(x.flourUsedKg,'11.2500');
 assert.equal(x.expectedOutputKg,'16.8750');
 assert.equal(x.soldKg,'10.0000');
 assert.equal(x.actualOutputKg,'16.8750');
 assert.equal(x.varianceKg,'0.0000');
 assert.equal(x.oilUsedL,'4.0000');
 assert.equal(x.syrupUsedL,'4.0000');
 assert.deepEqual(x.reasons,[]);
 assert.equal(x.status,'FORMULA_MATCH_REVIEW_SIGNOFF_REQUIRED');
});
test('Jalebi forbids the maker measuring, untested scale, missing issue slips and silent tolerance',()=>{
 assert.throws(()=>math.jalebiYield({
  ...goodJalebi,approvedToleranceKg:undefined, producedBy:'Same',measuredBy:'Same',
  scaleChecked:false, issueSlipRef:'', unsoldDecision:''
 }), /NUMBER_REQUIRED/);
});
test('Jalebi no tolerance or critical controls => warnings, not false approval',()=>{
 const {approvedToleranceKg,...rest}=goodJalebi;
 const x=math.jalebiYield({...rest,producedBy:'Same',measuredBy:'Same',scaleChecked:false,issueSlipRef:'',unsoldDecision:''});
 for(const code of ['INDEPENDENT_MEASURER_REQUIRED','SCALE_CHECK_REQUIRED','MATERIAL_ISSUE_SLIP_REQUIRED',
  'UNSOLD_DISPOSITION_REQUIRED','TOLERANCE_POLICY_REQUIRED'])assert.ok(x.reasons.includes(code),code);
 assert.equal(x.status,'REVIEW');
});
test('Jalebi changed sold/unsold without tolerance must surface discrepancy',()=>{
 const x=math.jalebiYield({...goodJalebi,unsoldKg:'4.875'});
 assert.equal(x.varianceKg,'-2.0000');
 assert.ok(x.reasons.includes('YIELD_OUTSIDE_APPROVED_TOLERANCE'));
 assert.equal(x.status,'REVIEW');
 assert.throws(()=>math.jalebiYield({...goodJalebi,approvedBaseConversionPercent:'0'}),/APPROVED_CONVERSION_YIELD_PRICE_REQUIRED/);
});
test('stock continuous balance: no phantom adjustment, zero/negative violation guarded',()=>{
 const x=math.stockBalance({opening:'10',received:'5',returnedIn:'1',issued:'2',sold:'4',
  wasted:'1',returnedOut:'0',physicalClose:'9'});
 assert.equal(x.expected,'9.0000');
 assert.equal(x.variance,'0.0000');
 assert.equal(x.status,'MATCH');
 assert.equal(x.adjustmentAuthorized,false);
 const bad=math.stockBalance({opening:'10',received:'5',returnedIn:'1',issued:'2',sold:'4',
  wasted:'1',returnedOut:'0',physicalClose:'8'});
 assert.equal(bad.status,'BLOCK');
 assert.ok(bad.reason.includes('STOCK_COUNT_VARIANCE'));
 const neg=math.stockBalance({opening:'0',received:'0',returnedIn:'0',issued:'10',sold:'0',
  wasted:'0',returnedOut:'0',physicalClose:'0'});
 assert.ok(neg.reason.includes('NEGATIVE_BOOK_STOCK'));
});
test('cash closing uses cents not binary float and finds real cash difference',()=>{
 const x=math.cashClosing({openingFloat:'10.10',cashSales:'20.20',receipts:'0.30',
  approvedExpenses:'4.10',refunds:'1.00',bankDeposits:'0',handovers:'10.00',countedClose:'15.50'});
 assert.equal(x.expected,'15.50');
 assert.equal(x.status,'MATCH');
 assert.equal(x.transferIsEvidenceOnly,true);
 assert.equal(math.cashClosing({openingFloat:'10.10',cashSales:'20.20',receipts:'0.30',
  approvedExpenses:'4.10',refunds:'1.00',bankDeposits:'0',handovers:'10.00',countedClose:'14.50'}).variance,'-1.00');
});
test('three-way match never grants payment authority; blocks mismatches even if approved',()=>{
 const good={poRef:'PO-1',grnRef:'GRN-1',billRef:'BILL-1',poAmount:'100',acceptedAmount:'100',
  invoiceAmount:'100',paymentProposed:'100',approvedBy:'Boss',preparedBy:'Cashier'};
 assert.equal(math.threeWay(good).status,'MATCHED_FOR_PAPER_REVIEW');
 assert.equal(math.threeWay(good).readyForERPPosting,false);
 const bad=math.threeWay({...good,acceptedAmount:'80'});
 assert.ok(bad.reasons.includes('PO_GRN_BILL_MISMATCH'));
 assert.ok(bad.reasons.includes('PAYMENT_REQUEST_WITH_MISMATCH'));
 assert.equal(bad.status,'BLOCK');
 assert.ok(math.threeWay({...good,approvedBy:'Cashier'}).reasons.includes('INDEPENDENT_APPROVAL_MISSING'));
 assert.throws(()=>math.threeWay({...good,grnRef:''}),/SOURCE_REFERENCE_REQUIRED/);
});
test('payment settlement detects paper/statement, fee/net, and personal-account mismatches',()=>{
 const good={paperRecorded:'110.10',statementGross:'110.10',processingFee:'2.10',bankReceived:'108'};
 assert.equal(math.digitalSettlement(good).status,'MATCH');
 const bad=math.digitalSettlement({...good,bankReceived:'107.99',paperRecorded:'110.09',personalAccount:true});
 assert.deepEqual(bad.reasons,['PAPER_STATEMENT_MISMATCH','BANK_NET_SETTLEMENT_MISMATCH','PERSONAL_ACCOUNT_ESCALATION']);
});
test('ageing requires external credit policy and fails on incomplete bucket split',()=>{
 const good={totalDue:'100',days0to30:'20',days31to60:'50',daysOver60:'30',creditLimit:'80',creditStopped:true};
 const x=math.receivableAging(good);
 assert.equal(x.bucketVariance,'0.00');
 assert.equal(x.creditOverLimit,true);
 assert.ok(x.reasons.includes('OVER_60_REVIEW_REQUIRED'));
 const overdue=math.receivableAging({...good,creditStopped:false,days31to60:'40'});
 assert.ok(overdue.reasons.includes('CREDIT_EXCEEDS_LIMIT_NOT_STOPPED'));
 assert.ok(overdue.reasons.includes('AGING_BUCKET_MISMATCH'));
 const {creditLimit,...without}=good;
 assert.ok(math.receivableAging(without).reasons.includes('CREDIT_LIMIT_POLICY_REQUIRED'));
});
test('quotation selection flags sole quote, non-lowest and no approved policy',()=>{
 const q=[{supplier:'A',rate:'90'},{supplier:'B',rate:'100'}];
 const good=math.quoteSelection({quotes:q,selectedSupplier:'A',comparisonThreshold:'500'});
 assert.deepEqual(good.reasons,[]);
 const review=math.quoteSelection({quotes:q,selectedSupplier:'B',comparisonThreshold:'500',selectionReason:'Quality',
  collectedBy:'Buyer',independentApprover:'Owner'});
 assert.ok(review.reasons.includes('NOT_LOWEST_RATE'));
 const single=math.quoteSelection({quotes:[q[0]],selectedSupplier:'A'});
 assert.ok(single.reasons.includes('SINGLE_QUOTE_REVIEW_REQUIRED'));
 assert.ok(single.reasons.includes('COMPARISON_POLICY_REQUIRED'));
 assert.throws(()=>math.quoteSelection({quotes:q,selectedSupplier:'C'}),/SELECTED_SUPPLIER_NOT_QUOTED/);
});
test('monthly profit uses original A-02 cost path and requires independent review',()=>{
 const v={sales:'500',openStock:'100',purchases:'400',closeStock:'180',
  operatingExpenses:'40',payroll:'60',bankCharges:'5',receivables:'30',payables:'20',
  checkedBy:'Checker',preparedBy:'Manager'};
 const x=math.monthlyProfit(v);
 assert.equal(x.cogs,'320.00');
 assert.equal(x.gross,'180.00');
 assert.equal(x.net,'75.00');
 assert.deepEqual(x.reasons,[]);
 assert.equal(x.postingAuthorized,false);
 assert.ok(math.monthlyProfit({...v,checkedBy:'Manager'}).reasons.includes('INDEPENDENT_REVIEW_REQUIRED'));
 assert.ok(math.monthlyProfit({...v,closeStock:'600'}).reasons.includes('NEGATIVE_COGS_CHECK_STOCK'));
});
test('unsafe values, missing data and invented precision are always rejected',()=>{
 assert.throws(()=>math.digitalSettlement({paperRecorded:'0.001',statementGross:'0',processingFee:'0',bankReceived:'0'}),
  /INVALID_PRECISION/);
 assert.throws(()=>math.digitalSettlement({paperRecorded:'',statementGross:'0',processingFee:'0',bankReceived:'0'}),
  /NUMBER_REQUIRED/);
 assert.throws(()=>math.digitalSettlement({paperRecorded:'NaN',statementGross:'0',processingFee:'0',bankReceived:'0'}),
  /NUMBER_REQUIRED/);
 assert.throws(()=>math.digitalSettlement({paperRecorded:'-1',statementGross:'0',processingFee:'0',bankReceived:'0'}),
  /NEGATIVE_NOT_ALLOWED/);
 assert.throws(()=>math.digitalSettlement({paperRecorded:'9999999999999999999999',statementGross:'0',processingFee:'0',bankReceived:'0'}),
  /UNSAFE_NUMBER/);
});
