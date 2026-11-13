"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const api=require("../../core10-build01-client.js");
const owner="11111111-1111-4111-8111-111111111111";
const config={enabled:true,mode:"isolated-development",url:"http://127.0.0.1:58081",publishableKey:"test-publishable"};
function fixture(){
 const calls=[];let actor=owner;
 const client={
  auth:{
   getUser:async()=>{calls.push("getUser");return {data:{user:actor?{id:actor}:null}};},
   signInWithPassword:async()=>({data:{user:{id:owner}}}),
   signOut:async args=>{calls.push(args);actor=null;return {error:null};}
  },
  schema:s=>{
   assert.equal(s,"c10_demo");
   return {rpc:async(name,args)=>{
    calls.push({name,args});
    if(name==="build01_context_v1")return {data:{actor_uid:owner,businesses:[],legal_entities:[],templates:[]}};
    return {data:{business:{id:101},business_id:101,site_id:1001,sites:[{id:1001,allowed_actions:["stock.read"]}],access:{},audit:[{id:1}]}};
   }};
  }
 };
 return {api:api.create({config,client}),client,calls,setActor:v=>actor=v};
}
test("explicit local config: refuses disabled, hosted and secret targets",()=>{
 assert.throws(()=>api.create({config:{...config,enabled:false}}),/NOT_CONFIGURED/);
 for(const url of ["https://project.supabase.co","http://example.com","http://127.0.0.1@evil.test","http://localhost/path"])
  assert.throws(()=>api.create({config:{...config,url}}));
 const token=["e30",Buffer.from(JSON.stringify({role:"service_role"})).toString("base64url"),"signature"].join(".");
 assert.throws(()=>api.create({config:{...config,publishableKey:token}}),/SECRET_KEY/);
});
test("setup reuses original A020 validator before network and requires fresh signed actor",async()=>{
 const f=fixture();
 await assert.rejects(f.api.setup({legalId:1,mode:"quick",slug:"INVALID",displayName:"x",template:"food_manufacturing",sites:[],requestKey:"key",brandHex:"#123456"}));
 assert.equal(f.calls.length,0);
 await f.api.setup({legalId:1,mode:"quick",slug:"valid",displayName:"Synthetic",template:"food_manufacturing",sites:[],requestKey:"build01-setup",brandHex:"#123456"});
 assert.equal(f.calls[0],"getUser");assert.equal(f.calls[1].name,"build01_setup_v1");
 f.setActor(null);await assert.rejects(f.api.workspace(101),/SIGN_IN_REQUIRED/);
});
test("effective access derives from a fresh server projection and never from role metadata",async()=>{
 const f=fixture();
 assert.equal((await f.api.effectivePermission({businessId:101,siteId:1001,action:"stock.post"})).allowed,false);
 assert.equal((await f.api.effectivePermission({businessId:101,siteId:1001,action:"stock.read"})).allowed,true);
 assert.equal(f.calls.filter(x=>x==="getUser").length,2);
 f.client.schema=()=>({rpc:async()=>({data:{business:{id:201},sites:[],access:{},audit:[]}})});
 await assert.rejects(f.api.workspace(101),/SCOPE_MISMATCH/);
});
test("access validation and exact RPC signature preserve denial, expiry and stale version",async()=>{
 const f=fixture();
 const input={businessId:101,subjectUid:"44444444-4444-4444-8444-444444444444",command:"site_grant.grant",siteId:1001,role:null,actions:["stock.read"],deniedActions:["stock.post"],expiresAt:"2027-01-01T00:00:00Z",requestKey:"build01-access",expectedVersion:2};
 await f.api.changeAccess(input);
 const call=f.calls[1];assert.equal(call.name,"build01_set_access_v1");assert.equal(call.args.p_expected_version,2);assert.deepEqual(call.args.p_denied_actions,["stock.post"]);
 const n=f.calls.length;await assert.rejects(f.api.changeAccess({...input,actions:["auth.admin"]}),/INVALID_ACTIONS/);assert.equal(f.calls.length,n);
 await assert.rejects(f.api.changeAccess({...input,command:"site_grant.revoke"}),/REVOKE_HAS_POLICY/);
});
test("actor mismatch and failed auth are rejected; local logout clears access",async()=>{
 const f=fixture();f.setActor("22222222-2222-4222-8222-222222222222");await assert.rejects(f.api.context(),/ACTOR_MISMATCH/);
 await f.api.signOut();assert.deepEqual(f.calls.at(-1),{scope:"local"});await assert.rejects(f.api.context(),/SIGN_IN_REQUIRED/);
});
