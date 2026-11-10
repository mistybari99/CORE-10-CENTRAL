/* CORE 10 CENTRAL | Business Creation workspace.
 * Same repository, same template catalog. Signed Supabase user required for writes.
 * Production provisioning explicitly locked until staged backend + owner release.
 */
(function(root,factory){ "use strict";var api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.CORE10_BUSINESS_BUILDER=api;})(typeof window!=="undefined"?window:globalThis,function(){
"use strict";
const KINDS=["showroom","factory","godown","warehouse","project"];
const MODES=["quick","advanced"];
const COLOR=/^#[0-9a-fA-F]{6}$/;
function str(v){return typeof v==="string"?v.trim():""}
function validate(catalog,model){
 const errors=[];
 if(!catalog||!Array.isArray(catalog.templates)||catalog.templates.length!==10)errors.push("INVALID_CATALOG");
 if(!model||typeof model!=="object")return {ok:false,errors:["INVALID_MODEL"]};
 const template=catalog&&catalog.templates&&catalog.templates.find(t=>t.id===model.templateId);
 if(!template)errors.push("UNKNOWN_TEMPLATE");
 if(!str(model.name)||str(model.name).length>120)errors.push("BUSINESS_NAME_REQUIRED");
 if(!/^[a-z][a-z0-9-]{0,79}$/.test(str(model.slug)))errors.push("INVALID_SLUG");
 if(!MODES.includes(model.mode))errors.push("INVALID_MODE");
 if(!COLOR.test(str(model.brandHex)))errors.push("INVALID_BRAND_COLOR");
 if(!Array.isArray(model.sites))errors.push("INVALID_SITES");
 const seen=new Set();
 if(Array.isArray(model.sites)){
  if(model.sites.length>500)errors.push("TOO_MANY_SITES");
  model.sites.forEach((site,i)=>{
   if(!site||!KINDS.includes(site.kind)||!str(site.label)||str(site.label).length>120)errors.push("INVALID_SITE:"+i);
   const key=site&&site.kind+":"+str(site.label).toLocaleLowerCase();
   if(seen.has(key))errors.push("DUPLICATE_SITE:"+i);
   seen.add(key);
  });
  if(model.mode==="advanced"&&!model.sites.length)errors.push("ADVANCED_SITE_REQUIRED");
  if(model.mode==="quick"&&model.sites.length)errors.push("QUICK_SITES_MUST_BE_EMPTY");
 }
 if(!Array.isArray(model.modules))errors.push("INVALID_MODULES");
 else {
  const allowed=new Set(template?template.modules.map(m=>m.id):[]),selected=new Set();
  model.modules.forEach(m=>{
   if(!allowed.has(m))errors.push("UNKNOWN_MODULE:"+m);
   if(selected.has(m))errors.push("DUPLICATE_MODULE:"+m);
   selected.add(m);
  });
 }
 return {ok:errors.length===0,errors,template:template||null};
}
function toBackendInput(catalog,model,context){
 const result=validate(catalog,model);
 if(!result.ok)throw Object.assign(new Error("BUSINESS_SETUP_INVALID"),{reasons:result.errors});
 if(!context||!Number.isSafeInteger(Number(context.legalId))||Number(context.legalId)<1)throw Error("AUTHORIZED_LEGAL_ENTITY_REQUIRED");
 if(!str(context.requestKey))throw Error("IDEMPOTENCY_KEY_REQUIRED");
 if(result.template.source_status!=="available"||!str(result.template.source_code))throw Error("TEMPLATE_BACKEND_UNAVAILABLE");
 return {legalId:Number(context.legalId),slug:str(model.slug),template:result.template.source_code,
  displayName:str(model.name),mode:model.mode,sites:model.mode==="advanced"?model.sites.map(s=>({kind:s.kind,label:str(s.label)})):[],
  requestKey:str(context.requestKey),brandHex:str(model.brandHex)};
}
function create(config){
 config=config||{};
 const catalog=config.catalog;
 let model={name:"",slug:"",templateId:"sweets_bakery",brandHex:"#7C263A",mode:"quick",sites:[],modules:[]};
 const subscribers=new Set();
 function emit(){subscribers.forEach(fn=>fn(snapshot()))}
 function snapshot(){return JSON.parse(JSON.stringify(model))}
 function update(patch){
  if(!patch||typeof patch!=="object")throw Error("INVALID_PATCH");
  const allowed=["name","slug","templateId","brandHex","mode","sites","modules"];
  if(Object.keys(patch).some(k=>!allowed.includes(k)))throw Error("UNKNOWN_FIELD");
  model={...model,...JSON.parse(JSON.stringify(patch))};emit();return snapshot();
 }
 function reset(){model={name:"",slug:"",templateId:"sweets_bakery",brandHex:"#7C263A",mode:"quick",sites:[],modules:[]};emit()}
 function onChange(fn){subscribers.add(fn);return()=>subscribers.delete(fn)}
 function preview(){return{schema_version:1,kind:"core10_business_setup_preview",production_ready:false,model:snapshot(),validation:validate(catalog,model)}}
 async function provision(context){
  if(config.releaseEnabled!==true)throw Error("BUSINESS_SETUP_RELEASE_LOCKED");
  if(!config.enterpriseClient||typeof config.enterpriseClient.setupBusiness!=="function")throw Error("SIGNED_BACKEND_REQUIRED");
  const request=toBackendInput(catalog,model,context);
  return config.enterpriseClient.setupBusiness(request);
 }
 return Object.freeze({snapshot,update,reset,onChange,preview,provision,validate:()=>validate(catalog,model)});
}
return Object.freeze({KINDS,MODES,validate,toBackendInput,create});
});
