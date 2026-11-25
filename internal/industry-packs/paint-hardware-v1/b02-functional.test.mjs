// Ordinary synthetic functional regressions; not signed/staging/security acceptance.
import test from 'node:test';
import assert from 'node:assert/strict';
import {PaintDealerDraft} from './dealership.mjs';
import {createDemoServer} from './lab-server.mjs';

const ctx={mode:'synthetic-only',tenant:'T1',business:'PAINT1',actor:'owner'};
const snapshot=(type,fields)=>({source:'canonical-readonly',type,tenant:ctx.tenant,business:ctx.business,version:'V1',...fields});
const newScheme=()=>{
  const dealer=new PaintDealerDraft();
  dealer.addPrincipalScheme(ctx,'scheme-1',{schemeId:'S1',version:1,principalId:'P1',sku:'BASE1',validFrom:'2026-01-01',validTo:'2026-12-31',rateBps:1000,currency:'BDT'});
  return dealer;
};
const invoice=date=>snapshot('principal-purchase-invoice',{invoiceId:'INV1',date,sku:'BASE1',principalId:'P1',currency:'BDT',status:'APPROVED',returnStatus:'PARTIAL_RETURN',approvedMinor:100000,returnedMinor:20000});
const claim=(date,asOf='2026-05-02')=>({claimId:'CL1',schemeId:'S1:v1',invoiceSnapshot:invoice(date),asOf});

test('B02 principal invoice date is a real calendar day and cannot follow report as-of',()=>{
  const dealer=newScheme();
  for(const invalid of [undefined,'2026-02-30','2026-13-01','2026-5-1']){
    assert.throws(()=>dealer.previewScheme(ctx,claim(invalid)),{message:'INVALID_ISO_DATE'});
  }
  assert.throws(()=>dealer.previewScheme(ctx,claim('2026-05-03')),{message:'INVOICE_AFTER_AS_OF'});
  assert.throws(()=>dealer.previewScheme(ctx,claim('2026-05-01','2026-13-01')),{message:'INVALID_ISO_DATE'});
  assert.throws(()=>dealer.previewScheme(ctx,claim('2025-12-31')),{message:'SCHEME_EXPIRED_OR_NOT_STARTED'});
  for(const date of ['2026-01-01','2026-05-02','2026-12-31']){
    const result=dealer.previewScheme(ctx,claim(date,date));
    assert.equal(result.eligibleMinor,80000);
    assert.equal(result.estimatedRebateMinor,8000);
    assert.equal(result.earnedCertifiedMinor,null);
  }
});

test('B02 invalid purchase date does not create a claim; corrected claim succeeds',()=>{
  const dealer=newScheme(), before=dealer.audit(ctx);
  assert.throws(()=>dealer.submitClaim(ctx,'claim-1',claim(undefined)),{message:'INVALID_ISO_DATE'});
  assert.deepEqual(dealer.audit(ctx),before);
  assert.equal(dealer.report(ctx).claimCount,0);
  const result=dealer.submitClaim(ctx,'claim-1',claim('2026-05-01'));
  assert.equal(result.status,'SUBMITTED');
  assert.equal(result.estimatedMinor,8000);
  assert.equal(dealer.claimSummary(ctx,'CL1').postingAllowed,false);
});

const serialInput={sku:'DRILL',serial:'SER1',variant:'12MM',unit:'PCS',warrantyMonths:12};
const sale=(fields={})=>snapshot('completed-sale-line',{sku:'DRILL',serial:'SER1',variant:'12MM',status:'POSTED',saleRef:'SALE1',saleDate:'2026-08-01',customerRef:'C1',...fields});

test('B02 warranty linkage validates all evidence fields before updating serial',()=>{
  for(const fields of [{saleDate:'2026-02-30'},{saleDate:'2026-13-01'},{customerRef:''}]){
    const dealer=new PaintDealerDraft();
    dealer.addSerial(ctx,'serial-1',serialInput);
    const before=dealer.audit(ctx);
    assert.throws(()=>dealer.linkWarranty(ctx,'sale-1',{hardwareId:'DRILL:SER1',saleSnapshot:sale(fields)}),/INVALID_ISO_DATE|INVALID_CUSTOMER_REF/);
    assert.deepEqual(dealer.audit(ctx),before);
    const linked=dealer.linkWarranty(ctx,'sale-1',{hardwareId:'DRILL:SER1',saleSnapshot:sale()});
    assert.equal(linked.warrantyMonths,12);
    assert.equal(linked.saleDate,'2026-08-01');
    assert.equal(linked.authenticity,'SYNTHETIC_SNAPSHOT_NOT_PROVEN');
    assert.equal(dealer.audit(ctx).length,before.length+1);
  }
});

test('B02 ordinary loopback demo walkthrough retains nonposting quote and rebate preview',async t=>{
  const demo=createDemoServer({port:0}),port=await demo.listen();
  t.after(()=>demo.close());
  const url=`http://127.0.0.1:${port}`;
  const html=await (await fetch(url+'/')).text();
  const token=html.match(/name="demo-token" content="([a-f0-9]+)"/)[1];
  const step=async action=>{
    const response=await fetch(url+'/api/step',{method:'POST',headers:{'Content-Type':'application/json','X-Demo-Token':token},body:JSON.stringify({action})});
    assert.equal(response.status,200);
    return response.json();
  };
  assert.equal((await step('start')).ticket.status,'DRAFT');
  assert.equal((await step('mix')).ticket.status,'MIXED');
  assert.equal((await step('qc-fail')).ticket.status,'QC_FAILED');
  assert.equal((await step('rework')).ticket.status,'MIXED');
  const final=await step('qc-pass');
  assert.equal(final.ticket.status,'QC_PASSED');
  assert.equal(final.scheme.estimatedRebateMinor,8000);
  assert.equal(final.quote.canPost,false);
  assert.equal(final.quote.payableMinor,null);
  assert.equal(final.postingAllowed,false);
  assert.equal((await step('reset')).ticket,null);
});
