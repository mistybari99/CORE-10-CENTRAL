"use strict";
const assert=require("node:assert/strict");
const {create}=require("../core10-owner-portfolio-client.js");
const biz={business_id:101,tenant_id:1,name:"Demo Sweets",can_manage:true,sites:[{site_id:1001,kind:"showroom",locations:[]}],
modules:[],operations_count:2,layout:{mode:"detailed",sections:["sites","operations"],version:1},
runtime:{inventory:"source_built_isolated"}};
let signed=true,wrong=false,calls=[];
const client={auth:{getUser:async()=>signed?{data:{user:{id:"test-user"}},error:null}:{data:{user:null},error:{code:"401"}}},
 schema:k=>{assert.equal(k,"c10_demo");return{rpc:async(name,args)=>{
  calls.push([name,args]);
  if(name==="read_portfolio_workspace_v1")return{data:wrong?{businesses:[]}:
   {server_authorized:true,production_ready:false,operationally_certified:false,businesses:[biz]},error:null};
  return{data:{business_id:args.p_business,version:2,replayed:false},error:null};
 }};}};
(async()=>{
 const api=create({client});
 assert.equal((await api.read()).businesses[0].business_id,101);
 assert.equal((await api.layout(101,"compact",["operations","sites"],1,"owner-layout-001")).version,2);
 assert.equal(api.release().production,false);
 await assert.rejects(()=>api.layout(101,"compact",["sites","sites"],1,"invalid-key-001"),/INVALID_LAYOUT/);
 await assert.rejects(()=>api.layout("other","compact",["sites"],1,"valid-key-001"),/INVALID_BUSINESS_ID/);
 wrong=true;await assert.rejects(()=>api.read(),/UNVERIFIED_PORTFOLIO/);
 wrong=false;signed=false;await assert.rejects(()=>api.read(),/SIGN_IN_REQUIRED/);
 assert.equal(calls.filter(x=>x[0]==="read_portfolio_workspace_v1").length,2);
 console.log("PASS A050 signed client, source scope, layout security and invalid-response checks");
})().catch(e=>{console.error(e);process.exitCode=1});
