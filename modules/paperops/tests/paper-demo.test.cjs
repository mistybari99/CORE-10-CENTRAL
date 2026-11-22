'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {runDemo}=require('../paper-demo.cjs');
const fixture=require('../demo-fixture.json');
const kit=require('../paper-kit.js');
function changed(fn){const f=structuredClone(fixture);fn(f);return f;}
function hasBlock(x,fragment){
 const result=runDemo(x);
 assert.equal(result.status,'DEMO_BLOCKED');
 assert.ok(result.blockers.some(b=>b.includes(fragment)),
  'expected '+fragment+' in '+JSON.stringify(result.blockers));
 assert.equal(result.readyForERPPosting,false);
 assert.equal(result.readyForLive,false);
}
test('isolated synthetic account has items, balances, role separation, voucher refs and all reconciliations',()=>{
 const r=runDemo();
 assert.equal(r.status,'DEMO_CONSISTENT_PROTOTYPE_ONLY',r.blockers.join(' | '));
 assert.equal(r.demoOnly,true);
 assert.equal(r.fixtureAccount,'DEMO-ACCOUNT-01');
 assert.equal(r.items.length,4);
 assert.equal(r.accountIds.length,3);
 assert.equal(r.stock.length,3);
 assert.ok(r.stock.every(x=>x.status==='MATCH'));
 assert.equal(r.cash.expected,'1000.00');
 assert.equal(r.cash.actual,'1000.00');
 assert.equal(r.settlement.netExpected,'1176.00');
 assert.equal(r.purchase.status,'MATCHED_FOR_PAPER_REVIEW');
 assert.equal(r.jalebi.flourUsedKg,'11.2500');
 assert.equal(r.monthly.net,'4200.00');
 assert.equal(r.ageing.bucketVariance,'0.00');
 assert.ok(r.notes.includes('OVER_60_COLLECTION_REVIEW_REQUIRED'));
 assert.ok(r.handoffChecks.every(x=>x.status==='REVIEW_READY_NOT_APPROVED'));
 assert.equal(r.plan.daily,1);
 assert.equal(r.plan.event,11);
 assert.equal(r.plan.count,12);
 assert.deepEqual(r.plan.batches.map(x=>x.sheets),[12]);
 assert.equal(r.plan.batches[0].rendered,12);
 assert.equal(r.readyForLive,false);
 assert.equal(r.readyForERPPosting,false);
 assert.equal(r.sourceParityCertified,false);
});
test('live or real account data cannot be routed through demo test engine',()=>{
 assert.throws(()=>runDemo(changed(x=>{x.synthetic_only=false;})),/ONLY_ISOLATED_SYNTHETIC_DEMO_ALLOWED/);
 assert.throws(()=>runDemo(changed(x=>{x.account.tenant='REAL-TENANT';})),/ONLY_ISOLATED_SYNTHETIC_DEMO_ALLOWED/);
 assert.throws(()=>runDemo(changed(x=>{x.account.businessName='Business';})),/ONLY_ISOLATED_SYNTHETIC_DEMO_ALLOWED/);
 assert.throws(()=>runDemo(changed(x=>{x.cashAccounts[1].id='CASH-001';})),/DUPLICATE_OR_MISSING_ACCOUNT/);
 assert.throws(()=>runDemo(changed(x=>{x.items[1].id='SUGAR-KG';})),/DUPLICATE_OR_MISSING_ITEM/);
 assert.throws(()=>runDemo(changed(x=>{x.stock[1].siteId='showroom';})),/CROSS_SITE_OR_UNKNOWN_ITEM/);
 assert.throws(()=>runDemo(changed(x=>{x.grn.qcBy='UNKNOWN_PERSON';})),/UNKNOWN_DEMO_STAFF/);
});
test('sales split, cash counts, return payouts and digital deposit reconcile to independent records',()=>{
 hasBlock(changed(x=>{x.daySales.total='3700.01';}),'DAY_SALES_SPLIT');
 hasBlock(changed(x=>{x.daySales.cash='2501';}),'DAY_SALES_SPLIT');
 hasBlock(changed(x=>{x.cashClosing.countedClose='999';}),'CASH_CLOSE_MISMATCH');
 hasBlock(changed(x=>{x.cashClosing.handovers='450';}),'CASH_HANDOVER_AMOUNT');
 hasBlock(changed(x=>{x.cashHandover.receivedCash='499';}),'cashHandover');
 hasBlock(changed(x=>{x.digitalSettlement.bankReceived='1175.99';}),'DIGITAL_SETTLEMENT_MISMATCH');
 hasBlock(changed(x=>{x.refund.refundAmount='201';}),'REFUND_CASH_OUT');
});
test('purchase quantity × unit rate and physical stock must tie back to GRN and invoice',()=>{
 hasBlock(changed(x=>{x.purchase.invoiceAmount='3001';}),'PURCHASE_THREE_WAY_MISMATCH');
 hasBlock(changed(x=>{x.purchase.acceptedAmount='2999';}),'INVOICE_QUANTITY_RATE_MISMATCH');
 hasBlock(changed(x=>{x.grn.acceptedQty='29';}),'goodsReceived');
 hasBlock(changed(x=>{x.stock[0].received='29';}),'ACCEPTED_STOCK_NOT_REFLECTED_IN_LEDGER');
 hasBlock(changed(x=>{x.stock[0].physicalClose='67';}),'STOCK_COUNT_MISMATCH');
 hasBlock(changed(x=>{x.stock[0].movementRefs=[];}),'MISSING_STOCK_SOURCE_REF');
 hasBlock(changed(x=>{x.stockTransfer.receivedQty='59';}),'stockTransfer');
});
test('factory, refund illness, independent authorization and order advance all fail safely',()=>{
 hasBlock(changed(x=>{x.factoryBatch.qcReleased=false;}),'factoryBatch');
 hasBlock(changed(x=>{x.factoryBatch.yieldCheckedBy=x.factoryBatch.producedBy;}),'factoryBatch');
 hasBlock(changed(x=>{x.refund.foodIllnessReported=true;x.refund.managementEscalated=false;}),'returnRefund');
 hasBlock(changed(x=>{x.grn.qcBy=x.grn.receivedBy;}),'goodsReceived');
 hasBlock(changed(x=>{x.order.advanceAmount='700';}),'customerOrder');
 hasBlock(changed(x=>{x.receivable.daysOver60='90';}),'AR_AGEING_UNRECONCILED');
 hasBlock(changed(x=>{x.monthly.checkedBy=x.monthly.preparedBy;}),'MONTHLY_SUMMARY_REVIEW_REQUIRED');
});
test('400 retail locations can be planned in four complete, explicitly selected print batches',()=>{
 const sites=Array.from({length:400},(_,i)=>({id:'show-'+String(i+1).padStart(3,'0'),
  name:'Synthetic Demo Site '+(i+1),kind:'showroom'}));
 const p=kit.planDay({date:'2026-11-22',businessName:'CORE10 DEMO TEST BUSINESS',
  industry:'sweets_bakery',sites});
 assert.equal(p.count,400);
 assert.throws(()=>kit.printKit(p),/PRINT_BATCH_LIMIT_100/);
 const batches=kit.partitionKit(p,100);
 assert.deepEqual(batches.map(x=>x.count),[100,100,100,100]);
 assert.equal(batches[3].firstSheet,301);
 assert.equal(batches[3].lastSheet,400);
 assert.equal(batches.reduce((n,b)=>n+b.count,0),p.count);
 assert.equal(new Set(batches.flatMap(x=>x.forms.map(y=>y.key))).size,400);
 const html=kit.printKit(batches[0],{lang:'bn',tableRows:3});
 assert.equal((html.match(/class="paperops-kit-sheet"/g)||[]).length,100);
 assert.match(html,/Synthetic Demo Site 100/);
 assert.doesNotMatch(html,/Synthetic Demo Site 101/);
});
test('batch partition refuses omissions, duplicates and silent oversized render',()=>{
 const p=kit.planDay({date:'2026-11-22',industry:'sweets_bakery',
  businessName:'CORE10 TEST',sites:[{id:'s1',name:'Showroom'}]});
 assert.equal(kit.partitionKit(p).length,1);
 assert.throws(()=>kit.partitionKit(p,101),/INVALID_PRINT_BATCH_SIZE/);
 assert.throws(()=>kit.partitionKit(p,0),/INVALID_PRINT_BATCH_SIZE/);
 assert.throws(()=>kit.partitionKit({...p,forms:[p.forms[0],p.forms[0]],count:2}),/DUPLICATE_OR_MISSING_SHEET_KEY/);
});
