// CORE10 Build 08 / C10-CAP-PROC-001 — isolated, deterministic procurement kernel.
// NO production authority: this in-memory draft is not a database, an API authentication
// boundary, a stock posting engine or an AP/payment integration. Never expose caller-supplied
// actor claims as trusted identity; the signed canonical adapter is a separate release gate.
import { createHash } from 'node:crypto';

export class ProcurementError extends Error {
  constructor(code, message = code) {
    super(message);
    this.name = 'ProcurementError';
    this.code = code;
  }
}

const fail = (code) => { throw new ProcurementError(code); };
const need = (value, code = 'INVALID_INPUT') => {
  if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9:_./-]{0,79}$/.test(value)) fail(code);
  return value;
};
const positive = (v) => {
  if (!Number.isSafeInteger(v) || v <= 0) fail('INVALID_POSITIVE_INTEGER');
  return v;
};
const nonnegative = (v) => {
  if (!Number.isSafeInteger(v) || v < 0) fail('INVALID_NONNEGATIVE_INTEGER');
  return v;
};
const day = (s) => {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s) ||
      Number.isNaN(Date.parse(s + 'T00:00:00Z')) ||
      new Date(s + 'T00:00:00Z').toISOString().slice(0, 10) !== s) fail('INVALID_DATE');
  return s;
};
const digest = (data) => createHash('sha256').update(JSON.stringify(data)).digest('hex');
const clone = (v) => structuredClone(v);
const sum = (xs) => xs.reduce((a, x) => a + x, 0);
const exactMinor = (unitPriceMinor, qtyMilli) => {
  nonnegative(unitPriceMinor); positive(qtyMilli);
  const product = BigInt(unitPriceMinor) * BigInt(qtyMilli);
  const result = (product + 500n) / 1000n; // positive half-up, minor-currency unit
  if (result > BigInt(Number.MAX_SAFE_INTEGER)) fail('AMOUNT_OVERFLOW');
  return Number(result);
};
function get(map, id, label) {
  need(id);
  if (!Object.hasOwn(map, id)) fail(label + '_NOT_FOUND');
  return map[id];
}
function put(map, id, value, label) {
  need(id);
  if (Object.hasOwn(map, id)) fail(label + '_DUPLICATE');
  map[id] = value;
}
function assertActor(actor, ctx, permission, siteId) {
  if (!actor || actor.revoked === true || need(actor.actorId) === '') fail('ACTOR_DENIED');
  if (actor.tenantId !== ctx.tenantId || actor.businessId !== ctx.businessId) fail('CROSS_SCOPE_DENIED');
  if (!Array.isArray(actor.permissions) || !actor.permissions.includes(permission)) fail('PERMISSION_DENIED');
  if (siteId && (!Array.isArray(actor.siteIds) || !actor.siteIds.includes(siteId))) fail('SITE_DENIED');
}
const sameSite = (record, siteId) => {
  if (record.siteId !== siteId) fail('SITE_MISMATCH');
};
const policy = Object.freeze({
  'supplier.register': 'proc.supplier.write',
  'requisition.create': 'proc.requisition.create',
  'requisition.approve': 'proc.requisition.approve',
  'quote.add': 'proc.quote.write',
  'po.create': 'proc.po.create',
  'po.revise': 'proc.po.revise',
  'po.approve': 'proc.po.approve',
  'receipt.record': 'proc.receipt.record',
  'receipt.inspect': 'proc.qc.inspect',
  'invoice.record': 'proc.invoice.record',
  'invoice.revise': 'proc.invoice.revise',
  'return.record': 'proc.return.record',
  'payment.propose': 'proc.payment.propose',
  'payment.authorize': 'proc.payment.authorize',
  'payment.cancel': 'proc.payment.cancel',
  'po.close': 'proc.po.close'
});

