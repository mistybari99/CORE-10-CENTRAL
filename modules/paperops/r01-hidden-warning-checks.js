/* Source-derived R-01 previously missed dynamic warning families. Isolated pure gates.
 * Frozen forms.js reviewed, never executed; no accounting posting or approval.
 */
(function(root,factory) {
 'use strict';
 const api=factory();
 if(typeof module==='object'&&module.exports)module.exports=api;
 if(root)root.CORE10_R01_MISSED_WARNING_CHECKS=api;
})(typeof globalThis==='object'?globalThis:this,function(){
 'use strict';
 function fixed(value,key,decimals=2,allowNegative=false){
  const raw=typeof value==='number'&&Number.isFinite(value)?String(value):value;
  const reg=allowNegative?/^-?\d+(?:\.\d{1,2})?$/:/^\d+(?:\.\d{1,2})?$/;
  if(typeof raw!=='string'||!reg.test(raw))throw Error('INVALID_SOURCE_MONEY:'+key);
  const negative=raw.startsWith('-'),normal=negative?raw.slice(1):raw;
  const [whole,fraction='']=normal.split('.');
  const n=Number(whole)*10**decimals+Number(fraction.padEnd(decimals,'0'));
  if(!Number.isSafeInteger(n))throw Error('UNSAFE_SOURCE_MONEY:'+key);
  return negative?-n:n;
 }
 function fmt(n){return (n/100).toFixed(2);}
 function gate(sourceCode,alerts,needs,evidence){
  return Object.freeze({legacyForm:'R-01',sourceWarning:sourceCode,
   status:alerts.length||needs.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
   alerts:Object.freeze(alerts),needs:Object.freeze(needs),evidence:Object.freeze(evidence),
   sourceFormulaParityCertified:false,authorized:false,erpPosted:false});
 }
 function goodsMoneyGap(v){
  if(!v||typeof v!=='object')throw Error('INVALID_GOODS_MONEY_INPUT');
  const sales=fixed(v.totalEnteredBDT,'totalEnteredBDT');
  const party=fixed(v.partyCashBDT,'partyCashBDT');
  const goods=fixed(v.goodsBasedBDT,'goodsBasedBDT');
  const retail=sales-party,difference=goods-retail,alerts=[],needs=[];
  if(retail<0)alerts.push({code:'RETAIL_AMOUNT_NEGATIVE',severity:'red'});
  const percentage=v.approvedPercentTolerance===undefined?null:fixed(v.approvedPercentTolerance,'approvedPercentTolerance');
  const maximum=v.approvedMaxToleranceBDT===undefined?null:fixed(v.approvedMaxToleranceBDT,'approvedMaxToleranceBDT');
  if(difference!==0){
   const abs=Math.abs(difference);
   const percentWithin=percentage!==null&&retail>0&&
    BigInt(abs)*100n*100n<=BigInt(retail)*BigInt(percentage);
   const amountWithin=maximum!==null&&abs<=maximum;
   if(percentage===null&&maximum===null)needs.push('goods_money_tol_pct','goods_money_tol_max');
   alerts.push({code:'goods_money_gap',severity:percentWithin||amountWithin?'yellow':'red'});
  }
  return gate('goods_money_gap',alerts,needs,{retailBDT:fmt(retail),goodsBasedBDT:fmt(goods),
    differenceBDT:fmt(difference),toleranceSource:'approved policy required; percent OR absolute BDT'});
 }
 function cashShortOver(v){
  if(!v||typeof v!=='object')throw Error('INVALID_CASH_SHORT_OVER_INPUT');
  const alerts=[],needs=[];
  const opening=v.openCountedBDT!==undefined?
   fixed(v.openCountedBDT,'openCountedBDT'):
   v.approvedDrawerFloatBDT!==undefined?fixed(v.approvedDrawerFloatBDT,'approvedDrawerFloatBDT'):null;
  if(opening===null)needs.push('drawer_float_or_open_counted');
  const keys=['totalEntered','digitalTotal','dues','newAdvance','priorAdvance','refund',
   'creditSales','middayHub','rounding'];
  const vals={};
  for(const key of keys){
   if(v[key+'BDT']===undefined){needs.push(key+'BDT');continue;}
   vals[key]=fixed(v[key+'BDT'],key+'BDT',2,key==='rounding');
  }
  if(v.countedCashBDT===undefined)needs.push('countedCashBDT');
  const count=v.countedCashBDT===undefined?null:fixed(v.countedCashBDT,'countedCashBDT');
  const tolerance=v.approvedCashToleranceBDT===undefined?null:fixed(v.approvedCashToleranceBDT,'approvedCashToleranceBDT');
  let expected=null,difference=null;
  if(opening!==null&&keys.every(k=>Object.hasOwn(vals,k))&&count!==null){
   expected=opening+vals.totalEntered-vals.digitalTotal+vals.dues+vals.newAdvance-
    vals.priorAdvance-vals.refund-vals.creditSales-vals.middayHub+vals.rounding;
   difference=count-expected;
   if(!Number.isSafeInteger(expected)||!Number.isSafeInteger(difference))throw Error('UNSAFE_CASH_EXPECTATION');
   if(count===0)alerts.push({code:'ZERO_CASH_COUNT_REQUIRES_PROOF',severity:'red'});
   if(difference!==0){
    if(tolerance===null)needs.push('cash_tol');
    alerts.push({code:'cash_short_over',severity:tolerance!==null&&Math.abs(difference)<=tolerance?'yellow':'red'});
   }
  }
  return gate('cash_short_over',alerts,needs,{expectedBDT:expected===null?null:fmt(expected),
   countedBDT:count===null?null:fmt(count),differenceBDT:difference===null?null:fmt(difference),
   sourceFormula:'opening + total_sales - digital + dues + new_adv - prior_adv - refunds - credit - midday_hub + rounding'});
 }
 function temperatureFlagFromChecker(index,checkerBlocker){
  if(!Number.isInteger(index)||index<0||index>2)throw Error('ONLY_THREE_SOURCE_FRIDGES');
  if(checkerBlocker!=='FRIDGE_TEMPERATURE_OUTSIDE_POLICY:'+index)
   throw Error('SOURCE_FRIDGE_FLAG_MAPPING_MISMATCH');
  return 'temp_out_'+String(index+1);
 }
 return Object.freeze({goodsMoneyGap,cashShortOver,temperatureFlagFromChecker});
});
