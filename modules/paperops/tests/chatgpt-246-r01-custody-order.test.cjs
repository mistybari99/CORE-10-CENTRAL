'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {reconcileR01}=require('../field-review/chatgpt-246/r01-custody-order-source-gate.cjs');
const manifest=require('../field-review/ownership-246-1000.json');
const clone=structuredClone;
const S={tenantId:'DEMO-T-1',businessId:'DEMO-B-1',siteId:'DEMO-S-1'};
function row(sourceRef,more={}){return {...S,sourceRef,...more};}
function fixture(){return {
  scope:{synthetic_only:true,...S},
  snapshot:{drawer_none:true,ho_count:2,ho_range:'REG-7..8',ho_written:true,
    stock_locked:true,orders_taken:2,order_range:'ORD-11..12',
    delivered_n:2,pending_next:1,advance_taken:'100.00'},
  handoverRegisterRef:'DEMO-REGISTER',
  handoverRegisterRange:'REG-7..8',
  handovers:[
    row('DEMO-H7',{serial:7,fromActor:'DEMO-A',toActor:'DEMO-B',
      senderEvidenceRef:'DEMO-A7',receiverEvidenceRef:'DEMO-B7'}),
    row('DEMO-H8',{serial:8,fromActor:'DEMO-B',toActor:'DEMO-C',
      senderEvidenceRef:'DEMO-B8',receiverEvidenceRef:'DEMO-C8'})],
  drawerExpenses:[],
  orderBook:{openingPendingRegisterRef:'DEMO-YESTERDAY-BOARD',orderRange:'ORD-11..12',
    openingPending:[row('DEMO-OLD-REC',{orderId:'OLD-10'})],
    taken:[row('DEMO-O11',{orderId:'ORD-11'}),row('DEMO-O12',{orderId:'ORD-12'})],
    delivered:[row('DEMO-D10',{orderId:'OLD-10'}),row('DEMO-D11',{orderId:'ORD-11'})],
    advances:[row('DEMO-ADV-12',{orderId:'ORD-12',amount:'100.00',
      moneyReceiptRef:'DEMO-MONEY-RECEIPT',moneyAccountRef:'DEMO-MONEY-ACC'})]}};}
