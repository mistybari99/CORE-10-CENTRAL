// Detail 272: ordinary synthetic QC workflow, not real instrument certification.
import test from 'node:test';
import assert from 'node:assert/strict';
import {PaintPackDraft} from './core.mjs';
import {createDemoServer} from './lab-server.mjs';

const actor=actor=>({mode:'synthetic-only',tenant:'T1',business:'PAINT1',actor});
const setup=()=>{
  const engine=new PaintPackDraft();
  const recipe=engine.addRecipe(actor('owner'),'recipe',{code:'SHADE',version:1,name:'Demo shade',baseSku:'BASE',outputSku:'SHADE1',qcMaxDE100:180,doseToleranceBps:200,pigments:[{sku:'RED',ulPerL:1000}]});
  engine.openTicket(actor('operator'),'open',{ticketId:'T1',recipeId:recipe.id,baseML:1000});
  engine.mix(actor('mixer'),'mix1',{ticketId:'T1',readings:[{sku:'RED',actualUL:1000}]});
  return {engine,recipe};
};
const measure=(overrides={})=>({ticketId:'T1',deltaE100:180,evidenceRef:'QC1',method:'SPECTRO',instrumentRef:'DEVICE1',calibrated:true,...overrides});

test('B02 QC requires stated method, instrument and positive calibration fixture before review',()=>{
  for(const changes of [{method:undefined},{method:''},{instrumentRef:undefined},{instrumentRef:''},{calibrated:false},{calibrated:undefined},{calibrated:'true'}]){
    const {engine}=setup();
    const before=engine.readTicket(actor('checker'),'T1'),audit=engine.audit(actor('checker'));
    assert.throws(()=>engine.inspect(actor('checker'),'qc1',measure(changes)),/INVALID_QC_METHOD|INVALID_QC_INSTRUMENT|QC_CALIBRATION_EVIDENCE_REQUIRED/);
    assert.deepEqual(engine.readTicket(actor('checker'),'T1'),before);
    assert.deepEqual(engine.audit(actor('checker')),audit);
    const corrected=engine.inspect(actor('checker'),'qc1',measure());
    assert.equal(corrected.status,'QC_PASSED');
  }
});

test('B02 QC stores method, actual value, version-bound tolerance and mix round across failed/rework/pass history',()=>{
  const {engine,recipe}=setup();
  const check1=engine.inspect(actor('checker'),'qc1',measure({deltaE100:181}));
  assert.equal(check1.status,'QC_FAILED');
  const failed=check1.qcChecks[0];
  const expected={round:1,mixRound:1,checker:'checker',recipeId:recipe.id,recipeVersion:1,method:'SPECTRO',instrumentRef:'DEVICE1',calibrated:true,calibrationStatus:'SYNTHETIC_ASSERTION_ONLY',deltaE100:181,qcMaxDE100:180,evidenceRef:'QC1',pass:false};
  assert.deepEqual(failed,expected);
  engine.addRecipe(actor('owner'),'recipe2',{code:'SHADE',version:2,name:'Demo shade new version',baseSku:'BASE',outputSku:'SHADE1',qcMaxDE100:200,doseToleranceBps:200,pigments:[{sku:'RED',ulPerL:1000}]});
  engine.mix(actor('mixer'),'mix2',{ticketId:'T1',readings:[{sku:'RED',actualUL:1000}]});
  const result=engine.inspect(actor('checker'),'qc2',measure({evidenceRef:'QC2'}));
  assert.equal(result.status,'QC_PASSED');
  assert.deepEqual(result.qcChecks,[expected,{...expected,round:2,mixRound:2,deltaE100:180,evidenceRef:'QC2',pass:true}]);
  const events=engine.audit(actor('checker')).filter(x=>x.op==='QC_RECORDED');
  assert.deepEqual(events.map(x=>x.detail),result.qcChecks);
  const proposal=engine.canonicalIntent(actor('checker'),'T1');
  assert.deepEqual(proposal.qcEvidence,result.qcChecks[1]);
  assert.equal(proposal.canPost,false);
  assert.equal(proposal.canSubmit,false);
});

test('B02 QC ordinary demo exposes measurement and threshold history through rework',async t=>{
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
  await step('start');await step('mix');
  const fail=await step('qc-fail');
  assert.equal(fail.ticket.qcChecks[0].qcMaxDE100,180);
  assert.equal(fail.ticket.qcChecks[0].method,'SPECTRO');
  assert.equal(fail.ticket.qcChecks[0].calibrationStatus,'SYNTHETIC_ASSERTION_ONLY');
  await step('rework');const final=await step('qc-pass');
  assert.deepEqual(final.ticket.qcChecks.map(x=>[x.mixRound,x.deltaE100,x.qcMaxDE100,x.pass]),[[1,230,180,false],[2,120,180,true]]);
  assert.equal(final.quote.canPost,false);
  assert.equal(final.postingAllowed,false);
  assert.match(html,/id="qc-history"/);
  assert.match(html,/Synthetic calibration assertion/);
});
