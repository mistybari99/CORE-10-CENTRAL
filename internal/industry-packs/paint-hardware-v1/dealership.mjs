
/**
 * C10-CAP-PAINT-001: complementary industry-evidence module.
 * Synthetic, in-memory and NON-POSTING. No real authentication or transaction authority.
 * Snapshot labels cannot prove authenticity and MUST be replaced by signed server adapters.
 */
import {createHash} from 'node:crypto';
const deny=x=>{throw new Error(x);};
const key=(x,n='ID')=>typeof x==='string'&&/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$/.test(x)?x:deny('INVALID_'+n);
const integer=(x,n,low=0,max=100000000000)=>Number.isSafeInteger(x)&&x>=low&&x<=max?x:deny('INVALID_'+n);
const clone=x=>structuredClone(x);
const ctx=x=>{
  if(x?.mode!=='synthetic-only')deny('SIGNED_BACKEND_AUTH_NOT_CONNECTED');
  return {tenant:key(x.tenant,'TENANT'),business:key(x.business,'BUSINESS'),actor:key(x.actor,'ACTOR')};
};
const date=s=>{
  if(typeof s!=='string'||!/^\d{4}-\d\d-\d\d$/.test(s)||new Date(s+'T00:00:00Z').toISOString().slice(0,10)!==s) deny('INVALID_ISO_DATE');
  return s;
};
const money=x=>integer(x,'MONEY_MINOR');
const round=(v,d)=>Number((v+d/2n)/d);
const scope=(c,id)=>[c.tenant,c.business,key(id)].join('|');
const fingerprint=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
const ev=(e,c,type)=>{
  if(e?.source!=='canonical-readonly'||e.type!==type||e.tenant!==c.tenant||e.business!==c.business||
     typeof e.version!=='string'||!e.version.trim())deny('SCOPED_CANONICAL_SNAPSHOT_REQUIRED');
  return e;
};
export class PaintDealerDraft {
  #packs=new Map();#dealers=new Map();#schemes=new Map();#claims=new Map();#cheques=new Map();
  #sds=new Map();#returns=new Map();#hardware=new Map();#receipts=new Map();#events=[];
  #record(c,op,id,rid,detail={}){
    this.#events.push({seq:this.#events.length+1,tenant:c.tenant,business:c.business,actor:c.actor,op,id,
      requestId:rid,detail:clone(detail)});
  }
  #write(input,action,requestId,payload,fn){
    const c=ctx(input),rid=key(requestId,'REQUEST'),receipt=scope(c,action+':'+rid),hash=fingerprint({actor:c.actor,payload});
    const cached=this.#receipts.get(receipt);
    if(cached){if(cached.hash!==hash)deny('IDEMPOTENCY_CONFLICT');return clone(cached.result);}
    const result=fn(c);
    this.#receipts.set(receipt,{hash,result:clone(result)});
    return clone(result);
  }
  #get(map,c,id){const v=map.get(scope(c,id));if(!v)deny('NOT_FOUND_IN_SCOPE');return v;}
  #insert(map,c,id,data){
    const k=scope(c,id);if(map.has(k))deny('IMMUTABLE_OR_DUPLICATE_RECORD');
    const row={id,tenant:c.tenant,business:c.business,...data};
    map.set(k,row);return row;
  }
  addPack(context,requestId,p){
    return this.#write(context,'pack',requestId,p,c=>{
      const packId=key(p?.packId,'PACK');
      if(p?.uom!=='L'||p.opened===true)deny('SEALED_LITRE_PACK_ONLY');
      const ml=integer(p.capacityML,'CAPACITY_ML',100,100000);
      const row=this.#insert(this.#packs,c,packId,{
        sku:key(p.sku,'SKU'),capacityML:ml,uom:'L',
        originalSealed:true,priceBasis:'per sealed pack',actualMassKG:null
      });this.#record(c,'PACK_REGISTERED',packId,requestId);return row;
    });
  }
  packPrice(context,input){
    const c=ctx(context),pack=this.#get(this.#packs,c,input?.packId);
    const p=ev(input?.priceSnapshot,c,'approved-pack-price');
    if(p.sku!==pack.sku||p.currency!=='BDT'||p.packId!==pack.id)deny('PACK_PRICE_SOURCE_MISMATCH');
    return {packId:pack.id,capacityML:pack.capacityML,uom:'L',sealedPackMinor:money(p.priceMinor),
      equivalentPerLMinor:round(BigInt(p.priceMinor)*1000n,BigInt(pack.capacityML)),
      sourceVersion:p.version,actualCostMinor:null,marginMinor:null,notAnOrder:true};
  }
  addDealer(context,requestId,p){
    return this.#write(context,'dealer',requestId,p,c=>{
      if(p?.status!=='ACTIVE')deny('DEALER_MUST_BE_ACTIVE');
      const dealerId=key(p.dealerId,'DEALER');
      const row=this.#insert(this.#dealers,c,dealerId,{
        status:'ACTIVE',currency:key(p.currency,'CURRENCY'),
        creditLimitMinor:money(p.creditLimitMinor),termsVersion:key(p.termsVersion,'TERMS_VERSION')
      });this.#record(c,'DEALER_TERMS_REGISTERED',dealerId,requestId);return row;
    });
  }
  creditCheck(context,input){
    const c=ctx(context),dealer=this.#get(this.#dealers,c,input?.dealerId);
    const s=ev(input?.exposureSnapshot,c,'receivables-exposure');
    if(dealer.status!=='ACTIVE'||s.dealerId!==dealer.id||s.currency!==dealer.currency||s.status!=='VERIFIED'||
       s.termsVersion!==dealer.termsVersion||date(input.asOf)!==date(s.asOf))deny('STALE_OR_UNAUTHORIZED_CREDIT');
    const approvedReceivablesMinor=money(s.approvedReceivablesMinor);
    const pendingOrdersMinor=money(s.pendingOrdersMinor);
    const requestedMinor=money(input.requestedMinor);
    const total=BigInt(approvedReceivablesMinor)+BigInt(pendingOrdersMinor)+BigInt(requestedMinor);
    if(total>BigInt(Number.MAX_SAFE_INTEGER))deny('CREDIT_OVERFLOW');
    return {dealerId:dealer.id,asOf:s.asOf,sourceVersion:s.version,
      approvedReceivablesMinor,pendingOrdersMinor,requestedMinor,
      creditLimitMinor:dealer.creditLimitMinor,withinLimit:total<=BigInt(dealer.creditLimitMinor),
      projectedExposureMinor:Number(total),canReleaseOrder:false,requires:'SIGNED_CANONICAL_ORDER_SERVICE'};
  }
  addPrincipalScheme(context,requestId,p){
    return this.#write(context,'scheme',requestId,p,c=>{
      const schemeId=key(p?.schemeId,'SCHEME'),version=integer(p.version,'SCHEME_VERSION',1,9999);
      const id=schemeId+':v'+version,from=date(p.validFrom),to=date(p.validTo);
      if(from>to)deny('INVALID_SCHEME_WINDOW');
      const row=this.#insert(this.#schemes,c,id,{
        principalId:key(p.principalId,'PRINCIPAL'),sku:key(p.sku,'SKU'),version,
        validFrom:from,validTo:to,rateBps:integer(p.rateBps,'RATE_BPS',0,5000),
        currency:key(p.currency,'CURRENCY'),basis:'eligible net purchase invoice'
      });this.#record(c,'SCHEME_REGISTERED',id,requestId);return row;
    });
  }
  previewScheme(context,input){
    const c=ctx(context),s=this.#get(this.#schemes,c,input?.schemeId);
    const invoice=ev(input.invoiceSnapshot,c,'principal-purchase-invoice');
    const at=date(input.asOf);
    if(at<s.validFrom||at>s.validTo||invoice.date<s.validFrom||invoice.date>s.validTo)deny('SCHEME_EXPIRED_OR_NOT_STARTED');
    if(invoice.sku!==s.sku||invoice.principalId!==s.principalId||invoice.currency!==s.currency||
      invoice.status!=='APPROVED'||invoice.returnStatus==='FULL_RETURN')deny('INELIGIBLE_PURCHASE_INVOICE');
    const gross=money(invoice.approvedMinor),returned=money(invoice.returnedMinor);
    if(returned>gross)deny('RETURNS_EXCEED_PURCHASE');
    const eligible=gross-returned,estimated=round(BigInt(eligible)*BigInt(s.rateBps),10000n);
    return {schemeId:s.id,invoiceId:key(invoice.invoiceId,'INVOICE'),invoiceVersion:invoice.version,
      eligibleMinor:eligible,estimatedRebateMinor:estimated,currency:s.currency,
      earnedCertifiedMinor:null,approvedMinor:null,receivedMinor:null,previewOnly:true};
  }
  submitClaim(context,requestId,input){
    return this.#write(context,'claim',requestId,input,c=>{
      const estimate=this.previewScheme(context,input);
      const id=key(input.claimId,'CLAIM');
      for(const x of this.#claims.values())if(x.tenant===c.tenant&&x.business===c.business&&
        x.schemeId===estimate.schemeId&&x.invoiceId===estimate.invoiceId)deny('DUPLICATE_INVOICE_CLAIM');
      const claim=this.#insert(this.#claims,c,id,{
        schemeId:estimate.schemeId,invoiceId:estimate.invoiceId,invoiceVersion:estimate.invoiceVersion,
        estimatedMinor:estimate.estimatedRebateMinor,currency:estimate.currency,claimant:c.actor,
        status:'SUBMITTED',approvedMinor:null,receivedEvidenceMinor:0,receipts:[]
      });this.#record(c,'CLAIM_SUBMITTED',id,requestId);return claim;
    });
  }
  reviewClaim(context,requestId,input){
    return this.#write(context,'claim-review',requestId,input,c=>{
      const claim=this.#get(this.#claims,c,input?.claimId);
      if(claim.status!=='SUBMITTED'||claim.claimant===c.actor)deny('INDEPENDENT_REVIEW_REQUIRED');
      const approvalRef=key(input.approvalRef,'APPROVAL_EVIDENCE');
      const approvedMinor=money(input.approvedMinor);
      if(approvedMinor>claim.estimatedMinor)deny('CLAIM_APPROVAL_EXCEEDS_ESTIMATE');
      claim.status='APPROVED_EVIDENCE';claim.approvedMinor=approvedMinor;
      claim.approvalRef=approvalRef;claim.reviewer=c.actor;
      this.#record(c,'CLAIM_REVIEWED',claim.id,requestId,{approvalRef,approvedMinor});return claim;
    });
  }
  recordClaimReceipt(context,requestId,input){
    return this.#write(context,'claim-receipt',requestId,input,c=>{
      const claim=this.#get(this.#claims,c,input?.claimId);
      if(!['APPROVED_EVIDENCE','PARTIAL_RECEIPT_EVIDENCED','FULL_RECEIPT_EVIDENCED'].includes(claim.status))deny('CLAIM_NOT_APPROVED');
      const amount=integer(input.amountMinor,'RECEIPT_AMOUNT',1);
      const evidenceRef=key(input.evidenceRef,'BANK_EVIDENCE');
      if(claim.receipts.some(x=>x.evidenceRef===evidenceRef))deny('DUPLICATE_RECEIPT_REFERENCE');
      if(claim.receivedEvidenceMinor+amount>claim.approvedMinor)deny('RECEIPT_EXCEEDS_APPROVAL');
      claim.receivedEvidenceMinor+=amount;
      claim.receipts.push({evidenceRef,amountMinor:amount,recordedBy:c.actor});
      claim.status=claim.receivedEvidenceMinor===claim.approvedMinor?'FULL_RECEIPT_EVIDENCED':'PARTIAL_RECEIPT_EVIDENCED';
      this.#record(c,'CLAIM_RECEIPT_EVIDENCE',claim.id,requestId,{evidenceRef,amount});
      return claim;
    });
  }
  claimSummary(context,claimId){
    const c=ctx(context),x=clone(this.#get(this.#claims,c,claimId));
    return {...x,claimedMinor:x.estimatedMinor,pendingMinor:x.approvedMinor===null?null:x.approvedMinor-x.receivedEvidenceMinor,
      reconciledBankMinor:null,postingAllowed:false};
  }
  addCheque(context,requestId,input){
    return this.#write(context,'cheque',requestId,input,c=>{
      const bank=key(input.bankCode,'BANK'),number=key(input.chequeNumber,'CHEQUE_NUMBER'),issuer=key(input.issuerId,'ISSUER');
      const ref=[bank,issuer,number].join(':');
      const row=this.#insert(this.#cheques,c,ref,{bankCode:bank,issuerId:issuer,chequeNumber:number,
        maturityDate:date(input.maturityDate),currency:key(input.currency,'CURRENCY'),
        amountMinor:integer(input.amountMinor,'CHEQUE_AMOUNT',1),status:'INSTRUMENT_HELD',
        clearanceEvidenceRef:null});
      this.#record(c,'PDC_RECORDED',ref,requestId);return row;
    });
  }
  chequeOutcome(context,requestId,input){
    return this.#write(context,'cheque-outcome',requestId,input,c=>{
      const row=this.#get(this.#cheques,c,input?.chequeId);
      if(row.status!=='INSTRUMENT_HELD')deny('PDC_FINAL_OUTCOME_ALREADY_RECORDED');
      const outcome=input.outcome,ref=key(input.bankEvidenceRef,'BANK_EVIDENCE');
      if(!['BOUNCED','BANK_CLEARANCE_EVIDENCED'].includes(outcome))deny('INVALID_CHEQUE_OUTCOME');
      if(outcome==='BANK_CLEARANCE_EVIDENCED'&&date(input.evidenceDate)<row.maturityDate)deny('PREMATURE_CHEQUE_CLEARANCE');
      row.status=outcome;row.clearanceEvidenceRef=ref;
      this.#record(c,'PDC_OUTCOME_EVIDENCED',row.id,requestId,{outcome,ref});
      return {...row,reconciledCashMinor:null,paymentPosted:false};
    });
  }
  addSds(context,requestId,input){
    return this.#write(context,'sds',requestId,input,c=>{
      const id=key(input?.sku,'PRODUCT')+':'+key(input.revision,'REVISION');
      const allowed=input.allowedStorageClasses;
      if(!Array.isArray(allowed)||!allowed.length||allowed.length>12||
        allowed.some(x=>typeof x!=='string'||!/^[A-Z0-9_-]{2,32}$/.test(x)))deny('INVALID_STORAGE_RULE');
      const row=this.#insert(this.#sds,c,id,{sku:input.sku,revision:input.revision,
        documentRef:key(input.documentRef,'SDS_DOCUMENT'),
        expiresOn:date(input.expiresOn),hazardClass:key(input.hazardClass,'HAZARD'),
        allowedStorageClasses:[...new Set(allowed)].sort()});
      this.#record(c,'SDS_VERSION_REGISTERED',id,requestId);return row;
    });
  }
  storageCheck(context,input){
    const c=ctx(context),s=this.#get(this.#sds,c,input?.sdsId);
    const at=date(input.asOf),storage=key(input.storageClass,'STORAGE_CLASS');
    const allowed=at<=s.expiresOn&&s.allowedStorageClasses.includes(storage);
    return {sdsId:s.id,revision:s.revision,at,storageClass:storage,allowedForDraftHandling:allowed,
      canReceive: false,canShip:false,
      blockers:[...(at>s.expiresOn?['SDS_EXPIRED']:[]),...(!s.allowedStorageClasses.includes(storage)?['INCOMPATIBLE_STORAGE']:[]),
        'SIGNED_JURISDICTION_AND_CANONICAL_INVENTORY_GATES_UNMET']};
  }
  quarantineReturn(context,requestId,input,tintEngine){
    return this.#write(context,'return',requestId,input,c=>{
      if(!tintEngine||typeof tintEngine.readTicket!=='function')deny('CANONICAL_TINT_SOURCE_REQUIRED');
      const tint=tintEngine.readTicket(context,key(input.sourceTicketId,'SOURCE_TICKET'));
      if(tint.status!=='QC_PASSED')deny('RETURN_SOURCE_NOT_QC_PASSED');
      const id=key(input.returnId,'RETURN');
      const row=this.#insert(this.#returns,c,id,{
        sourceTicketId:tint.id,sourceRecipeId:tint.recipeId,sourceOutputSku:tint.outputSku,
        reasonCode:key(input.reasonCode,'REASON'),evidenceRef:key(input.evidenceRef,'EVIDENCE'),
        state:'QUARANTINED',availableForSale:false,refundedMinor:null
      });this.#record(c,'RETURN_QUARANTINED',id,requestId);return row;
    });
  }
  proposeReturnDisposition(context,requestId,input){
    return this.#write(context,'disposition',requestId,input,c=>{
      const r=this.#get(this.#returns,c,input?.returnId);
      if(r.state!=='QUARANTINED')deny('RETURN_DISPOSITION_ALREADY_REQUESTED');
      if(!['RETINT_REVIEW','DISPOSAL_REVIEW'].includes(input.action))deny('INVALID_DISPOSITION');
      const ref=key(input.inspectionRef,'INSPECTION_EVIDENCE');
      r.state=input.action+'_PENDING';r.inspectionRef=ref;
      this.#record(c,'DISPOSITION_PROPOSED',r.id,requestId,{action:input.action,ref});return r;
    });
  }
  addSerial(context,requestId,input){
    return this.#write(context,'hardware-serial',requestId,input,c=>{
      const sku=key(input.sku,'SKU'),serial=key(input.serial,'SERIAL');
      const id=sku+':'+serial;
      const row=this.#insert(this.#hardware,c,id,{sku,serial,
        variant:key(input.variant,'VARIANT'),unit:key(input.unit,'UOM'),
        warrantyMonths:integer(input.warrantyMonths,'WARRANTY_MONTHS',0,120),
        saleEvidenceRef:null,saleDate:null,customerReference:null});
      this.#record(c,'HARDWARE_SERIAL_REGISTERED',id,requestId);return row;
    });
  }
  linkWarranty(context,requestId,input){
    return this.#write(context,'hardware-warranty',requestId,input,c=>{
      const serial=this.#get(this.#hardware,c,input?.hardwareId);
      const sale=ev(input.saleSnapshot,c,'completed-sale-line');
      if(serial.saleEvidenceRef!==null)deny('SERIAL_ALREADY_SOLD');
      if(sale.sku!==serial.sku||sale.variant!==serial.variant||sale.serial!==serial.serial||
        sale.status!=='POSTED')deny('SALE_SERIAL_MISMATCH');
      serial.saleEvidenceRef=key(sale.saleRef,'SALE_REF');
      serial.saleDate=date(sale.saleDate);
      serial.customerReference=key(sale.customerRef,'CUSTOMER_REF');
      this.#record(c,'SERIAL_SALE_EVIDENCE',serial.id,requestId,{saleRef:serial.saleEvidenceRef});
      return {serial:serial.id,saleDate:serial.saleDate,warrantyMonths:serial.warrantyMonths,
        sourceVersion:sale.version,authenticity:'SYNTHETIC_SNAPSHOT_NOT_PROVEN'};
    });
  }
  profitability(context,input){
    const c=ctx(context);
    const sales=ev(input?.sales,c,'sales-return-summary');
    const cost=ev(input?.cost,c,'certified-cost-summary');
    const rebates=ev(input?.rebates,c,'rebate-reconciliation');
    const credit=ev(input?.credit,c,'credit-summary');
    if(sales.currency!==cost.currency||sales.currency!==rebates.currency||sales.currency!==credit.currency)
      deny('REPORT_CURRENCY_MISMATCH');
    const grossSales=money(sales.grossMinor),returns=money(sales.returnsMinor);
    const outstanding=money(credit.outstandingMinor);
    const pending=money(rebates.pendingMinor),receivedEvidence=money(rebates.receivedEvidenceMinor);
    const costCertified=cost.certification==='CERTIFIED'&&cost.allFreightIncluded===true;
    const cogs=costCertified?money(cost.cogsMinor):null;
    if(returns>grossSales)deny('RETURNS_EXCEED_SALES');
    const netSales=grossSales-returns;
    const grossMargin=cogs===null?null:netSales-cogs;
    return {business:c.business,currency:sales.currency,
      netSalesMinor:netSales,costCertified,cogsMinor:cogs,grossMarginMinor:grossMargin,
      pendingRebatesExcludedFromProfitMinor:pending,receivedRebateEvidenceMinor:receivedEvidence,
      creditExposureMinor:outstanding,
      netProfitMinor:null,actualCashFlowMinor:null,reportStatus:costCertified?'GROSS_MARGIN_ONLY':'INCOMPLETE_COST_EVIDENCE',
      sources:{sales:sales.version,cost:cost.version,rebates:rebates.version,credit:credit.version},
      canPost:false};
  }
  report(context){
    const c=ctx(context),inScope=x=>x.tenant===c.tenant&&x.business===c.business;
    const count=m=>[...m.values()].filter(inScope).length;
    return {business:c.business,packCount:count(this.#packs),dealerCount:count(this.#dealers),
      schemeCount:count(this.#schemes),claimCount:count(this.#claims),chequeCount:count(this.#cheques),
      sdsCount:count(this.#sds),returnCount:count(this.#returns),serialCount:count(this.#hardware),
      availableCashMinor:null,actualInventoryQuantity:null};
  }
  audit(context){const c=ctx(context);return clone(this.#events.filter(x=>x.tenant===c.tenant&&x.business===c.business));}
}
