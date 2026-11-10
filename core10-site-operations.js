/* CORE 10 CENTRAL · Site Operations Build Package
 * Deterministic domain layer. No DB writes; persistence requires authorized RPC.
 * All identifiers are server-issued, never generated or inferred here.
 */
(function(root,factory){
 "use strict";
 var api=factory(typeof module==="object"&&module.exports?require("./core10-site-hierarchy.js"):root.CORE10_SITE_HIERARCHY);
 if(typeof module==="object"&&module.exports)module.exports=api;
 else if(root)root.CORE10_SITE_OPERATIONS=api;
})(typeof globalThis!=="undefined"?globalThis:null,function(H){
 "use strict";
 if(!H)throw Error("site_hierarchy_dependency_missing");
 var STATUS=Object.freeze(["planned","setting_up","live","paused","closed"]);
 var TRANSITIONS=Object.freeze({planned:["setting_up","closed"],setting_up:["live","paused","closed"],live:["paused","closed"],paused:["live","closed"],closed:[]});
 var TEMPLATES=Object.freeze([
  "sweets_bakery","restaurant","paint_hardware","retail_wholesale","manufacturing",
  "construction","import_export","ecommerce","technology_digital","services"
 ]);
 function fail(code){return {ok:false,reason:code}}
 function str(x){return typeof x==="string"?x.trim():""}
 function validCode(x){return /^[a-z][a-z0-9_]{1,29}$/.test(x)}
 function validName(x){return x.length>0&&x.length<=120}
 function createSiteDraft(input){
  if(!input||typeof input!=="object")return fail("invalid_input");
  var business=H.id(input.business_id),kind=H.kind(input.kind);
  var bn=str(input.name_bn),en=str(input.name_en),code=str(input.code);
  if(!business)return fail("invalid_business");
  if(!kind)return fail("invalid_kind");
  if((!bn&&!en)||(bn&&!validName(bn))||(en&&!validName(en)))return fail("invalid_name");
  if(code&&!validCode(code))return fail("invalid_code");
  return {ok:true,draft:Object.freeze({business_id:business,kind:kind,name_bn:bn||null,
   name_en:en||null,code:code||null,status:"setting_up"})};
 }
 function transition(input,next,readiness){
  if(!input||!H.id(input.id)||!H.id(input.business_id)||STATUS.indexOf(input.status)<0)return fail("invalid_site");
  if(STATUS.indexOf(next)<0||TRANSITIONS[input.status].indexOf(next)<0)return fail("invalid_transition");
  if(next==="live"){
   if(!readiness||readiness.business_verified!==true||readiness.permissions_verified!==true||
      readiness.stock_locations_verified!==true)return fail("activation_prerequisites_missing");
  }
  return {ok:true,command:Object.freeze({site_id:H.id(input.id),business_id:H.id(input.business_id),
   expected_status:input.status,next_status:next})};
 }
 function assignLocation(input){
  if(!input||typeof input!=="object")return fail("invalid_input");
  var business=H.id(input.business_id),site=H.id(input.site_id),location=H.id(input.location_id);
  if(!business||!site||!location)return fail("invalid_mapping");
  return {ok:true,command:Object.freeze({business_id:business,site_id:site,location_id:location})};
 }
 function transfer(input){
  if(!input||typeof input!=="object")return fail("invalid_input");
  var business=H.id(input.business_id),from=H.id(input.from_location_id),to=H.id(input.to_location_id),
      item=H.id(input.item_id),qty=input.quantity;
  if(!business||!from||!to||from===to||!item)return fail("invalid_transfer_scope");
  if(typeof qty!=="number"||!Number.isFinite(qty)||qty<=0||qty>1e9)return fail("invalid_quantity");
  if(input.from_business_id!==undefined&&H.id(input.from_business_id)!==business)return fail("cross_business_transfer");
  if(input.to_business_id!==undefined&&H.id(input.to_business_id)!==business)return fail("cross_business_transfer");
  if(input.from_site_status!=="live"||input.to_site_status!=="live")return fail("site_not_live");
  return {ok:true,command:Object.freeze({business_id:business,from_location_id:from,to_location_id:to,
   item_id:item,quantity:qty,status:"draft"})};
 }
 function planBusiness(input){
  if(!input||typeof input!=="object")return fail("invalid_input");
  var legal=H.id(input.legal_entity_id),template=str(input.template_code),name=str(input.name);
  if(!legal)return fail("invalid_legal_entity");
  if(TEMPLATES.indexOf(template)<0)return fail("unknown_template");
  if(!validName(name))return fail("invalid_name");
  // Deliberately no invented module readiness, ownership or finance records.
  return {ok:true,plan:Object.freeze({legal_entity_id:legal,template_code:template,name:name,
   status:"draft",requires_server_authorization:true})};
 }
 function summarize(sites,locations,businessId){
  var r=H.reconcile(sites,locations,businessId);
  if(!r.ok)return r;
  var counters={showroom:0,factory:0,godown:0},siteIds=new Set();
  for(var i=0;i<sites.length;i++){var s=H.site(sites[i]);counters[s.kind]++;siteIds.add(s.id)}
  return {ok:true,business_id:r.business_id,sites:sites.length,stock_locations:locations.length,
   unmapped_locations:r.unmapped,by_kind:Object.freeze(counters),mappings:r.mappings};
 }
 return Object.freeze({STATUS:STATUS,TRANSITIONS:TRANSITIONS,TEMPLATES:TEMPLATES,
  createSiteDraft:createSiteDraft,transition:transition,assignLocation:assignLocation,
  transfer:transfer,planBusiness:planBusiness,summarize:summarize});
});
