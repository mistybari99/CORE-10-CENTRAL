"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const S=require("../../core10-pack02-signed.js");
const A="11111111-1111-4111-8111-111111111111",B="22222222-2222-4222-8222-222222222222";
const rej=(p,c)=>assert.rejects(p,e=>e&&e.code===c,c);
function client(state){
 return {auth:{getUser:async()=>{state.calls.push("getUser");return state.user?{data:{user:{id:state.user}}}:{data:{user:null}};}},
  schema:s=>{assert.equal(s,"core10");return {rpc:async(n,a)=>{state.calls.push([n,a]);return state.reply?state.reply(n,a):{data:{ok:true}};}};}};
}
test("only the six PACK-02 RPCs with known argument names are reachable",async()=>{
 const st={user:A,calls:[]},x=S.fromClient(client(st));
 assert.equal(S.RPC_NAMES.length,6);
 for(const n of ["build01_set_access_v1","change_access_v1","pack02_brand_v1","__proto__","toString",""])await rej(x.rpc(n,{}),"PACK02_RPC_NOT_ALLOWED");
 await rej(x.rpc("pack02_workspace_v1",{p_mode:"staff",p_business:1,p_actor:B}),"PACK02_RPC_ARGS_INVALID");
 await rej(x.rpc("pack02_owner_report_v1",[]),"PACK02_RPC_ARGS_INVALID");
 assert.deepEqual(st.calls,[],"rejected before any network call");
});
test("fresh getUser precedes every call; signed-out and bad ids fail closed",async()=>{
 const st={user:A,calls:[]},x=S.fromClient(client(st));
 await x.rpc("pack02_owner_report_v1");await x.rpc("pack02_business_report_v1",{p_business:101});
 assert.deepEqual(st.calls.map(c=>Array.isArray(c)?c[0]:c),["getUser","pack02_owner_report_v1","getUser","pack02_business_report_v1"]);
 st.user=null;await rej(x.rpc("pack02_owner_report_v1"),"PACK02_SIGN_IN_REQUIRED");
 const y=S.fromClient(client({user:"not-a-uuid",calls:[]}));await rej(y.rpc("pack02_owner_report_v1"),"PACK02_SIGN_IN_REQUIRED");
 assert.throws(()=>S.fromClient({}),e=>e.code==="PACK02_SIGNED_CLIENT_REQUIRED");
});
test("actor switch poisons the adapter; forged actor in response is refused",async()=>{
 const st={user:A,calls:[]},x=S.fromClient(client(st));
 await x.rpc("pack02_owner_report_v1");
 st.user=B;await rej(x.rpc("pack02_owner_report_v1"),"PACK02_SESSION_CHANGED");
 st.user=A;await rej(x.rpc("pack02_owner_report_v1"),"PACK02_SESSION_CHANGED");
 const st2={user:A,calls:[],reply:()=>({data:{actor_uid:B}})};
 await rej(S.fromClient(client(st2)).rpc("pack02_workspace_v1",{p_mode:"universal_owner",p_business:null}),"PACK02_ACTOR_MISMATCH");
});
test("server errors are reduced to safe codes; non-object data refused",async()=>{
 const mk=reply=>S.fromClient(client({user:A,calls:[],reply}));
 await rej(mk(()=>({error:{message:"PACK02_WORKSPACE_DENIED"}})).rpc("pack02_owner_report_v1"),"PACK02_WORKSPACE_DENIED");
 await rej(mk(()=>({error:{message:"relation \"core10.tenants\" <script>"}})).rpc("pack02_owner_report_v1"),"PACK02_RPC_DENIED_OR_UNAVAILABLE");
 await rej(mk(()=>({data:[1]})).rpc("pack02_owner_report_v1"),"PACK02_INVALID_RESPONSE");
 await rej(mk(()=>{throw new Error("net");}).rpc("pack02_owner_report_v1"),"PACK02_RPC_DENIED_OR_UNAVAILABLE");
});
test("fromRpc wraps a host-signed rpc with the same allowlist",async()=>{
 const seen=[],x=S.fromRpc(async(n,a)=>{seen.push(n);if(n==="pack02_owner_report_v1")return {ok:1};const e=new Error("BUILD01_SIGN_IN_REQUIRED");e.code="BUILD01_SIGN_IN_REQUIRED";throw e;});
 assert.deepEqual(await x.rpc("pack02_owner_report_v1"),{ok:1});
 await rej(x.rpc("build01_setup_v1",{}),"PACK02_RPC_NOT_ALLOWED");
 await rej(x.rpc("pack02_business_report_v1",{p_business:1}),"BUILD01_SIGN_IN_REQUIRED");
 assert.deepEqual(seen,["pack02_owner_report_v1","pack02_business_report_v1"]);
 assert.throws(()=>S.fromRpc(null),e=>e.code==="PACK02_SIGNED_RPC_REQUIRED");
});
