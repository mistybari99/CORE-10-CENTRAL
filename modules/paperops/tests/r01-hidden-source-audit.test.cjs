'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const sourceAudit=require('../r01-hidden-source-audit.cjs');
const checks=require('../r01-hidden-warning-checks.js');
const existing=require('../field-batch-002-003-checks.js');
const goods={totalEnteredBDT:'5000',partyCashBDT:'1000',goodsBasedBDT:'4000',
 approvedPercentTolerance:'1',approvedMaxToleranceBDT:'20'};
const cash={openCountedBDT:'500',totalEnteredBDT:'3500',digitalTotalBDT:'800',
 duesBDT:'0',newAdvanceBDT:'100',priorAdvanceBDT:'0',refundBDT:'200',
 creditSalesBDT:'300',middayHubBDT:'1000',roundingBDT:'0',
 countedCashBDT:'1800',approvedCashToleranceBDT:'5'};
function onlyAlert(r,code,severity){
 assert.equal(r.status,'BLOCK');
 assert.equal(r.authorized,false);
 assert.equal(r.sourceFormulaParityCertified,false);
 assert.equal(r.erpPosted,false);
 assert.ok(r.alerts.some(a=>a.code===code&&a.severity===severity),JSON.stringify(r.alerts));
}
test('frozen R-01 calculator contains five missed runtime warnings not covered by first-pass extractor',()=>{
 const a=sourceAudit.audit();
 assert.equal(a.r01_static_warning_candidates,11);
 assert.equal(a.additional_count,5);
 assert.deepEqual(a.newly_found_runtime_warning_codes,
  ['goods_money_gap','cash_short_over','temp_out_1','temp_out_2','temp_out_3']);
 assert.equal(a.all_32_forms_fully_scanned_for_dynamic_warnings,false);
 assert.equal(a.ready_for_release,false);
});
test('R-01 goods-money candidate reproduces subtotal minus party cash and external OR tolerances',()=>{
 const clean=checks.goodsMoneyGap(goods);
 assert.equal(clean.status,'REVIEW_READY_NOT_APPROVED');
 assert.equal(clean.evidence.retailBDT,'4000.00');
 assert.equal(clean.evidence.differenceBDT,'0.00');
 onlyAlert(checks.goodsMoneyGap({...goods,goodsBasedBDT:'4010'}),
  'goods_money_gap','yellow');
 onlyAlert(checks.goodsMoneyGap({...goods,goodsBasedBDT:'4100'}),
  'goods_money_gap','red');
 // 100 BDT difference, 3% threshold of 4,000=120 BDT -> yellow under pct policy.
 onlyAlert(checks.goodsMoneyGap({...goods,goodsBasedBDT:'4100',
  approvedPercentTolerance:'3',approvedMaxToleranceBDT:'0'}),
  'goods_money_gap','yellow');
 const {approvedPercentTolerance,approvedMaxToleranceBDT,...noPolicy}=goods;
 const mismatch=checks.goodsMoneyGap({...noPolicy,goodsBasedBDT:'4010'});
 assert.equal(mismatch.status,'BLOCK');
 assert.ok(mismatch.needs.includes('goods_money_tol_pct'));
 assert.ok(mismatch.needs.includes('goods_money_tol_max'));
 assert.throws(()=>checks.goodsMoneyGap({...goods,goodsBasedBDT:'4000.001'}),/INVALID_SOURCE_MONEY/);
});
test('R-01 cash short/over candidate matches source opening, digital, advances, refunds, credit and cash tolerances',()=>{
 const clean=checks.cashShortOver(cash);
 assert.equal(clean.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(clean));
 assert.equal(clean.evidence.expectedBDT,'1800.00');
 assert.equal(clean.evidence.differenceBDT,'0.00');
 onlyAlert(checks.cashShortOver({...cash,countedCashBDT:'1798'}),
  'cash_short_over','yellow');
 onlyAlert(checks.cashShortOver({...cash,countedCashBDT:'1500'}),
  'cash_short_over','red');
 const {approvedCashToleranceBDT,...noPolicy}=cash;
 const missing=checks.cashShortOver({...noPolicy,countedCashBDT:'1798'});
 assert.equal(missing.status,'BLOCK');
 assert.ok(missing.needs.includes('cash_tol'));
 const {openCountedBDT,...fallback}=cash;
 assert.equal(checks.cashShortOver({...fallback,approvedDrawerFloatBDT:'500'}).status,
  'REVIEW_READY_NOT_APPROVED');
 const {roundingBDT,...noRounding}=cash;
 assert.ok(checks.cashShortOver(noRounding).needs.includes('roundingBDT'));
 assert.throws(()=>checks.cashShortOver({...cash,middayHubBDT:'-2'}),/INVALID_SOURCE_MONEY/);
 assert.ok(checks.cashShortOver({...cash,countedCashBDT:'0'}).alerts.some(x=>
   x.code==='ZERO_CASH_COUNT_REQUIRES_PROOF'));
});
test('all three dynamic fridge flag codes are recovered and off-policy checks are blocked',()=>{
 const baseline={
  dayType:'busy',preparedBy:'Shop maker',dutyManager:'Manager',closeRef:'CLOSE-R01-001',
  openingSafetyOk:true,expiredProductIsolated:true,
  approvedDrawerFloat:'500',openCountedBDT:'500',floatLeftBDT:'500',
  approvedImprest:'1000',imprestCashBDT:'800',imprestReceiptsBDT:'200',
  fridges:[{name:'Display',temperatureC:'4',minTempC:'0',maxTempC:'5'},
   {name:'Freezer',temperatureC:'-18',minTempC:'-22',maxTempC:'-16'},
   {name:'Cold Room',temperatureC:'4',minTempC:'0',maxTempC:'5'}],
  receipts:[],cleaning:[],salesCategories:[{amount:'1000'}],
  totalSalesBDT:'1000',firstCashCountBDT:'800',secondCashCountBDT:'800',
  witness:'Other checker',secondSigner:'Manager',stock:[]
 };
 for(let i=0;i<3;i++){
  const x=structuredClone(baseline);
  x.fridges[i].temperatureC='30';
  const r=existing.showroomSourceReview(x);
  assert.equal(r.status,'BLOCK');
  const blocker='FRIDGE_TEMPERATURE_OUTSIDE_POLICY:'+i;
  assert.ok(r.blockers.includes(blocker),JSON.stringify(r.blockers));
  assert.equal(checks.temperatureFlagFromChecker(i,blocker),'temp_out_'+(i+1));
 }
 assert.throws(()=>checks.temperatureFlagFromChecker(3,'FRIDGE_TEMPERATURE_OUTSIDE_POLICY:3'),
  /ONLY_THREE_SOURCE_FRIDGES/);
 assert.throws(()=>checks.temperatureFlagFromChecker(0,'FRIDGE_TEMPERATURE_OUTSIDE_POLICY:1'),
  /SOURCE_FRIDGE_FLAG_MAPPING_MISMATCH/);
});
