import test from 'node:test';
import assert from 'node:assert/strict';
import {manufacturingClient} from '../../modules/manufacturing/client.mjs';
test('signed context is required and command args cannot replace its scope', async()=>{
 assert.throws(()=>manufacturingClient(()=>{},{}),/SIGNED_CONTEXT/);
 let got;
 const c=manufacturingClient(async(n,a)=>{got=a;return {data:{status:'NOT_CONNECTED'}};},{tenant_id:1,business_id:2,site_id:3});
 assert.equal((await c.call('mfg_request_handoff_v1',{p_business:999,p_site:999})).status,'NOT_CONNECTED');
 assert.equal(got.p_business,2);assert.equal(got.p_site,3);
 await assert.rejects(c.call('post_stock_event'),/RPC_NOT_ALLOWED/);
});
test('context disposal invalidates in-flight responses and later calls', async()=>{
 let resolve;
 const c=manufacturingClient(()=>new Promise(r=>resolve=r),{tenant_id:1,business_id:2,site_id:3});
 const pending=c.call('mfg_inspect_v1');c.close();resolve({data:{recipes:['foreign stale data']}});
 await assert.rejects(pending,/CONTEXT_CLOSED/);await assert.rejects(c.call('mfg_inspect_v1'),/CONTEXT_CLOSED/);
});
test('RPC permission errors remain visible',async()=>{
 const c=manufacturingClient(async()=>({error:{message:'MFG_SCOPE_DENIED'}}),{tenant_id:1,business_id:2,site_id:3});
 await assert.rejects(c.call('mfg_inspect_v1'),/MFG_SCOPE_DENIED/);
});

test('material requirements uses the same signed scope and remains a read RPC',async()=>{
 let captured;
 const c=manufacturingClient(async(n,a)=>{captured={n,a};return {data:{planning_only:true,lines:[]}};},{tenant_id:951,business_id:9511,site_id:9521});
 assert.equal((await c.call('mfg_material_requirements_v1',{p_recipe:12,p_multiplier:2,p_site:999})).planning_only,true);
 assert.equal(captured.n,'mfg_material_requirements_v1');assert.equal(captured.a.p_site,9521);assert.equal(captured.a.p_multiplier,2);
 assert.equal(captured.a.p_key,undefined);
});

test('waste reads and writes keep signed scope and the supplied retry key',async()=>{
 const seen=[];
 const c=manufacturingClient(async(n,a)=>{seen.push({n,a});return {data:{included_in_consumption:true}};},{tenant_id:951,business_id:9511,site_id:9521});
 await c.call('mfg_record_material_waste_v1',{p_business:999,p_site:999,p_batch:12,p_quantity:.1,p_key:'retry_stable_01'});
 await c.call('mfg_material_waste_report_v1',{p_business:999,p_site:999,p_batch:12});
 assert.equal(seen[0].a.p_business,9511);assert.equal(seen[0].a.p_site,9521);assert.equal(seen[0].a.p_key,'retry_stable_01');assert.equal(seen[1].a.p_site,9521);
});

test('substitution drafting and previews preserve signed scope and caller retry key',async()=>{
 const seen=[];const c=manufacturingClient(async(n,a)=>{seen.push({n,a});return {data:{planning_only:true}};},{tenant_id:951,business_id:9511,site_id:9521});
 await c.call('mfg_define_substitution_v1',{p_site:999,p_recipe:7,p_key:'sub_retry_01'});
 await c.call('mfg_recipe_substitutions_v1',{p_recipe:7});
 await c.call('mfg_preview_substitution_v1',{p_rule:8,p_multiplier:2,p_replacement_pct:50,p_business:999});
 assert.equal(seen[0].a.p_site,9521);assert.equal(seen[0].a.p_key,'sub_retry_01');assert.equal(seen[2].a.p_business,9511);assert.equal(seen[2].a.p_key,undefined);
});
test('canonical Master report and v2 preview retain shell business/site scope',async()=>{
 const calls=[];const c=manufacturingClient(async(n,a)=>{calls.push([n,a]);return {data:{master:'VERIFIED_CANONICAL'}};},{tenant_id:951,business_id:9511,site_id:9521});
 for(const name of ['mfg_master_validation_v1','mfg_preview_substitution_v2'])await c.call(name,{p_business:9512,p_site:9522});
 assert.equal(calls.length,2);for(const [,args] of calls){assert.equal(args.p_business,9511);assert.equal(args.p_site,9521);}
});
