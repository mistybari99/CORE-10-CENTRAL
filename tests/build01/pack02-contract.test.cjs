"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const {create}=require("../../core10-build01-client.js"),U="11111111-1111-4111-8111-111111111111",V="22222222-2222-4222-8222-222222222222";
function fixture(){
 let actor=U,response={actor_uid:U,contract:"C10_PACK02_WORKSPACE_V1"};
 const calls=[],client={auth:{getUser:async()=>({data:{user:actor?{id:actor}:null}}),signOut:async()=>({error:null})},
 schema:s=>{assert.equal(s,"core10");return{rpc:async(name,args)=>{calls.push([name,args]);return{data:response};}}}};
 return{api:create({config:{enabled:true,mode:"isolated-development",url:"http://127.0.0.1:58081",publishableKey:"fake-publishable"},client}),calls,setActor:x=>actor=x,setResponse:x=>response=x};
}
test("five read-only S2 RPCs recheck signed user; all write and unknown names denied",async()=>{
 const f=fixture(),pairs=[["pack02_workspace_v1",{p_mode:"staff",p_business:101}],
  ["pack02_controls_v1",{p_surface:"business",p_business:101}],["pack02_business_report_v1",{p_business:101}],
  ["pack02_owner_report_v1",{}],["pack02_setup_readback_v1",{p_business:101}]];
 for(const[name,args]of pairs)assert.ok(await f.api.pack02(name,args));
 assert.deepEqual(f.calls.map(x=>x[0]),pairs.map(x=>x[0]));
 const before=f.calls.length;
 await assert.rejects(f.api.pack02("pack02_setup_business_v1",{}),/RPC_NOT_ALLOWED/);
 await assert.rejects(f.api.pack02("pack02_workspace_v1",{p_business:101,evil:true}),/RPC_ARGUMENTS_INVALID/);
 assert.equal(f.calls.length,before);
 f.setActor(null);await assert.rejects(f.api.pack02("pack02_owner_report_v1",{}),/SIGN_IN_REQUIRED/);
});
test("S2 actor change poisons signed adapter, projection spoofing denied",async()=>{
 const f=fixture();await f.api.pack02("pack02_owner_report_v1",{});
 f.setActor(V);await assert.rejects(f.api.pack02("pack02_owner_report_v1",{}),/SESSION_CHANGED/);
 f.setActor(U);await assert.rejects(f.api.pack02("pack02_owner_report_v1",{}),/SESSION_CHANGED/);
 const g=fixture();g.setResponse({actor_uid:V});
 await assert.rejects(g.api.pack02("pack02_workspace_v1",{p_mode:"universal_owner",p_business:null}),/ACTOR_MISMATCH/);
});
