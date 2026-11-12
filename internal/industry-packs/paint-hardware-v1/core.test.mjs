
import test from 'node:test';
import assert from 'node:assert/strict';
import {PaintPackDraft,BUILD05_MODE} from './core.mjs';
const actor=(actor='worker',business='paintA',tenant='tenantA')=>({mode:'synthetic-only',actor,business,tenant});
const recipe=()=>({code:'SHADE01',version:1,name:'Synthetic Brown',baseSku:'BASE1',outputSku:'SHADE1',
  qcMaxDE100:180,doseToleranceBps:200,pigments:[{sku:'RED',ulPerL:16000},{sku:'BLACK',ulPerL:2000}]});
const setup=()=>{
  const e=new PaintPackDraft(),r=e.addRecipe(actor('owner'),'r1',recipe());
  const t=e.openTicket(actor(),'t1',{ticketId:'ticket01',recipeId:r.id,baseML:2500});
  return {e,r,t};
};
const mix={ticketId:'ticket01',readings:[{sku:'BLACK',actualUL:5000},{sku:'RED',actualUL:40000}]};
const inspect=(n=100,ref='QC1')=>({ticketId:'ticket01',deltaE100:n,evidenceRef:ref});
test('synthetic-only execution; no impersonation of real signed sessions',()=>{
  const {e}=setup();assert.equal(BUILD05_MODE,'SYNTHETIC_NON_POSTING_ONLY');
  assert.throws(()=>e.summary({...actor(),mode:'production'}),/REAL_SIGNED_AUTH_NOT_CONNECTED/);
  assert.throws(()=>e.summary({business:'paintA',tenant:'tenantA',actor:'staff'}),/REAL_SIGNED_AUTH_NOT_CONNECTED/);
});
test('recipe version is immutable and doses scale exactly for 2.5 litres',()=>{
  const {e,r,t}=setup();assert.deepEqual(t.doses.map(x=>[x.sku,x.expectedUL]),[['BLACK',5000],['RED',40000]]);
  assert.throws(()=>e.addRecipe(actor('owner'),'r2',recipe()),/IMMUTABLE_RECIPE_VERSION/);
  const newer=e.addRecipe(actor('owner'),'r3',{...recipe(),version:2});assert.notEqual(newer.id,r.id);
});
test('independent QC: pass creates a non-posting canonical proposal',()=>{
  const {e}=setup();
  assert.equal(e.mix(actor('mixer'),'mix1',mix).status,'MIXED');
  assert.throws(()=>e.inspect(actor('mixer'),'qc-self',inspect()),/INDEPENDENT_QC_CHECKER_REQUIRED/);
  assert.equal(e.inspect(actor('checker'),'qc1',inspect()).status,'QC_PASSED');
  const proposal=e.canonicalIntent(actor('owner'),'ticket01');
  assert.equal(proposal.canPost,false);assert.equal(proposal.stockChanged,false);
  assert.equal(proposal.ledgerChanged,false);assert.ok(proposal.requires.includes('balanced_journal'));
});
test('QC failure, block quote, rework and independent re-inspection',()=>{
  const {e}=setup();e.mix(actor('mixer'),'mix1',mix);
  assert.equal(e.inspect(actor('checker'),'qc1',inspect(200)).status,'QC_FAILED');
  assert.throws(()=>e.canonicalIntent(actor(),'ticket01'),/QC_PASS_REQUIRED/);
  e.mix(actor('mixer'),'mix2',mix);
  assert.equal(e.inspect(actor('checker'),'qc2',inspect(150,'QC2')).status,'QC_PASSED');
  assert.equal(e.summary(actor()).qcRuns,2);
});
test('other business and tenant cannot read or use same recipe',()=>{
  const {e,r}=setup();
  for(const ctx of [actor('bad','paintB'),actor('bad','paintA','tenantB')]){
    assert.throws(()=>e.readTicket(ctx,'ticket01'),/NOT_FOUND_IN_SCOPE/);
    assert.throws(()=>e.openTicket(ctx,'ab',{ticketId:'new',recipeId:r.id,baseML:1000}),/NOT_FOUND_IN_SCOPE/);
    assert.deepEqual(e.listTickets(ctx),[]);assert.deepEqual(e.audit(ctx),[]);
  }
});
test('idempotent receipts; changed replay payload fails without event change',()=>{
  const {e}=setup(),start=e.audit(actor()).length;
  const original=e.mix(actor('mixer'),'mix1',mix);
  assert.deepEqual(e.mix(actor('mixer'),'mix1',mix),original);
  assert.equal(e.audit(actor()).length,start+1);
  assert.throws(()=>e.mix(actor('mixer'),'mix1',{...mix,readings:[{sku:'BLACK',actualUL:5000},{sku:'RED',actualUL:40001}]}),/IDEMPOTENCY_CONFLICT/);
  assert.equal(e.audit(actor()).length,start+1);
});
test('incomplete mix or overdose fail atomically',()=>{
  const {e}=setup();
  assert.throws(()=>e.mix(actor(),'bad1',{ticketId:'ticket01',readings:[{sku:'RED',actualUL:40000}]}),/INCOMPLETE_READINGS/);
  assert.throws(()=>e.mix(actor(),'bad2',{ticketId:'ticket01',readings:[{sku:'RED',actualUL:50000},{sku:'BLACK',actualUL:5000}]}),/DOSAGE_OUT_OF_TOLERANCE/);
  assert.equal(e.readTicket(actor(),'ticket01').status,'DRAFT');
});
test('quoted paisa rounding, rebate and unknown tax never produce payable',()=>{
  const {e}=setup();e.mix(actor('mix'),'mix1',mix);e.inspect(actor('qc'),'qc1',inspect());
  const price={source:'canonical-readonly',version:'P07',currency:'BDT',unitMinor:19999,tintFeeMinor:2500,rebateBps:1250};
  const q=e.quote(actor(),{ticketId:'ticket01',price});
  assert.deepEqual([q.paintMinor,q.grossMinor,q.rebateMinor,q.netBeforeUnknownTaxMinor],[49998,52498,6562,45936]);
  assert.equal(q.payableMinor,null);assert.equal(q.stockAvailability,'UNVERIFIED');assert.equal(q.canPost,false);
  assert.throws(()=>e.quote(actor(),{ticketId:'ticket01',price:{...price,source:'hand-entered'}}),/VERIFIED_PRICE_SOURCE_REQUIRED/);
  assert.throws(()=>e.quote(actor(),{ticketId:'ticket01',price:{...price,rebateBps:6000}}),/INVALID_REBATE_BPS/);
});
test('duplicate formula pigments, oversized tint and invalid IDs rejected',()=>{
  const e=new PaintPackDraft();
  assert.throws(()=>e.addRecipe(actor(),'x',{...recipe(),pigments:[{sku:'RED',ulPerL:100},{sku:'RED',ulPerL:200}]}),/DUPLICATE_PIGMENT/);
  assert.throws(()=>e.addRecipe(actor(),'y',{...recipe(),pigments:[{sku:'RED',ulPerL:200000},{sku:'BLK',ulPerL:100000}]}),/TINT_EXCEEDS_25_PERCENT/);
  assert.throws(()=>e.addRecipe(actor(),'z',{...recipe(),baseSku:'../private'}),/INVALID_BASE/);
});
test('defensive reads do not mutate ticket, audit or business report',()=>{
  const {e}=setup();const t=e.readTicket(actor(),'ticket01');t.status='QC_PASSED';
  const audit=e.audit(actor());audit[0].detail.version=999;
  assert.equal(e.readTicket(actor(),'ticket01').status,'DRAFT');
  assert.equal(e.audit(actor())[0].detail.version,1);
  assert.equal(e.summary(actor()).actualSalesMinor,null);
});

test('same ticket id in independent businesses does not collide',()=>{
  const {e,r}=setup();
  const rb=e.addRecipe(actor('boss','paintB'),'recipe-b',recipe());
  e.openTicket(actor('staff','paintB'),'ticket-b',{ticketId:'ticket01',recipeId:rb.id,baseML:1000});
  assert.equal(e.readTicket(actor(),'ticket01').baseML,2500);
  assert.equal(e.readTicket(actor('staff','paintB'),'ticket01').baseML,1000);
  assert.equal(e.listTickets(actor('staff','paintB')).length,1);
  assert.throws(()=>e.openTicket(actor(),'again',{ticketId:'ticket01',recipeId:r.id,baseML:1000}),/DUPLICATE_TICKET_ID/);
});
