import test from 'node:test';
import assert from 'node:assert/strict';
import { createProcurementKernel, ProcurementError, allocateLandedCost } from '../../internal/enterprise-procurement/build08/procurement-kernel.mjs';

const roles = {
  maker: ['proc.supplier.write','proc.requisition.create','proc.quote.write','proc.po.create',
    'proc.po.revise','proc.receipt.record','proc.invoice.record','proc.invoice.revise',
    'proc.return.record','proc.payment.propose','proc.payment.cancel','proc.report','proc.audit.read'],
  checker: ['proc.requisition.approve','proc.po.approve','proc.qc.inspect',
    'proc.payment.authorize','proc.po.close','proc.report','proc.audit.read'],
  viewer: ['proc.report']
};
const actor = (id='maker',siteIds=['SITE-A'],patch={}) => ({
  actorId:id,tenantId:'TENANT-1',businessId:'BUS-1',siteIds,
  permissions:roles[id]||[],revoked:false,...patch
});
function harness(config={}) {
  const kernel=createProcurementKernel({tenantId:'TENANT-1',businessId:'BUS-1',
    siteIds:['SITE-A','SITE-B'],overdeliveryBps:config.overdeliveryBps??0});
  let n=0;
  const send=(type,payload={},who=actor(),extra={})=> kernel.dispatch({
    requestId:'req-'+(++n),type,payload,actor:who,onDate:'2026-11-12',...extra
  });
  function prepare(level='PO_APPROVED') {
    send('supplier.register',{id:'SUP-1',status:'ACTIVE',relatedPartyHold:false,validThrough:'2027-01-01'});
    send('requisition.create',{id:'REQ-1',siteId:'SITE-A',itemId:'FLOUR',uom:'KG',
      sourceDemandId:'PLAN-1',qtyMilli:10000,neededOn:'2026-11-19'});
    send('requisition.approve',{requisitionId:'REQ-1'},actor('checker'));
    send('quote.add',{id:'QUOTE-1',requisitionId:'REQ-1',supplierId:'SUP-1',uom:'KG',
      currency:'BDT',unitPriceMinor:20500,taxMinor:0,freightMinor:1500,
      leadDays:2,validThrough:'2026-12-01'});
    send('po.create',{id:'PO-1',quoteId:'QUOTE-1'});
    if(level!=='DRAFT') send('po.approve',{poId:'PO-1',expectedRevision:1},actor('checker'));
    if(['RECEIVED','MATCHED','AUTHORIZED'].includes(level)){
      send('receipt.record',{id:'GRN-1',poId:'PO-1',siteId:'SITE-A',qtyMilli:10000});
      send('receipt.inspect',{receiptId:'GRN-1',decision:'ACCEPTED',evidenceId:'QC-E1'},actor('checker'));
    }
    if(['MATCHED','AUTHORIZED'].includes(level)) send('invoice.record',{
      id:'INV-1',poId:'PO-1',supplierRef:'BILL-001',currency:'BDT',qtyMilli:10000,
      unitPriceMinor:20500,taxMinor:0,freightMinor:1500
    });
    return kernel;
  }
  return {kernel,send,prepare};
}
const denied=(fn,code)=> assert.throws(fn,(err)=>err instanceof ProcurementError && err.code===code);

