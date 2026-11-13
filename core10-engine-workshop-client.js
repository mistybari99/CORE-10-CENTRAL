/* C10-A045 Micro-Engine Workshop signed-RPC adapter.
 * Same c10_demo schema RPCs as the A044 control service. No local permissions, no persisted tokens,
 * no simulated success, no direct table access, no eval/Function, no outbound URL execution.
 * Client validation mirrors the server DSL for UX only: the SERVER is the authority.
 */
(function(root,factory){"use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_ENGINE_WORKSHOP_API=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 const FIELDS=["on_hand","reorder_gap","days_cover","margin_pct","order_total"];
 const OPS=["lt","lte","gt","gte","eq"];
 const OUTCOMES=["allow","warn","block","approval_required"];
 const PLACEMENTS=["central_only","business_only","both","hidden_from_menus"];
 const MODES=["central_only","business_owner","request_approval"];
 const STATES=["PUBLISHED","PAUSED","REVOKED"];
 const KEY=/^[a-z][a-z0-9]*(_[a-z0-9]+)*$/,REQ=/^[A-Za-z0-9_-]{8,100}$/;
 const LIMIT=1e9;
 function fail(code){const e=new Error(code);e.code=code;throw e}
 const num=(v)=>typeof v==="number"&&Number.isFinite(v)&&Math.abs(v)<=LIMIT;
 const pos=(v)=>Number.isSafeInteger(v)&&v>0;
 /* Returns {ok,errors[]} — never throws, used by the UI for field-level messages. */
 function validateDescriptor(d){
  const errors=[];
  if(!d||typeof d!=="object"||Array.isArray(d))return{ok:false,errors:["descriptor must be an object"]};
  for(const k of Object.keys(d))if(!["field","op","threshold","outcome","message"].includes(k))errors.push("unknown key: "+k);
  if(!FIELDS.includes(d.field))errors.push("field must be one of "+FIELDS.join(", "));
  if(!OPS.includes(d.op))errors.push("op must be one of "+OPS.join(", "));
  if(!num(d.threshold))errors.push("threshold must be a finite number within ±1,000,000,000");
  if(!OUTCOMES.includes(d.outcome))errors.push("outcome must be one of "+OUTCOMES.join(", "));
  if("message" in d&&(typeof d.message!=="string"||d.message.length>200||/[\u0000-\u001f\u007f]/.test(d.message)))
   errors.push("message must be text up to 200 characters");
  return{ok:errors.length===0,errors};
 }
 function validateParams(p){
  const errors=[];
  if(!p||typeof p!=="object"||Array.isArray(p))return{ok:false,errors:["params must be an object"]};
  for(const k of Object.keys(p))if(!["threshold","outcome"].includes(k))errors.push("unknown parameter: "+k);
  if("threshold" in p&&!num(p.threshold))errors.push("threshold must be a finite number");
  if("outcome" in p&&!OUTCOMES.includes(p.outcome))errors.push("outcome must be one of "+OUTCOMES.join(", "));
  return{ok:errors.length===0,errors};
 }
 function create({client}={}){
  async function db(){
   if(!client||!client.auth||typeof client.auth.getUser!=="function"||typeof client.schema!=="function")fail("SIGNED_SUPABASE_CLIENT_REQUIRED");
   const r=await client.auth.getUser();
   if(!r||r.error||!r.data||!r.data.user||typeof r.data.user.id!=="string"||!r.data.user.id)fail("AUTHENTICATED_USER_REQUIRED");
   const s=client.schema("c10_demo");
   if(!s||typeof s.rpc!=="function"||typeof s.from!=="function")fail("ENGINE_SCHEMA_NOT_AVAILABLE");
   return s;
  }
  function unwrap(r){
   if(!r||r.error){const e=new Error(r&&r.error&&r.error.message||"ENGINE_RPC_UNAVAILABLE");
    e.code=r&&r.error&&r.error.code||"ENGINE_RPC_UNAVAILABLE";throw e}
   return r.data;
  }
  const req=(k,r)=>{if(typeof k!=="string"||!REQ.test(k)||typeof r!=="string"||r.trim().length<5||r.length>500)fail("INVALID_ENGINE_REQUEST")};
  async function listBusinesses(){
   const s=await db();
   const rows=unwrap(await s.from("businesses").select("id,tenant_id,slug,status").order("id",{ascending:true}).limit(200));
   if(!Array.isArray(rows)||rows.some(x=>!pos(x.id)||!pos(x.tenant_id)))fail("INVALID_BUSINESS_SCOPE_RESPONSE");
   return rows;
  }
  async function readRegistry(tenantId){
   if(!pos(tenantId))fail("INVALID_TENANT_ID");
   const s=await db(),d=unwrap(await s.rpc("read_engines_v1",{p_tenant:tenantId}));
   if(!d||d.server_authorized!==true||d.operationally_certified!==false||d.tenant_id!==tenantId||
      !Array.isArray(d.engines)||!Array.isArray(d.handlers))fail("ENGINE_REGISTRY_RESPONSE_REJECTED");
   return d;
  }
  async function readAudit(engineId){
   if(!pos(engineId))fail("INVALID_ENGINE_ID");
   const s=await db(),d=unwrap(await s.rpc("read_engine_audit_v1",{p_engine:engineId}));
   if(!d||d.engine_id!==engineId||!Array.isArray(d.items))fail("ENGINE_AUDIT_RESPONSE_REJECTED");
   return d.items;
  }
  async function readBusiness(businessId){
   if(!pos(businessId))fail("INVALID_BUSINESS_ID");
   const s=await db(),d=unwrap(await s.rpc("read_business_engines_v1",{p_business:businessId}));
   if(!d||d.server_authorized!==true||d.operationally_certified!==false||d.business_id!==businessId||!Array.isArray(d.items))
    fail("ENGINE_BUSINESS_RESPONSE_REJECTED");
   return d;
  }
  async function pending(tenantId){
   if(!pos(tenantId))fail("INVALID_TENANT_ID");
   const s=await db(),d=unwrap(await s.rpc("read_engine_pending_v1",{p_tenant:tenantId}));
   if(!d||d.tenant_id!==tenantId||!Array.isArray(d.items))fail("ENGINE_PENDING_RESPONSE_REJECTED");
   return d.items;
  }
  async function previewDraft({tenantId,descriptor,params,inputs}){
   if(!pos(tenantId)||!validateDescriptor(descriptor).ok||!validateParams(params||{}).ok||!inputs||typeof inputs!=="object")fail("INVALID_ENGINE_PREVIEW");
   const s=await db();
   return unwrap(await s.rpc("preview_engine_draft_v1",{p_tenant:tenantId,p_handler:"threshold_rule_v1",
    p_descriptor:descriptor,p_params:params||{},p_inputs:inputs}));
  }
  async function previewBusiness({engineId,businessId,inputs}){
   if(!pos(engineId)||!pos(businessId)||!inputs||typeof inputs!=="object")fail("INVALID_ENGINE_PREVIEW");
   const s=await db();
   return unwrap(await s.rpc("preview_business_engine_v1",{p_engine:engineId,p_business:businessId,p_inputs:inputs}));
  }
  async function saveDraft(x){
   if(!x||!pos(x.tenantId)||typeof x.key!=="string"||!KEY.test(x.key)||x.key.length>60||
      typeof x.name!=="string"||x.name.trim().length<3||x.name.length>80||
      typeof x.handler!=="string"||!/^[a-z][a-z0-9_]{2,40}$/.test(x.handler)||
      !Number.isSafeInteger(x.expectedVersion)||x.expectedVersion<0)fail("INVALID_ENGINE_DRAFT");
   if(x.handler==="threshold_rule_v1"&&!validateDescriptor(x.descriptor).ok)fail("INVALID_ENGINE_DESCRIPTOR");
   req(x.requestKey,x.reason);
   const s=await db(),r=unwrap(await s.rpc("save_engine_draft_v1",{p_tenant:x.tenantId,p_key:x.key,p_name:x.name.trim(),
    p_handler:x.handler,p_descriptor:x.descriptor,p_expected_version:x.expectedVersion,p_request:x.requestKey,p_reason:x.reason.trim()}));
   if(!r||r.status!=="saved"||!pos(r.engine_id)||!pos(r.version))fail("INVALID_ENGINE_SAVE_RECEIPT");
   return r;
  }
  async function validateVersion({engineId,version,requestKey,reason}){
   if(!pos(engineId)||!pos(version))fail("INVALID_ENGINE_VERSION");
   req(requestKey,reason);
   const s=await db(),r=unwrap(await s.rpc("validate_engine_version_v1",{p_engine:engineId,p_version:version,p_request:requestKey,p_reason:reason.trim()}));
   if(!r||r.status!=="validated")fail("INVALID_ENGINE_VALIDATE_RECEIPT");
   return r;
  }
  async function assign(x){
   if(!x||!pos(x.engineId)||!pos(x.businessId)||!pos(x.version)||!STATES.includes(x.state)||
      !PLACEMENTS.includes(x.placement)||!MODES.includes(x.localEditMode)||
      !Number.isSafeInteger(x.expected)||x.expected<0||!validateParams(x.params||{}).ok||
      ((x.placement==="central_only"||x.placement==="hidden_from_menus")&&x.localEditMode!=="central_only"))fail("INVALID_ENGINE_ASSIGNMENT");
   req(x.requestKey,x.reason);
   const s=await db(),r=unwrap(await s.rpc("assign_engine_v1",{p_engine:x.engineId,p_business:x.businessId,p_version:x.version,
    p_state:x.state,p_params:x.params||{},p_placement:x.placement,p_local_edit:x.localEditMode,p_expected:x.expected,
    p_request:x.requestKey,p_reason:x.reason.trim()}));
   if(!r||r.status!=="applied")fail("INVALID_ENGINE_ASSIGN_RECEIPT");
   return r;
  }
  async function editParams(x){
   if(!x||!pos(x.engineId)||!pos(x.businessId)||!pos(x.expected)||!validateParams(x.params||{}).ok)fail("INVALID_ENGINE_PARAMS");
   req(x.requestKey,x.reason);
   const s=await db(),r=unwrap(await s.rpc("edit_engine_params_v1",{p_engine:x.engineId,p_business:x.businessId,
    p_params:x.params||{},p_expected:x.expected,p_request:x.requestKey,p_reason:x.reason.trim()}));
   if(!r||!["applied","pending"].includes(r.status))fail("INVALID_ENGINE_PARAMS_RECEIPT");
   return r;
  }
  async function decide(requestId,decision){
   if(!pos(requestId)||!["approve","reject"].includes(decision))fail("INVALID_ENGINE_DECISION");
   const s=await db(),r=unwrap(await s.rpc("decide_engine_request_v1",{p_request_id:requestId,p_decision:decision}));
   if(!r||!["approved","rejected"].includes(r.status))fail("INVALID_ENGINE_DECISION_RECEIPT");
   return r;
  }
  async function rollback(x){
   if(!x||!pos(x.engineId)||!pos(x.businessId)||!pos(x.auditId)||!pos(x.expected))fail("INVALID_ENGINE_ROLLBACK");
   req(x.requestKey,x.reason);
   const s=await db(),r=unwrap(await s.rpc("rollback_engine_assignment_v1",{p_engine:x.engineId,p_business:x.businessId,
    p_audit_id:x.auditId,p_expected:x.expected,p_request:x.requestKey,p_reason:x.reason.trim()}));
   if(!r||r.status!=="rolled_back"||r.config_only!==true)fail("INVALID_ENGINE_ROLLBACK_RECEIPT");
   return r;
  }
  async function setSiteOverride(x){
   if(!x||!pos(x.engineId)||!pos(x.businessId)||!pos(x.siteId)||!Number.isSafeInteger(x.expected)||x.expected<0||
      !validateParams(x.params||{}).ok)fail("INVALID_ENGINE_SITE_OVERRIDE");
   req(x.requestKey,x.reason);
   const s=await db(),r=unwrap(await s.rpc("set_engine_site_override_v1",{p_engine:x.engineId,p_business:x.businessId,p_site:x.siteId,
    p_params:x.params||{},p_expected:x.expected,p_request:x.requestKey,p_reason:x.reason.trim()}));
   if(!r||r.status!=="applied"||!pos(r.site_id))fail("INVALID_ENGINE_SITE_RECEIPT");
   return r;
  }
  async function previewSite({engineId,businessId,siteId,inputs}){
   if(!pos(engineId)||!pos(businessId)||!pos(siteId)||!inputs||typeof inputs!=="object")fail("INVALID_ENGINE_PREVIEW");
   const s=await db();
   return unwrap(await s.rpc("preview_site_engine_v1",{p_engine:engineId,p_business:businessId,p_site:siteId,p_inputs:inputs}));
  }
  return Object.freeze({listBusinesses,readRegistry,readAudit,readBusiness,pending,previewDraft,previewBusiness,
   saveDraft,validateVersion,assign,editParams,decide,rollback,setSiteOverride,previewSite,
   releaseStatus:()=>Object.freeze({serverOnly:true,operationallyCertified:false,advisoryOnly:true,
    stockWrites:false,financeWrites:false,arbitraryCode:false})});
 }
 return Object.freeze({create,validateDescriptor,validateParams,FIELDS,OPS,OUTCOMES,PLACEMENTS,MODES,STATES});
});
