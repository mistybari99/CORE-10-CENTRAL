import test from 'node:test';
import assert from 'node:assert/strict';
import {createGov002ReviewClient} from '../internal/enterprise-client/c10_gov002_signed_review_client_v1.mjs';
const task=(id,business_id=101)=>({request_id:id,business_id,domain:'demo_inventory',action_code:'review',source_key:'SOURCE-41',source_version:2,policy_version:3,stage_no:2,stage_total:3,expires_at:'2035-01-01T00:00:00Z'});
function supabase(rows){
 let user='reviewer-101',calls=[];
 const client={auth:{async getUser(){return {data:{user:user?{id:user}:null}}}},
  schema(){return {async rpc(name,args){calls.push([name,args]);return {data:rows,error:null}}}}};
 return {client,calls,setUser:x=>{user=x}};
}
test('only signed user can request business-scoped current reviewer tasks',async()=>{
 const x=supabase([task(1)]),c=createGov002ReviewClient(x.client);
 const rows=await c.listReviewerTasks({businessId:101});
 assert.equal(rows.length,1);
 assert.deepEqual(x.calls,[['my_routed_review_tasks_v2',{p_business:101}]]);
 assert.equal(rows[0].stage_no,2);
});
test('wrong-business, unsupported tasks and missing auth fail closed',async()=>{
 const x=supabase([task(1,202)]),c=createGov002ReviewClient(x.client);
 await assert.rejects(c.listReviewerTasks({businessId:101}),/server_scope_mismatch/);
 await assert.rejects(c.listReviewerTasks({businessId:0}),/invalid_business_id/);
 const y=supabase([task(1)]);y.setUser(null);
 await assert.rejects(createGov002ReviewClient(y.client).listReviewerTasks({businessId:101}),/auth_required/);
});
test('actor changed after RPC response cannot receive old-account inbox',async()=>{
 const x=supabase([task(1)]);
 x.client.schema=()=>({async rpc(){x.setUser('different');return {data:[task(1)],error:null}}});
 await assert.rejects(createGov002ReviewClient(x.client).listReviewerTasks({businessId:101}),/signed_actor_changed/);
});
test('malformed stage counters and unbounded server list are rejected rather than rendered',async()=>{
 for(const rows of [[{...task(1),stage_no:4}],Array.from({length:101},(_,i)=>task(i+1))]){
  await assert.rejects(createGov002ReviewClient(supabase(rows).client).listReviewerTasks({businessId:101}),/reviewer_task_invalid_response/);
 }
});