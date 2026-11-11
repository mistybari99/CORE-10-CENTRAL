/* CORE 10 CENTRAL | A018 Business Template Foundation Planner
 * Pure, read-only planning contract. No database writes or authorization.
 * Provisioning MUST be performed by an authenticated, transactional backend.
 */
"use strict";
const registry=require("./core10-capability-registry.js");
const SITE_KINDS=Object.freeze(["branch","factory","warehouse"]);
const SETUP_MODES=Object.freeze(["quick","advanced"]);
function plain(x){return x!==null&&typeof x==="object"&&!Array.isArray(x)}
function nonempty(x){return typeof x==="string"&&x.trim().length>0}
function planBusinessSetup(catalog,input){
  const errors=[];
  if(!registry.validateCatalog(catalog).ok)return{ok:false,errors:["INVALID_CATALOG"],plan:null};
  if(!plain(input))return{ok:false,errors:["INVALID_INPUT"],plan:null};
  if(!nonempty(input.tenant_id))errors.push("TENANT_ID_REQUIRED");
  if(!nonempty(input.business_name))errors.push("BUSINESS_NAME_REQUIRED");
  if(!SETUP_MODES.includes(input.mode))errors.push("INVALID_SETUP_MODE");
  const template=registry.findTemplate(catalog,input.template_id);
  if(!template)errors.push("UNKNOWN_TEMPLATE");
  const sites=input.sites===undefined?[]:input.sites;
  if(!Array.isArray(sites))errors.push("INVALID_SITES");
  const seen=new Set();
  if(Array.isArray(sites))sites.forEach((s,i)=>{
    if(!plain(s)||!nonempty(s.client_key)||!nonempty(s.name)||!SITE_KINDS.includes(s.kind)){
      errors.push("INVALID_SITE:"+i);return;
    }
    if(seen.has(s.client_key))errors.push("DUPLICATE_SITE_KEY:"+s.client_key);
    seen.add(s.client_key);
  });
  const requested=input.modules===undefined?[]:input.modules;
  if(!Array.isArray(requested))errors.push("INVALID_MODULES");
  const allowed=new Set(template?template.modules.map(m=>m.id):[]);
  if(Array.isArray(requested)){
    const unique=new Set();
    requested.forEach((m,i)=>{
      if(!nonempty(m)||unique.has(m))errors.push("INVALID_OR_DUPLICATE_MODULE:"+i);
      else if(!allowed.has(m))errors.push("MODULE_NOT_DECLARED:"+m);
      unique.add(m);
    });
  }
  if(errors.length)return{ok:false,errors,plan:null};
  // A plan may be previewed for an unimplemented template; never treat it as deployable.
  const gate=registry.assessReadiness(catalog,template.id);
  const plan={
    schema_version:1,operation:"business_setup_preview_only",
    tenant_id:input.tenant_id.trim(),business_name:input.business_name.trim(),
    template_id:template.id,source_template_code:template.source_code,
    mode:input.mode,modules:requested.slice(),
    sites:sites.map(s=>({client_key:s.client_key,name:s.name.trim(),kind:s.kind})),
    canonical_hierarchy:registry.CANONICAL_HIERARCHY.slice(),
    executable:false,requires_authenticated_backend:true,
    requires_atomic_idempotent_provisioning:true,
    requires_tenant_business_site_rls:true,
    requires_legacy_location_id_preservation:true,
    readiness:gate
  };
  return{ok:true,errors:[],plan};
}
module.exports=Object.freeze({SITE_KINDS,SETUP_MODES,planBusinessSetup});