export function allocateLandedCost({ chargeMinor, lines, basis }) {
  nonnegative(chargeMinor);
  if (!Array.isArray(lines) || !lines.length || lines.length > 500) fail('INVALID_ALLOCATION_LINES');
  if (!['quantity', 'value'].includes(basis)) fail('INVALID_ALLOCATION_BASIS');
  const ids = new Set();
  const weights = lines.map((x) => {
    need(x.id);
    if (ids.has(x.id)) fail('DUPLICATE_ALLOCATION_LINE');
    ids.add(x.id);
    return BigInt(positive(basis === 'quantity' ? x.qtyMilli : x.valueMinor));
  });
  const total = weights.reduce((a, b) => a + b, 0n);
  if (total === 0n) fail('ZERO_ALLOCATION_BASE');
  const allocated = weights.map((w, i) => ({
    id: lines[i].id,
    minor: Number(BigInt(chargeMinor) * w / total),
    rem: BigInt(chargeMinor) * w % total
  }));
  let outstanding = BigInt(chargeMinor) - allocated.reduce((a, x) => a + BigInt(x.minor), 0n);
  const priority = [...allocated].sort((a, b) => a.rem === b.rem ? a.id.localeCompare(b.id) : (a.rem > b.rem ? -1 : 1));
  for (const line of priority) {
    if (outstanding === 0n) break;
    line.minor += 1;
    outstanding--;
  }
  return {
    basis, chargeMinor,
    allocations: allocated.map(({id, minor}) => ({id, minor})),
    allocatedMinor: sum(allocated.map(x => x.minor)),
    unallocatedMinor: Number(outstanding),
    authority: 'CALCULATION_ONLY_NOT_CAPITALIZED'
  };
}

