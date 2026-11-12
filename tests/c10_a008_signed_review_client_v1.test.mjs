import test from "node:test";
import assert from "node:assert/strict";
import { createGov002ReviewClient } from "../internal/enterprise-client/c10_gov002_signed_review_client_v1.mjs";

const event = {
 activity_id:"approval:22",business_id:101,request_id:27,
 domain:"demo_ops",action_code:"exception_review",source_key:"=1+1",
 source_version:1,request_maker:"33333333-3333-4333-8333-333333333333",
 event_actor:"22222222-2222-4222-8222-222222222222",
 activity_type:"approval",action:"approve",severity:null,
 occurred_at:"2026-11-12T12:00:00Z",approval_status:"approved"
};
function fakeSupabase({user="signed-test-actor",row=[event],readError=null,rpcError=null,rpcData=99}={}) {
 const calls=[];
 const database={
  from(name) {
   calls.push({verb:"from",name});
   const q={
    select(columns) { calls.push({verb:"select",columns}); return q; },
    eq(field,value) { calls.push({verb:"eq",field,value});return q; },
    order(field,opts) { calls.push({verb:"order",field,opts});return q; },
    async limit(n) {calls.push({verb:"limit",n});return {data:row,error:readError};}
   };
   return q;
  },
  async rpc(name,params) {calls.push({verb:"rpc",name,params});return {data:rpcData,error:rpcError};}
 };
 const supabase={
  auth:{async getUser(){calls.push({verb:"getUser"});return {data:{user:user?{id:user}:null},error:null};}},
  schema(s) {calls.push({verb:"schema",name:s});return database;}
 };
 return {supabase,calls};
}
test("requires a real Supabase-shape signed client",()=>{
 assert.throws(()=>createGov002ReviewClient(null),/signed_supabase_client_required/);
 assert.throws(()=>createGov002ReviewClient({auth:{getUser(){}}}),/signed_supabase_client_required/);
});
test("only scoped read-only view and explicit business filter after auth.getUser",async()=>{
 const f=fakeSupabase();
 const c=createGov002ReviewClient(f.supabase);
 const rows=await c.listActivity({businessId:101,limit:25});
 assert.deepEqual(rows,[event]);
 assert.deepEqual(f.calls.map(x=>x.verb),
  ["getUser","schema","from","select","eq","order","limit","getUser"]);
 assert.equal(f.calls[2].name,"approval_activity_feed_v1");
 assert.deepEqual(f.calls[4],{verb:"eq",field:"business_id",value:101});
 assert.equal(f.calls[5].field,"occurred_at");
 assert.equal(f.calls[6].n,25);
});
test("status and exception read go only to intended security-invoker views",async()=>{
 for(const [fn,view] of [
  ["listStatus","approval_status_report_v1"],
  ["listExceptions","approval_exception_inbox_v1"]
 ]) {
  const f=fakeSupabase({row:[{business_id:101}]});
  await createGov002ReviewClient(f.supabase)[fn]({businessId:101});
  assert.equal(f.calls.find(x=>x.verb==="from").name,view);
 }
});
test("missing/revoked user fails before any SQL view or RPC",async()=>{
 const f=fakeSupabase({user:null});
 const c=createGov002ReviewClient(f.supabase);
 await assert.rejects(c.listActivity({businessId:101}),/auth_required/);
 await assert.rejects(c.decideApproval({requestId:7,action:"approve",idempotencyKey:"decision_01"}),/auth_required/);
 assert.equal(f.calls.some(x=>x.verb==="schema" || x.verb==="rpc"),false);
});
test("signed decision RPC passes only request/action/key; never supplied actor/tenant/role",async()=>{
 const f=fakeSupabase();
 const c=createGov002ReviewClient(f.supabase);
 assert.equal(await c.decideApproval({requestId:55,action:"approve",idempotencyKey:"decision_001",role:"tenant_owner",actor:"admin"}),99);
 const rpc=f.calls.find(x=>x.verb==="rpc");
 assert.equal(rpc.name,"decide_approval");
 assert.deepEqual(rpc.params,{p_request:55,p_action:"approve",p_key:"decision_001"});
 assert.equal(Object.keys(rpc.params).some(x=>/role|actor|tenant|posted|effect/.test(x)),false);
 assert.deepEqual(await c.withdrawApproval({requestId:55,idempotencyKey:"withdraw_001"}),99);
 assert.equal(f.calls.filter(x=>x.verb==="getUser").length,4);
});
test("bounded exception methods never call stock/finance execute RPCs",async()=>{
 const f=fakeSupabase();
 const c=createGov002ReviewClient(f.supabase);
 await c.requestException({requestId:5,reason:"Urgent check of contradictory source",severity:"urgent",ttlMinutes:20,idempotencyKey:"except_create_01"});
 await c.decideException({escalationId:8,action:"acknowledged",idempotencyKey:"except_vote_01"});
 await c.withdrawException({escalationId:8,idempotencyKey:"except_withdraw_01"});
 const names=f.calls.filter(x=>x.verb==="rpc").map(x=>x.name);
 assert.deepEqual(names,["request_approval_exception_v1","decide_approval_exception_v1","withdraw_approval_exception_v1"]);
 assert.deepEqual(f.calls.find(x=>x.name==="request_approval_exception_v1").params,{
  p_request:5,p_reason:"Urgent check of contradictory source",p_severity:"urgent",p_minutes:20,p_key:"except_create_01"
 });
});
test("malformed key, unsupported decision or unbounded escalation blocked before RPC",async()=>{
 const f=fakeSupabase();
 const c=createGov002ReviewClient(f.supabase);
 assert.throws(()=>c.decideApproval({requestId:1,action:"pay",idempotencyKey:"key_wrong"}),/invalid_approval_action/);
 assert.throws(()=>c.requestException({requestId:1,reason:"bad",severity:"normal",idempotencyKey:"valid_key_01"}),/invalid_escalation_reason/);
 assert.throws(()=>c.requestException({requestId:1,reason:"Long enough valid reason",ttlMinutes:1441,idempotencyKey:"valid_key_01"}),/invalid_escalation_policy/);
 assert.throws(()=>c.decideException({escalationId:2,action:"override",idempotencyKey:"valid_key_01"}),/invalid_escalation_decision/);
 assert.throws(()=>c.withdrawApproval({requestId:1,idempotencyKey:"bad"}),/invalid_idempotency_key/);
 assert.throws(()=>c.decideApproval({requestId:-10,action:"approve",idempotencyKey:"valid_key_01"}),/invalid_positive_id/);
 assert.equal(f.calls.some(x=>x.verb==="rpc"),false);
});
test("backend errors never produce success, invalid response and foreign business rejected",async()=>{
 const f=fakeSupabase({rpcError:new Error("approval_not_authorized")});
 await assert.rejects(createGov002ReviewClient(f.supabase).decideApproval({requestId:1,action:"approve",idempotencyKey:"valid_key_01"}),/approval_not_authorized/);
 const wrong=fakeSupabase({row:[{...event,business_id:999}]});
 await assert.rejects(createGov002ReviewClient(wrong.supabase).listActivity({businessId:101}),/server_scope_mismatch/);
 const empty=fakeSupabase({row:null});
 await assert.rejects(createGov002ReviewClient(empty.supabase).listStatus({businessId:101}),/approval_read_invalid_response/);
});
test("export is first signed RLS page only, Excel formula injection sanitized",async()=>{
 const f=fakeSupabase();
 const c=createGov002ReviewClient(f.supabase);
 const csv=await c.exportActivityCsv({businessId:101,limit:15});
 assert.ok(csv.includes("'=1+1"));
 assert.ok(csv.includes('"approval:22"'));
 assert.equal(f.calls.find(x=>x.verb==="from").name,"approval_activity_feed_v1");
 assert.equal(f.calls.find(x=>x.verb==="limit").n,15);
 await assert.rejects(c.listActivity({businessId:0}),/invalid_business_id/);
 await assert.rejects(c.listActivity({businessId:101,limit:1001}),/invalid_page_limit/);
 const foreign=fakeSupabase({row:[{...event,business_id:102}]});
 await assert.rejects(createGov002ReviewClient(foreign.supabase).exportActivityCsv({businessId:101}),/server_scope_mismatch/);
});

