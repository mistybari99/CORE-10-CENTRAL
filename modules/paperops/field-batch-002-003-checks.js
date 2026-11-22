/* CORE-10 PaperOps first-pass source candidate control gates, batches 002–003.
 * Legacy source: W-03 Stock Count, R-01 Daily Showroom. No ERP posting, no signoff.
 * The original compiled code is NOT loaded or executed.
 */
(function(root,factory){
  'use strict';
  const api=factory();
  if(typeof module==='object'&&module.exports)module.exports=api;
  if(root)root.CORE10_PAPER_BATCH023_CHECKS=api;
})(typeof globalThis==='object'?globalThis:this,function(){
 'use strict';
 function present(v){return typeof v==='string'&&v.trim().length>0;}
 function dec(value,field,places=4){
  const raw=typeof value==='number'&&Number.isFinite(value)?String(value):value;
  if(typeof raw!=='string'||!(new RegExp('^\\d+(?:\\.\\d{1,'+places+'})?$')).test(raw))
   throw Error('INVALID_DECIMAL:'+field);
  const [whole,frac='']=raw.split('.');
  const n=Number(whole)*10**places+Number(frac.padEnd(places,'0'));
  if(!Number.isSafeInteger(n))throw Error('UNSAFE_AMOUNT:'+field);
  return n;
 }
 const qty=(v,k)=>dec(v,k,4), money=(v,k)=>dec(v,k,2);
 const fmt=(v,places)=>Number(v/10**places).toFixed(places);
 function r(value,reason,flags){
  if(!value)return;
  if(!flags.includes(reason))flags.push(reason);
 }
 function finish(source,flags,needs,evidence,legacyMap){
  return {source,status:flags.length||needs.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
    blockers:flags,needs,legacyFlags:flags.filter(x=>Object.hasOwn(legacyMap,x)).map(x=>legacyMap[x]),
    evidence,postingAuthorized:false,approved:false,parityCertified:false};
 }
 const COUNT_FLAGS=Object.freeze({
  COUNT_VARIANCE_OUTSIDE_APPROVED_TOLERANCE:'count_variance',
  COUNT_VARIANCE_WITHIN_APPROVED_TOLERANCE:'count_variance_small',
  COUNTER_IS_STOREKEEPER:'counter_is_storekeeper',
  WITNESS_IS_COUNTER:'same_witness'
 });
 function stockCountReview(v){
  if(!v||!Array.isArray(v.rows)||!v.rows.length||v.rows.length>100)
   throw Error('INVALID_COUNT_ROWS');
  const flags=[],needs=[],policyPct=v.approvedTolerancePercent===undefined?null:dec(v.approvedTolerancePercent,'approvedTolerancePercent'),
    policyMax=v.approvedToleranceValueBDT===undefined?null:money(v.approvedToleranceValueBDT,'approvedToleranceValueBDT');
  if(policyPct===null&&policyMax===null)needs.push('count_tol_pct','count_tol_max');
  if(!present(v.counter)||!present(v.storekeeper)||!present(v.witness))
   r(true,'COUNT_ACTOR_PROOF_REQUIRED',flags);
  r(present(v.counter)&&v.counter===v.storekeeper,'COUNTER_IS_STOREKEEPER',flags);
  r(present(v.counter)&&v.counter===v.witness,'WITNESS_IS_COUNTER',flags);
  if(!present(v.countSheetRef)||!present(v.stockLedgerRef))
   r(true,'COUNT_SOURCE_REFS_REQUIRED',flags);
  if(v.movementDuringCount===true){
   r(true,'COUNT_MOVEMENT_DURING_FREEZE_REVIEW',flags);
   if(!present(v.movementDetails))r(true,'COUNT_MOVEMENT_DETAILS_REQUIRED',flags);
  }else if(v.movementDuringCount!==false)r(true,'COUNT_FREEZE_CONFIRMATION_REQUIRED',flags);
  const refs=new Set(),results=[];
  let outside=0,inside=0,totalVarianceQty=0n;
  for(let i=0;i<v.rows.length;i++){
   const row=v.rows[i];
   if(!row||!present(row.item)||refs.has(row.item))throw Error('MISSING_OR_DUPLICATE_COUNT_ITEM:'+i);
   refs.add(row.item);
   const book=qty(row.bookQty,'rows['+i+'].bookQty'),
    count=qty(row.countQty,'rows['+i+'].countQty'),
    unitPrice=money(row.sellPriceBDT,'rows['+i+'].sellPriceBDT'),
    diff=BigInt(count)-BigInt(book),abs=diff<0n?-diff:diff;
   const approximateValueCents=(abs*BigInt(unitPrice)+9999n)/10000n;
   const withinPct=policyPct!==null&&book>0&&abs*1000000n<=BigInt(book)*BigInt(policyPct);
   const withinValue=policyMax!==null&&approximateValueCents<=BigInt(policyMax);
   const within=diff===0n||withinPct||withinValue;
   if(diff!==0n){if(within)inside++;else outside++;}
   totalVarianceQty+=abs;
   results.push({item:row.item,bookQty:fmt(book,4),countQty:fmt(count,4),
    varianceQty:fmt(Number(diff),4),status:diff===0n?'MATCH':within?'SMALL_VARIANCE_REVIEW':'OUTSIDE_POLICY_BLOCK',
    estimatedValueBDT:fmt(Number(approximateValueCents),2)});
  }
  r(outside>0,'COUNT_VARIANCE_OUTSIDE_APPROVED_TOLERANCE',flags);
  r(inside>0,'COUNT_VARIANCE_WITHIN_APPROVED_TOLERANCE',flags);
  return finish('W-03',flags,needs,{rows:results,outside,inside,
   countedUnits:results.length,adjustmentAuthorized:false},COUNT_FLAGS);
 }
 const DAILY_FLAGS=Object.freeze({
  OPEN_DRAWER_FLOAT_MISMATCH:'open_float_diff',
  OPEN_IMPREST_MISMATCH:'open_imprest_diff',
  GOODS_RECEIPT_SHORTAGE:'receipt_short',
  CLEANER_IS_CHECKER:'same_person_cleaning',
  CATEGORY_SALES_TOTAL_MISMATCH:'cat_total_mismatch',
  SECOND_CASH_COUNT_MISMATCH:'second_count_mismatch',
  WITNESS_IS_WRITER:'witness_is_maker',
  CLOSING_FLOAT_DIFFERS:'float_left_diff',
  SELF_APPROVED_WASTE:'self_waste_approval',
  EXPIRED_PRODUCT_LOSS:'expired_loss',
  SECOND_SIGNER_IS_WRITER:'second_sig_is_maker'
 });
 function showroomSourceReview(v){
  if(!v||typeof v!=='object')throw Error('INVALID_SHOWROOM_INPUT');
  const flags=[],needs=[];
  const drawer=v.approvedDrawerFloat===undefined?null:money(v.approvedDrawerFloat,'approvedDrawerFloat'),
    imprest=v.approvedImprest===undefined?null:money(v.approvedImprest,'approvedImprest');
  if(drawer===null)needs.push('drawer_float');
  if(imprest===null)needs.push('imprest');
  const opening=money(v.openCountedBDT,'openCountedBDT'),
    floatLeft=money(v.floatLeftBDT,'floatLeftBDT'),
    impCash=money(v.imprestCashBDT,'imprestCashBDT'),
    impReceipts=money(v.imprestReceiptsBDT,'imprestReceiptsBDT');
  r(drawer!==null&&opening!==drawer,'OPEN_DRAWER_FLOAT_MISMATCH',flags);
  r(imprest!==null&&impCash+impReceipts!==imprest,'OPEN_IMPREST_MISMATCH',flags);
  r(drawer!==null&&floatLeft!==drawer,'CLOSING_FLOAT_DIFFERS',flags);
  if(!present(v.preparedBy)||!present(v.dutyManager)||!present(v.closeRef))
   r(true,'SHOWROOM_SIGNED_SOURCE_REQUIRED',flags);
  if(!['normal','busy'].includes(v.dayType))r(true,'DAY_TYPE_REQUIRED',flags);
  if(v.openingSafetyOk!==true)r(true,'OPENING_SAFETY_NOT_CONFIRMED',flags);
  if(v.expiredProductIsolated!==true)r(true,'EXPIRED_STOCK_ISOLATION_NOT_CONFIRMED',flags);
  if(!Array.isArray(v.fridges)||v.fridges.length>3)
   throw Error('INVALID_FRIDGE_CHECKS');
  for(let i=0;i<v.fridges.length;i++){
   const f=v.fridges[i];
   if(!present(f.name))r(true,'FRIDGE_IDENTITY_REQUIRED:'+i,flags);
   const temp=dec(f.temperatureC,'fridge.temperatureC['+i+']',2);
   if(f.minTempC===undefined||f.maxTempC===undefined){
    needs.push('fridge'+(i+1)+'_min','fridge'+(i+1)+'_max');
   }else{
    const min=dec(f.minTempC,'fridge.minTempC['+i+']',2),max=dec(f.maxTempC,'fridge.maxTempC['+i+']',2);
    if(min>max||temp<min||temp>max)r(true,'FRIDGE_TEMPERATURE_OUTSIDE_POLICY:'+i,flags);
   }
  }
  let shortage=0,expiredLoss=0;
  if(!Array.isArray(v.receipts)||!Array.isArray(v.cleaning)||!Array.isArray(v.stock)||!Array.isArray(v.salesCategories))
   throw Error('SOURCE_ROWS_REQUIRED');
  for(let i=0;i<v.receipts.length;i++){
   const x=v.receipts[i],written=qty(x.writtenQty,'receipt.written['+i+']'),
    actual=qty(x.countedQty,'receipt.counted['+i+']');
   if(written>actual)shortage+=written-actual;
   if(!present(x.challanRef))r(true,'RECEIPT_SOURCE_REF_REQUIRED:'+i,flags);
  }
  r(shortage>0,'GOODS_RECEIPT_SHORTAGE',flags);
  r(v.cleaning.some(x=>present(x.doer)&&x.doer===x.verifier),'CLEANER_IS_CHECKER',flags);
  let sum=0;
  for(const [i,x] of v.salesCategories.entries()){
   sum+=money(x.amount,'salesCategories['+i+']');
   if(!Number.isSafeInteger(sum))throw Error('SALES_TOTAL_UNSAFE');
  }
  const total=money(v.totalSalesBDT,'totalSalesBDT');
  r(sum!==total,'CATEGORY_SALES_TOTAL_MISMATCH',flags);
  const first=money(v.firstCashCountBDT,'firstCashCountBDT'),second=money(v.secondCashCountBDT,'secondCashCountBDT');
  r(first!==second,'SECOND_CASH_COUNT_MISMATCH',flags);
  r(present(v.witness)&&v.witness===v.preparedBy,'WITNESS_IS_WRITER',flags);
  for(let i=0;i<v.stock.length;i++){
   const x=v.stock[i],waste=qty(x.wasteQty,'stock.waste['+i+']'),
    expired=money(x.expiredLossBDT,'stock.expiredLossBDT['+i+']');
   r(waste>0&&x.wasteApprovedBy===v.preparedBy,'SELF_APPROVED_WASTE',flags);
   expiredLoss+=expired;if(!Number.isSafeInteger(expiredLoss))throw Error('EXPIRED_LOSS_UNSAFE');
  }
  r(expiredLoss>0,'EXPIRED_PRODUCT_LOSS',flags);
  r(present(v.secondSigner)&&v.secondSigner===v.preparedBy,'SECOND_SIGNER_IS_WRITER',flags);
  if(!present(v.witness)||!present(v.secondSigner))r(true,'INDEPENDENT_WITNESS_PROOF_REQUIRED',flags);
  return finish('R-01',flags,needs,{receiptShortQty:fmt(shortage,4),
    totalSalesBDT:fmt(total,2),categoryTotalBDT:fmt(sum,2),
    expiredLossBDT:fmt(expiredLoss,2),fridgesChecked:v.fridges.length},DAILY_FLAGS);
 }
 return Object.freeze({COUNT_FLAGS,DAILY_FLAGS,stockCountReview,showroomSourceReview});
});