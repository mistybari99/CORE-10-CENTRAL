"use strict";
/* C10-A019 — SG read-only canonical-scope/RLS compatibility gate.
 * Does not connect to production, alter RLS, or certify Supabase Auth.
 * Postgres RLS SELECT semantics: (OR of permissive policies)
 * AND (AND of restrictive policies), for every applicable policy.
 * Do not call a sole is_active() permissive SELECT a confirmed data leak
 * when a restrictive SELECT policy also applies.
 */
const REQUIRED_RLS = ["org_units","locations","items","business_profiles","business_templates","user_locations"];
const REQUIRED_COLS = {
  org_units:{id:"int8",parent_id:"int8",kind:"text",template_code:"text",client_id:"uuid"},
  locations:{id:"int4",org_unit_id:"int8",kind:"text",code:"text"}
};
function object(v){return v!==null&&typeof v==="object"&&!Array.isArray(v)}
function id(v){const s=String(v==null?"":v);return /^[1-9][0-9]*$/.test(s)?s:null}
function inspect(snapshot, legacy){
  const errors=[],blockers=[],observed={};
  function fatal(s){if(!errors.includes(s))errors.push(s)}
  function block(s){if(!blockers.includes(s))blockers.push(s)}
  if(!object(snapshot)||snapshot.schema_version!==1||snapshot.source!=="IMG-ERP-SG"||
      snapshot.read_only!==true||snapshot.contains_personal_data!==false){
    return {ok:false,errors:["INVALID_READONLY_SG_SNAPSHOT"],blockers:["MANUAL_REVIEW_REQUIRED"],observed,release_ready:false};
  }
  if(!object(legacy)||!Array.isArray(legacy.locations)||!Array.isArray(legacy.org_units)||
     !Array.isArray(snapshot.locations)||!Array.isArray(snapshot.org_units)||
     !Array.isArray(snapshot.policies)||!Array.isArray(snapshot.rls)||
     !Array.isArray(snapshot.functions)||!Array.isArray(snapshot.columns)||
     !object(snapshot.foreign_key_refs)){
    return {ok:false,errors:["INVALID_LEGACY_OR_CURRENT_SHAPE"],blockers:["MANUAL_REVIEW_REQUIRED"],observed,release_ready:false};
  }
  // This is an intentionally sanitized public fixture; raw auth/customer identifiers
  // and policy source bodies must NEVER be copied into the test asset.
  const forbidden=/"(?:client_id|user_id|user_metadata|email|raw_uuid|policy_sql|qual|with_check)"\s*:/i;
  if(forbidden.test(JSON.stringify(snapshot)))fatal("UNSANITIZED_SNAPSHOT");
  const org=new Map(),loc=new Map();
  for(const n of snapshot.org_units){
    const k=object(n)&&id(n.id);
    if(!k){fatal("INVALID_ORG_ID");continue}
    if(org.has(k))fatal("DUPLICATE_ORG_ID:"+k);
    org.set(k,n);
  }
  for(const n of snapshot.locations){
    const k=object(n)&&id(n.id);
    if(!k){fatal("INVALID_LOCATION_ID");continue}
    if(loc.has(k))fatal("DUPLICATE_LOCATION_ID:"+k);
    loc.set(k,n);
    if(n.code_present!==true)fatal("MISSING_LOCATION_CODE:"+k);
    if(!org.has(id(n.org_unit_id)))fatal("ORPHAN_LOCATION:"+k);
  }
  const baselineLocations=new Set();
  for(const n of legacy.locations){
    const k=object(n)&&id(n.id);
    if(!k){fatal("INVALID_BASELINE_LOCATION");continue}
    baselineLocations.add(k);
    const now=loc.get(k);
    if(!now){fatal("LEGACY_LOCATION_ID_LOST:"+k);continue}
    // Reparenting may be legitimate later, but must be backed by a staged FK map.
    if(id(n.org_unit_id)!==id(now.org_unit_id))
      block("LOCATION_REPARENT_STAGING_PROOF_REQUIRED:"+k);
    if(now.kind!==n.kind)block("LEGACY_LOCATION_KIND_DRIFT_REVIEW:"+k);
  }
  for(const n of legacy.org_units){
    const k=object(n)&&id(n.id),now=org.get(k);
    if(!now){fatal("LEGACY_ORG_ID_LOST:"+k);continue}
    if(now.kind!==n.kind || id(now.parent_id)!==id(n.parent_id))
      block("ORG_ANCESTRY_MIGRATION_REVIEW:"+k);
  }
  const fks=snapshot.foreign_key_refs;
  for(const [key,minimum] of [["locations",136],["org_units",72]]){
    if(!Number.isInteger(fks[key])||fks[key]<minimum)
      fatal("FK_DEPENDENCY_COUNT_REGRESSION:"+key);
  }
  observed.fk_locations=fks.locations;
  observed.fk_org_units=fks.org_units;
  observed.legacy_ids_preserved=baselineLocations.size===legacy.locations.length &&
    [...baselineLocations].every(k=>loc.has(k));
  observed.legacy_location_count=loc.size;
  const rls=new Map();
  for(const entry of snapshot.rls){
    if(!object(entry)||typeof entry.table!=="string"){fatal("INVALID_RLS_ROW");continue}
    if(rls.has(entry.table))fatal("DUPLICATE_RLS_ROW:"+entry.table);
    rls.set(entry.table,entry);
  }
  for(const tbl of REQUIRED_RLS){
    if(!rls.has(tbl)||rls.get(tbl).enabled!==true)fatal("MISSING_ENABLED_RLS:"+tbl);
  }
  const columns=new Map(snapshot.columns.filter(object).map(x=>[x.table+"."+x.column,x.type]));
  for(const [table,fields] of Object.entries(REQUIRED_COLS)){
    for(const [col,type] of Object.entries(fields)){
      if(columns.get(table+"."+col)!==type)fatal("SG_COLUMN_INCOMPATIBLE:"+table+"."+col);
    }
  }
  const policies=snapshot.policies;
  if(policies.some(p=>!object(p)||typeof p.name!=="string"||typeof p.table!=="string"||
           !["PERMISSIVE","RESTRICTIVE"].includes(p.permissive)))
    fatal("INVALID_POLICY_CLASSIFICATION");
  const applicable=(table)=>policies.filter(p=>object(p)&&p.table===table&&
    (p.cmd==="SELECT"||p.cmd==="ALL")&&
    typeof p.roles==="string"&&p.roles.includes("authenticated"));
  const lp=applicable("locations");
  const restrictiveLocation=lp.some(p=>p.permissive==="RESTRICTIVE"&&p.loc_scope_helper===true);
  const activeOnlyPermissive=lp.some(p=>p.permissive==="PERMISSIVE"&&p.active_only===true);
  observed.locations_active_only_permissive=activeOnlyPermissive;
  observed.locations_restrictive_scope_policy_present=restrictiveLocation;
  observed.rls_static_combination="(OR permissive) AND (AND restrictive)";
  if(!restrictiveLocation)fatal("LOCATION_RESTRICTIVE_SCOPE_POLICY_MISSING");
  // Static policy presence says NOTHING about _loc_vis123() correctness.
  block("AUTHENTICATED_CROSS_BUSINESS_RLS_E2E_REQUIRED");
  const itemScope=applicable("items");
  observed.items_org_disabled_fallback_seen=itemScope.some(p=>p.org_disabled_bypass===true);
  if(observed.items_org_disabled_fallback_seen)block("ITEMS_ORG_DISABLED_FALLBACK_REVIEW_REQUIRED");
  const funcs=snapshot.functions;
  for(const name of ["_org_on123","_loc_vis123","business_place_create135"]){
    if(!funcs.some(x=>object(x)&&x.name===name))fatal("REQUIRED_SG_HELPER_MISSING:"+name);
  }
  if(funcs.some(x=>object(x)&&x.name==="business_place_create135"&&
       x.security_definer===true&&x.authenticated_execute===true))
    block("PRIVILEGED_PROVISIONING_RPC_AUTH_REVIEW_REQUIRED");
  observed.operating_site_layer_present=snapshot.org_units.some(n=>n.kind==="operating_site");
  observed.tenant_layer_present=snapshot.org_units.some(n=>n.kind==="tenant");
  if(!observed.operating_site_layer_present)block("CANONICAL_SITE_LAYER_MISSING");
  if(!observed.tenant_layer_present)block("CANONICAL_TENANT_LAYER_MISSING");
  block("STAGING_RESTORE_AND_ROLLBACK_PROOF_REQUIRED");
  block("REAL_SUPABASE_AUTH_SIGNED_ROLE_MATRIX_REQUIRED");
  block("OWNER_HIGH_RISK_RELEASE_APPROVAL_REQUIRED");
  // Release readiness can never be inferred from this SELECT-only snapshot.
  return {ok:errors.length===0,errors,blockers,observed,
    release_ready:false,certification:"STATIC_COMPATIBILITY_ONLY"};
}
module.exports={inspect};
if(require.main===module){
  const s=require("../data/c10_sg_scope_preflight_2026-11-11.json");
  const old=require("../data/core10_sg_readonly_structure_2026-11-10.json");
  const report=inspect(s,old);
  console.log(JSON.stringify(report,null,2));
  process.exitCode=report.ok?0:1;
}
