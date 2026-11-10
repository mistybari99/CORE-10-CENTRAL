/* CORE 10 CENTRAL | A020 signed-user ten-industry draft RPC adapter.
 * Draft-only; tenant owner authorization and idempotency enforced in PostgreSQL.
 * No service role, no stock/finance writes, no automatic production activation.
 */
(function(root,factory){"use strict";var api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.CORE10_INDUSTRY_CLIENT=api;})(typeof window!=="undefined"?window:globalThis,function(){
"use strict";
const KINDS=new Set(["showroom","factory","godown","warehouse","project"]);
const SLUG=/^[a-z][a-z0-9-]{0,79}$/;
const COLOR=/^#[a-fA-F0-9]{6}$/;
const text=v=>typeof v==="string"?v.trim():"";
function fail(code){const e=new Error(code);e.code=code;throw e}
function validate(catalog,input,context){
 if(!catalog||!Array.isArray(catalog.templates)||catalog.templates.length!==10)fail("INVALID_CATALOG");
 if(!input||typeof input!=="object")fail("INVALID_INPUT");
 const template=catalog.templates.find(t=>t.id===input.templateId);
 if(!template)fail("UNKNOWN_TEMPLATE");
 if(!context||!Number.isSafeInteger(context.legalId)||context.legalId<1)fail("LEGAL_ID_REQUIRED");
 if(!text(context.requestKey)||text(context.requestKey).length>110)fail("REQUEST_KEY_REQUIRED");
 if(!SLUG.test(text(input.slug))||!text(input.name)||text(input.name).length>120||!COLOR.test(text(input.brandHex)))fail("INVALID_BUSINESS_PROFILE");
 if(!["quick","advanced"].includes(input.mode))fail("INVALID_SETUP_MODE");
 if(!Array.isArray(input.modules)||input.modules.length>100)fail("INVALID_MODULES");
 const declared=new Set(template.modules.map(m=>m.id)),seenMods=new Set();
 for(const mod of input.modules){if(typeof mod!=="string"||!declared.has(mod)||seenMods.has(mod))fail("INVALID_MODULES");seenMods.add(mod)}
 if(!Array.isArray(input.sites)||input.sites.length>500)fail("INVALID_SITE_MANIFEST");
 if(input.mode==="quick"&&input.sites.length)fail("QUICK_SITES_MUST_BE_EMPTY");
 if(input.mode==="advanced"&&!input.sites.length)fail("ADVANCED_SITES_REQUIRED");
 const seenSites=new Set();
 const sites=input.sites.map(s=>{
   if(!s||typeof s!=="object"||!KINDS.has(s.kind)||!text(s.label)||text(s.label).length>120)fail("INVALID_SITE_MANIFEST");
   const key=s.kind+":"+text(s.label).toLocaleLowerCase();
   if(seenSites.has(key))fail("DUPLICATE_SITE");
   seenSites.add(key);return{kind:s.kind,label:text(s.label)};
 });
 return Object.freeze({p_legal:context.legalId,p_slug:text(input.slug),p_template_id:template.id,
  p_display_name:text(input.name),p_mode:input.mode,p_sites:input.mode==="quick"?null:sites,
  p_modules:input.modules.slice(),p_request:text(context.requestKey),p_brand_hex:text(input.brandHex)});
}
function create(options){
 options=options||{};
 const client=options.client,catalog=options.catalog;
 const stagingEnabled=options.stagingEnabled===true;
 const draftWritesEnabled=stagingEnabled&&options.draftWritesEnabled===true;
 async function db(){
  if(!client||!client.auth||typeof client.auth.getUser!=="function"||typeof client.schema!=="function")
    fail("SIGNED_SUPABASE_CLIENT_REQUIRED");
  const result=await client.auth.getUser();
  if(result.error||!result.data||!result.data.user||!text(result.data.user.id))
    fail("AUTHENTICATED_USER_REQUIRED");
  const scoped=client.schema("c10_demo");
  if(!scoped||typeof scoped.rpc!=="function"||typeof scoped.from!=="function")fail("BACKEND_SCHEMA_MISSING");
  return scoped;
 }
 async function listLegalEntities(){
  if(!stagingEnabled)fail("STAGING_UNAVAILABLE");
  const scoped=await db();
  const r=await scoped.from("legal_entities").select("id,label,tenant_id").order("id");
  if(r.error)throw r.error;
  return r.data;
 }
 async function listTemplates(){
  if(!stagingEnabled)fail("STAGING_UNAVAILABLE");
  const scoped=await db();
  const r=await scoped.from("industry_catalog_v2").select("id,name_en,legacy_code,legacy_status,readiness,enterprise_certified").order("id");
  if(r.error)throw r.error;return r.data;
 }
 async function setupDraft(input,context){
  if(!draftWritesEnabled)fail("DRAFT_PROVISIONING_RELEASE_LOCKED");
  const payload=validate(catalog,input,context);
  const scoped=await db();
  const r=await scoped.rpc("setup_industry_draft_v2",payload);
  if(r.error)throw r.error;
  return Object.freeze({business_id:r.data,setup_status:"draft",operational_enabled:false});
 }
 return Object.freeze({status:()=>Object.freeze({stagingEnabled,draftWritesEnabled,productionCertified:false}),
  listLegalEntities,listTemplates,setupDraft});
}
return Object.freeze({validate,create});
});
