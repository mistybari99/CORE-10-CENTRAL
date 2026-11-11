"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const {create,PLACEMENTS,MODES}=require("../core10-control-settings-client.js");
assert.equal(PLACEMENTS.length,4);assert.equal(MODES.length,3);
let user=null,calls=[],lastBusiness=101;
function rpc(name,args){calls.push({name,args});if(name==="read_control_settings_v1"){
 return Promise.resolve({data:{business_id:args.p_business,tenant_id:1,server_authorized:true,
 operationally_certified:false,items:Array.from({length:18},(_,i)=>({
  control_id:"control.item_"+i,group:"other",placement:"central_only",
  local_edit_mode:"central_only",preferred_enabled:false,version:0
 }))},error:null})}
 if(name==="write_control_setting_v1")return Promise.resolve({data:{status:"applied",version:1},error:null});
 if(name==="decide_control_setting_v1")return Promise.resolve({data:{status:"approved"},error:null});
 return Promise.resolve({data:{business_id:args.p_business,items:[]},error:null});
}
const api=create({client:{
 auth:{getUser:async()=>({data:{user},error:null})},
 schema(name){assert.equal(name,"c10_demo");return {
  rpc,
  from(name){assert.equal(name,"businesses");return {
   select(){return this},order(){return this},limit(){return Promise.resolve({data:[{id:101,tenant_id:1,slug:"demo"}],error:null})}
  }}
 }}
}});
(async()=>{
 await assert.rejects(()=>api.listBusinesses(),/AUTHENTICATED_USER_REQUIRED/);
 assert.equal(calls.length,0);
 user={id:"verified-auth-user"};
 assert.equal((await api.listBusinesses())[0].id,101);
 assert.equal((await api.read(101)).items.length,18);
 await assert.rejects(()=>api.read("101x"),/INVALID_BUSINESS_ID/);
 await assert.rejects(()=>api.write(101,{controlId:"unknown",placement:"both",localEditMode:"central_only",
 enabled:true,version:0,requestKey:"abc12345",reason:"valid reason"}),/INVALID_CONTROL_CHANGE/);
 assert.equal(calls.filter(x=>x.name==="write_control_setting_v1").length,0);
 const result=await api.write(101,{controlId:"inventory.count",placement:"both",localEditMode:"central_only",
 enabled:false,version:0,requestKey:"req_auth_test_001",reason:"Owner setting preference"});
 assert.equal(result.status,"applied");
 assert.equal(calls.at(-1).args.p_business,101);
 assert.equal((await api.decide(1,"approve")).status,"approved");
 assert.equal((await api.pending(101)).length,0);
 for(const page of ["core10-control-studio.html","core10-business-controls.html"]){
  const html=fs.readFileSync(path.join(__dirname,"..",page),"utf8");
  assert.match(html,/core10-control-settings-client.js/);assert.match(html,/core10-control-studio.js/);
  assert.match(html,/Content-Security-Policy/);assert.doesNotMatch(html,/unsafe-inline/);
 }
 const ui=fs.readFileSync(path.join(__dirname,"..","core10-control-studio.js"),"utf8");
 assert.match(ui,/read_control_settings|api\.read\(/);
 assert.match(ui,/api\.write\(/);assert.match(ui,/api\.decide\(/);
 assert.match(ui,/server authorization|server-authorized/i);
 const entry=fs.readFileSync(path.join(__dirname,"..","core10-control-studio-entry.js"),"utf8");
 assert.match(entry,/ctx\.is_owner!==true/);assert.match(entry,/B\.biz\.cur\(\)/);
 for(const page of ["index.html","owner.html"])
 assert.match(fs.readFileSync(path.join(__dirname,"..",page),"utf8"),/core10-control-studio-entry.js/);
 console.log("PASS A044 signed-auth adapter, scoped RPC, central/business shared UI navigation and no client-side permission grants");
})().catch(e=>{console.error(e);process.exitCode=1});
