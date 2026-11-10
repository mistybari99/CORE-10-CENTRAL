/* CORE 10 CENTRAL — A010 canonical site/location hierarchy contract.
 * Pure compatibility helpers; no network, database or production mutations.
 * Legacy location IDs remain authoritative until an approved migration.
 */
(function(root,factory){
  "use strict";
  var api=factory();
  if(typeof module==="object"&&module.exports)module.exports=api;
  if(root)root.CORE10_SITE_HIERARCHY=api;
})(typeof globalThis!=="undefined"?globalThis:null,function(){
  "use strict";
  var SITE_KINDS=Object.freeze(["showroom","factory","godown"]);
  function id(value){
    if(typeof value==="number")return Number.isSafeInteger(value)&&value>0?value:null;
    if(typeof value!=="string"||!/^[1-9][0-9]*$/.test(value))return null;
    var parsed=Number(value);
    return Number.isSafeInteger(parsed)?parsed:null;
  }
  function kind(value){return SITE_KINDS.indexOf(value)>=0?value:null}
  function site(input){
    if(!input||typeof input!=="object"||Array.isArray(input))return null;
    var businessId=id(input.business_id),siteId=id(input.id),siteKind=kind(input.kind);
    if(!businessId||!siteId||!siteKind)return null;
    return Object.freeze({id:siteId,business_id:businessId,kind:siteKind});
  }
  function location(input){
    if(!input||typeof input!=="object"||Array.isArray(input))return null;
    var locationId=id(input.id),businessId=id(input.business_id),siteId=id(input.site_id);
    if(!locationId||!businessId)return null;
    // Null means unmapped legacy location; never infer site from branch/name.
    if(input.site_id!=null&&!siteId)return null;
    return Object.freeze({id:locationId,business_id:businessId,site_id:siteId});
  }
  function reconcile(sites,locations,businessId){
    var requested=id(businessId);
    if(!requested||!Array.isArray(sites)||!Array.isArray(locations))
      return {ok:false,reason:"invalid_input"};
    var bySite=new Map(),byLocation=new Set(),out=[];
    for(var i=0;i<sites.length;i++){
      var s=site(sites[i]);
      if(!s||s.business_id!==requested||bySite.has(s.id))
        return {ok:false,reason:"invalid_site"};
      bySite.set(s.id,s);
    }
    for(var j=0;j<locations.length;j++){
      var loc=location(locations[j]);
      if(!loc||loc.business_id!==requested||byLocation.has(loc.id))
        return {ok:false,reason:"invalid_location"};
      byLocation.add(loc.id);
      if(loc.site_id!==null&&!bySite.has(loc.site_id))
        return {ok:false,reason:"unverified_site_mapping"};
      out.push(Object.freeze({location_id:loc.id,site_id:loc.site_id,
        site_kind:loc.site_id===null?null:bySite.get(loc.site_id).kind}));
    }
    return {ok:true,business_id:requested,unmapped:out.filter(function(x){return x.site_id===null}).length,
      mappings:Object.freeze(out)};
  }
  return Object.freeze({SITE_KINDS:SITE_KINDS,id:id,kind:kind,site:site,location:location,reconcile:reconcile});
});
