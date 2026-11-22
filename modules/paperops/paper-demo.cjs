'use strict';
/* Deterministic paper-only demo, with synthetic account/item/amounts. Nothing persisted or posted. */
const kit=require('./paper-kit.js');
const math=require('./paper-math.js');
const controls=require('./paper-controls.js');
const demo=require('./demo-fixture.json');
function cents(v,label){
 const s=typeof v==='number'&&Number.isFinite(v)?String(v):v;
 if(typeof s!=='string'||!/^\d+(?:\.\d{1,2})?$/.test(s))throw Error('INVALID_DEMO_AMOUNT:'+label);
 const [whole,decimal='']=s.split('.');
 const n=Number(whole)*100+Number(decimal.padEnd(2,'0'));
 if(!Number.isSafeInteger(n))throw Error('UNSAFE_DEMO_AMOUNT:'+label);
 return n;
}
function units(v,label){
 const s=typeof v==='number'&&Number.isFinite(v)?String(v):v;
 if(typeof s!=='string'||!/^\d+(?:\.\d{1,4})?$/.test(s))throw Error('INVALID_DEMO_QUANTITY:'+label);
 const [whole,decimal='']=s.split('.');
 const n=Number(whole)*10000+Number(decimal.padEnd(4,'0'));
 if(!Number.isSafeInteger(n))throw Error('UNSAFE_DEMO_QUANTITY:'+label);
 return n;
}
function unique(rows,code){
 const ids=rows.map(x=>x.id);
 if(ids.some(x=>typeof x!=='string'||!x.trim())||new Set(ids).size!==ids.length)throw Error('DUPLICATE_OR_MISSING_'+code);
 return new Set(ids);
}
function runDemo(data=demo){
 if(!data||data.synthetic_only!==true||data.account?.tenant!=='DEMO-TENANT-ISOLATED'||
   data.account?.currency!=='BDT'||!String(data.account?.businessName||'').includes('DEMO'))
   throw Error('ONLY_ISOLATED_SYNTHETIC_DEMO_ALLOWED');
 const siteIds=unique(data.sites,'SITE');
 const itemIds=unique(data.items,'ITEM');
 const staffIds=unique(data.staff,'STAFF');
 const accountIds=unique(data.cashAccounts,'ACCOUNT');
 for(const item of data.items)if(!siteIds.has(item.siteId)||!['kg','L','pcs'].includes(item.uom))
   throw Error('INVALID_DEMO_ITEM_SCOPE_OR_UNIT');
 for(const row of data.stock)if(!siteIds.has(row.siteId)||!itemIds.has(row.itemId)||
   data.items.find(x=>x.id===row.itemId).siteId!==row.siteId)
   throw Error('CROSS_SITE_OR_UNKNOWN_ITEM');
 for(const event of data.events)if(!siteIds.has(event.siteId))throw Error('UNKNOWN_EVENT_SITE');
 if(!accountIds.has(data.cashHandover.cashLedgerRef))throw Error('CASH_BOOK_ACCOUNT_NOT_FOUND');
 const staffCheck=[data.cashHandover.sentBy,data.cashHandover.receivedBy,
   data.stockTransfer.issuedBy,data.stockTransfer.receivedBy,
   data.grn.receivedBy,data.grn.qcBy,data.factoryBatch.producedBy,
   data.factoryBatch.yieldCheckedBy,data.monthly.checkedBy,data.monthly.preparedBy];
 if(staffCheck.some(s=>!staffIds.has(s)))throw Error('UNKNOWN_DEMO_STAFF');
 const blocked=[],notes=[];
 function control(name,value){
  const x=controls[name](value);
  if(x.status==='BLOCK')blocked.push(name+':'+x.blockers.join(','));
  if(x.authorized!==false||x.fieldParityConfirmed!==false)blocked.push('INVALID_SIGNOFF_CLAIM:'+name);
  return {name,status:x.status,blockers:x.blockers};
 }
 function check(name,expectation,result){
  if(!expectation)blocked.push(name);
  return {name,status:expectation?'MATCH':'BLOCK',result};
 }
 const plan=kit.planDay({date:data.account.date,industry:data.account.industry,
   businessName:data.account.businessName,sites:data.sites,events:data.events});
 const batches=kit.partitionKit(plan,100);
 if(batches.reduce((sum,p)=>sum+p.count,0)!==plan.count)blocked.push('PRINT_SHEET_LOSS');
 const prints=batches.map(b=>({batch:b.batchNumber,sheets:b.count,
   rendered:(kit.printKit(b,{lang:'bn',tableRows:3}).match(/class="paperops-kit-sheet"/g)||[]).length}));
 if(prints.some(x=>x.sheets!==x.rendered))blocked.push('PRINT_FORM_MISMATCH');
 const inventory=[];
 const referencedItems=new Set();
 for(const row of data.stock){
  const x=math.stockBalance(row);
  inventory.push({itemId:row.itemId,siteId:row.siteId,expected:x.expected,physical:x.counted,status:x.status});
  if(x.status!=='MATCH')blocked.push('STOCK_COUNT_MISMATCH:'+row.itemId);
  if(!Array.isArray(row.movementRefs)||!row.movementRefs.length)blocked.push('MISSING_STOCK_SOURCE_REF:'+row.itemId);
  referencedItems.add(row.itemId);
 }
 const cash=math.cashClosing(data.cashClosing);
 if(cash.status!=='MATCH')blocked.push('CASH_CLOSE_MISMATCH');
 const settlement=math.digitalSettlement(data.digitalSettlement);
 if(settlement.status!=='MATCH')blocked.push('DIGITAL_SETTLEMENT_MISMATCH');
 const purchase=math.threeWay({
  poRef:data.grn.poRef,grnRef:data.grn.grnRef,billRef:data.grn.invoiceRef,
  poAmount:data.purchase.poTotal,acceptedAmount:data.purchase.acceptedAmount,
  invoiceAmount:data.purchase.invoiceAmount,paymentProposed:data.purchase.paymentProposed,
  approvedBy:data.purchase.approvedBy,preparedBy:data.purchase.preparedBy
 });
 if(purchase.status!=='MATCHED_FOR_PAPER_REVIEW')blocked.push('PURCHASE_THREE_WAY_MISMATCH');
 if(purchase.readyForERPPosting!==false)blocked.push('PURCHASE_FALSE_APPROVAL');
 if(!itemIds.has(data.purchase.itemId))blocked.push('UNKNOWN_PURCHASE_ITEM');
 const purchasedStock=data.stock.find(x=>x.itemId===data.purchase.itemId);
 if(!purchasedStock||!purchasedStock.movementRefs.includes(data.grn.grnRef))
   blocked.push('PURCHASE_GRN_NOT_IN_STOCK_LEDGER');
 else{
  const grnUnits=units(data.grn.acceptedQty,'acceptedQty');
  if(units(purchasedStock.received,'stock.received')!==grnUnits)
   blocked.push('ACCEPTED_STOCK_NOT_REFLECTED_IN_LEDGER');
  const acceptedValue=grnUnits*cents(data.purchase.unitRateBDT,'unitRateBDT')/10000;
  if(!Number.isSafeInteger(acceptedValue)||acceptedValue!==cents(data.purchase.acceptedAmount,'acceptedAmount'))
   blocked.push('INVOICE_QUANTITY_RATE_MISMATCH');
 }
 const transferStock=data.stock.find(x=>x.itemId==='RAS-PCS');
 if(!transferStock||!transferStock.movementRefs.includes(data.stockTransfer.challanRef)||
  units(transferStock.received,'transferStock')!==units(data.stockTransfer.receivedQty,'receivedQty'))
  blocked.push('TRANSFER_NOT_REFLECTED_IN_RECEIVING_LEDGER');
 check('DAY_SALES_SPLIT',cents(data.daySales.cash,'salesCash')+
   cents(data.daySales.digital,'salesDigital')+cents(data.daySales.credit,'salesCredit')===
   cents(data.daySales.total,'daySales.total'),data.daySales.total);
 check('SALES_CASH_LEDGER',cents(data.daySales.cash,'salesCash')===
   cents(data.cashClosing.cashSales,'cashClose.sales'),data.daySales.cash);
 check('SALES_PSP_LEDGER',cents(data.daySales.digital,'salesDigital')===
   cents(data.digitalSettlement.paperRecorded,'provider.paper'),data.daySales.digital);
 check('CASH_HANDOVER_REF',data.daySales.showroomCloseRef===data.cashHandover.closingRef,
   data.cashHandover.closingRef);
 check('CASH_HANDOVER_AMOUNT',cents(data.cashClosing.handovers,'cashClose.handover')===
   cents(data.cashHandover.dispatchedCash,'handover.sent'),data.cashClosing.handovers);
 check('REFUND_CASH_OUT',cents(data.cashClosing.refunds,'cashClose.refund')===
   cents(data.refund.refundAmount,'refund.amount'),data.refund.refundAmount);
 const gates=[
  control('cashHandover',data.cashHandover),
  control('stockTransfer',data.stockTransfer),
  control('goodsReceived',data.grn),
  control('factoryBatch',data.factoryBatch),
  control('discountApproval',data.discount),
  control('returnRefund',data.refund),
  control('customerOrder',data.order)
 ];
 const quote=math.quoteSelection(data.quote);
 if(quote.status!=='MATCH')blocked.push('QUOTE_SELECTION_REVIEW_REQUIRED:'+quote.reasons.join(','));
 const jalebi=math.jalebiYield(data.jalebiYield);
 if(jalebi.status!=='FORMULA_MATCH_REVIEW_SIGNOFF_REQUIRED')blocked.push('JALEBI_YIELD_REVIEW_REQUIRED:'+jalebi.reasons.join(','));
 const monthly=math.monthlyProfit(data.monthly);
 if(monthly.status!=='PAPER_SUMMARY_MATCH')blocked.push('MONTHLY_SUMMARY_REVIEW_REQUIRED:'+monthly.reasons.join(','));
 const ageing=math.receivableAging(data.receivable);
 if(ageing.bucketVariance!=='0.00'||ageing.missingPolicy||ageing.reasons.some(x=>x!=='OVER_60_REVIEW_REQUIRED'))
  blocked.push('AR_AGEING_UNRECONCILED:'+ageing.reasons.join(','));
 else if(ageing.reviewRequired)notes.push('OVER_60_COLLECTION_REVIEW_REQUIRED');
 if(plan.eventCount!==data.events.length)blocked.push('EVENT_COUNT_MISMATCH');
 return Object.freeze({
  demoOnly:true,fixtureAccount:data.account.id,accountIds:[...accountIds],
  items:data.items.map(x=>({itemId:x.id,uom:x.uom,siteId:x.siteId})),
  stock:inventory,cash,settlement,purchase,quote,jalebi,monthly,ageing,
  handoffChecks:gates,
  plan:{count:plan.count,daily:plan.dailyCount,event:plan.eventCount,
    batches:prints,sites:data.sites.length},
  notes,blockers:blocked,
  status:blocked.length?'DEMO_BLOCKED':'DEMO_CONSISTENT_PROTOTYPE_ONLY',
  readyForLive:false,readyForERPPosting:false,sourceParityCertified:false
 });
}
if(require.main===module){
 const result=runDemo();
 console.log(JSON.stringify(result,null,2));
 if(result.status!=='DEMO_CONSISTENT_PROTOTYPE_ONLY')process.exitCode=1;
}
module.exports={runDemo};
