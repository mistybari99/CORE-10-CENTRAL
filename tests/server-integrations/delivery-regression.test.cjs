'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {runOnce} = require('../../server/integrations/worker.js');
const {createRegistry} = require('../../server/integrations/adapters.js');
function fixture(mode, rows, registry = createRegistry({}), terminal = 'failed') {
  const reports = []; let claims=0, secrets=0, sends=0;
  const args = {account:{id:1,mode,provider_code:'sms',family:'messaging'}, registry,
    db:{async claim(){claims++;return rows;},async report(id,ok,transient,ref,error){reports.push({id,ok,transient,ref,error});return ok?(rows.find(r=>r.id===id).is_dry_run?'dry_run_logged':'sent'):terminal;}},
    async resolveSecret(){secrets++;throw Error('test-secret');},async http(){sends++;throw Error('no network');}};
  return {args,reports,counts:()=>[claims,secrets,sends]};
}
test('unimplemented live provider cannot record a successful delivery',async()=>{
  const f=fixture('live',[{id:1,is_dry_run:false}]); const result=await runOnce(f.args);
  assert.equal(result.sent,0);assert.equal(result.failed,1);assert.equal(f.reports[0].error,'live_adapter_unavailable');assert.equal(f.reports[0].ref,null);assert.deepEqual(f.counts(),[1,0,0]);
});
test('registry ignores inherited keys',()=>{const r=createRegistry({});for(const k of ['constructor','toString','__proto__']) assert.equal(r.get(k,'messaging').kind,'dry_run');});
test('invalid mode never claims',async()=>{const f=fixture('unexpected',[{id:1,is_dry_run:false}]);await assert.rejects(()=>runOnce(f.args),/integration_mode_invalid/);assert.deepEqual(f.counts(),[0,0,0]);});
test('dry-run mismatch cannot invoke adapter or resolve secret',async()=>{
  let invoked=0;const reg=createRegistry({sms:{kind:'http',async send(){invoked++;return {ok:true};}}});
  const f=fixture('live',[{id:1,is_dry_run:true},{id:2}],reg);const r=await runOnce(f.args);
  assert.equal(r.failed,2);assert.equal(invoked,0);assert.deepEqual(f.counts(),[1,0,0]);assert.ok(f.reports.every(x=>x.error==='job_mode_mismatch'));
});
test('secret failure counts exhausted retry as failed, not requeued',async()=>{
  const f=fixture('live',[{id:1,is_dry_run:false}],createRegistry({sms:{kind:'http',async send(){throw Error('must not send');}}}));const r=await runOnce(f.args);
  assert.equal(r.failed,1);assert.equal(r.requeued,0);assert.equal(f.reports[0].error,'secret_unavailable');assert.equal(f.reports[0].transient,true);assert.deepEqual(f.counts(),[1,1,0]);
});
test('known dry-run remains successful without secrets or network',async()=>{
  const f=fixture('dry_run',[{id:1,is_dry_run:true}]);const r=await runOnce(f.args);assert.equal(r.dry_run_logged,1);assert.equal(r.sent,0);assert.deepEqual(f.counts(),[1,0,0]);
});