export function createProcurementKernel(input) {
  const ctx = {
    tenantId: need(input?.tenantId), businessId: need(input?.businessId),
    sites: [...new Set(input?.siteIds || [])].map(s => need(s)),
    overdeliveryBps: nonnegative(input?.overdeliveryBps ?? 0)
  };
  if (!ctx.sites.length || ctx.overdeliveryBps > 1000) fail('INVALID_POLICY');
  let s = { suppliers:{}, requisitions:{}, quotes:{}, orders:{}, receipts:{},
    invoices:{}, returns:{}, payments:{}, seen:{}, audit:[] };
  const isSite = (siteId) => {
    need(siteId);
    if (!ctx.sites.includes(siteId)) fail('UNKNOWN_SITE');
    return siteId;
  };
  const sumReceipt = (state, poId, statuses) => sum(Object.values(state.receipts)
    .filter(x => x.poId === poId && statuses.includes(x.status)).map(x => x.qtyMilli));
  const sumReturn = (state, receiptId) => sum(Object.values(state.returns)
    .filter(x => x.receiptId === receiptId).map(x => x.qtyMilli));
  const invoiceQty = (state, poId, exclude) => sum(Object.values(state.invoices)
    .filter(x => x.poId === poId && x.status === 'MATCHED' && x.id !== exclude).map(x => x.qtyMilli));
  const supplierEligible = (state, id, onDate) => {
    const supplier = get(state.suppliers,id,'SUPPLIER');
    if (supplier.status !== 'ACTIVE' || supplier.validThrough < onDate || supplier.relatedPartyHold)
      fail('SUPPLIER_NOT_ELIGIBLE');
    return supplier;
  };
  function report(actor) {
    assertActor(actor, ctx, 'proc.report');
    const included = new Set(actor.siteIds || []);
    const orders = Object.values(s.orders).filter(x => included.has(x.siteId));
    const ids = new Set(orders.map(x => x.id));
    const receipts = Object.values(s.receipts).filter(x => ids.has(x.poId));
    const invoices = Object.values(s.invoices).filter(x => ids.has(x.poId));
    const payments = Object.values(s.payments).filter(x => invoices.some(i => i.id === x.invoiceId));
    return clone({
      businessId:ctx.businessId, tenantId:ctx.tenantId, reportAuthority:'DRAFT_NOT_ACCOUNTING',
      orders: orders.map(x=>({id:x.id, siteId:x.siteId, status:x.status, revision:x.revision,
        orderedQtyMilli:x.qtyMilli, acceptedQtyMilli:sumReceipt(s,x.id,['ACCEPTED']),
        quarantinedQtyMilli:sumReceipt(s,x.id,['QUARANTINED']),
        returnedQtyMilli:sum(Object.values(s.returns).filter(r=>r.poId===x.id).map(r=>r.qtyMilli))})),
      holds: invoices.filter(x=>x.status==='HOLD').map(x=>({id:x.id, reasons:x.reasons})),
      invoices: invoices.map(x=>({id:x.id,status:x.status,totalMinor:x.totalMinor,currency:x.currency})),
      paymentProposals: payments.map(x=>({id:x.id,status:x.status,amountMinor:x.amountMinor})),
      receiptCount:receipts.length
    });
  }
  function dispatch(envelope) {
    if (!envelope || typeof envelope !== 'object') fail('INVALID_ENVELOPE');
    const {requestId,actor,type,payload,onDate} = envelope;
    need(requestId, 'INVALID_REQUEST_ID'); day(onDate);
    if (!Object.hasOwn(policy,type)) fail('UNKNOWN_COMMAND');
    const p = payload || {};
    // Resolve the site from the canonical existing record FIRST. A caller may not
    // substitute p.siteId to authorize a different site than the referenced document.
    const recordSite = (p.poId ? s.orders[p.poId]?.siteId : undefined)
      ?? (p.receiptId ? s.receipts[p.receiptId]?.siteId : undefined)
      ?? (p.invoiceId ? s.invoices[p.invoiceId]?.siteId : undefined)
      ?? (type === 'invoice.revise' && p.id ? s.invoices[p.id]?.siteId : undefined)
      ?? (p.requisitionId ? s.requisitions[p.requisitionId]?.siteId : undefined)
      ?? (p.quoteId ? s.requisitions[s.quotes[p.quoteId]?.requisitionId]?.siteId : undefined)
      ?? (p.paymentId ? s.payments[p.paymentId]?.siteId : undefined);
    if (recordSite && p.siteId && p.siteId !== recordSite) fail('SITE_MISMATCH');
    const targetSite = recordSite ?? p.siteId;
    assertActor(actor,ctx,policy[type],targetSite);
    if (targetSite) isSite(targetSite);
    const fingerprint = digest({tenantId:ctx.tenantId,businessId:ctx.businessId,type,payload:p,
      onDate,actorId:actor.actorId,siteId:targetSite});
    if (s.seen[requestId]) {
      if (s.seen[requestId].fingerprint !== fingerprint) fail('IDEMPOTENCY_CONFLICT');
      return clone({...s.seen[requestId].result, replay:true});
    }
    const tx = clone(s);
    let result;
    switch(type) {
      case 'supplier.register': {
        need(p.id); day(p.validThrough);
        if (!['ACTIVE','BLOCKED'].includes(p.status) || typeof p.relatedPartyHold !== 'boolean')
          fail('INVALID_SUPPLIER_STATUS');
        put(tx.suppliers,p.id,{id:p.id,status:p.status,validThrough:p.validThrough,
          relatedPartyHold:p.relatedPartyHold},'SUPPLIER');
        result={supplierId:p.id,status:p.status}; break;
      }
      case 'requisition.create': {
        const siteId=isSite(p.siteId); need(p.id); need(p.itemId); need(p.uom); need(p.sourceDemandId);
        positive(p.qtyMilli); day(p.neededOn);
        if (Object.values(tx.requisitions).some(x=>x.siteId===siteId && x.sourceDemandId===p.sourceDemandId))
          fail('DUPLICATE_SOURCE_DEMAND');
        put(tx.requisitions,p.id,{id:p.id,siteId,itemId:p.itemId,uom:p.uom,sourceDemandId:p.sourceDemandId,
          qtyMilli:p.qtyMilli,neededOn:p.neededOn,status:'DRAFT',makerId:actor.actorId},'REQUISITION');
        result={requisitionId:p.id,status:'DRAFT'}; break;
      }
      case 'requisition.approve': {
        const q=get(tx.requisitions,p.requisitionId,'REQUISITION');
        if(q.status!=='DRAFT') fail('INVALID_REQUISITION_STATUS');
        if(q.makerId===actor.actorId) fail('MAKER_CANNOT_APPROVE');
        q.status='APPROVED';q.approvedBy=actor.actorId;
        result={requisitionId:q.id,status:q.status}; break;
      }
      case 'quote.add': {
        const req=get(tx.requisitions,p.requisitionId,'REQUISITION');
        if(req.status!=='APPROVED') fail('REQUISITION_NOT_APPROVED');
        supplierEligible(tx,p.supplierId,onDate);
        if(p.uom!==req.uom) fail('UOM_MISMATCH');
        day(p.validThrough);
        if(p.validThrough<onDate) fail('QUOTE_EXPIRED');
        need(p.currency);positive(p.unitPriceMinor);nonnegative(p.taxMinor);nonnegative(p.freightMinor);
        nonnegative(p.leadDays);
        put(tx.quotes,p.id,{id:p.id,requisitionId:req.id,supplierId:p.supplierId,
          currency:p.currency,unitPriceMinor:p.unitPriceMinor,taxMinor:p.taxMinor,
          freightMinor:p.freightMinor,leadDays:p.leadDays,validThrough:p.validThrough},'QUOTE');
        result={quoteId:p.id,comparableUom:req.uom,
          totalMinor:exactMinor(p.unitPriceMinor,req.qtyMilli)+p.taxMinor+p.freightMinor};break;
      }
      case 'po.create': {
        const offer=get(tx.quotes,p.quoteId,'QUOTE');
        const req=get(tx.requisitions,offer.requisitionId,'REQUISITION');
        supplierEligible(tx,offer.supplierId,onDate);
        if(offer.validThrough<onDate) fail('QUOTE_EXPIRED');
        if(Object.values(tx.orders).some(x=>x.requisitionId===req.id && x.status!=='CANCELLED'))
          fail('REQUISITION_ALREADY_ORDERED');
        put(tx.orders,p.id,{id:p.id,siteId:req.siteId,requisitionId:req.id,quoteId:offer.id,
          supplierId:offer.supplierId,currency:offer.currency,qtyMilli:req.qtyMilli,
          unitPriceMinor:offer.unitPriceMinor,revision:1,status:'DRAFT',makerId:actor.actorId,
          overdeliveryBps:ctx.overdeliveryBps},'PO');
        result={poId:p.id,revision:1,status:'DRAFT'};break;
      }
      case 'po.revise': {
        const po=get(tx.orders,p.poId,'PO');
        if(!['DRAFT','APPROVED'].includes(po.status)) fail('PO_NOT_EDITABLE');
        if(Object.values(tx.receipts).some(x=>x.poId===po.id)) fail('PO_HAS_RECEIPT');
        if(p.expectedRevision!==po.revision) fail('STALE_PO_REVISION');
        positive(p.qtyMilli);positive(p.unitPriceMinor);
        po.qtyMilli=p.qtyMilli;po.unitPriceMinor=p.unitPriceMinor;po.revision++;
        po.status='DRAFT';delete po.approvedBy;po.makerId=actor.actorId;
        result={poId:po.id,revision:po.revision,status:po.status};break;
      }
      case 'po.approve': {
        const po=get(tx.orders,p.poId,'PO');
        if(po.status!=='DRAFT') fail('PO_NOT_DRAFT');
        if(p.expectedRevision!==po.revision) fail('STALE_PO_REVISION');
        if(po.makerId===actor.actorId) fail('MAKER_CANNOT_APPROVE');
        supplierEligible(tx,po.supplierId,onDate);
        po.status='APPROVED';po.approvedBy=actor.actorId;
        result={poId:po.id,revision:po.revision,status:po.status};break;
      }
      case 'receipt.record': {
        const po=get(tx.orders,p.poId,'PO');
        if(po.status!=='APPROVED') fail('PO_NOT_APPROVED');
        if(p.siteId!==po.siteId) fail('SITE_MISMATCH');
        positive(p.qtyMilli);
        const prev=sumReceipt(tx,po.id,['ACCEPTED','QUARANTINED','REJECTED']);
        const max=(BigInt(po.qtyMilli)*(10000n+BigInt(po.overdeliveryBps)))/10000n;
        if(BigInt(prev)+BigInt(p.qtyMilli)>max) fail('OVERDELIVERY_TOLERANCE');
        if(prev+p.qtyMilli>po.qtyMilli && !actor.permissions.includes('proc.overdelivery'))
          fail('OVERDELIVERY_REQUIRES_PERMISSION');
        put(tx.receipts,p.id,{id:p.id,poId:po.id,siteId:po.siteId,qtyMilli:p.qtyMilli,
          status:'QUARANTINED',makerId:actor.actorId},'RECEIPT');
        result={receiptId:p.id,status:'QUARANTINED',stockEffect:'NONE'};break;
      }
      case 'receipt.inspect': {
        const receipt=get(tx.receipts,p.receiptId,'RECEIPT');
        if(receipt.status!=='QUARANTINED') fail('RECEIPT_ALREADY_INSPECTED');
        if(receipt.makerId===actor.actorId) fail('MAKER_CANNOT_INSPECT');
        if(!['ACCEPTED','REJECTED'].includes(p.decision)) fail('INVALID_QC_DECISION');
        need(p.evidenceId);
        receipt.status=p.decision;receipt.inspectedBy=actor.actorId;receipt.evidenceId=p.evidenceId;
        result={receiptId:receipt.id,status:receipt.status,stockEffect:'NONE'};break;
      }
      case 'invoice.record':
      case 'invoice.revise': {
        const revising=type==='invoice.revise';
        const invoice=revising?get(tx.invoices,p.id,'INVOICE'):null;
        if(revising && invoice.status!=='HOLD') fail('MATCHED_INVOICE_IMMUTABLE');
        const po=get(tx.orders,revising?invoice.poId:p.poId,'PO');
        if(po.status!=='APPROVED') fail('PO_NOT_APPROVED');
        need(p.supplierRef);need(p.currency);positive(p.qtyMilli);
        positive(p.unitPriceMinor);nonnegative(p.freightMinor);nonnegative(p.taxMinor);
        const supplierId=revising?invoice.supplierId:po.supplierId;
        if(!revising && Object.values(tx.invoices).some(x=>x.supplierId===supplierId && x.supplierRef===p.supplierRef))
          fail('DUPLICATE_SUPPLIER_INVOICE');
        const reasons=[];
        if(p.currency!==po.currency) reasons.push('CURRENCY_MISMATCH');
        if(p.unitPriceMinor!==po.unitPriceMinor) reasons.push('PRICE_MISMATCH');
        const accepted=sumReceipt(tx,po.id,['ACCEPTED']);
        const returned=sum(Object.values(tx.returns).filter(x=>x.poId===po.id).map(x=>x.qtyMilli));
        if(p.qtyMilli+invoiceQty(tx,po.id,revising?invoice.id:undefined)>accepted-returned)
          reasons.push('INSUFFICIENT_ACCEPTED_RECEIPTS');
        const totalMinor=exactMinor(p.unitPriceMinor,p.qtyMilli)+p.taxMinor+p.freightMinor;
        if(!Number.isSafeInteger(totalMinor)) fail('AMOUNT_OVERFLOW');
        const rec={id:p.id,poId:po.id,siteId:po.siteId,supplierId,supplierRef:p.supplierRef,
          currency:p.currency,qtyMilli:p.qtyMilli,unitPriceMinor:p.unitPriceMinor,
          freightMinor:p.freightMinor,taxMinor:p.taxMinor,totalMinor,
          status:reasons.length?'HOLD':'MATCHED',reasons,revision:revising?invoice.revision+1:1};
        if(revising) {
          if(p.supplierRef!==invoice.supplierRef) fail('INVOICE_IDENTITY_IMMUTABLE');
          tx.invoices[p.id]=rec;
        } else put(tx.invoices,p.id,rec,'INVOICE');
        result={invoiceId:p.id,status:rec.status,reasons,revision:rec.revision,
          apEffect:'NONE',totalMinor};break;
      }
      case 'return.record': {
        const receipt=get(tx.receipts,p.receiptId,'RECEIPT');
        if(receipt.status!=='ACCEPTED') fail('RETURN_REQUIRES_ACCEPTED_RECEIPT');
        positive(p.qtyMilli);need(p.reasonCode);
        if(p.qtyMilli+sumReturn(tx,receipt.id)>receipt.qtyMilli) fail('RETURN_EXCEEDS_RECEIPT');
        put(tx.returns,p.id,{id:p.id,receiptId:receipt.id,poId:receipt.poId,
          siteId:receipt.siteId,qtyMilli:p.qtyMilli,reasonCode:p.reasonCode,
          status:'PENDING_CANONICAL_POST'},'RETURN');
        result={returnId:p.id,status:'PENDING_CANONICAL_POST',stockEffect:'NONE'};break;
      }
      case 'payment.propose': {
        const invoice=get(tx.invoices,p.invoiceId,'INVOICE');
        if(invoice.status!=='MATCHED') fail('UNMATCHED_INVOICE');
        positive(p.amountMinor);need(p.bankFingerprint);
        if(p.currency!==invoice.currency) fail('CURRENCY_MISMATCH');
        const reserved=sum(Object.values(tx.payments).filter(x=>x.invoiceId===invoice.id && x.status!=='CANCELLED')
          .map(x=>x.amountMinor));
        if(p.amountMinor+reserved>invoice.totalMinor) fail('PROPOSAL_EXCEEDS_INVOICE');
        put(tx.payments,p.id,{id:p.id,invoiceId:invoice.id,siteId:invoice.siteId,
          amountMinor:p.amountMinor,currency:p.currency,bankFingerprint:p.bankFingerprint,
          status:'PROPOSED',makerId:actor.actorId},'PAYMENT');
        result={paymentId:p.id,status:'PROPOSED',bankEffect:'NONE'};break;
      }
      case 'payment.authorize': {
        const payment=get(tx.payments,p.paymentId,'PAYMENT');
        if(payment.status!=='PROPOSED') fail('PAYMENT_NOT_PROPOSED');
        if(payment.makerId===actor.actorId) fail('MAKER_CANNOT_APPROVE');
        if(payment.bankFingerprint!==p.expectedBankFingerprint) fail('BANK_DETAILS_CHANGED');
        payment.status='AUTHORIZED_PENDING_EXTERNAL_SETTLEMENT';
        payment.approvedBy=actor.actorId;
        result={paymentId:payment.id,status:payment.status,bankEffect:'NONE'};break;
      }
      case 'payment.cancel': {
        const payment=get(tx.payments,p.paymentId,'PAYMENT');
        if(payment.status!=='PROPOSED') fail('AUTHORIZED_PAYMENT_NOT_CANCELLABLE_HERE');
        payment.status='CANCELLED';
        result={paymentId:payment.id,status:'CANCELLED',bankEffect:'NONE'};break;
      }
      case 'po.close': {
        const po=get(tx.orders,p.poId,'PO');
        if(po.status!=='APPROVED') fail('PO_NOT_APPROVED');
        const accepted=sumReceipt(tx,po.id,['ACCEPTED']);
        const returned=sum(Object.values(tx.returns).filter(x=>x.poId===po.id).map(x=>x.qtyMilli));
        const pending=sumReceipt(tx,po.id,['QUARANTINED']);
        if(pending>0 || accepted-returned<po.qtyMilli) fail('PO_RECEIPT_NOT_RECONCILED');
        if(Object.values(tx.invoices).some(x=>x.poId===po.id && x.status==='HOLD'))
          fail('UNRESOLVED_INVOICE_HOLD');
        if(invoiceQty(tx,po.id)!==accepted-returned) fail('PO_INVOICE_NOT_RECONCILED');
        po.status='CLOSED';
        result={poId:po.id,status:'CLOSED',warning:'UNSETTLED_AP_NOT_PAID_OR_POSTED'};break;
      }
    }
    const receipt={...result,requestId,replay:false};
    tx.audit.push({sequence:tx.audit.length+1,requestId,type,actorId:actor.actorId,
      tenantId:ctx.tenantId,businessId:ctx.businessId,siteId:targetSite||null,
      fingerprint,outcome:result.status||'RECORDED',authority:'DRAFT_ONLY'});
    tx.seen[requestId]={fingerprint,result:receipt};
    s=tx;
    return clone(receipt);
  }
  return Object.freeze({dispatch,report,
    describe:()=>({tenantId:ctx.tenantId,businessId:ctx.businessId,sites:[...ctx.sites],
      authority:'ISOLATED_DRAFT_ONLY',sideEffects:'NONE',implementedCommands:Object.keys(policy)}),
    inspect:(actor)=>{assertActor(actor,ctx,'proc.audit.read');return clone(s);}
  });
}
