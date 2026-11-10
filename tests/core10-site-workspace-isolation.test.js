"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),vm=require("node:vm");
const source=fs.readFileSync(path.join(__dirname,"..","core10-site-workspace.js"),"utf8");
function boot(search){
 const listeners={};let observed=false,appended=0;
 const host={appendChild(){appended++},querySelector(){return null}};
 const document={readyState:"complete",body:{},getElementById(id){return id==="ph_overview"?host:null},createElement(){return {dataset:{}}},addEventListener(){}};
 const window={document,location:{search},BOS_APP:{S:{ctx:{is_owner:true},lang:"bn"}},BOS:{ENV:{locsAll:[{id:1,name_en:"Sensitive Other Business"}]}},addEventListener(name,fn){listeners[name]=fn}};
 const context={window,MutationObserver:class{observe(){observed=true}},Promise};
 vm.runInNewContext(source,context,{filename:"core10-site-workspace.js"});
 return {appended,observed};
}
test("P0: default portfolio does not render unscoped location feed",()=>assert.equal(boot("").appended,0));
test("P0: business query flag cannot authorize unscoped location feed",()=>assert.equal(boot("?workspace=business").appended,0));
test("P0: unrelated workspace flag cannot bypass fail-closed",()=>assert.equal(boot("?workspace=anything").appended,0));
