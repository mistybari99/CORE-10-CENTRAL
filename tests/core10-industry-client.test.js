"use strict";
const assert=require("node:assert/strict");
const catalog=require("../data/core10_capability_catalog_v1.json");
const api=require("../core10-industry-client.js");
const base={name:"Demo Business",slug:"demo-business",templateId:"sweets_bakery",brandHex:"#7C263A",mode:"advanced",
  sites:[{kind:"showroom",label:"Main"},{kind:"factory",label:"Cake factory"}],modules:["stock"]};
const ctx={legalId:11,requestKey:"replay-key-001"};
assert.equal(api.validate(catalog,base,ctx).p_template_id,"sweets_bakery");
for(const t of catalog.templates){
 assert.equal(api.validate(catalog,{...base,templateId:t.id,modules:t.modules.slice(0,1).map(m=>m.id)},ctx).p_template_id,t.id);
}
assert.throws(()=>api.validate(catalog,{...base,templateId:"surprise"},ctx),/UNKNOWN_TEMPLATE/);
assert.throws(()=>api.validate(catalog,{...base,modules:["root"]},ctx),/INVALID_MODULES/);
assert.throws(()=>api.validate(catalog,{...base,modules:["stock","stock"]},ctx),/INVALID_MODULES/);
assert.throws(()=>api.validate(catalog,{...base,sites:[base.sites[0],base.sites[0]]},ctx),/DUPLICATE_SITE/);
assert.throws(()=>api.validate(catalog,{...base,mode:"quick"},ctx),/QUICK_SITES_MUST_BE_EMPTY/);
assert.throws(()=>api.validate(catalog,base,{...ctx,legalId:0}),/LEGAL_ID_REQUIRED/);
assert.equal(api.validate(catalog,{...base,sites:Array.from({length:303},(_,i)=>({kind:"warehouse",label:"Site "+i}))},ctx).p_sites.length,303);
let called=0;
const client={auth:{getUser:async()=>({data:{user:{id:"signed-owner-id"}}})},schema:()=>({
 rpc:async(name,payload)=>{called++;assert.equal(name,"setup_industry_draft_v2");assert.equal(payload.p_template_id,"sweets_bakery");return{data:901}},
 from:()=>({select:()=>({order:async()=>({data:[{id:"sweets_bakery"}]})})})
})};
async function main(){
 const locked=api.create({client,catalog});
 await assert.rejects(()=>locked.setupDraft(base,ctx),/DRAFT_PROVISIONING_RELEASE_LOCKED/);
 assert.equal(locked.status().productionCertified,false);
 const stage=api.create({client,catalog,stagingEnabled:true,draftWritesEnabled:true});
 const rows=await stage.listTemplates();assert.equal(rows.length,1);
 const result=await stage.setupDraft(base,ctx);
 assert.deepEqual(result,{business_id:901,setup_status:"draft",operational_enabled:false});
 assert.equal(called,1);
 const anon={...client,auth:{getUser:async()=>({data:{user:null}})}};
 await assert.rejects(()=>api.create({client:anon,catalog,stagingEnabled:true,draftWritesEnabled:true}).setupDraft(base,ctx),/AUTHENTICATED_USER_REQUIRED/);
 assert.equal(called,1);
 console.log("PASS: 10 templates, signed-user RPC, locked releases, 303 sites, role-denied session");
}
main().catch(e=>{console.error(e);process.exitCode=1});
