"use strict";
const assert=require("node:assert/strict");
const catalog=require("../data/core10_capability_catalog_v1.json");
const {planBusinessSetup}=require("../core10-business-template-planner.js");
const base={tenant_id:"tenant-1",business_name:"Islamia",template_id:"sweets_bakery",mode:"quick",modules:["stock"],sites:[{client_key:"main",name:"Main",kind:"branch"}]};
const good=planBusinessSetup(catalog,base);
assert.equal(good.ok,true);
assert.equal(good.plan.executable,false);
assert.equal(good.plan.requires_authenticated_backend,true);
assert.equal(good.plan.requires_atomic_idempotent_provisioning,true);
assert.equal(good.plan.canonical_hierarchy.length,6);
assert.equal(planBusinessSetup(catalog,{...base,template_id:"unknown"}).ok,false);
assert.equal(planBusinessSetup(catalog,{...base,modules:["super_admin"]}).ok,false);
assert.equal(planBusinessSetup(catalog,{...base,sites:[base.sites[0],base.sites[0]]}).ok,false);
assert.equal(planBusinessSetup(catalog,{...base,tenant_id:""}).ok,false);
assert.equal(planBusinessSetup(catalog,{...base,mode:"advanced",sites:Array.from({length:301},(_,i)=>({client_key:"site-"+i,name:"Site "+i,kind:"warehouse"}))}).ok,true);
for(const t of catalog.templates){
  const p=planBusinessSetup(catalog,{...base,template_id:t.id,modules:[]});
  assert.equal(p.ok,true,t.id);
  assert.equal(p.plan.executable,false,t.id);
}
console.log("A018 business template planning contracts PASS");
