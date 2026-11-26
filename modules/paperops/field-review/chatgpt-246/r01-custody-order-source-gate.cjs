'use strict';
/* R-01 reserved original fields: source-event reconciliation (synthetic only).
 * The original 10 constructors do NOT declare these checks as required, and
 * do NOT compute them. This is a STRICTER review candidate, NOT original
 * calc(e) parity, signed ERP authority or an accounting posting engine.
 * Sales/Stock/Money/Approval/Audit/Control canonical ports are NOT called.
 */
const {createHash}=require('node:crypto');
const OWNED=require('../ownership-246-1000.json').lane_B_chatgpt.reserved_next_10_keys;
const REQUIRED=['drawer_none','ho_count','ho_range','ho_written','stock_locked',
  'orders_taken','order_range','delivered_n','pending_next','advance_taken'].map(k=>'R-01:'+k);
if(JSON.stringify(OWNED)!==JSON.stringify(REQUIRED))throw Error('R01_10_OWNERSHIP_CHANGED');
const key=v=>typeof v==='string'&&/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$/.test(v);
function count(v,label){
  const s=typeof v==='number'&&Number.isSafeInteger(v)?String(v):v;
  if(typeof s!=='string'||! /^(?:0|[1-9]\d*)$/.test(s)||!Number.isSafeInteger(Number(s)))
    throw Error('INVALID_R01_COUNT:'+label);
  return Number(s);
}
function cents(v,label){
  const s=typeof v==='number'&&Number.isFinite(v)?String(v):v;
  if(typeof s!=='string'||! /^(?:0|[1-9]\d*)(?:\.\d{1,2})?$/.test(s))
    throw Error('INVALID_R01_MONEY:'+label);
  const p=s.split('.'),n=Number(p[0])*100+Number((p[1]||'').padEnd(2,'0'));
  if(!Number.isSafeInteger(n))throw Error('R01_MONEY_OVERFLOW:'+label);
  return n;
}
function scopeOf(input){
  const s=input?.scope;
  if(!s||s.synthetic_only!==true||
    ![s.tenantId,s.businessId,s.siteId].every(v=>key(v)&&v.startsWith('DEMO-')))
    throw Error('R01_REQUIRES_SYNTHETIC_SCOPE');
  return s;
}
function sourceRow(row,s,kind){
  if(!row||row.tenantId!==s.tenantId||row.businessId!==s.businessId||row.siteId!==s.siteId)
    throw Error('CROSS_TENANT_BUSINESS_OR_SITE:'+kind);
  if(!key(row.sourceRef))throw Error('IMMUTABLE_SOURCE_REFERENCE_REQUIRED:'+kind);
}
function reconcileR01(input){
  const scope=scopeOf(input),v=input.snapshot;
  if(!v||typeof v!=='object')throw Error('R01_SOURCE_SNAPSHOT_REQUIRED');
  const book=input.orderBook,handovers=input.handovers;
  if(!book||!Array.isArray(book.openingPending)||!Array.isArray(book.taken)||
    !Array.isArray(book.delivered)||!Array.isArray(book.advances)||
    !Array.isArray(handovers)||!Array.isArray(input.drawerExpenses))
    throw Error('R01_COMPLETE_SOURCE_EVENT_SETS_REQUIRED');
  if(handovers.length>500||book.openingPending.length>500||book.taken.length>500||
    book.delivered.length>1000||book.advances.length>1000)
    throw Error('R01_INPUT_TOO_LARGE');
  const blockers=[],seenRefs=new Set();
  const flag=x=>{if(!blockers.includes(x))blockers.push(x);};
  function register(row,kind){
    sourceRow(row,scope,kind);
    if(seenRefs.has(row.sourceRef))throw Error('DUPLICATE_OR_REPLAYED_SOURCE_REFERENCE');
    seenRefs.add(row.sourceRef);
  }
  const countH=count(v.ho_count,'ho_count'),taken=count(v.orders_taken,'orders_taken'),
    delivered=count(v.delivered_n,'delivered_n'),pending=count(v.pending_next,'pending_next'),
    claimedAdvance=cents(v.advance_taken,'advance_taken');
  if(v.drawer_none!==true)flag('DRAWER_EXPENSE_SEPARATION_NOT_ATTESTED');
  if(v.stock_locked!==true)flag('STOCK_CUSTODY_LOCK_NOT_ATTESTED');
  if(input.drawerExpenses.length!==0)flag('SALES_DRAWER_EXPENSE_EVENT_CONTRADICTS_R01');
  for(const x of input.drawerExpenses){
    register(x,'DRAWER_EXPENSE');
    if(cents(x.amount,'drawerExpense')>0)flag('SALES_DRAWER_CASH_EXPENSE_EVENT');
  }
  if(countH!==handovers.length)flag('HANDOVER_COUNT_DIFFERS_FROM_REGISTER');
  const serials=new Set();
  for(const h of handovers){
    register(h,'HANDOVER');
    const serial=count(h.serial,'handoverSerial');
    if(serial<1||serials.has(serial))throw Error('DUPLICATE_OR_INVALID_HANDOVER_SERIAL');
    serials.add(serial);
    if(!key(h.fromActor)||!key(h.toActor)||h.fromActor===h.toActor)
      flag('HANDOVER_INDEPENDENT_CUSTODY_ACTORS_MISSING');
    if(!key(h.senderEvidenceRef)||!key(h.receiverEvidenceRef))
      flag('HANDOVER_TWO_PARTY_EVIDENCE_REFS_MISSING');
  }
  const sorted=[...serials].sort((a,b)=>a-b);
  for(let i=1;i<sorted.length;i++)
    if(sorted[i]!==sorted[i-1]+1)flag('HANDOVER_SERIAL_CONTINUITY_BROKEN');
  if(handovers.length){
    if(v.ho_written!==true)flag('HANDOVER_REGISTER_ATTESTATION_MISSING');
    if(!key(input.handoverRegisterRef)||typeof input.handoverRegisterRange!=='string'||
      v.ho_range!==input.handoverRegisterRange||!v.ho_range.trim())
      flag('HANDOVER_REGISTER_CROSS_REFERENCE_MISMATCH');
  }else if(v.ho_range!==''&&v.ho_range!=null)flag('HANDOVER_RANGE_WITHOUT_HANDOVERS');
  const knownOrders=new Set(),newOrders=new Set();
  if(!key(book.openingPendingRegisterRef))flag('OPENING_PENDING_REGISTER_REFERENCE_MISSING');
  for(const x of book.openingPending){
    register(x,'OPENING_PENDING_ORDER');
    if(!key(x.orderId)||knownOrders.has(x.orderId))throw Error('DUPLICATE_OPENING_PENDING_ORDER');
    knownOrders.add(x.orderId);
  }
  for(const x of book.taken){
    register(x,'NEW_ORDER');
    if(!key(x.orderId)||knownOrders.has(x.orderId))throw Error('DUPLICATE_OR_CROSS_PERIOD_ORDER');
    knownOrders.add(x.orderId);newOrders.add(x.orderId);
  }
  if(taken!==newOrders.size)flag('R01_ORDERS_TAKEN_SOURCE_MISMATCH');
  if(book.taken.length){
    if(typeof book.orderRange!=='string'||v.order_range!==book.orderRange||!v.order_range.trim())
      flag('R01_ORDER_BOOK_RANGE_MISMATCH');
  }else if(v.order_range!==''&&v.order_range!=null)flag('R01_RANGE_WITHOUT_ORDERS');
  const fulfilled=new Set();
  for(const x of book.delivered){
    register(x,'DELIVERY');
    if(!key(x.orderId)||!knownOrders.has(x.orderId))throw Error('DELIVERY_WITHOUT_ORIGINAL_ORDER');
    if(fulfilled.has(x.orderId))throw Error('DUPLICATE_DELIVERY_OF_ORDER');
    fulfilled.add(x.orderId);
  }
  if(delivered!==fulfilled.size)flag('R01_DELIVERY_COUNT_SOURCE_MISMATCH');
  if(Array.isArray(book.cancellations)&&book.cancellations.length)
    flag('ORDER_CANCELLATION_REQUIRES_SIGNED_SALES_RECONCILIATION');
  const calculatedPending=knownOrders.size-fulfilled.size;
  if(pending!==calculatedPending)flag('R01_PENDING_NEXT_RECONCILIATION_MISMATCH');
  let advanced=0;
  for(const x of book.advances){
    register(x,'ORDER_ADVANCE');
    if(!key(x.orderId)||!knownOrders.has(x.orderId))throw Error('ADVANCE_WITHOUT_ORIGINAL_ORDER');
    if(!key(x.moneyReceiptRef)||!key(x.moneyAccountRef))
      flag('ADVANCE_MONEY_SOURCE_AND_ACCOUNT_EVIDENCE_MISSING');
    const amt=cents(x.amount,'advance');
    if(!Number.isSafeInteger(advanced+amt))throw Error('R01_ADVANCE_SUM_OVERFLOW');
    advanced+=amt;
  }
  if(advanced!==claimedAdvance)flag('R01_ADVANCE_MONEY_SOURCE_MISMATCH');
  const digest=createHash('sha256').update(JSON.stringify({
    scope:{tenantId:scope.tenantId,businessId:scope.businessId,siteId:scope.siteId},
    v,handovers,book,drawerExpenses:input.drawerExpenses
  })).digest('hex');
  return Object.freeze({source:'R-01',owned_source_ids:REQUIRED.slice(),
    sourceOnly:true,syntheticOnly:true,sourceLineageDigest:digest,
    status:blockers.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
    blockers:Object.freeze(blockers),evidence:Object.freeze({
      observedHandovers:handovers.length,observedOrders:newOrders.size,
      observedDeliveries:fulfilled.size,expectedPending:calculatedPending,
      expectedAdvanceBDT:(advanced/100).toFixed(2)
    }),sourceCalcParityApproved:false,physicalCustodyAuthenticated:false,
    canonicalSalesVerified:false,canonicalStockVerified:false,
    canonicalMoneyVerified:false,canonicalControlVerified:false,
    signedApprovalVerified:false,canPost:false,ownerAccepted:false});
}
module.exports={reconcileR01};
