"use strict";
const assert=require("node:assert/strict");
const catalog=require("../data/core10_capability_catalog_v1.json");
const {analyzeLegacyEntitySnapshot:analyze}=require("../core10-entity-compatibility.js");
const clone=x=>JSON.parse(JSON.stringify(x));
function fixture(){
  const org_units=[
    {id:1,parent_id:null,kind:"group",client_id:null},
    {id:2,parent_id:1,kind:"legal_entity",client_id:null},
    {id:3,parent_id:2,kind:"business",template_code:"food_manufacturing",client_id:null},
    {id:4,parent_id:1,kind:"legal_entity",client_id:"synthetic-second-entity"}
  ];
  const kinds=["showroom","showroom","showroom","showroom","factory","factory","godown","factory"];
  return {org_units,locations:kinds.map((kind,i)=>({id:i+1,code:"loc_"+(i+1),kind,org_unit_id:3})),
    business_profiles:[{org_unit_id:3}],business_templates:[
      {code:"food_manufacturing",status:"available"},
      {code:"hardware_paint",status:"not_implemented"}]};
}
const run=x=>analyze(x,catalog);
function baseline(){
  const s=fixture(),original=JSON.stringify(s),r=run(s);
  assert.equal(r.ok,true,r.errors.join(","));
  assert.equal(r.summary.legacy_direct_locations,8);
  assert.equal(r.summary.explicit_site_locations,0);
  assert.equal(r.mappings.length,8);
  assert.deepEqual(r.mappings.map(m=>m.legacy_location_id),s.locations.map(l=>l.id));
  assert.ok(r.mappings.every(m=>m.business_id===3&&m.legal_entity_id===2&&m.legacy_group_id===1));
  assert.ok(r.mappings.every(m=>m.operating_site_id===null&&m.tenant_id===null&&m.platform_id===null));
  assert.ok(r.warnings.includes("OPERATING_SITE_LAYER_MISSING:8"));
  assert.equal(r.certifications.release_ready,false);
  assert.equal(r.certifications.tenant_isolation_verified,false);
  assert.equal(JSON.stringify(s),original,"No input may be mutated");
  console.log("PASS A018: eight synthetic legacy locations retain identifiers; absent sites/tenants are NOT invented");
}
function explicitSite(){
  const s=fixture();
  s.org_units.push({id:5,parent_id:3,kind:"operating_site"});
  s.locations[0].org_unit_id=5;
  const r=run(s);
  assert.equal(r.ok,true,r.errors.join(","));
  assert.equal(r.mappings[0].operating_site_id,"5");
  assert.equal(r.mappings[0].legacy_location_id,1);
  assert.equal(r.summary.legacy_direct_locations,7);
  assert.equal(r.summary.explicit_site_locations,1);
  console.log("PASS A018: explicit site ancestry resolved with stable stock location IDs");
}
function reject(label,mutator,code){
  const s=fixture();mutator(s);const r=run(s);
  assert.equal(r.ok,false,label+" unexpectedly accepted");
  assert.equal(r.mappings.length,0,label+" must fail closed without partial mappings");
  assert.ok(r.errors.some(e=>e.startsWith(code)),label+" missing "+code+": "+r.errors.join(","));
}
function negatives(){
  reject("orphan location",s=>s.locations[0].org_unit_id=999,"UNMAPPED_LOCATION:");
  reject("duplicate location",s=>s.locations[1].id=s.locations[0].id,"DUPLICATE_LOCATION_ID:");
  reject("duplicate org",s=>s.org_units.push(clone(s.org_units[2])),"DUPLICATE_ORG_ID:");
  reject("wrong parent",s=>s.org_units[2].parent_id=1,"INVALID_PARENT:");
  reject("self parent",s=>s.org_units[2].parent_id=3,"INVALID_PARENT:");
  reject("unknown org kind",s=>s.org_units[2].kind="unreviewed_kind","UNKNOWN_ORG_KIND:");
  reject("profile linked to legal",s=>s.business_profiles[0].org_unit_id=2,"PROFILE_NOT_BUSINESS:");
  reject("duplicate profile",s=>s.business_profiles.push({org_unit_id:3}),"DUPLICATE_BUSINESS_PROFILE:");
  reject("unknown business template",s=>s.org_units[2].template_code="unregistered","UNREGISTERED_BUSINESS_TEMPLATE:");
  reject("unknown source template",s=>{s.business_templates.push({code:"not_in_catalog",status:"available"});s.org_units[2].template_code="not_in_catalog"},"UNREGISTERED_BUSINESS_TEMPLATE:");
  reject("client mismatch",s=>{s.org_units[1].client_id="client_a";s.org_units[2].client_id="client_b"},"CROSS_CLIENT_PARENT:");
  reject("location points to group",s=>s.locations[0].org_unit_id=1,"LOCATION_PARENT_NOT_SITE_OR_BUSINESS:");
  assert.equal(run(null).ok,false);
  assert.equal(analyze(fixture(),{}).ok,false);
  console.log("PASS A018: invalid ancestry, orphan/duplicate IDs, incompatible templates and client conflicts rejected");
}
function driftAndScale(){
  const drift=fixture();
  drift.business_templates[0].status="needs_setup";
  const result=run(drift);
  assert.equal(result.ok,true);
  assert.ok(result.warnings.includes("TEMPLATE_STATUS_DRIFT:food_manufacturing"));
  assert.equal(result.certifications.release_ready,false);
  const many=fixture();
  many.locations=Array.from({length:305},(_,i)=>({id:10000+i,code:"l"+i,kind:"showroom",org_unit_id:3}));
  const scaled=run(many);
  assert.equal(scaled.ok,true,scaled.errors.join(","));
  assert.equal(scaled.mappings.length,305);
  assert.equal(scaled.certifications.scale_measured,false);
  console.log("PASS A018: 305-node structural fixture has no arbitrary ceiling; NOT a live load/capacity certification");
}
baseline();explicitSite();negatives();driftAndScale();
console.log("PASS: C10-A018 entity compatibility PRE-FLIGHT ONLY. No production DB, RLS, RPC, merge or deployment.");
