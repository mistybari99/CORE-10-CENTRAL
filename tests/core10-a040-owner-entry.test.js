"use strict";
// C10-A040 Owner Workspace navigation; DOM visibility is NOT backend stock permission.
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const code=fs.readFileSync(path.resolve(__dirname,"../core10-owner-business-entry.js"),"utf8");
const html=fs.readFileSync(path.resolve(__dirname,"../owner.html"),"utf8");
assert.match(html,/src="core10-owner-business-entry\.js/);
assert.ok(!html.includes('src="core10-stocktake-preview.js"'));
const ids=new Map(),events=new Map();
let observer=null,observed=false,frames=0;
const header={children:[],appendChild(a){
 if(ids.has(a.id))throw Error("DUPLICATE_LINK:"+a.id);
 a.parent=this;this.children.push(a);ids.set(a.id,a);
}};
const app={querySelector(sel){assert.equal(sel,"header.top");return header}};
function createElement(tag){return{tag,style:{cssText:""},attrs:{},setAttribute(k,v){this.attrs[k]=v},
 remove(){ids.delete(this.id);if(this.parent)this.parent.children=this.parent.children.filter(x=>x!==this)}}}
let state={S:{ctx:null}};
const document={body:{dataset:{core10Owner:"1"}},getElementById(id){return id==="app"?app:ids.get(id)||null},createElement};
const window={BOS_APP:state,addEventListener(event,cb){events.set(event,cb)}};
function MutationObserver(cb){observer=cb;this.observe=(target,opts)=>{
 assert.equal(target,app);assert.equal(opts.subtree,true);observed=true}}
vm.runInNewContext(code,{document,window,MutationObserver,requestAnimationFrame(cb){frames++;cb()}},
 {filename:"core10-owner-business-entry.js"});
assert.ok(observed);
assert.equal(ids.size,0);
function update(ctx){state.S.ctx=ctx;observer()}
update({is_owner:false});assert.equal(ids.size,0);
update({is_owner:"true"});assert.equal(ids.size,0,"owner must be boolean true");
update({is_owner:true});
assert.equal(ids.size,2);
const builder=ids.get("core10-owner-create-business"),take=ids.get("core10-owner-stocktake-preview");
assert.ok(builder&&take);
assert.equal(builder.href,"./core10-business-builder.html");
assert.equal(take.href,"./core10-stocktake-preview.html");
assert.equal(take.attrs["data-preview-only"],"true");
assert.match(take.attrs["aria-label"],/no real stock changes/);
observer();events.get("hashchange")();assert.equal(ids.size,2,"no duplicate links on repeated render");
update({is_owner:false});assert.equal(ids.size,0,"logout must remove both links");
update({is_owner:true});assert.equal(ids.size,2);
update(null);assert.equal(ids.size,0);
assert.ok(frames>=5);
console.log("PASS A040 Owner entry link: signed role visibility, builder preserved, logout revocation, no duplication, demo-only destination");
