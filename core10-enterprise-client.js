/* CORE 10 CENTRAL — Enterprise browser API bridge candidate.
 * Reuses the existing Supabase JS authenticated session; never a service role key.
 * DISABLED by default. Production enablement is blocked until A019 staging, signed
 * Supabase Auth, RLS negative cases, legacy mapping & Owner release gates pass.
 * This file is an integration component, not a new app, auth mechanism, or UI claim.
 */
(function(root,factory){
 "use strict";
 var api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_ENTERPRISE_CLIENT=api;
})(typeof window!=="undefined"?window:(typeof globalThis!=="undefined"?globalThis:null),function(){
 "use strict";
 var SCHEMA="c10_demo";
 var SITE_TYPES={showroom:true,factory:true,godown:true,warehouse:true,project:true};
 function text(v){return String(v==null?"":v).trim()}
 function fail(code){var err=new Error(code);err.code=code;throw err}
 function object(v){return v&&typeof v==="object"&&!Array.isArray(v)}
 function present(v){return typeof v==="string"&&v.trim().length>0}
 function siteList(value){
  if(!Array.isArray(value)||value.length<1||value.length>500)fail("INVALID_SITE_MANIFEST");
  var seen=new Set();
  return value.map(function(v){
   if(!object(v)||Object.keys(v).sort().join(",")!=="kind,label")fail("INVALID_SITE_MANIFEST");
   var kind=text(v.kind),label=text(v.label);
   if(!SITE_TYPES[kind]||!label||label.length>120)fail("INVALID_SITE_MANIFEST");
   var sig=kind+":"+label.toLowerCase();
   if(seen.has(sig))fail("DUPLICATE_SITE");
   seen.add(sig);
   return{kind:kind,label:label};
  });
 }
 function validateSetup(x){
  if(!object(x))fail("INVALID_SETUP");
  var mode=text(x.mode);
  if(mode!=="quick"&&mode!=="advanced")fail("INVALID_SETUP_MODE");
  var legal=Number(x.legalId),slug=text(x.slug),name=text(x.displayName),
   request=text(x.requestKey),template=text(x.template),brand=text(x.brandHex);
  if(!Number.isSafeInteger(legal)||legal<1||!/^[a-z][a-z0-9-]{0,79}$/.test(slug)||
    !name||name.length>120||!template||
    !request||request.length>120||!/^#[0-9A-Fa-f]{6}$/.test(brand))fail("INVALID_SETUP");
  var sites=mode==="quick"?null:siteList(x.sites);
  if(mode==="quick"&&x.sites!=null&&
     (!Array.isArray(x.sites)||x.sites.length!==0))fail("QUICK_NO_CUSTOM_SITES");
  return {p_legal:legal,p_slug:slug,p_template:template,
   p_display_name:name,p_mode:mode,p_sites:sites,
   p_request:request,p_brand_hex:brand};
 }
 function create(config){
  config=config||{};
  var client=config.client,read= config.experimentalRead===true,
   write=read&&config.experimentalWrite===true;
  // Flags only prevent accidental UI access. They are NEVER authorization.
  function ready(kind){
   if(!read||kind==="write"&&!write)fail("ENTERPRISE_BACKEND_NOT_RELEASED");
   if(!client||!client.auth||typeof client.auth.getUser!=="function"||
     typeof client.schema!=="function")fail("SIGNED_SUPABASE_CLIENT_REQUIRED");
  }
  async function scope(kind){
   ready(kind);
   var result=await client.auth.getUser();
   if(!result||result.error||!result.data||!result.data.user||
      !present(result.data.user.id))fail("AUTHENTICATED_USER_REQUIRED");
   var db=client.schema(SCHEMA);
   if(!db||typeof db.rpc!=="function"||typeof db.from!=="function")fail("API_SCHEMA_UNAVAILABLE");
   return db;
  }
  function unwrap(result){
   if(!result||result.error) {
    var e=new Error("ENTERPRISE_RPC_FAILED");
    e.code=result&&result.error&&result.error.code||"ENTERPRISE_RPC_FAILED";
    e.message=result&&result.error&&result.error.message||e.message;
    throw e;
   }
   return result.data;
  }
  async function listBusinesses(){
   var db=await scope("read");
   var q=db.from("businesses").select("id,tenant_id,legal_entity_id,slug,template_code,status").order("id",{ascending:true}).limit(200);
   return unwrap(await q);
  }
  async function listSetupOverview(){
   var db=await scope("read");
   return unwrap(await db.from("business_setup_overview_v1")
    .select("business_id,slug,status,display_name,brand_hex,setup_mode,setup_status,visible_sites,visible_modules")
    .order("business_id",{ascending:true}).limit(200));
  }
  async function listStockReconciliation(businessId){
   if(!Number.isSafeInteger(Number(businessId))||Number(businessId)<1)fail("INVALID_BUSINESS_ID");
   var db=await scope("read");
   return unwrap(await db.from("inventory_reconciliation_v1")
    .select("business_id,site_id,location_id,item_id,on_hand,ledger_units,reconciled")
    .eq("business_id",Number(businessId)).limit(200));
  }
  async function setupBusiness(input){
   var values=validateSetup(input);
   var db=await scope("write");
   return unwrap(await db.rpc("setup_business_v1",values));
  }
  // No stock write method: real legacy integration, costing and offline guards
  // have not been certified. Reusing unsafe old ledger writes is forbidden.
  return Object.freeze({
   status:function(){return Object.freeze({readEnabled:read,writeEnabled:write,
     schema:SCHEMA,certified:false})},
   listBusinesses:listBusinesses,
   listSetupOverview:listSetupOverview,
   listStockReconciliation:listStockReconciliation,
   setupBusiness:setupBusiness
  });
 }
 return Object.freeze({create:create,validateSetup:validateSetup});
});
