import test from 'node:test';
import assert from 'node:assert/strict';
import {createCanonicalGov002ReviewClient} from '../internal/enterprise-client/c10_np01_canonical_review_client_v1.mjs';

const owner='01111111-1111-4111-8111-111111111111';
const other='02222222-2222-4222-8222-222222222222';
const status={request_id:'81',business_id:101,domain:'inventory',action_code:'adjust',
 source_key:'demo-stock-1',source_version:1,policy_version:1,
 created_at:'2026-11-16T01:00:00Z',expires_at:'2099-11-16T01:00:00Z',
 stored_status:'pending',display_status:'awaiting_stage_2',
 required_checks:3,completed_checks:1,can_review_now:true,is_maker:false};
const task={request_id:'81',business_id:101,domain:'inventory',action_code:'adjust',
 source_key:'demo-stock-1',source_version:1,policy_version:1,
 stage_no:2,stage_total:3,expires_at:'2099-11-16T01:00:00Z'};
const event={event_id:'201',business_id:101,request_id:'81',action:'approve',
 occurred_at:'2026-11-16T01:02:00Z',stage_no:1,
 approval_status:'pending',audit_event_id:'301'};

function fixture({responder=()=>({data:[]}),initial=owner}={}){
 let who=initial,subscriber=null,subs=0;
 const calls=[];
 const sdk={
  auth:{
   getUser:async()=>({data:{user:who?{id:who}:null},error:null}),
   onAuthStateChange(cb){
    subscriber=cb;
    return {data:{subscription:{unsubscribe:()=>{subs++;subscriber=null;}}}};
   }
  },
  schema(schema){
   assert.equal(schema,'core10');
   return {rpc:async(name,params)=>{
    calls.push({name,params,who});
    return await responder(name,params);
   }};
  }
 };
 return {sdk,calls,setUser(x){who=x;},emit(x,u=who){subscriber?.(x,{user:u?{id:u}:null});},get unsubscribed(){return subs}};
}
function response(name){
 switch(name){
  case 'my_approval_status_v1':return {data:[status]};
  case 'my_approval_activity_v1':return {data:[event]};
  case 'my_routed_review_tasks_v1':return {data:[task]};
  case 'decide_approval':return {data:'901'};
  case 'withdraw_typed_approval_v1':return {data:'902'};
  default:throw Error('unexpected rpc '+name);
 }
}
test('reads ONLY canonical core10 RPCs with verified signed identity and scoped rows',async()=>{
 const {sdk,calls}=fixture({responder:response});
 const c=createCanonicalGov002ReviewClient(sdk);
 assert.equal(c.getState().connected,true);
 assert.equal((await c.listStatus({businessId:101}))[0].display_status,'awaiting_stage_2');
 assert.equal((await c.listActivity({businessId:101}))[0].audit_event_id,'301');
 assert.equal((await c.listReviewerTasks({businessId:101}))[0].stage_no,2);
 assert.deepEqual(calls.map(x=>x.name),[
  'my_approval_status_v1','my_approval_activity_v1','my_routed_review_tasks_v1'
 ]);
 assert.equal(calls.every(x=>x.who===owner),true);
 await assert.rejects(c.decideApproval({businessId:101,requestId:81,action:'approve',idempotencyKey:'vote_1234'}),/approval_mutations_disabled/);
 c.destroy();assert.equal(c.getState().connected,false);
});
test('explicit mutation unlock still needs a current server reviewer task and idempotency key',async()=>{
 const f=fixture({responder:response});
 const c=createCanonicalGov002ReviewClient(f.sdk,{allowMutations:true});
 assert.equal(await c.decideApproval({
  businessId:101,requestId:'81',action:'approve',idempotencyKey:'vote_1234'
 }),'901');
 assert.deepEqual(f.calls.map(x=>x.name),['my_routed_review_tasks_v1','decide_approval']);
 assert.deepEqual(f.calls[1].params,{p_request:'81',p_action:'approve',p_key:'vote_1234'});
 await assert.rejects(c.decideApproval({businessId:101,requestId:82,action:'approve',idempotencyKey:'vote_5678'}),/reviewer_task_not_available/);
 await assert.rejects(c.decideApproval({businessId:101,requestId:81,action:'post',idempotencyKey:'vote_5678'}),/invalid_approval_action/);
 await assert.rejects(c.decideApproval({businessId:101,requestId:81,action:'reject',idempotencyKey:'bad'}),/invalid_idempotency_key/);
 c.destroy();
});
test('canonical one-stage tasks are actionable, including Manufacturing',async()=>{
 const single={...task,domain:'manufacturing',action_code:'recipe_approve',
  source_key:'mfg-recipe:40',stage_no:1,stage_total:1};
 const f=fixture({responder:name=>name==='my_routed_review_tasks_v1'?{data:[single]}:response(name)});
 const c=createCanonicalGov002ReviewClient(f.sdk,{allowMutations:true});
 assert.deepEqual(await c.listReviewerTasks({businessId:101}),[single]);
 assert.equal(await c.decideApproval({
  businessId:101,requestId:single.request_id,action:'approve',idempotencyKey:'mfg_review_1'
 }),'901');
 c.destroy();
});
test('maker withdrawal requires maker, pending and zero votes; server remains final authority',async()=>{
 const f=fixture({responder:name=>name==='my_approval_status_v1'?{data:[{...status,is_maker:true,completed_checks:0,display_status:'awaiting_stage_1'}]}:response(name)});
 const c=createCanonicalGov002ReviewClient(f.sdk,{allowMutations:true});
 assert.equal(await c.withdrawApproval({businessId:101,requestId:'81',idempotencyKey:'withdraw_123'}),'902');
 assert.equal(f.calls.at(-1).name,'withdraw_typed_approval_v1');
 c.destroy();
 const denied=fixture({responder:response});
 const d=createCanonicalGov002ReviewClient(denied.sdk,{allowMutations:true});
 await assert.rejects(d.withdrawApproval({businessId:101,requestId:81,idempotencyKey:'withdraw_123'}),/maker_withdraw_not_available/);
 d.destroy();
});
test('rejects cross-tenant, malformed, duplicated, oversized and invented rows',async()=>{
 const bad=[
  ['my_approval_status_v1',[{...status,business_id:102}]],
  ['my_approval_status_v1',[{...status,stored_status:'unknown'}]],
  ['my_approval_status_v1',[status,status]],
  ['my_approval_activity_v1',[{...event,audit_event_id:null}]],
  ['my_routed_review_tasks_v1',[{...task,stage_no:6}]],
  ['my_routed_review_tasks_v1',[{...task,stage_no:2,stage_total:1}]],
  ['my_routed_review_tasks_v1',[{...task,stage_no:1,stage_total:0}]],
  ['my_routed_review_tasks_v1',[{...task,business_id:999}]],
 ];
 for(const [name,data] of bad){
  const f=fixture({responder:()=>({data})});
  const c=createCanonicalGov002ReviewClient(f.sdk);
  const method=name==='my_approval_status_v1'?'listStatus':name==='my_approval_activity_v1'?'listActivity':'listReviewerTasks';
  await assert.rejects(c[method]({businessId:101}),/canonical_approval|invalid_positive_id/);
  c.destroy();
 }
 const f=fixture({responder:response});
 const c=createCanonicalGov002ReviewClient(f.sdk);
 await assert.rejects(c.listStatus({businessId:0}),/invalid_business_id/);
 await assert.rejects(c.listActivity({businessId:101,limit:101}),/invalid_page_limit/);
 c.destroy();
});
test('session switch, signout and stale response fail closed; no cross-user data returned',async()=>{
 let resolve;
 const f=fixture({responder:()=>new Promise(r=>{resolve=r;})});
 const c=createCanonicalGov002ReviewClient(f.sdk);
 const pending=c.listStatus({businessId:101});
 for(let i=0;i<20&&!resolve;i++)await Promise.resolve();
 assert.equal(typeof resolve,'function');
 f.setUser(other);
 resolve({data:[status]});
 await assert.rejects(pending,/signed_session_invalidated/);
 assert.equal(c.getState().connected,false);
 c.destroy();assert.equal(f.unsubscribed,1);

 const g=fixture({responder:response});
 const d=createCanonicalGov002ReviewClient(g.sdk);
 await d.listReviewerTasks({businessId:101});
 g.emit('SIGNED_OUT',null);
 await assert.rejects(d.listReviewerTasks({businessId:101}),/signed_session_invalidated/);
 d.destroy();
});
test('CSV export is read-only, bounded, signed RPC-backed and Excel-formula safe',async()=>{
 const f=fixture({responder:name=>name==='my_approval_activity_v1'
  ?{data:[{...event,action:'revoke',approval_status:'=2+2',occurred_at:'+SUM(A1)'}]}
  :response(name)});
 const c=createCanonicalGov002ReviewClient(f.sdk);
 const csv=await c.exportActivityCsv({businessId:101});
 assert.match(csv,/audit_event_id/);
 assert.match(csv,/"'=2\+2"/);
 assert.match(csv,/"'\+SUM\(A1\)"/);
 assert.equal(f.calls.length,1);
 assert.equal(f.calls[0].name,'my_approval_activity_v1');
 c.destroy();
});
