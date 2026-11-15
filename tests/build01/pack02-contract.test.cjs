"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {create}=require("../../core10-build01-client.js");
const U="11111111-1111-4111-8111-111111111111";
const config={enabled:true,mode:"isolated-development",url:"http://127.0.0.1:58081",publishableKey:"synthetic-public"};
function fixture(){
 const calls=[];let who=U;
 const rpcPayload={contract:"C10_PACK02_WORKSPACE_V1",mode:"business_owner",actor_uid:U,
  business:{id:101,brand:{name:"Synthetic brand",hex:"#234567"}},umbrella:{visible:false},sites:[],nav:[],production_certified:false};
 const client={auth:{getUser:async()=>({data:{user:who?{id:who}:null}})},schema:s=>{
  assert.equal(s,"c10_demo");return{rpc:async(name,args)=>{calls.push([name,args]);return{data:rpcPayload};}}}};
 return {api:create({config,client}),calls,response:rpcPayload,setWho:v=>{who=v;}};
}
test("S2 uses only signed Build01 client, exact RPC and server contract",async()=>{
 const f=fixture(),p=await f.api.pack02Workspace("business_owner",101);
 assert.equal(p.contract,"C10_PACK02_WORKSPACE_V1");
 assert.deepEqual(f.calls,[["pack02_workspace_v1",{p_mode:"business_owner",p_business:101}]]);
 assert.deepEqual(Object.keys(f.api).includes("pack02Workspace"),true);
 await assert.rejects(f.api.pack02Workspace("admin",101),/PACK02_MODE_INVALID/);
 await assert.rejects(f.api.pack02Workspace("staff","101;DROP"),/INVALID_ID/);
 await assert.rejects(f.api.pack02Workspace("universal_owner",101),/PACK02_SCOPE_INVALID/);
 f.response.actor_uid="22222222-2222-4222-8222-222222222222";
 await assert.rejects(f.api.pack02Workspace("business_owner",101),/ACTOR_MISMATCH/);
 f.response.actor_uid=U;f.response.business.id=201;
 await assert.rejects(f.api.pack02Workspace("business_owner",101),/SCOPE_MISMATCH/);
 f.response.business.id=101;f.response.production_certified=true;
 await assert.rejects(f.api.pack02Workspace("business_owner",101),/PACK02_CONTRACT_INVALID/);
 f.setWho(null);await assert.rejects(f.api.pack02Workspace("business_owner",101),/SIGN_IN_REQUIRED/);
});
test("S2 staff response must omit actor, tenant, sister and umbrella metadata",async()=>{
 const f=fixture();f.response.mode="staff";delete f.response.actor_uid;
 assert.equal((await f.api.pack02Workspace("staff",101)).mode,"staff");
 f.response.actor_uid=U;
 await assert.rejects(f.api.pack02Workspace("staff",101),/STAFF_LEAK/);
 delete f.response.actor_uid;f.response.tenants=[{id:1}];
 await assert.rejects(f.api.pack02Workspace("staff",101),/STAFF_LEAK/);
 delete f.response.tenants;f.response.umbrella.visible=true;
 await assert.rejects(f.api.pack02Workspace("staff",101),/STAFF_LEAK/);
});
