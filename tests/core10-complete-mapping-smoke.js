// CORE 10 / SECURITY: assigned-location completion gate test.
// Run from repo root: node tests/core10-complete-mapping-smoke.js
// Do not interpret a frontend result as RLS certification.
"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const source=fs.readFileSync(path.join(__dirname,"..","core10-shell.js"),"utf8");
function make(assigned=[11,12],owner=false){
 const pending=new Map,ctx={is_owner:owner,profile:{id:owner?"owner":"staff"},locations:assigned};
 let current=2;const rows=[{id:11},{id:12}];
 const env={};
 Object.defineProperty(env,"locs",{configurable:true,get:()=>rows,set(){}});
 Object.defineProperty(env,"locsAll",{configurable:true,get:()=>rows});
 const businesses=[{id:1,name_en:"Islamia"},{id:2,name_en:"Paint"}];
 const biz={
  brand:()=>current===1?{bn:"Islamia",en:"Islamia"}:{bn:"Paint",en:"Paint"},
  brandFor:()=>({bn:"Place",en:"Place"}),list:()=>businesses,
  cur:()=>current,setCur:id=>(current=Number(id),true),
  switcherHTML:()=>"<select>ALL</select>",multi:()=>true,isAll:()=>false
 };
 const B={ENV:env,biz,ia:{visible:()=>true},loadStatic:async()=>true};
 const A={S:{ctx},H:{},sb:{rpc(name,arg){
  assert.equal(name,"org_unit_scope");
  const id=arg.p_location;
  return new Promise(resolve=>{if(!pending.has(id))pending.set(id,[]);pending.get(id).push(resolve)})
 }}};
 const loc={hash:"#/home",href:"https://example.test/index.html",search:"",replace(){}};
 const doc={body:null,title:"",head:{appendChild(){}},createElement:()=>({style:{},setAttribute(){}}),
  addEventListener(){},querySelectorAll:()=>[],querySelector:()=>null,getElementById:()=>null};
 const win={BOS:B,BOS_APP:A,BOS_LAZY:{load:()=>Promise.resolve()},BOS_PAGES:{organization:()=>{}},location:loc,addEventListener(){},dispatchEvent(){}};
 vm.runInNewContext(source,{window:win,document:doc,location:loc,Promise,Map,Set,Number,Array,Event,console});
 return {B,A,ctx,pending,visible:()=>env.locs.map(x=>x.id),options:()=>biz.list().map(x=>x.id),
  answer(id,result){(pending.get(id)||[]).forEach(resolve=>resolve(result));pending.delete(id)}};
}
const tick=async()=>{await new Promise(resolve=>setImmediate(resolve))};
async function audit(round){
 const s=make(),original=s.options();
 assert.equal(original.length,0);
 assert.deepEqual(s.visible(),[]);
 await tick();
 // Verify in opposite order between the two independent audit rounds.
 const first=round===1?11:12,second=first===11?12:11;
 s.answer(first,{data:{mapped:true,business_id:1}});await tick();
 assert.deepEqual(s.visible(),[]);assert.deepEqual(s.options(),[]);
 s.answer(second,{data:{mapped:true,business_id:1}});await tick();
 assert.deepEqual(s.visible(),[11,12]);assert.deepEqual(s.options(),[1]);
 s.ctx.locations=[11];
 assert.deepEqual(s.options(),[]);assert.deepEqual(s.visible(),[]);
 await tick();s.answer(11,{data:{mapped:true,business_id:1}});await tick();
 assert.deepEqual(s.visible(),[11]);
 const conflict=make();assert.deepEqual(conflict.options(),[]);await tick();
 conflict.answer(11,{data:{mapped:true,business_id:1}});
 conflict.answer(12,{data:{mapped:true,business_id:2}});await tick();
 assert.deepEqual(conflict.options(),[]);assert.deepEqual(conflict.visible(),[]);
 const missing=make();missing.options();await tick();
 missing.answer(11,{data:{mapped:true,business_id:1}});
 missing.answer(12,{error:{message:"Denied"}});await tick();
 assert.deepEqual(missing.visible(),[]);assert.deepEqual(missing.options(),[]);
 const master=make([],true);
 assert.deepEqual(master.options(),[1,2]);assert.deepEqual(master.visible(),[11,12]);
 console.log("PASS: complete staff mapping and owner permissions round "+round)
}
(async()=>{await audit(1);await audit(2)})().catch(e=>{console.error(e);process.exitCode=1});
