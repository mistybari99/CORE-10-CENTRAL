
import test from 'node:test';
import assert from 'node:assert/strict';
import {PaintDealerDraft} from './dealership.mjs';
import {PaintPackDraft} from './core.mjs';
const a=(actor='owner',business='paintA',tenant='tenantA')=>({actor,business,tenant,mode:'synthetic-only'});
const evidence=(type,extras={},business='paintA',tenant='tenantA')=>({source:'canonical-readonly',type,tenant,business,version:'v7',...extras});
const f=()=>new PaintDealerDraft();
const scheme=()=>({schemeId:'S1',version:1,principalId:'P1',sku:'BASE-W',validFrom:'2026-01-01',validTo:'2026-12-31',rateBps:1000,currency:'BDT'});
const invoice=()=>evidence('principal-purchase-invoice',{date:'2026-05-01',principalId:'P1',sku:'BASE-W',
  invoiceId:'IN1',status:'APPROVED',returnStatus:'PARTIAL_RETURN',currency:'BDT',approvedMinor:100000,returnedMinor:20000});
test('4-litre sealed pack preserves litres; refuses KG or opened containers',()=>{
  const e=f(),ctx=a(),pack=e.addPack(ctx,'pack1',{packId:'PK4',sku:'SHADE-W',uom:'L',capacityML:4000});
  assert.equal(pack.capacityML,4000);
  assert.throws(()=>e.addPack(ctx,'wrong',{packId:'PKKG',sku:'SHADE-W',uom:'KG',capacityML:4000}),/SEALED_LITRE/);
  assert.throws(()=>e.addPack(ctx,'opened',{packId:'OPEN',sku:'SHADE-W',uom:'L',capacityML:4000,opened:true}),/SEALED_LITRE/);
  const q=e.packPrice(ctx,{packId:'PK4',priceSnapshot:evidence('approved-pack-price',
    {packId:'PK4',sku:'SHADE-W',currency:'BDT',priceMinor:120000})});
  assert.equal(q.equivalentPerLMinor,30000);assert.equal(q.marginMinor,null);
});
test('dealer credit exposure includes approved receivables and pending orders',()=>{
  const e=f(),ctx=a();
  e.addDealer(ctx,'dealer1',{dealerId:'DL1',status:'ACTIVE',currency:'BDT',creditLimitMinor:200000,termsVersion:'T1'});
  const exposure=evidence('receivables-exposure',
    {dealerId:'DL1',currency:'BDT',status:'VERIFIED',termsVersion:'T1',asOf:'2026-11-12',
     approvedReceivablesMinor:150000,pendingOrdersMinor:30000});
  assert.equal(e.creditCheck(ctx,{dealerId:'DL1',exposureSnapshot:exposure,asOf:'2026-11-12',requestedMinor:20000}).withinLimit,true);
  const over=e.creditCheck(ctx,{dealerId:'DL1',exposureSnapshot:exposure,asOf:'2026-11-12',requestedMinor:30000});
  assert.equal(over.withinLimit,false);assert.equal(over.canReleaseOrder,false);
  assert.throws(()=>e.creditCheck(ctx,{dealerId:'DL1',exposureSnapshot:{...exposure,asOf:'2026-11-11'},asOf:'2026-11-12',requestedMinor:100}),/STALE_OR_UNAUTHORIZED/);
});
test('principal scheme estimated eligible net purchases only; returned or expired denied',()=>{
  const e=f(),ctx=a();
  e.addPrincipalScheme(ctx,'sch1',scheme());
  const estimate=e.previewScheme(ctx,{schemeId:'S1:v1',invoiceSnapshot:invoice(),asOf:'2026-05-02'});
  assert.equal(estimate.eligibleMinor,80000);assert.equal(estimate.estimatedRebateMinor,8000);
  assert.equal(estimate.earnedCertifiedMinor,null);
  assert.throws(()=>e.previewScheme(ctx,{schemeId:'S1:v1',invoiceSnapshot:{...invoice(),returnStatus:'FULL_RETURN'},asOf:'2026-05-02'}),/INELIGIBLE_PURCHASE/);
  assert.throws(()=>e.previewScheme(ctx,{schemeId:'S1:v1',invoiceSnapshot:invoice(),asOf:'2027-01-01'}),/SCHEME_EXPIRED/);
});
test('claim submitted, independently approved, partial evidence then full evidence; no bank ledger',()=>{
  const e=f(),ctx=a('claimant');e.addPrincipalScheme(ctx,'sch1',scheme());
  const create={claimId:'CL1',schemeId:'S1:v1',invoiceSnapshot:invoice(),asOf:'2026-05-02'};
  assert.equal(e.submitClaim(ctx,'submit1',create).status,'SUBMITTED');
  assert.throws(()=>e.submitClaim(ctx,'submit2',{...create,claimId:'CL2'}),/DUPLICATE_INVOICE_CLAIM/);
  assert.throws(()=>e.reviewClaim(ctx,'self',{claimId:'CL1',approvedMinor:6000,approvalRef:'APP1'}),/INDEPENDENT_REVIEW/);
  assert.throws(()=>e.reviewClaim(a('checker'),'too-high',{claimId:'CL1',approvedMinor:9000,approvalRef:'APP1'}),/EXCEEDS_ESTIMATE/);
  e.reviewClaim(a('checker'),'approve',{claimId:'CL1',approvedMinor:6000,approvalRef:'APP1'});
  let r=e.recordClaimReceipt(a('accounting'),'recv1',{claimId:'CL1',amountMinor:2000,evidenceRef:'BANK1'});
  assert.equal(r.status,'PARTIAL_RECEIPT_EVIDENCED');
  assert.throws(()=>e.recordClaimReceipt(a('accounting'),'recv2',{claimId:'CL1',amountMinor:5000,evidenceRef:'BANK2'}),/EXCEEDS_APPROVAL/);
  r=e.recordClaimReceipt(a('accounting'),'recv3',{claimId:'CL1',amountMinor:4000,evidenceRef:'BANK2'});
  assert.equal(r.status,'FULL_RECEIPT_EVIDENCED');
  const summary=e.claimSummary(a(),'CL1');
  assert.equal(summary.pendingMinor,0);assert.equal(summary.reconciledBankMinor,null);assert.equal(summary.postingAllowed,false);
});
test('postdated cheque is instrument only; premature clearance blocked; bounced not cash',()=>{
  const e=f(),ctx=a();
  const cheque=e.addCheque(ctx,'pdc1',{bankCode:'BANK1',issuerId:'DL1',chequeNumber:'12345',maturityDate:'2026-11-25',currency:'BDT',amountMinor:150000});
  assert.equal(cheque.status,'INSTRUMENT_HELD');
  assert.throws(()=>e.chequeOutcome(ctx,'early',{chequeId:cheque.id,outcome:'BANK_CLEARANCE_EVIDENCED',bankEvidenceRef:'BR1',evidenceDate:'2026-11-23'}),/PREMATURE_CHEQUE/);
  assert.equal(e.chequeOutcome(ctx,'bounce',{chequeId:cheque.id,outcome:'BOUNCED',bankEvidenceRef:'BR2'}).paymentPosted,false);
  assert.throws(()=>e.addCheque(ctx,'pdc2',{bankCode:'BANK1',issuerId:'DL1',chequeNumber:'12345',maturityDate:'2026-12-01',currency:'BDT',amountMinor:150000}),/IMMUTABLE_OR_DUPLICATE/);
});
test('SDS expiry and incompatible storage block handling, never authorize shipment',()=>{
  const e=f(),ctx=a();
  const s=e.addSds(ctx,'s1',{sku:'CHEM-A',revision:'R1',documentRef:'SDS001',expiresOn:'2026-11-30',hazardClass:'FLAMMABLE',allowedStorageClasses:['SAFE-FLAM']});
  const good=e.storageCheck(ctx,{sdsId:s.id,asOf:'2026-11-12',storageClass:'SAFE-FLAM'});
  assert.equal(good.allowedForDraftHandling,true);assert.equal(good.canShip,false);
  const wrong=e.storageCheck(ctx,{sdsId:s.id,asOf:'2026-11-12',storageClass:'FOOD-STORE'});
  assert.deepEqual(wrong.blockers.slice(0,1),['INCOMPATIBLE_STORAGE']);
  assert.ok(e.storageCheck(ctx,{sdsId:s.id,asOf:'2026-12-01',storageClass:'SAFE-FLAM'}).blockers.includes('SDS_EXPIRED'));
});
test('returned tint preserves origin genealogy and stays quarantined, no refund',()=>{
  const e=f(),tint=new PaintPackDraft(),ctx=a();
  const r=tint.addRecipe(ctx,'t-r',{code:'BRN',version:1,name:'Brown',baseSku:'BASE',outputSku:'OUT',
    qcMaxDE100:150,doseToleranceBps:300,pigments:[{sku:'RED',ulPerL:1000}]});
  tint.openTicket(ctx,'t-o',{ticketId:'T100',recipeId:r.id,baseML:1000});
  tint.mix(a('mixer'),'t-m',{ticketId:'T100',readings:[{sku:'RED',actualUL:1000}]});
  tint.inspect(a('checker'),'t-q',{ticketId:'T100',deltaE100:100,evidenceRef:'QC100'});
  const ret=e.quarantineReturn(ctx,'ret1',{returnId:'RT1',sourceTicketId:'T100',reasonCode:'COLOR_DIFF',evidenceRef:'EV01'},tint);
  assert.equal(ret.state,'QUARANTINED');assert.equal(ret.refundedMinor,null);assert.equal(ret.availableForSale,false);
  assert.equal(e.proposeReturnDisposition(ctx,'disp',{returnId:'RT1',action:'RETINT_REVIEW',inspectionRef:'INSP01'}).state,'RETINT_REVIEW_PENDING');
  assert.throws(()=>e.proposeReturnDisposition(ctx,'again',{returnId:'RT1',action:'DISPOSAL_REVIEW',inspectionRef:'INSP02'}),/ALREADY_REQUESTED/);
});
test('hardware serial uniquely matches variant and sold-customer source',()=>{
  const e=f(),ctx=a();
  e.addSerial(ctx,'serial1',{sku:'DRILL',serial:'SER01',variant:'V12MM',unit:'PCS',warrantyMonths:12});
  assert.throws(()=>e.addSerial(ctx,'dup',{sku:'DRILL',serial:'SER01',variant:'V15MM',unit:'PCS',warrantyMonths:12}),/IMMUTABLE_OR_DUPLICATE/);
  assert.throws(()=>e.linkWarranty(ctx,'wrong',{hardwareId:'DRILL:SER01',saleSnapshot:evidence('completed-sale-line',
    {sku:'DRILL',serial:'SER01',variant:'V15MM',status:'POSTED',saleRef:'SALE1',saleDate:'2026-08-01',customerRef:'C1'})}),/SALE_SERIAL_MISMATCH/);
  const ok=e.linkWarranty(ctx,'sale',{hardwareId:'DRILL:SER01',saleSnapshot:evidence('completed-sale-line',
    {sku:'DRILL',serial:'SER01',variant:'V12MM',status:'POSTED',saleRef:'SALE1',saleDate:'2026-08-01',customerRef:'C1'})});
  assert.equal(ok.warrantyMonths,12);assert.match(ok.authenticity,/SYNTHETIC/);
});
test('profit report excludes pending rebates and uncertified costs, no net profit',()=>{
  const e=f(),ctx=a();
  const snap={
    sales:evidence('sales-return-summary',{currency:'BDT',grossMinor:100000,returnsMinor:10000}),
    cost:evidence('certified-cost-summary',{currency:'BDT',certification:'UNVERIFIED',allFreightIncluded:false,cogsMinor:45000}),
    rebates:evidence('rebate-reconciliation',{currency:'BDT',pendingMinor:20000,receivedEvidenceMinor:5000}),
    credit:evidence('credit-summary',{currency:'BDT',outstandingMinor:30000})
  };
  let r=e.profitability(ctx,snap);assert.equal(r.grossMarginMinor,null);assert.equal(r.pendingRebatesExcludedFromProfitMinor,20000);
  assert.equal(r.netProfitMinor,null);assert.equal(r.actualCashFlowMinor,null);
  r=e.profitability(ctx,{...snap,cost:{...snap.cost,certification:'CERTIFIED',allFreightIncluded:true}});
  assert.equal(r.grossMarginMinor,45000);assert.equal(r.netProfitMinor,null);
  assert.throws(()=>e.profitability(ctx,{...snap,credit:{...snap.credit,currency:'USD'}}),/REPORT_CURRENCY_MISMATCH/);
});
test('cross-business/tenant snapshot and state isolation and independent same IDs',()=>{
  const e=f();
  e.addDealer(a('owner','paintA'),'dA',{dealerId:'DL1',status:'ACTIVE',currency:'BDT',creditLimitMinor:1000,termsVersion:'T1'});
  e.addDealer(a('owner','paintB'),'dB',{dealerId:'DL1',status:'ACTIVE',currency:'BDT',creditLimitMinor:5000,termsVersion:'T1'});
  assert.equal(e.report(a('viewer','paintB')).dealerCount,1);
  assert.equal(e.report(a('viewer','paintA')).dealerCount,1);
  assert.equal(e.report(a('viewer','paintA','tenantB')).dealerCount,0);
  assert.throws(()=>e.creditCheck(a('other','paintB'),{dealerId:'DL1',asOf:'2026-11-12',requestedMinor:1,
    exposureSnapshot:evidence('receivables-exposure',{status:'VERIFIED'},'paintA')}),/SCOPED_CANONICAL_SNAPSHOT_REQUIRED/);
});
test('request replay stable, changed idempotency payload blocked, audit immutable to caller',()=>{
  const e=f(),ctx=a(),input={packId:'P1',sku:'BASE1',uom:'L',capacityML:4000};
  const first=e.addPack(ctx,'r1',input);
  assert.deepEqual(e.addPack(ctx,'r1',input),first);
  assert.throws(()=>e.addPack(ctx,'r1',{...input,capacityML:1000}),/IDEMPOTENCY_CONFLICT/);
  const audit=e.audit(ctx);audit[0].detail.fake=true;
  assert.equal(e.audit(ctx)[0].detail.fake,undefined);
  assert.throws(()=>e.report({actor:'hacker',business:'paintA',tenant:'tenantA'}),/SIGNED_BACKEND_AUTH_NOT_CONNECTED/);
});
