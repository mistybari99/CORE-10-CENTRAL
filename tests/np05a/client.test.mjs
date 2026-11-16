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
