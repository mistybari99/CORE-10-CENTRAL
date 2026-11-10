/* CORE 10 CENTRAL | C10-A018 legacy entity compatibility preflight v1
 * Pure, read-only structural analysis of explicitly supplied snapshots.
 * Not authorization, migration SQL, tenant certification or a release gate.
 * Never infer platform/tenant/operating-site IDs from legacy group/client/location IDs.
 */
(function(root,factory){
  "use strict";
  var api=factory();
  if(typeof module==="object" && module.exports)module.exports=api;
  if(root)root.CORE10_ENTITY_COMPATIBILITY=api;
})(typeof window!=="undefined"?window:(typeof globalThis!=="undefined"?globalThis:null),function(){
  "use strict";
  var SITE_KINDS=["operating_site","site","branch","showroom","factory","godown","warehouse","project"];
  var PARENTS={group:null,legal_entity:"group",business:"legal_entity"};
  SITE_KINDS.forEach(function(k){PARENTS[k]="business"});
  function obj(v){return v!==null&&typeof v==="object"&&!Array.isArray(v)}
  function txt(v){return typeof v==="string"&&v.trim().length>0}
  function key(v){
    if(typeof v==="number"&&Number.isSafeInteger(v)&&v>0)return String(v);
    if(typeof v==="string"&&/^[1-9][0-9]*$/.test(v))return v;
    return null;
  }
  function result(errors,warnings,mappings,summary){
    return{
      ok:errors.length===0,
      errors:errors,
      warnings:warnings,
      mappings:errors.length===0?mappings:[],
      summary:summary,
      certifications:{
        tenant_isolation_verified:false,
        operating_site_security_verified:false,
        live_authenticated_tests_passed:false,
        scale_measured:false,
        release_ready:false
      }
    };
  }
  function analyzeLegacyEntitySnapshot(snapshot,catalog){
    var errors=[],warnings=[],mappings=[];
    var summary={org_units:0,businesses:0,locations:0,operating_sites:0,legacy_direct_locations:0,explicit_site_locations:0};
    if(!obj(snapshot)||!["org_units","locations","business_profiles","business_templates"].every(function(k){return Array.isArray(snapshot[k])}))
      return result(["INVALID_SNAPSHOT_SHAPE"],[],[],summary);
    if(!obj(catalog)||!Array.isArray(catalog.templates)||!Array.isArray(catalog.optional_packs)||
       !Array.isArray(catalog.canonical_hierarchy)||catalog.canonical_hierarchy.map(function(x){return x&&x.kind}).join("/")!=="platform/tenant/legal_entity/business/operating_site/stock_location")
      return result(["INVALID_CANONICAL_CATALOG"],[],[],summary);
    var liveCodes=new Map(),catalogCodes=new Map();
    catalog.templates.concat(catalog.optional_packs).forEach(function(t){
      if(obj(t)&&txt(t.source_code))catalogCodes.set(t.source_code,t);
    });
    snapshot.business_templates.forEach(function(t){
      if(!obj(t)||!txt(t.code)){errors.push("INVALID_LIVE_TEMPLATE");return}
      if(liveCodes.has(t.code))errors.push("DUPLICATE_LIVE_TEMPLATE:"+t.code);
      liveCodes.set(t.code,t);
      var declared=catalogCodes.get(t.code);
      if(declared&&declared.source_status!==t.status)warnings.push("TEMPLATE_STATUS_DRIFT:"+t.code);
    });
    var nodes=new Map(),locationIds=new Set(),profileIds=new Set();
    snapshot.org_units.forEach(function(n){
      var id=obj(n)&&key(n.id);
      if(!id){errors.push("INVALID_ORG_ID");return}
      if(nodes.has(id))errors.push("DUPLICATE_ORG_ID:"+id);
      if(!txt(n.kind)||!Object.prototype.hasOwnProperty.call(PARENTS,n.kind))errors.push("UNKNOWN_ORG_KIND:"+id);
      nodes.set(id,n);
      summary.org_units++;
      if(n.kind==="business")summary.businesses++;
      if(SITE_KINDS.includes(n.kind))summary.operating_sites++;
    });
    snapshot.org_units.forEach(function(n){
      var id=obj(n)&&key(n.id);
      if(!id||!Object.prototype.hasOwnProperty.call(PARENTS,n.kind))return;
      var wanted=PARENTS[n.kind],parentId=n.parent_id==null?null:key(n.parent_id);
      if(wanted===null){
        if(parentId!==null)errors.push("ROOT_HAS_PARENT:"+id);
        return;
      }
      var parent=parentId&&nodes.get(parentId);
      if(!parent||parent.kind!==wanted){errors.push("INVALID_PARENT:"+id);return}
      if(txt(n.client_id)&&txt(parent.client_id)&&n.client_id!==parent.client_id)
        errors.push("CROSS_CLIENT_PARENT:"+id);
      if(n.kind==="business"){
        if(!txt(n.template_code)||!liveCodes.has(n.template_code)){
          errors.push("UNREGISTERED_BUSINESS_TEMPLATE:"+id);
        }else if(n.template_code==="food_manufacturing"){
          // REV-009: this historical legacy business is structurally mapped,
          // but NEVER becomes the neutral sweets/bakery engine or shared tenant adapter.
          var neutral=catalog.templates.find(function(t){return t&&t.id==="sweets_bakery"});
          if(!neutral||neutral.source_code!==null||neutral.source_status==="available")
            errors.push("LEGACY_FOOD_TEMPLATE_NOT_ISOLATED:"+id);
          else warnings.push("LEGACY_FOOD_SOURCE_ISOLATED:"+id);
        }else if(!catalogCodes.has(n.template_code)){
          errors.push("UNREGISTERED_BUSINESS_TEMPLATE:"+id);
        }
      }
    });
    snapshot.business_profiles.forEach(function(p){
      var id=obj(p)&&key(p.org_unit_id);
      if(!id){errors.push("INVALID_PROFILE_BUSINESS_ID");return}
      if(profileIds.has(id))errors.push("DUPLICATE_BUSINESS_PROFILE:"+id);
      profileIds.add(id);
      if(!nodes.has(id)||nodes.get(id).kind!=="business")errors.push("PROFILE_NOT_BUSINESS:"+id);
    });
    snapshot.org_units.forEach(function(n){
      if(obj(n)&&n.kind==="business"&&!profileIds.has(key(n.id)))warnings.push("MISSING_BUSINESS_PROFILE:"+key(n.id));
    });
    snapshot.locations.forEach(function(l){
      var id=obj(l)&&key(l.id);
      if(!id){errors.push("INVALID_LOCATION_ID");return}
      if(locationIds.has(id))errors.push("DUPLICATE_LOCATION_ID:"+id);
      locationIds.add(id);
      summary.locations++;
      if(!txt(l.code)||!txt(l.kind))errors.push("INCOMPLETE_LOCATION:"+id);
      var ownerId=key(l.org_unit_id),owner=ownerId&&nodes.get(ownerId),business=null,siteId=null;
      if(!owner){errors.push("UNMAPPED_LOCATION:"+id);return}
      if(owner.kind==="business"){
        business=owner;
        summary.legacy_direct_locations++;
      }else if(SITE_KINDS.includes(owner.kind)){
        siteId=ownerId;
        business=nodes.get(key(owner.parent_id));
        summary.explicit_site_locations++;
      }else{
        errors.push("LOCATION_PARENT_NOT_SITE_OR_BUSINESS:"+id);return;
      }
      if(!business||business.kind!=="business"){errors.push("LOCATION_BUSINESS_NOT_FOUND:"+id);return}
      var legal=nodes.get(key(business.parent_id));
      var group=legal&&nodes.get(key(legal.parent_id));
      if(!legal||legal.kind!=="legal_entity"||!group||group.kind!=="group"){
        errors.push("LOCATION_ANCESTRY_INVALID:"+id);return;
      }
      mappings.push({
        legacy_location_id:l.id,
        legacy_org_unit_id:l.org_unit_id,
        legacy_location_code:l.code,
        stock_location_kind:l.kind,
        operating_site_id:siteId,
        site_mapping_state:siteId?"explicit_site":"legacy_business_direct",
        business_id:business.id,
        legal_entity_id:legal.id,
        legacy_group_id:group.id,
        tenant_id:null,
        platform_id:null
      });
    });
    if(summary.legacy_direct_locations)warnings.push("OPERATING_SITE_LAYER_MISSING:"+summary.legacy_direct_locations);
    warnings.push("TENANT_BOUNDARY_NOT_PROVEN");
    warnings.push("RLS_RPC_AUTHORIZATION_NOT_TESTED");
    return result(errors,warnings,mappings,summary);
  }
  return Object.freeze({analyzeLegacyEntitySnapshot:analyzeLegacyEntitySnapshot});
});