test('complete draft procurement path preserves the payment/stock/AP boundaries',()=>{
  const h=harness();h.prepare('MATCHED');
  const report=h.kernel.report(actor());
  assert.equal(report.orders[0].acceptedQtyMilli,10000);
  assert.equal(report.invoices[0].totalMinor,206500);
  assert.equal(report.invoices[0].status,'MATCHED');
  const p=h.send('payment.propose',{id:'PAY-1',invoiceId:'INV-1',amountMinor:100000,
    currency:'BDT',bankFingerprint:'BANK-HASH-1'});
  assert.equal(p.bankEffect,'NONE');
  const a=h.send('payment.authorize',{paymentId:'PAY-1',expectedBankFingerprint:'BANK-HASH-1'},actor('checker'));
  assert.equal(a.status,'AUTHORIZED_PENDING_EXTERNAL_SETTLEMENT');
  const closed=h.send('po.close',{poId:'PO-1'},actor('checker'));
  assert.equal(closed.status,'CLOSED');
  assert.equal(h.kernel.report(actor()).paymentProposals[0].status,'AUTHORIZED_PENDING_EXTERNAL_SETTLEMENT');
  assert.equal(h.kernel.describe().authority,'ISOLATED_DRAFT_ONLY');
});
test('exact replay returns one receipt and does not append audit twice',()=>{
  const h=harness();
  const e={requestId:'fixed',type:'supplier.register',actor:actor(),
    onDate:'2026-11-12',payload:{id:'S',status:'ACTIVE',relatedPartyHold:false,validThrough:'2027-01-01'}};
  assert.equal(h.kernel.dispatch(e).replay,false);
  assert.equal(h.kernel.dispatch(e).replay,true);
  assert.equal(h.kernel.inspect(actor()).audit.length,1);
  denied(()=>h.kernel.dispatch({...e,payload:{...e.payload,status:'BLOCKED'}}),'IDEMPOTENCY_CONFLICT');
});
test('failed command is atomic and does not consume request key',()=>{
  const h=harness();h.prepare();
  const before=h.kernel.inspect(actor());
  denied(()=>h.send('receipt.record',{id:'BAD',poId:'PO-1',siteId:'SITE-A',qtyMilli:20000}),'OVERDELIVERY_TOLERANCE');
  const after=h.kernel.inspect(actor());
  assert.equal(after.audit.length,before.audit.length);
  assert.equal(Object.keys(after.receipts).length,0);
});
test('cross-business actor denied',()=>{const h=harness();denied(()=>h.send('supplier.register',{
  id:'S',status:'ACTIVE',relatedPartyHold:false,validThrough:'2027-01-01'
},actor('maker',['SITE-A'],{businessId:'BUS-OTHER'})),'CROSS_SCOPE_DENIED');});
test('cross-tenant actor denied',()=>{const h=harness();denied(()=>h.send('supplier.register',{
  id:'S',status:'ACTIVE',relatedPartyHold:false,validThrough:'2027-01-01'
},actor('maker',['SITE-A'],{tenantId:'TENANT-OTHER'})),'CROSS_SCOPE_DENIED');});
test('revoked actor denied',()=>{const h=harness();denied(()=>h.send('supplier.register',{
  id:'S',status:'ACTIVE',relatedPartyHold:false,validThrough:'2027-01-01'
},actor('maker',['SITE-A'],{revoked:true})),'ACTOR_DENIED');});
test('insufficient permission denied',()=>{const h=harness();denied(()=>h.send('supplier.register',{
  id:'S',status:'ACTIVE',relatedPartyHold:false,validThrough:'2027-01-01'
},actor('viewer')),'PERMISSION_DENIED');});
test('site-only staff cannot create demand at another site',()=>{const h=harness();denied(()=>h.send('requisition.create',{
  id:'REQ-X',siteId:'SITE-B',itemId:'FLOUR',uom:'KG',qtyMilli:1000,
  sourceDemandId:'D-1',neededOn:'2026-11-20'
}),'SITE_DENIED');});
test('caller-supplied site cannot override referenced PO canonical site',()=>{
  const h=harness();h.prepare();
  const other=actor('maker',['SITE-B']);
  denied(()=>h.send('receipt.record',{id:'X',poId:'PO-1',siteId:'SITE-B',qtyMilli:1000},other),'SITE_MISMATCH');
});
test('referenced PO site checked even without supplied site',()=>{
  const h=harness();h.prepare();
  denied(()=>h.send('po.revise',{poId:'PO-1',expectedRevision:1,qtyMilli:10000,
    unitPriceMinor:20500},actor('maker',['SITE-B'])),'SITE_DENIED');
});
test('duplicate source demand rejected',()=>{
  const h=harness();h.prepare('DRAFT');
  denied(()=>h.send('requisition.create',{id:'REQ-X',siteId:'SITE-A',
    itemId:'FLOUR',uom:'KG',qtyMilli:3000,sourceDemandId:'PLAN-1',
    neededOn:'2026-11-20'}),'DUPLICATE_SOURCE_DEMAND');
});
test('requisition maker cannot self approve',()=>{
  const h=harness(); h.send('requisition.create',{id:'REQ-X',siteId:'SITE-A',
    itemId:'FLOUR',uom:'KG',qtyMilli:1000,sourceDemandId:'PLAN-X',
    neededOn:'2026-11-20'});
  denied(()=>h.send('requisition.approve',{requisitionId:'REQ-X'},
    actor('maker',['SITE-A'],{permissions:[...roles.maker,'proc.requisition.approve']})),'MAKER_CANNOT_APPROVE');
});
test('blocked or expired supplier prevents new offer',()=>{
  const h=harness();
  h.send('supplier.register',{id:'BLOCKED',status:'BLOCKED',
    relatedPartyHold:false,validThrough:'2027-01-01'});
  h.send('requisition.create',{id:'REQ-X',siteId:'SITE-A',
    itemId:'FLOUR',uom:'KG',qtyMilli:1000,sourceDemandId:'PLAN-X',
    neededOn:'2026-11-20'});
  h.send('requisition.approve',{requisitionId:'REQ-X'},actor('checker'));
  denied(()=>h.send('quote.add',{id:'QX',requisitionId:'REQ-X',supplierId:'BLOCKED',
    uom:'KG',currency:'BDT',unitPriceMinor:200,taxMinor:0,freightMinor:0,
    leadDays:2,validThrough:'2027-01-01'}),'SUPPLIER_NOT_ELIGIBLE');
});
test('quote UOM mismatch denied and original quote cannot be silently converted',()=>{
  const h=harness();h.prepare('DRAFT');
  denied(()=>h.send('quote.add',{id:'QX',requisitionId:'REQ-1',supplierId:'SUP-1',
    uom:'PCS',currency:'BDT',unitPriceMinor:200,taxMinor:0,freightMinor:0,
    leadDays:2,validThrough:'2027-01-01'}),'UOM_MISMATCH');
});
test('expired quote rejected',()=>{
  const h=harness();h.prepare('DRAFT');
  denied(()=>h.send('quote.add',{id:'QX',requisitionId:'REQ-1',supplierId:'SUP-1',
    uom:'KG',currency:'BDT',unitPriceMinor:200,taxMinor:0,freightMinor:0,
    leadDays:2,validThrough:'2026-01-01'}),'QUOTE_EXPIRED');
});
test('PO revision invalidates previous approval and stale revision rejected',()=>{
  const h=harness();h.prepare('DRAFT');
  h.send('po.revise',{poId:'PO-1',expectedRevision:1,qtyMilli:12000,unitPriceMinor:19000});
  denied(()=>h.send('po.approve',{poId:'PO-1',expectedRevision:1},actor('checker')),'STALE_PO_REVISION');
  const a=h.send('po.approve',{poId:'PO-1',expectedRevision:2},actor('checker'));
  assert.equal(a.revision,2);
  const b=h.send('po.revise',{poId:'PO-1',expectedRevision:2,qtyMilli:10000,unitPriceMinor:19500});
  assert.equal(b.status,'DRAFT');
  denied(()=>h.send('receipt.record',{id:'G',poId:'PO-1',siteId:'SITE-A',qtyMilli:1000}),'PO_NOT_APPROVED');
});
test('purchase order maker cannot self approve even with permission',()=>{
  const h=harness();h.prepare('DRAFT');
  denied(()=>h.send('po.approve',{poId:'PO-1',expectedRevision:1},
    actor('maker',['SITE-A'],{permissions:[...roles.maker,'proc.po.approve']})),'MAKER_CANNOT_APPROVE');
});
test('partial receipt leaves open quantity, starts quarantined and never posts stock',()=>{
  const h=harness();h.prepare();
  const r=h.send('receipt.record',{id:'GRN-1',poId:'PO-1',siteId:'SITE-A',qtyMilli:4000});
  assert.equal(r.stockEffect,'NONE');
  assert.equal(h.kernel.report(actor()).orders[0].quarantinedQtyMilli,4000);
  denied(()=>h.send('po.close',{poId:'PO-1'},actor('checker')),'PO_RECEIPT_NOT_RECONCILED');
});
test('overdelivery denied without policy; policy alone still requires extra permission',()=>{
  const a=harness();a.prepare();
  denied(()=>a.send('receipt.record',{id:'GRN-2',poId:'PO-1',siteId:'SITE-A',qtyMilli:10001}),'OVERDELIVERY_TOLERANCE');
  const b=harness({overdeliveryBps:500});b.prepare();
  denied(()=>b.send('receipt.record',{id:'GRN-2',poId:'PO-1',siteId:'SITE-A',qtyMilli:10100}),'OVERDELIVERY_REQUIRES_PERMISSION');
  const r=b.send('receipt.record',{id:'GRN-2',poId:'PO-1',siteId:'SITE-A',qtyMilli:10100},
    actor('maker',['SITE-A'],{permissions:[...roles.maker,'proc.overdelivery']}));
  assert.equal(r.status,'QUARANTINED');
});
test('QC rejects absent evidence and self inspection',()=>{
  const h=harness();h.prepare();
  h.send('receipt.record',{id:'GRN-1',poId:'PO-1',siteId:'SITE-A',qtyMilli:10000});
  denied(()=>h.send('receipt.inspect',{receiptId:'GRN-1',decision:'ACCEPTED',evidenceId:'QC-1'},
    actor('maker',['SITE-A'],{permissions:[...roles.maker,'proc.qc.inspect']})),'MAKER_CANNOT_INSPECT');
  denied(()=>h.send('receipt.inspect',{receiptId:'GRN-1',decision:'ACCEPTED'},actor('checker')),'INVALID_INPUT');
});
test('invoice without accepted goods is HOLD and cannot propose payment',()=>{
  const h=harness();h.prepare();
  const inv=h.send('invoice.record',{id:'INV-X',poId:'PO-1',supplierRef:'BILL-X',
    currency:'BDT',qtyMilli:10000,unitPriceMinor:20500,taxMinor:0,freightMinor:0});
  assert.equal(inv.status,'HOLD');
  assert.deepEqual(inv.reasons,['INSUFFICIENT_ACCEPTED_RECEIPTS']);
  denied(()=>h.send('payment.propose',{id:'P',invoiceId:'INV-X',amountMinor:1000,
    currency:'BDT',bankFingerprint:'B'}),'UNMATCHED_INVOICE');
});
test('invoice price mismatch remains explicit hold until revised',()=>{
  const h=harness();h.prepare('RECEIVED');
  h.send('invoice.record',{id:'INV-X',poId:'PO-1',supplierRef:'BILL-X',
    currency:'BDT',qtyMilli:10000,unitPriceMinor:23000,taxMinor:0,freightMinor:0});
  assert.deepEqual(h.kernel.report(actor()).holds[0].reasons,['PRICE_MISMATCH']);
  const v=h.send('invoice.revise',{id:'INV-X',supplierRef:'BILL-X',
    currency:'BDT',qtyMilli:10000,unitPriceMinor:20500,taxMinor:0,freightMinor:0});
  assert.equal(v.status,'MATCHED');assert.equal(v.revision,2);
  denied(()=>h.send('invoice.revise',{id:'INV-X',supplierRef:'BILL-X',
    currency:'BDT',qtyMilli:10000,unitPriceMinor:20500,taxMinor:0,freightMinor:0}),'MATCHED_INVOICE_IMMUTABLE');
});
test('duplicate supplier invoice blocked and double matching cannot consume same receipt',()=>{
  const h=harness();h.prepare('MATCHED');
  denied(()=>h.send('invoice.record',{id:'INV-2',poId:'PO-1',supplierRef:'BILL-001',
    currency:'BDT',qtyMilli:1000,unitPriceMinor:20500,taxMinor:0,freightMinor:0}),'DUPLICATE_SUPPLIER_INVOICE');
  const second=h.send('invoice.record',{id:'INV-3',poId:'PO-1',supplierRef:'BILL-002',
    currency:'BDT',qtyMilli:1000,unitPriceMinor:20500,taxMinor:0,freightMinor:0});
  assert.equal(second.status,'HOLD');
});
test('supplier return capped by original accepted receipt',()=>{
  const h=harness();h.prepare('RECEIVED');
  h.send('return.record',{id:'RET-1',receiptId:'GRN-1',qtyMilli:3000,reasonCode:'DAMAGE'});
  denied(()=>h.send('return.record',{id:'RET-2',receiptId:'GRN-1',qtyMilli:8000,
    reasonCode:'DAMAGE'}),'RETURN_EXCEEDS_RECEIPT');
});
test('unauthorized payment self-approval and changed bank proof denied',()=>{
  const h=harness();h.prepare('MATCHED');
  h.send('payment.propose',{id:'PAY',invoiceId:'INV-1',amountMinor:20000,
    currency:'BDT',bankFingerprint:'HASH-A'});
  denied(()=>h.send('payment.authorize',{paymentId:'PAY',expectedBankFingerprint:'HASH-B'},
    actor('checker')),'BANK_DETAILS_CHANGED');
  denied(()=>h.send('payment.authorize',{paymentId:'PAY',expectedBankFingerprint:'HASH-A'},
    actor('maker',['SITE-A'],{permissions:[...roles.maker,'proc.payment.authorize']})),'MAKER_CANNOT_APPROVE');
});
test('payment proposals never overallocate even when payment is not settled',()=>{
  const h=harness();h.prepare('MATCHED');
  h.send('payment.propose',{id:'PAY-A',invoiceId:'INV-1',amountMinor:150000,
    currency:'BDT',bankFingerprint:'BANK-A'});
  denied(()=>h.send('payment.propose',{id:'PAY-B',invoiceId:'INV-1',amountMinor:60000,
    currency:'BDT',bankFingerprint:'BANK-A'}),'PROPOSAL_EXCEEDS_INVOICE');
  h.send('payment.cancel',{paymentId:'PAY-A'});
  const second=h.send('payment.propose',{id:'PAY-B',invoiceId:'INV-1',amountMinor:206500,
    currency:'BDT',bankFingerprint:'BANK-A'});
  assert.equal(second.bankEffect,'NONE');
});
test('payment authorization cannot be cancelled in the planning engine',()=>{
  const h=harness();h.prepare('MATCHED');
  h.send('payment.propose',{id:'PAY-A',invoiceId:'INV-1',amountMinor:10000,
    currency:'BDT',bankFingerprint:'BANK-A'});
  h.send('payment.authorize',{paymentId:'PAY-A',expectedBankFingerprint:'BANK-A'},actor('checker'));
  denied(()=>h.send('payment.cancel',{paymentId:'PAY-A'}),'AUTHORIZED_PAYMENT_NOT_CANCELLABLE_HERE');
});
test('landed cost allocation conserves every minor unit with deterministic tie-break',()=>{
  const x=allocateLandedCost({chargeMinor:100,lines:[
    {id:'A',qtyMilli:1000,valueMinor:200},{id:'B',qtyMilli:1000,valueMinor:200},
    {id:'C',qtyMilli:1000,valueMinor:200}],basis:'quantity'});
  assert.equal(x.allocatedMinor,100);
  assert.equal(x.unallocatedMinor,0);
  assert.deepEqual(x.allocations.map(l=>l.minor),[34,33,33]);
  assert.equal(x.authority,'CALCULATION_ONLY_NOT_CAPITALIZED');
});
test('allocation blocks zero base, duplicate identifiers, and negative charge',()=>{
  denied(()=>allocateLandedCost({chargeMinor:1,lines:[{id:'X',qtyMilli:0}],basis:'quantity'}),'INVALID_POSITIVE_INTEGER');
  denied(()=>allocateLandedCost({chargeMinor:1,lines:[
    {id:'X',qtyMilli:1},{id:'X',qtyMilli:2}],basis:'quantity'}),'DUPLICATE_ALLOCATION_LINE');
  denied(()=>allocateLandedCost({chargeMinor:-1,lines:[{id:'A',qtyMilli:1000}],basis:'quantity'}),'INVALID_NONNEGATIVE_INTEGER');
});
test('site-specific reporting excludes another site; audit requires explicit permission',()=>{
  const h=harness();h.prepare('MATCHED');
  const b=h.kernel.report(actor('viewer',['SITE-B']));
  assert.equal(b.orders.length,0);assert.equal(b.invoices.length,0);
  denied(()=>h.kernel.inspect(actor('viewer')),'PERMISSION_DENIED');
});
test('invalid date and fractional stock quantity are refused',()=>{
  const h=harness();
  denied(()=>h.send('supplier.register',{id:'S',status:'ACTIVE',relatedPartyHold:false,
    validThrough:'2026-02-30'}),'INVALID_DATE');
  denied(()=>h.send('requisition.create',{id:'R',siteId:'SITE-A',itemId:'X',uom:'KG',
    sourceDemandId:'D',neededOn:'2026-11-20',qtyMilli:1.25}),'INVALID_POSITIVE_INTEGER');
});

