// Decision Book 279/281: synthetic, nonposting functional evidence only.
import test from 'node:test';
import assert from 'node:assert/strict';
import {PaintPackDraft} from './core.mjs';
import {PaintDealerDraft} from './dealership.mjs';
const a=(actor='owner')=>({mode:'synthetic-only',tenant:'T1',business:'PAINT1',actor});
const qc=(deltaE100,evidenceRef)=>({ticketId:'T1',deltaE100,evidenceRef,method:'SPECTRO',instrumentRef:'DEVICE1',calibrated:true});
function tintFixture(){
  const t=new PaintPackDraft();
  const r=t.addRecipe(a(),'recipe',{code:'SHADE',version:1,name:'Demo shade',baseSku:'BASE',outputSku:'SHADE1',qcMaxDE100:180,doseToleranceBps:200,pigments:[{sku:'RED',ulPerL:1000}]});
  t.openTicket(a(),'open',{ticketId:'T1',recipeId:r.id,baseML:1000});
  t.mix(a('mixer'),'mix1',{ticketId:'T1',readings:[{sku:'RED',actualUL:1000}]});
  t.inspect(a('checker'),'qc1',qc(181,'QC1'));
  t.mix(a('mixer'),'mix2',{ticketId:'T1',readings:[{sku:'RED',actualUL:1000}]});
  t.inspect(a('checker'),'qc2',qc(180,'QC2'));
  return t;
}
test('B02 return keeps original recipe version and complete mix and QC genealogy through disposition',()=>{
  const t=tintFixture(),d=new PaintDealerDraft(),origin=t.readTicket(a(),'T1');
  const ret=d.quarantineReturn(a(),'return1',{returnId:'R1',sourceTicketId:'T1',reasonCode:'COLOR_DIFF',evidenceRef:'EV1'},t);
  assert.deepEqual(ret.sourceGenealogy,{recipeVersion:origin.recipeVersion,baseSku:origin.baseSku,baseML:origin.baseML,mixes:origin.mixes,qcChecks:origin.qcChecks});
  const disposed=d.proposeReturnDisposition(a('reviewer'),'disp1',{returnId:'R1',action:'DISPOSAL_REVIEW',inspectionRef:'INSP1'});
  assert.deepEqual(disposed.sourceGenealogy,ret.sourceGenealogy);
  assert.equal(disposed.availableForSale,false);assert.equal(disposed.refundedMinor,null);
  assert.deepEqual(d.audit(a()).find(x=>x.op==='RETURN_QUARANTINED').detail,{sourceTicketId:'T1',sourceRecipeId:origin.recipeId,sourceRecipeVersion:1,sourceQcEvidenceRef:'QC2',reasonCode:'COLOR_DIFF',evidenceRef:'EV1'});
});
const ev=(type,fields)=>({source:'canonical-readonly',type,tenant:'T1',business:'PAINT1',version:'v1',currency:'BDT',...fields});
const report=()=>({sales:ev('sales-return-summary',{grossMinor:100000,returnsMinor:10000}),cost:ev('certified-cost-summary',{certification:'CERTIFIED',allFreightIncluded:true,cogsMinor:45000}),rebates:ev('rebate-reconciliation',{pendingMinor:20000,receivedEvidenceMinor:5000}),credit:ev('credit-summary',{outstandingMinor:30000})});
test('B02 profitability explicitly reconciles gross sales, returns and net sales without adding rebates',()=>{
  const d=new PaintDealerDraft(),r=d.profitability(a(),report());
  assert.equal(r.grossSalesMinor,100000);assert.equal(r.salesReturnsMinor,10000);
  assert.equal(r.netSalesMinor,r.grossSalesMinor-r.salesReturnsMinor);
  assert.equal(r.grossMarginMinor,r.netSalesMinor-r.cogsMinor);
  assert.equal(r.pendingRebatesExcludedFromProfitMinor,20000);assert.equal(r.receivedRebateEvidenceMinor,5000);
  assert.deepEqual(r.costEvidenceBlockers,[]);assert.equal(r.authenticity,'SYNTHETIC_SNAPSHOT_NOT_PROVEN');
  assert.equal(r.netProfitMinor,null);assert.equal(r.actualCashFlowMinor,null);assert.equal(r.canPost,false);
});
test('B02 profitability explains incomplete freight and cost certification separately',()=>{
  const d=new PaintDealerDraft(),s=report();
  for(const [cost,blockers] of [[{...s.cost,allFreightIncluded:false},['FREIGHT_NOT_CONFIRMED']],[{...s.cost,certification:'UNVERIFIED'},['COST_NOT_CERTIFIED']],[{...s.cost,certification:'UNVERIFIED',allFreightIncluded:false},['COST_NOT_CERTIFIED','FREIGHT_NOT_CONFIRMED']]]){
    const r=d.profitability(a(),{...s,cost});assert.deepEqual(r.costEvidenceBlockers,blockers);assert.equal(r.cogsMinor,null);assert.equal(r.grossMarginMinor,null);assert.equal(r.reportStatus,'INCOMPLETE_COST_EVIDENCE');
  }
});
