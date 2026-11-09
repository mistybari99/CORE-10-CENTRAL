// CORE 10 / SECURITY: two-pass owner inbox contract smoke suite.
// Run from repo root: node tests/core10-owner-inbox-smoke.js
// Mock/UI tests only. NOT a substitute for production RLS or authenticated RPC tests.
"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const source=fs.readFileSync(path.join(__dirname,"..","core10-owner-inbox.js"),"utf8");
function harness(mode,reply){
 const calls=[],location={
  hash:mode==="master"?"#/organization":"#/home",
  search:mode==="master"?"":"?workspace=islamia&biz=1",
  href:"https://example.test/"+(mode==="master"?"owner.html":"index.html")
 };
 const host={isConnected:true,child:null,innerHTML:"",
  querySelector(s){return s===".c10-inbox"?this.child:s===".ph-master-actions"||s===".bo-attention-head"?this.anchor:null},
  insertBefore(el){this.child=el},appendChild(el){this.child=el}};
 host.anchor={insertAdjacentElement(_pos,el){host.child=el}};
 const document={
  body:{dataset:mode==="master"?{core10Owner:"1"}:{}},
  head:{appendChild(){}},addEventListener(){},
  createElement(){return {className:"",innerHTML:"",isConnected:true}},
  querySelector(s){
   if(mode==="master"&&s==="#ph_overview")return host;
   if(mode!=="master"&&s===".bo-attention")return host;
   return null
  }
 };
 const app={S:{ctx:{is_owner:mode!=="staff"},lang:"bn"},H:{},
  sb:{rpc(name,args){calls.push({name,args});return Promise.resolve(reply)}}};
 const biz={list:()=>[{id:1,name_bn:"Islamia"},{id:2,name_bn:"Paint"}],cur:()=>1};
 const win={location,BOS_APP:app,BOS:{biz},addEventListener(){}};
 vm.runInNewContext(source,{window:win,document,location,MutationObserver:undefined,Promise,Array,Set,Map,Number,console});
 return {calls,node:()=>host.child,api:win.CORE10_OWNER_INBOX};
}
async function settle(){await new Promise(r=>setImmediate(r))}
function valid(){
 return {certified:true,scope:"owner",business_id:1,
  items:[{id:"entry:123",business_id:1,request_type:"stock",
   title:"Islamia stock",status:"pending",created_at:"2026-11-09T10:00:00Z"}]}
}
async function audit(round){
 const one=harness("business",{data:valid()});
 const all=harness("master",{data:{...valid(),business_id:null,
  items:[...valid().items,{id:"entry:124",business_id:2,
   request_type:"stock",title:"Paint stock",status:"pending"}]}});
 const foreign=harness("business",{data:{...valid(),items:[
  {...valid().items[0],business_id:2,title:"Paint confidential"}]}});
 const missing=harness("business",{error:{code:"PGRST202"}});
 const staff=harness("staff",{data:valid()});
 await settle();
 assert.equal(one.calls[0].name,"core10_owner_inbox_v1");
 assert.equal(one.calls[0].args.p_business_id,1);
 assert.match(one.node().innerHTML,/Islamia stock/);
 assert.equal(all.calls[0].args.p_business_id,null);
 assert.match(all.node().innerHTML,/Paint stock/);
 assert.doesNotMatch(foreign.node().innerHTML,/Paint confidential/);
 assert.match(foreign.node().innerHTML,/Scope যাচাই ব্যর্থ/);
 assert.match(missing.node().innerHTML,/প্রস্তুত নয়/);
 assert.equal(staff.calls.length,0);
 const test=one.api.validate;
 const sc={kind:"business",id:1};
 assert.equal(test({...valid(),items:Array.from({length:41},(_,i)=>(
  {id:"entry:"+i,business_id:1,title:"x",request_type:"entry",status:"pending"}
 ))},sc),null);
 assert.equal(test({...valid(),items:[{...valid().items[0],business_id:"1"}]},sc),null);
 assert.equal(test({...valid(),items:[{...valid().items[0],business_id:2}]},sc),null);
 assert.equal(test({...valid(),items:[valid().items[0],valid().items[0]]},sc),null);
 assert.equal(test({...valid(),items:[{...valid().items[0],id:"<evil>"}]},sc),null);
 assert.equal(test({...valid(),items:[{...valid().items[0],title:""}]},sc),null);
 assert.equal(test({...valid(),items:[{...valid().items[0],status:"approved"}]},sc),null);
 assert.equal(test({...valid(),certified:false},sc),null);
 assert.equal(test({...valid(),business_id:2},sc),null);
 console.log("PASS: Auditor A+B, validation round "+round);
}
(async()=>{await audit(1);await audit(2)})().catch(e=>{console.error(e);process.exitCode=1});
