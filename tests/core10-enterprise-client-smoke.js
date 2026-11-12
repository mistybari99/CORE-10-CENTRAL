"use strict";
const assert=require("node:assert/strict");
const {create,validateSetup}=require("../core10-enterprise-client.js");
const input={legalId:11,slug:"test-sweets",template:"food_manufacturing",
 displayName:"Sweets",mode:"quick",requestKey:"test-create-001",
 brandHex:"#6D1D2A"};
function rejectsCode(p,code){return assert.rejects(p,e=>e&&e.code===code);}
(async()=>{
 const events=[],resp={data:[],error:null};
 const db={
  rpc:function(name,args){events.push(["rpc",name,args]);return Promise.resolve({data:222,error:null})},
  from:function(name){
   events.push(["from",name]);
   return {select:function(){events.push(["select",name]);return this},
    order:function(){return this},limit:function(){return Promise.resolve(resp)},
    eq:function(){return this}};
  }
 };
 const client={
  auth:{getUser:async function(){events.push(["getUser"]);return{data:{user:{id:"11111111-1111-4111-8111-111111111111"}},error:null}}},
  schema:function(schema){events.push(["schema",schema]);return db}
 };
 const disabled=create({client});
 assert.deepEqual(disabled.status(),{readEnabled:false,writeEnabled:false,schema:"c10_demo",certified:false});
 await rejectsCode(disabled.listBusinesses(),"ENTERPRISE_BACKEND_NOT_RELEASED");
 await rejectsCode(disabled.setupBusiness(input),"ENTERPRISE_BACKEND_NOT_RELEASED");
 assert.equal(events.length,0,"disabled bridge must not call network");

 const ro=create({client,experimentalRead:true});
 await ro.listBusinesses();
 assert.ok(events.some(x=>x[0]==="getUser"),"signed user session not checked");
 assert.ok(events.some(x=>x[0]==="from"&&x[1]==="businesses"));
 await rejectsCode(ro.setupBusiness(input),"ENTERPRISE_BACKEND_NOT_RELEASED");

 const api=create({client,experimentalRead:true,experimentalWrite:true});
 assert.equal(await api.setupBusiness(input),222);
 const rpc=events.find(x=>x[0]==="rpc");
 assert.equal(rpc[1],"setup_business_v1");
 assert.deepEqual(rpc[2],{
  p_legal:11,p_slug:"test-sweets",p_template:"food_manufacturing",
  p_display_name:"Sweets",p_mode:"quick",p_sites:null,
  p_request:"test-create-001",p_brand_hex:"#6D1D2A"});
 assert.ok(events.some(x=>x[0]==="schema"&&x[1]==="c10_demo"));
 await api.listSetupOverview();
 await api.listStockReconciliation(101);
 assert.ok(events.some(x=>x[0]==="from"&&x[1]==="inventory_reconciliation_v1"));
 assert.ok(!events.some(x=>x[0]==="insert"||x[0]==="update"||x[0]==="upsert"),
   "adapter must never post directly to tables");

 assert.deepEqual(validateSetup({...input,mode:"advanced",sites:[
  {kind:"showroom",label:"Misty 1"},{kind:"factory",label:"Cake factory"},
  {kind:"godown",label:"Storage"}]}).p_sites.length,3);
 assert.throws(()=>validateSetup({...input,mode:"advanced",sites:[]}),/INVALID_SITE_MANIFEST/);
 assert.throws(()=>validateSetup({...input,mode:"advanced",sites:[
  {kind:"showroom",label:"A"},{kind:"showroom",label:"a"}]}),/DUPLICATE_SITE/);
 assert.throws(()=>validateSetup({...input,mode:"quick",sites:[{kind:"factory",label:"A"}]}),/QUICK_NO_CUSTOM_SITES/);
 assert.throws(()=>validateSetup({...input,requestKey:""}),/INVALID_SETUP/);
 assert.throws(()=>validateSetup({...input,brandHex:"red"}),/INVALID_SETUP/);
 assert.throws(()=>validateSetup({...input,mode:"advanced",sites:[{kind:"showroom",label:"A",tenant_id:2}]}),/INVALID_SITE_MANIFEST/);
 await rejectsCode(api.listStockReconciliation("bad"),"INVALID_BUSINESS_ID");
 assert.throws(()=>validateSetup({...input,mode:"silent-downgrade"}),/INVALID_SETUP_MODE/);

 const noUser=create({client:{...client,auth:{getUser:async()=>({data:{user:null},error:null})}},
  experimentalRead:true,experimentalWrite:true});
 await rejectsCode(noUser.setupBusiness(input),"AUTHENTICATED_USER_REQUIRED");
 const badBackend=create({client:{...client,schema:function(){return{
   ...db,rpc:()=>Promise.resolve({data:null,error:{code:"42501",message:"permission denied"}})
  }}},experimentalRead:true,experimentalWrite:true});
 await assert.rejects(badBackend.setupBusiness(input),e=>e&&e.code==="42501");
 console.log("PASS: client adapter disabled by default, verified auth session required, typed Quick/Advanced payload, read scope, RPC-only write, permission rejection.");
})().catch(e=>{console.error(e);process.exitCode=1});