test('comparable supplier quotations are ranked by full explicit charge, without automatic PO choice',()=>{
  const h=harness();h.prepare('DRAFT');
  h.send('quote.add',{id:'QUOTE-2',requisitionId:'REQ-1',supplierId:'SUP-1',
    uom:'KG',currency:'BDT',unitPriceMinor:20000,taxMinor:1000,freightMinor:0,
    leadDays:3,validThrough:'2026-12-01'});
  const view=h.kernel.compareQuotes(actor('maker',['SITE-A'],{
    permissions:[...roles.maker,'proc.quote.compare']
  }),'REQ-1','2026-11-12');
  assert.equal(view.quotes.length,2);
  assert.equal(view.quotes[0].quoteId,'QUOTE-2');
  assert.equal(view.quotes[0].totalMinor,201000);
  assert.equal(view.comparison,'ADVISORY_ONLY_NO_AUTO_SUPPLIER_SELECTION');
});
test('mixed quote currencies fail closed instead of applying an invented FX rate',()=>{
  const h=harness();h.prepare('DRAFT');
  h.send('quote.add',{id:'USD-QUOTE',requisitionId:'REQ-1',supplierId:'SUP-1',
    uom:'KG',currency:'USD',unitPriceMinor:100,taxMinor:0,freightMinor:0,
    leadDays:2,validThrough:'2026-12-01'});
  denied(()=>h.kernel.compareQuotes(actor('maker',['SITE-A'],{
    permissions:[...roles.maker,'proc.quote.compare']
  }),'REQ-1','2026-11-12'),'MIXED_CURRENCY_COMPARISON_DENIED');
});
test('quote comparison remains site-scoped and never trusts supplied user identity',()=>{
  const h=harness();h.prepare('DRAFT');
  denied(()=>h.kernel.compareQuotes(actor('maker',['SITE-B'],{
    permissions:[...roles.maker,'proc.quote.compare']
  }),'REQ-1','2026-11-12'),'SITE_DENIED');
});
