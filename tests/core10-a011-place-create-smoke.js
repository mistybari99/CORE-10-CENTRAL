"use strict";
const assert=require("node:assert/strict");
const site=require("../core10-place-setup.js");
const fs=require("node:fs");
const path=require("node:path");
let passed=0;
const check=(name,fn)=>Promise.resolve().then(fn).then(()=>{passed++;console.log("PASS",name)});
function fixture(){
 const elements={
  c10_place_form:{},c10_place_kind:{value:"factory"},c10_place_bn:{value:"কারখানা"},
  c10_place_en:{value:"Main Factory"},c10_place_code:{value:"main_factory"},
  c10_place_error:{hidden:true,textContent:""},c10_place_submit:{disabled:false}
 };
 let calls=[],toast=[],opened=[],closed=0,n=0;
 const w={
  document:{body:{dataset:{}},getElementById(id){return elements[id]||null}},
  location:{href:"https://example.test/index.html?workspace=islamia&biz=3",hash:"#/home"},
  crypto:{randomUUID(){return "00000000-0000-4000-8000-"+String(++n).padStart(12,"0")}},
  BOS:{biz:{cur:()=>3,list:()=>[{id:3,kind:"business",status:"active",name_bn:"ইসলামিয়া"}]}},
  BOS_APP:{S:{ctx:{is_owner:true,profile:{id:"owner1"}}},H:{},
   sb:{rpc:async(name,args)=>{calls.push({name,args});return{data:{id:41,code:"sw_main_factory",business_id:3,kind:"factory",status:"setting_up"},error:null}}},
   openSheet:s=>opened.push(s),closeSheet:()=>closed++,toast:s=>toast.push(s)}
 };
 return{w,elements,calls,toast,opened,closeCount:()=>closed};
}
async function run(){
 const filenames=["index.html","business.html"];
 await check("entry HTML imports the real module",()=>{
  for(const file of filenames)assert.match(fs.readFileSync(file,"utf8"),/src="core10-place-setup\.js/);
  const owner=fs.readFileSync("core10-business-owner.js","utf8");
  assert.match(owner,/c10_place_open/);
 });
 await check("validation rejects empty/invalid/long inputs",()=>{
  assert.equal(site.validate({kind:"factory",name_bn:"",name_en:"",code:""}).ok,false);
  assert.equal(site.validate({kind:"factory",name_bn:"OK",name_en:"",code:"UpperCase-!"}).ok,false);
  assert.equal(site.validate({kind:"factory",name_bn:"a".repeat(121),name_en:"",code:""}).ok,false);
  assert.equal(site.validate({kind:"restaurant",name_bn:"OK",name_en:"",code:""}).ok,false);
  assert.equal(site.validate({kind:"godown",name_bn:"Store",name_en:"",code:"depot_1"}).ok,true);
 });
 await check("no staff or wrong business context can open a form",()=>{
  let f=fixture();site.install(f.w);f.w.BOS_APP.S.ctx.is_owner=false;
  f.w.BOS_APP.H.c10_place_open();assert.equal(f.opened.length,0);
  f.w.BOS_APP.S.ctx.is_owner=true;f.w.BOS.biz.cur=()=>5;
  f.w.BOS_APP.H.c10_place_open();assert.equal(f.opened.length,0);
  f.w.BOS.biz.cur=()=>3;f.w.location.href="https://example.test/index.html?workspace=islamia&biz=999";
  f.w.BOS_APP.H.c10_place_open();assert.equal(f.opened.length,0);
 });
 await check("authorized workflow uses existing transactional RPC with correct business and idempotency",async()=>{
  let f=fixture();assert.equal(site.install(f.w),true);
  f.w.BOS_APP.H.c10_place_open();assert.equal(f.opened.length,1);
  await f.w.BOS_APP.H.c10_place_create();
  assert.equal(f.calls.length,1);
  assert.equal(f.calls[0].name,"business_place_create135");
  assert.deepEqual(f.calls[0].args,{
   p_business:3,p_kind:"factory",p_code:"main_factory",p_name_bn:"কারখানা",p_name_en:"Main Factory",
   p_org_branch:null,p_client:"00000000-0000-4000-8000-000000000001"
  });
  assert.equal(f.closeCount(),1);assert.equal(f.w.location.hash,"#/locations");
  assert.match(f.toast[0],/setup required/);
 });
 await check("network error retains idempotency ID for safe retry",async()=>{
  let f=fixture();site.install(f.w);let count=0;
  f.w.BOS_APP.sb.rpc=async(name,args)=>{f.calls.push({name,args});if(++count===1)return{error:{message:"network error"}};return{data:{id:51,business_id:3,code:"s_factory"}}};
  await f.w.BOS_APP.H.c10_place_create();
  assert.match(f.elements.c10_place_error.textContent,/not confirmed/i);
  await f.w.BOS_APP.H.c10_place_create();
  assert.equal(f.calls.length,2);assert.equal(f.calls[0].args.p_client,f.calls[1].args.p_client);
  assert.equal(f.closeCount(),1);
 });
 await check("changing payload generates a new idempotency request ID",async()=>{
  let f=fixture();site.install(f.w);f.w.BOS_APP.sb.rpc=async(name,args)=>{f.calls.push({name,args});return{error:{message:"offline"}}};
  await f.w.BOS_APP.H.c10_place_create();f.elements.c10_place_code.value="factory_two";
  await f.w.BOS_APP.H.c10_place_create();
  assert.notEqual(f.calls[0].args.p_client,f.calls[1].args.p_client);
 });
 await check("concurrent duplicate click is ignored",async()=>{
  let f=fixture();site.install(f.w);let complete;
  f.w.BOS_APP.sb.rpc=(name,args)=>{f.calls.push({name,args});return new Promise(resolve=>{complete=resolve})};
  const first=f.w.BOS_APP.H.c10_place_create();
  assert.equal(f.elements.c10_place_submit.disabled,true);
  await f.w.BOS_APP.H.c10_place_create();assert.equal(f.calls.length,1);
  complete({data:{id:57,business_id:3,code:"factory"}});
  await first;assert.equal(f.elements.c10_place_submit.disabled,false);
 });
 await check("forged foreign-business response never triggers success",async()=>{
  let f=fixture();site.install(f.w);f.w.BOS_APP.sb.rpc=async()=>({data:{id:77,business_id:66,code:"foreign"}});
  await f.w.BOS_APP.H.c10_place_create();assert.equal(f.closeCount(),0);assert.equal(f.w.location.hash,"#/home");
  assert.match(f.elements.c10_place_error.textContent,/not confirmed/i);
 });
 await check("session switch suppresses stale success/navigation",async()=>{
  let f=fixture();site.install(f.w);let complete;
  f.w.BOS_APP.sb.rpc=()=>new Promise(resolve=>{complete=resolve});
  let inflight=f.w.BOS_APP.H.c10_place_create();
  f.w.BOS_APP.S.ctx.profile.id="other";
  complete({data:{id:83,business_id:3,code:"new"}});
  await inflight;assert.equal(f.closeCount(),0);assert.equal(f.w.location.hash,"#/home");
 });
 console.log("RESULT:",passed,"PASS, 0 FAIL");
}
run().catch(e=>{console.error("FAIL",e);process.exitCode=1});