test("account switch during scoped read rejects stale rows and CSV",async()=>{
 for(const method of ["listActivity","exportActivityCsv"]){
  let user="actor-A";
  const f=fakeSupabase();
  f.supabase.auth.getUser=async()=>({data:{user:{id:user}},error:null});
  const base=f.supabase.schema;
  f.supabase.schema=(name)=>{
   const db=base(name),original=db.from;
   db.from=(view)=>{
    const q=original(view),limit=q.limit;
    q.limit=async(n)=>{const r=await limit(n);user="actor-B";return r;};
    return q;
   };
   return db;
  };
  await assert.rejects(createGov002ReviewClient(f.supabase)[method]({businessId:101}),/signed_actor_changed/);
 }
});
test("account switch during approval or exception RPC rejects stale success receipt",async()=>{
 for(const method of ["decideApproval","requestException"]){
  let user="actor-A";
  const f=fakeSupabase();
  f.supabase.auth.getUser=async()=>({data:{user:{id:user}},error:null});
  const base=f.supabase.schema;
  f.supabase.schema=(name)=>{
   const db=base(name),original=db.rpc;
   db.rpc=async(...args)=>{const r=await original(...args);user="actor-B";return r;};
   return db;
  };
  const args=method==="decideApproval"
   ? {requestId:7,action:"approve",idempotencyKey:"switch_actor_01"}
   : {requestId:7,reason:"Account switch during review",idempotencyKey:"switch_actor_02"};
  await assert.rejects(createGov002ReviewClient(f.supabase)[method](args),/signed_actor_changed/);
 }
});