function changed(fn){const x=fixture();fn(x);return reconcileR01(x);}
test('10 reserved R-01 fields reconcile source books, no guessed signoff or ERP posting',()=>{
 const x=reconcileR01(fixture()),y=reconcileR01(fixture());
 assert.equal(x.status,'REVIEW_READY_NOT_APPROVED');
 assert.deepEqual(x.owned_source_ids,manifest.lane_B_chatgpt.reserved_next_10_keys);
 assert.equal(x.sourceLineageDigest,y.sourceLineageDigest);
 assert.equal(x.evidence.observedHandovers,2);
 assert.equal(x.evidence.expectedPending,1);
 assert.equal(x.evidence.expectedAdvanceBDT,'100.00');
 assert.equal(x.canPost,false);
 assert.equal(x.canonicalMoneyVerified,false);
 assert.equal(x.canonicalSalesVerified,false);
 assert.equal(x.ownerAccepted,false);
});
test('reconciliation blocks false drawer attestation and contradictory money event',()=>{
 assert.ok(changed(x=>{x.snapshot.drawer_none=false}).blockers.includes('DRAWER_EXPENSE_SEPARATION_NOT_ATTESTED'));
 assert.ok(changed(x=>{x.drawerExpenses.push(row('DEMO-DRAWER',{amount:'20.00'}))})
   .blockers.includes('SALES_DRAWER_CASH_EXPENSE_EVENT'));
 assert.ok(changed(x=>{x.snapshot.stock_locked=false}).blockers.includes('STOCK_CUSTODY_LOCK_NOT_ATTESTED'));
});
test('handover count, serial continuity, register and two independent actors are checked',()=>{
 assert.ok(changed(x=>{x.snapshot.ho_count=1}).blockers.includes('HANDOVER_COUNT_DIFFERS_FROM_REGISTER'));
 assert.ok(changed(x=>{x.handovers[1].serial=9}).blockers.includes('HANDOVER_SERIAL_CONTINUITY_BROKEN'));
 assert.ok(changed(x=>{x.handoverRegisterRange='WRONG'}).blockers.includes('HANDOVER_REGISTER_CROSS_REFERENCE_MISMATCH'));
 assert.ok(changed(x=>{x.handovers[1].toActor=x.handovers[1].fromActor})
   .blockers.includes('HANDOVER_INDEPENDENT_CUSTODY_ACTORS_MISSING'));
 assert.throws(()=>changed(x=>{x.handovers[1].serial=7}),/DUPLICATE_OR_INVALID_HANDOVER_SERIAL/);
});
test('order book compares taken, delivered, pending and advance amounts without double entry',()=>{
 assert.ok(changed(x=>{x.snapshot.orders_taken=4}).blockers.includes('R01_ORDERS_TAKEN_SOURCE_MISMATCH'));
 assert.ok(changed(x=>{x.snapshot.delivered_n=3}).blockers.includes('R01_DELIVERY_COUNT_SOURCE_MISMATCH'));
 assert.ok(changed(x=>{x.snapshot.pending_next=2}).blockers.includes('R01_PENDING_NEXT_RECONCILIATION_MISMATCH'));
 assert.ok(changed(x=>{x.snapshot.advance_taken='100.01'}).blockers.includes('R01_ADVANCE_MONEY_SOURCE_MISMATCH'));
 assert.ok(changed(x=>{x.orderBook.cancellations=[{id:'DEMO-CANCEL'}]})
   .blockers.includes('ORDER_CANCELLATION_REQUIRES_SIGNED_SALES_RECONCILIATION'));
 assert.ok(changed(x=>{x.orderBook.advances[0].moneyReceiptRef=null})
   .blockers.includes('ADVANCE_MONEY_SOURCE_AND_ACCOUNT_EVIDENCE_MISSING'));
 assert.throws(()=>changed(x=>{x.orderBook.delivered[1].orderId='OLD-10'}),/DUPLICATE_DELIVERY_OF_ORDER/);
 assert.throws(()=>changed(x=>{x.orderBook.delivered[1].orderId='OTHER-SITE-ORDER'}),/DELIVERY_WITHOUT_ORIGINAL_ORDER/);
});
test('cross-tenant, replay and unsafe numeric representations are always rejected',()=>{
 assert.throws(()=>changed(x=>{x.orderBook.taken[0].tenantId='DEMO-T-OTHER'}),/CROSS_TENANT_BUSINESS_OR_SITE/);
 assert.throws(()=>changed(x=>{x.handovers[0].siteId='DEMO-OTHER-SITE'}),/CROSS_TENANT_BUSINESS_OR_SITE/);
 assert.throws(()=>changed(x=>{x.orderBook.taken[1].sourceRef=x.orderBook.taken[0].sourceRef}),/DUPLICATE_OR_REPLAYED_SOURCE_REFERENCE/);
 assert.throws(()=>changed(x=>{x.snapshot.ho_count=-1}),/INVALID_R01_COUNT/);
 assert.throws(()=>changed(x=>{x.snapshot.advance_taken='1e5'}),/INVALID_R01_MONEY/);
 assert.throws(()=>changed(x=>{x.snapshot.advance_taken='9007199254740993'}),/R01_MONEY_OVERFLOW/);
 assert.throws(()=>changed(x=>{x.scope.synthetic_only=false}),/R01_REQUIRES_SYNTHETIC_SCOPE/);
});
test('source digest changes with evidence edits, but no state is posted',()=>{
 const a=reconcileR01(fixture());
 const b=changed(x=>{x.handovers[1].receiverEvidenceRef='DEMO-NEW-PROOF'});
 assert.notEqual(a.sourceLineageDigest,b.sourceLineageDigest);
 assert.equal(b.canPost,false);
});
