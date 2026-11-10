"use strict";
const assert=require("node:assert/strict");
const site=require("../core10-place-setup.js");
const fs=require("node:fs");
let passed=0;
const check=(name,fn)=>Promise.resolve().then(fn).then(()=>{passed++;console.log("PASS",name)});
function fixture(){
 const elements={
  c10_place_form:{events:{},addEventListener(name,fn){this.events[name]=fn}},
  c10_place_bn:{value:"কারখানা"},c10_place_en:{value:"Main Factory"},
  c10_place_code:{value:"main_factory"},
  c10_place_preview_name:{textContent:""},c10_place_preview_detail:{textContent:""},
  c10_place_error:{hidden:true,textContent:""},
  c10_place_submit:{disabled:false,textContent:"",setAttribute(){},removeAttribute(){}},
  previewIcon:{textContent:""}
 };
 let kind="factory",formOpen=false,calls=[],toast=[],opened=[],closed=0,n=0;
 const w={
  document:{body:{dataset:{}},
   getElementById(id){return formOpen?elements[id]||null:null},
   querySelector(selector){
    if(!formOpen)return null;
    if(selector==='input[name="c10_place_kind"]:checked')return{value:kind};
    if(selector===".c10-site-preview-icon")return elements.previewIcon;
    return null;
   }},
  location:{href:"https://example.test/index.html?workspace=islamia&biz=3",hash:"#/home"},
  crypto:{randomUUID(){return "00000000-0000-4000-8000-"+String(++n).padStart(12,"0")}},
  BOS:{biz:{cur:()=>3,list:()=>[{id:3,kind:"business",status:"active",name_bn:"ইসলামিয়া"}]}},
  BOS_APP:{S:{ctx:{is_owner:true,profile:{id:"owner1"}}},H:{},
   sb:{rpc:async(name,args)=>{calls.push({name,args});return{data:{id:41,code:"sw_main_factory",business_id:3,kind:"factory",status:"setting_up"},error:null}}},
   openSheet:s=>{opened.push(s);formOpen=true},
   closeSheet:()=>{closed++;formOpen=false},
   toast:s=>toast.push(s)}
 };
 return{w,elements,calls,toast,opened,closeCount:()=>closed,setKind:x=>kind=x,closeForm:()=>formOpen=false,open:()=>w.BOS_APP.H.c10_place_open()};
}
async function run(){
 await check("both entrypoints link scoped responsive CSS and new JS",()=>{
  for(const file of ["index.html","business.html"]){
   const contents=fs.readFileSync(file,"utf8");
   assert.match(contents,/href="core10-place-setup\.css/);
   assert.match(contents,/src="core10-place-setup\.js/);
  }
  const css=fs.readFileSync("core10-place-setup.css","utf8");
  assert.match(css,/@media\(max-width:600px\)/);
  assert.match(css,/\.c10-site-type input:focus-visible/);
  assert.doesNotMatch(css,/^body\s*\{|^:root\s*\{/m);
  assert.match(fs.readFileSync("core10-business-owner.js","utf8"),/c10_place_open/);
 });
 await check("UI has three real type radio choices, status preview, accessible error and non-GPS wording",()=>{
  let f=fixture(),ctx=site.context(f.w),h=site.html(f.w,ctx);
  for(const kind of ["showroom","factory","godown"])assert.ok(h.includes('value="'+kind+'"'));
  assert.match(h,/aria-live="polite"/);
  assert.match(h,/role="alert"/);
  assert.match(h,/GPS/);
  assert.match(h,/data-act="c10_place_create"/);
  assert.match(h,/data-act="closesheet"/);
  assert.match(h,/Setup/);
 });
 await check("validation rejects invalid type, blank, overlong and malformed code",()=>{
  for(const fields of [
   {kind:"factory",name_bn:"",name_en:"",code:""},
   {kind:"factory",name_bn:"OK",name_en:"",code:"UpperCase-!"},
   {kind:"factory",name_bn:"a".repeat(121),name_en:"",code:""},
   {kind:"restaurant",name_bn:"OK",name_en:"",code:""}
  ])assert.equal(site.validate(fields).ok,false);
  assert.equal(site.validate({kind:"godown",name_bn:"Store",name_en:"",code:"depot_1"}).ok,true);
 });
 await check("staff, global Central and wrong business cannot open",()=>{
  let f=fixture();site.install(f.w);f.w.BOS_APP.S.ctx.is_owner=false;
  f.open();assert.equal(f.opened.length,0);
  f.w.BOS_APP.S.ctx.is_owner=true;f.w.BOS.biz.cur=()=>5;
  f.open();assert.equal(f.opened.length,0);
  f.w.BOS.biz.cur=()=>3;f.w.location.href="https://example.test/index.html?workspace=islamia&biz=999";
  f.open();assert.equal(f.opened.length,0);
  f.w.location.href="https://example.test/owner.html?workspace=islamia&biz=3";
  f.w.document.body.dataset.core10Owner="1";
  f.open();assert.equal(f.opened.length,0);
 });
 await check("authorized creation invokes old server RPC, follows locations and shows status",async()=>{
  let f=fixture();assert.equal(site.install(f.w),true);f.open();assert.equal(f.opened.length,1);
  await f.w.BOS_APP.H.c10_place_create();
  assert.equal(f.calls.length,1);
  assert.equal(f.calls[0].name,"business_place_create135");
  assert.deepEqual(f.calls[0].args,{
   p_business:3,p_kind:"factory",p_code:"main_factory",p_name_bn:"কারখানা",p_name_en:"Main Factory",
   p_org_branch:null,p_client:"00000000-0000-4000-8000-000000000001"
  });
  assert.equal(f.closeCount(),1);assert.equal(f.w.location.hash,"#/locations");
  assert.match(f.toast[0],/সেটআপ/);
 });
 await check("preview changes with type, name and automatic code",()=>{
  let f=fixture();site.install(f.w);f.open();f.setKind("godown");
  f.elements.c10_place_bn.value="নতুন স্টোর";f.elements.c10_place_code.value="";
  f.elements.c10_place_form.events.input();
  assert.equal(f.elements.c10_place_preview_name.textContent,"নতুন স্টোর");
  assert.match(f.elements.c10_place_preview_detail.textContent,/স্বয়ংক্রিয় কোড/);
  assert.equal(f.elements.previewIcon.textContent,"▤");
 });
 await check("retry after network error reuses same idempotency UUID",async()=>{
  let f=fixture();site.install(f.w);f.open();let count=0;
  f.w.BOS_APP.sb.rpc=async(name,args)=>{f.calls.push({name,args});if(++count===1)return{error:{message:"network error"}};return{data:{id:51,business_id:3,code:"s_factory"}}};
  await f.w.BOS_APP.H.c10_place_create();assert.match(f.elements.c10_place_error.textContent,/not confirmed/);
  await f.w.BOS_APP.H.c10_place_create();
  assert.equal(f.calls.length,2);assert.equal(f.calls[0].args.p_client,f.calls[1].args.p_client);
  assert.equal(f.closeCount(),1);
 });
 await check("changing payload after error generates a fresh UUID",async()=>{
  let f=fixture();site.install(f.w);f.open();
  f.w.BOS_APP.sb.rpc=async(name,args)=>{f.calls.push({name,args});return{error:{message:"offline"}}};
  await f.w.BOS_APP.H.c10_place_create();f.elements.c10_place_code.value="factory_two";
  await f.w.BOS_APP.H.c10_place_create();
  assert.notEqual(f.calls[0].args.p_client,f.calls[1].args.p_client);
 });
 await check("rapid double-click produces one RPC",async()=>{
  let f=fixture();site.install(f.w);f.open();let complete;
  f.w.BOS_APP.sb.rpc=(name,args)=>{f.calls.push({name,args});return new Promise(resolve=>{complete=resolve})};
  const first=f.w.BOS_APP.H.c10_place_create();
  assert.equal(f.elements.c10_place_submit.disabled,true);
  await f.w.BOS_APP.H.c10_place_create();assert.equal(f.calls.length,1);
  complete({data:{id:57,business_id:3,code:"factory"}});
  await first;assert.equal(f.elements.c10_place_submit.disabled,false);
 });
 await check("foreign business response is not accepted",async()=>{
  let f=fixture();site.install(f.w);f.open();
  f.w.BOS_APP.sb.rpc=async()=>({data:{id:77,business_id:66,code:"foreign"}});
  await f.w.BOS_APP.H.c10_place_create();
  assert.equal(f.closeCount(),0);assert.equal(f.w.location.hash,"#/home");
  assert.match(f.elements.c10_place_error.textContent,/not confirmed/);
 });
 await check("RPC cannot confirm a different site kind or unexpectedly active location",async()=>{
  for(const payload of [{id:88,business_id:3,kind:"godown",status:"setting_up"},{id:89,business_id:3,kind:"factory",status:"active"}]){
   let f=fixture();site.install(f.w);f.open();f.w.BOS_APP.sb.rpc=async()=>({data:payload});
   await f.w.BOS_APP.H.c10_place_create();
   assert.equal(f.closeCount(),0);assert.equal(f.w.location.hash,"#/home");
   assert.equal(f.toast.length,0);assert.match(f.elements.c10_place_error.textContent,/not confirmed/);
  }
 });
 await check("identity switch during await prevents stale navigation",async()=>{
  let f=fixture();site.install(f.w);f.open();let complete;
  f.w.BOS_APP.sb.rpc=()=>new Promise(resolve=>{complete=resolve});
  let inflight=f.w.BOS_APP.H.c10_place_create();
  f.w.BOS_APP.S.ctx.profile.id="other";
  complete({data:{id:83,business_id:3,code:"new"}});
  await inflight;assert.equal(f.closeCount(),0);assert.equal(f.w.location.hash,"#/home");
 });
 await check("closed sheet during await is never accidentally closed or redirected",async()=>{
  let f=fixture();site.install(f.w);f.open();let complete;
  f.w.BOS_APP.sb.rpc=()=>new Promise(resolve=>{complete=resolve});
  let inflight=f.w.BOS_APP.H.c10_place_create();
  f.closeForm();complete({data:{id:99,business_id:3,code:"new"}});
  await inflight;assert.equal(f.closeCount(),0);assert.equal(f.w.location.hash,"#/home");
 });
 await check("stale session RPC failure never leaks an error into the next owner session",async()=>{
  let f=fixture();site.install(f.w);f.open();let finish;
  f.w.BOS_APP.sb.rpc=()=>new Promise(resolve=>{finish=resolve});
  let request=f.w.BOS_APP.H.c10_place_create();
  f.w.BOS_APP.S.ctx.profile.id="other-owner";
  finish({error:{message:"permission denied"}});
  await request;
  assert.equal(f.elements.c10_place_error.hidden,true);
  assert.equal(f.toast.length,0);
 });
 await check("closed sheet or changed route suppresses stale success toast",async()=>{
  for(const change of ["close","route"]){
   let f=fixture();site.install(f.w);f.open();let finish;
   f.w.BOS_APP.sb.rpc=()=>new Promise(resolve=>{finish=resolve});
   let request=f.w.BOS_APP.H.c10_place_create();
   if(change==="close")f.closeForm();else f.w.location.hash="#/inventory";
   finish({data:{id:85,business_id:3,code:"factory"}});
   await request;
   assert.equal(f.toast.length,0);
   assert.equal(f.closeCount(),0);
  }
 });
 await check("business context switch during RPC cannot close sheet, navigate or show a success",async()=>{
  let f=fixture();site.install(f.w);f.open();let finish;
  f.w.BOS_APP.sb.rpc=()=>new Promise(resolve=>{finish=resolve});
  let request=f.w.BOS_APP.H.c10_place_create();
  f.w.BOS.biz.cur=()=>4;
  f.w.location.href="https://example.test/business.html?workspace=business&biz=4";
  f.w.BOS.biz.list=()=>[{id:4,kind:"business",status:"active",name_en:"Paint"}];
  finish({data:{id:86,business_id:3,code:"old_business"}});
  await request;
  assert.equal(f.closeCount(),0);
  assert.equal(f.w.location.hash,"#/home");
  assert.equal(f.toast.length,0);
 });
 await check("business context switch during RPC suppresses old business permission error",async()=>{
  let f=fixture();site.install(f.w);f.open();let finish;
  f.w.BOS_APP.sb.rpc=()=>new Promise(resolve=>{finish=resolve});
  let request=f.w.BOS_APP.H.c10_place_create();
  f.w.BOS.biz.cur=()=>4;
  f.w.location.href="https://example.test/business.html?workspace=business&biz=4";
  f.w.BOS.biz.list=()=>[{id:4,kind:"business",status:"active",name_en:"Paint"}];
  finish({error:{message:"permission denied for business 3"}});
  await request;
  assert.equal(f.elements.c10_place_error.hidden,true);
  assert.equal(f.toast.length,0);
 });
 await check("replaced sheet with same DOM IDs cannot receive old RPC success or error",async()=>{
  for(const outcome of ["success","error"]){
   let f=fixture();site.install(f.w);f.open();let finish;
   f.w.BOS_APP.sb.rpc=()=>new Promise(resolve=>{finish=resolve});
   const pending=f.w.BOS_APP.H.c10_place_create();
   // Simulate a different modal replacing the original DOM nodes while keeping IDs.
   const replacement={events:{},addEventListener(){}};
   const originalGet=f.w.document.getElementById;
   f.w.document.getElementById=id=>id==="c10_place_form"?replacement:originalGet(id);
   finish(outcome==="success"?{data:{id:105,business_id:3,kind:"factory",status:"setting_up"}}:{error:{message:"permission denied"}});
   await pending;
   assert.equal(f.closeCount(),0);assert.equal(f.toast.length,0);
   assert.equal(f.w.location.hash,"#/home");
   assert.equal(f.elements.c10_place_error.hidden,true);
  }
 });
 await check("SG idempotent replay without kind/status cannot certify new creation",async()=>{
  let f=fixture();site.install(f.w);f.open();
  f.w.BOS_APP.sb.rpc=async()=>({data:{dup:true,id:41,business_id:3,code:"old_site",org_unit_id:3}});
  await f.w.BOS_APP.H.c10_place_create();
  assert.equal(f.closeCount(),0);
  assert.equal(f.w.location.hash,"#/home");
  assert.equal(f.toast.length,0);
  assert.match(f.elements.c10_place_error.textContent,/already processed/i);
 });
 await check("never issues direct table writes from creation UI",()=>{
  const s=fs.readFileSync("core10-place-setup.js","utf8");
  assert.doesNotMatch(s,/\.from\s*\(|\.insert\s*\(|\.update\s*\(|\.delete\s*\(/);
  assert.equal((s.match(/\.rpc\("business_place_create135"/g)||[]).length,1);
 });
 console.log("RESULT:",passed,"PASS, 0 FAIL");
}
run().catch(e=>{console.error("FAIL",e);process.exitCode=1});
