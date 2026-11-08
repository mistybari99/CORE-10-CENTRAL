// CORE 10 UI smoke tests. Run from repository root: node tests/core10-shell-smoke.js
// Deliberately tests the UI boundary; database RLS requires its own authenticated integration tests.
"use strict";
const fs=require("fs"),vm=require("vm"),assert=require("node:assert/strict"),path=require("path");
const source=fs.readFileSync(path.join(__dirname,"..","core10-shell.js"),"utf8");
function session(owner,assigned,cur){
 let id=cur;
 const rows=[{id:11,org_unit_id:101},{id:12,org_unit_id:102}];
 const businesses=[{id:1,name_bn:"Islamia"},{id:2,name_bn:"Paint"}];
 const ctx={is_owner:owner,locations:assigned};
 const app={S:{ctx,lang:"bn"},H:{}};
 const env={};
 Object.defineProperty(env,"locs",{configurable:true,get(){return rows},set(_){}});
 Object.defineProperty(env,"locsAll",{configurable:true,get(){return rows}});
 const bos={ENV:env,biz:{brand(){return id===1?{bn:"Islamia",en:"Islamia"}:{bn:"Paint",en:"Paint"}},brandFor(){return {bn:"Place",en:"Place"}},list(){return businesses},cur(){return id},setCur(x){id=Number(x);return true},switcherHTML(){return "<select>ALL</select>"},multi(){return true},isAll(){return false},locBizId(loc){return loc.org_unit_id===101?1:2}},ia:{visible(){return true}}};
 const mockDoc={body:null,title:"",head:{appendChild(){}},createElement(){return {setAttribute(){},style:{}}},addEventListener(){},querySelectorAll(){return []},querySelector(){return null}};
 const win={BOS:bos,BOS_APP:app,BOS_LAZY:{load(){return Promise.resolve()}},BOS_PAGES:{organization(){return true}},BOS_PORTFOLIO:{render(){return true}},addEventListener(){}};
 const context={window:win,document:mockDoc,location:{hash:"#/home"},console,Promise,Set,Number,Array};
 vm.runInNewContext(source,context,{filename:"core10-shell.js"});
 return {bos,win,id:()=>id,app};
}
let s=session(false,[11],2);
assert.deepEqual(Array.from(s.bos.biz.list(),x=>x.id),[1]);
assert.deepEqual(Array.from(s.bos.ENV.locsAll,x=>x.id),[11]);
assert.equal(s.bos.biz.switcherHTML(),"");
assert.equal(s.bos.ia.visible({route:"organization"}),false);
assert.equal(s.bos.biz.setCur(2),false);
assert.equal(s.bos.biz.brand().en,"Islamia");
let orphan=session(false,[],2);
assert.equal(orphan.bos.biz.list().length,0);
assert.equal(orphan.bos.biz.brand().en,"Your Business");
let owner=session(true,[],1);
assert.deepEqual(Array.from(owner.bos.biz.list(),x=>x.id),[1,2]);
assert.equal(owner.bos.ENV.locsAll.length,2);
assert.match(owner.bos.biz.switcherHTML(),/ALL/);
assert.equal(owner.bos.ia.visible({route:"organization"}),true);
console.log("PASS: owner, authorized Islamia staff, and unassigned staff UI smoke tests");
