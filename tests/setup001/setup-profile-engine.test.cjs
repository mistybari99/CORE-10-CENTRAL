"use strict";
const {test} = require("node:test");
const assert = require("node:assert/strict");
const engine = require("../../internal/setup001/setup-profile-engine.cjs");
const registry = require("../../internal/setup001/profiles-v1.json");
function draft(override={}) {
  return {industryId:"paint_hardware",profileVersion:1,legalId:4,
    name:"Independent Paint",slug:"independent-paint",brandHex:"#AabbCC",
    mode:"advanced",sites:[{kind:"showroom",label:"Main"}],
    requestedModules:[],...override};
}
function code(fn, expected) {assert.throws(fn,e => e && e.code === expected);}
test("registry certifies 10 distinct family profile contracts but NO module capability",()=>{
  assert.equal(engine.validateRegistry(registry),true);
  assert.equal(registry.profiles.length,10);
  assert.equal(registry.profiles.every(p=>p.release_state==="BLOCKED_UNTIL_CERTIFIED" &&
    p.automatic_modules.length===0 && p.automatic_roles.length===0),true);
});
test("unknown industry and version drift fail closed",()=>{
  code(()=>engine.normalizeDraft(draft({industryId:"not_real"})),"SETUP_UNKNOWN_INDUSTRY");
  code(()=>engine.normalizeDraft(draft({profileVersion:2})),"SETUP_PROFILE_VERSION_MISMATCH");
});
test("all 10 families offer advisory profiles not ready engines",()=>{
  for (const p of registry.profiles) {
    const x=engine.normalizeDraft(draft({industryId:p.industry_id,mode:"quick",sites:[]}));
    assert.equal(x.may_activate,false);assert.equal(x.may_create,false);
    assert.equal(x.recommendations.first_site_kind,p.first_site_hint);
  }
});
test("Quick and Advanced plan share canonical contract; Quick has zero explicit sites",()=>{
  const q=engine.normalizeDraft(draft({mode:"quick",sites:[]}));
  const a=engine.normalizeDraft(draft());
  assert.equal(q.contract,a.contract);
  assert.deepEqual(q.sites,[]);
  assert.equal(a.sites.length,1);
  assert.equal(q.recommendations.mode_does_not_reduce_entitlements,true);
});
test("client cannot add a tenant, owner, role or certification by injected fields",()=>{
  code(()=>engine.normalizeDraft(draft({is_owner:true})),"SETUP_DRAFT_INVALID");
  code(()=>engine.normalizeDraft(draft({tenantId:99})),"SETUP_DRAFT_INVALID");
  code(()=>engine.normalizeDraft(draft({releaseEnabled:true})),"SETUP_DRAFT_INVALID");
  code(()=>engine.normalizeDraft(draft({grant:"finance.post"})),"SETUP_DRAFT_INVALID");
});
test("legal/business identity and names never inferred from label",()=>{
  code(()=>engine.normalizeDraft(draft({legalId:0})),"SETUP_LEGAL_ID_INVALID");
  code(()=>engine.normalizeDraft(draft({legalId:"1.5"})),"SETUP_LEGAL_ID_INVALID");
  code(()=>engine.normalizeDraft(draft({slug:"../IMG"})),"SETUP_SLUG_INVALID");
  code(()=>engine.normalizeDraft(draft({name:"   "})),"SETUP_NAME_INVALID");
  code(()=>engine.normalizeDraft(draft({brandHex:"red"})),"SETUP_BRAND_INVALID");
});
test("site kind, count, casefold duplicate and mode rules",()=>{
  code(()=>engine.normalizeDraft(draft({sites:[]})),"SETUP_SITES_INVALID");
  code(()=>engine.normalizeDraft(draft({mode:"quick",sites:[{kind:"factory",label:"Factory"}]})),"SETUP_SITES_INVALID");
  code(()=>engine.normalizeDraft(draft({sites:[{kind:"unknown",label:"Main"}]})),"SETUP_SITE_INVALID");
  code(()=>engine.normalizeDraft(draft({sites:[{kind:"showroom",label:"Main"},{kind:"showroom",label:"main"}]})),"SETUP_SITE_DUPLICATE");
  code(()=>engine.normalizeDraft(draft({sites:[{kind:"showroom",label:"M",id:100}]})),"SETUP_SITE_INVALID");
});
test("303-site fixture covers 100/100/100 and three projects without assuming live performance",()=>{
  const sites=engine.make303SiteFixture();
  assert.equal(sites.length,303);
  for (const kind of ["showroom","factory","godown"]) assert.equal(sites.filter(s=>s.kind===kind).length,100);
  assert.equal(engine.normalizeDraft(draft({sites})).sites.length,303);
  code(()=>engine.normalizeDraft(draft({sites:Array.from({length:501},(_,i)=>({kind:"showroom",label:"S"+i}))})),"SETUP_SITES_INVALID");
});
test("requested modules not auto-applied, even if caller asks for finance",()=>{
  const x=engine.normalizeDraft(draft({requestedModules:["finance","sales"]}));
  assert.deepEqual(x.requested_modules,["finance","sales"]);
  assert.equal(x.may_create,false);
  code(()=>engine.normalizeDraft(draft({requestedModules:["finance","finance"]})),"SETUP_MODULES_INVALID");
  code(()=>engine.normalizeDraft(draft({requestedModules:["finance",123]})),"SETUP_MODULES_INVALID");
});
test("locale and tax jurisdiction remain explicit unapproved inputs",()=>{
  const x=engine.normalizeDraft(draft({localeCode:"bn-BD",jurisdictionCode:"BD"}));
  assert.equal(x.locale_code,"bn-BD");
  assert.equal(x.jurisdiction_code,"BD");
  assert.equal(x.may_activate,false);
  code(()=>engine.normalizeDraft(draft({jurisdictionCode:"100% VAT"})),"SETUP_JURISDICTION_INVALID");
  code(()=>engine.normalizeDraft(draft({localeCode:"Bangla"})),"SETUP_LOCALE_INVALID");
});
test("Build01 adapter uses only explicit signed-context candidate and immutable supplied replay key",()=>{
  const plan=engine.normalizeDraft(draft());
  const ctx={legal_entities:[{id:4}],templates:[{industry_id:"paint_hardware",code:"paint_hardware",source_status:"not_implemented",draft_supported:true}]};
  const r=engine.toBuild01Request(plan,ctx,"build04_request_01234567");
  assert.equal(r.template,"paint_hardware");
  assert.equal(r.legalId,4);
  assert.deepEqual(Object.keys(r).sort(),["legalId","slug","template","displayName","mode","sites","requestKey","brandHex"].sort());
});
test("Build01 adapter blocks foreign legal, unready template, forged context and invalid replay key",()=>{
  const plan=engine.normalizeDraft(draft());
  const ctx={legal_entities:[{id:4}],templates:[{industry_id:"paint_hardware",code:"paint_hardware",source_status:"not_implemented",draft_supported:true}]};
  code(()=>engine.toBuild01Request(plan,{...ctx,legal_entities:[{id:5}]},"build04_request_01234567"),"SETUP_CONTEXT_LEGAL_NOT_PRESENT");
  code(()=>engine.toBuild01Request(plan,{...ctx,templates:[{industry_id:"paint_hardware",code:"paint_hardware",source_status:"not_implemented",draft_supported:false}]},"build04_request_01234567"),"SETUP_CONTEXT_TEMPLATE_UNAVAILABLE");
  code(()=>engine.toBuild01Request(plan,{...ctx,is_owner:true},"build04_request_01234567"),"SETUP_CONTEXT_INVALID");
  code(()=>engine.toBuild01Request(plan,ctx,"short"),"SETUP_REQUEST_KEY_INVALID");
});
test("activation gate never self-certifies: all self-reported checks are NOT signed evidence",()=>{
  const yes=Object.fromEntries(engine.GATES.map(k=>[k,true]));
  const all=engine.assessActivation(yes);
  assert.equal(all.missing.length,0);
  assert.equal(all.certified,false);
  assert.equal(all.can_activate,false);
  assert.equal(all.checks.every(x=>x.status==="REPORTED_UNVERIFIED"),true);
  const none=engine.assessActivation({});
  assert.equal(none.missing.length,engine.GATES.length);
  code(()=>engine.assessActivation({signed:true}),"SETUP_EVIDENCE_INVALID");
});
test("legacy import dry-run refuses other business, missing target, duplicate source",()=>{
  const r=engine.legacyImportPreview([
    {legacy_id:"IMG-M",business_id:10,target_site_id:1,label:"Main"},
    {legacy_id:"IMG-2",business_id:20,target_site_id:2,label:"Second"},
    {legacy_id:"IMG-3",business_id:10,target_site_id:999,label:"Third"},
    {legacy_id:"IMG-M",business_id:10,target_site_id:1,label:"Duplicate"},
    {legacy_id:"IMG-4",business_id:10,target_site_id:null,label:"Unknown"}
  ],10,[1,2]);
  assert.deepEqual(r.results.map(x=>x.status),[
    "MAPPED_ID_REVIEW_REQUIRED","BLOCKED_FOREIGN_BUSINESS",
    "BLOCKED_UNKNOWN_TARGET_ID","BLOCKED_DUPLICATE_SOURCE",
    "UNMAPPED_NEEDS_EXPLICIT_CROSSWALK"]);
  assert.equal(r.can_import,false);assert.equal(r.write_count,0);
});
test("registry tampering and profile 'ready' claim fail",()=>{
  const bad=structuredClone(registry);
  bad.profiles[0].release_state="READY";
  code(()=>engine.validateRegistry(bad),"SETUP_PROFILE_INVALID");
  const bad2=structuredClone(registry);
  bad2.profiles[2].industry_id=bad2.profiles[1].industry_id;
  code(()=>engine.validateRegistry(bad2),"SETUP_PROFILE_INVALID");
});
