/* CORE 10 CENTRAL | A018 Enterprise Capability Contract v1
 * Read-only, deterministic catalog checks. Not a permission system.
 * The catalog lives in data/core10_capability_catalog_v1.json.
 * Do NOT use these helpers to authorize API/RPC/stock/finance actions.
 * Server-side authenticated tenant/business/site/action checks remain mandatory.
 */
(function(root, factory) {
  "use strict";
  var api=factory();
  if(typeof module==="object" && module.exports)module.exports=api;
  if(root)root.CORE10_FOUNDATION_CATALOG=api;
})(typeof window!=="undefined"?window:(typeof globalThis!=="undefined"?globalThis:null),function(){
  "use strict";
  var VALID_STATUS=["supported_and_tested","implemented_unverified","partial","not_implemented","not_applicable"];
  var VALID_SOURCE=["available","needs_setup","not_implemented","unregistered"];
  var EXPECTED=["sweets_bakery","restaurant","paint_hardware","retail_wholesale","general_manufacturing","construction","import_export","ecommerce","technology_digital","services"];
  var HIERARCHY=["platform","tenant","legal_entity","business","operating_site","stock_location"];
  var GATES=["end_to_end","authenticated_permissions","report_reconciliation","security_negative_tests","rollback_recovery"];
  var isObj=function(x){return x!==null&&typeof x==="object"&&!Array.isArray(x)};
  var txt=function(x){return typeof x==="string"&&x.trim().length>0};
  var has=function(a,v){return Array.isArray(a)&&a.indexOf(v)!==-1};
  function certified(item){
    if(!isObj(item)||!isObj(item.verification))return false;
    return GATES.every(function(g){return txt(item.verification[g])});
  }
  function validateCatalog(catalog){
    var errors=[];
    if(!isObj(catalog))return{ok:false,errors:["catalog_not_object"]};
    if(catalog.schema_version!==1)errors.push("unsupported_schema_version");
    if(!txt(catalog.version))errors.push("missing_catalog_version");
    if(!isObj(catalog.authority)||catalog.authority.action!=="C10-A018")errors.push("wrong_authoritative_action");
    if(!Array.isArray(catalog.templates)||catalog.templates.length<10)errors.push("missing_enterprise_templates");
    if(!isObj(catalog.enterprise_capacity_target))errors.push("missing_capacity_target");
    else{
      ["branches_per_business","factories_per_business","warehouses_per_business"].forEach(function(k){
        if(!Number.isInteger(catalog.enterprise_capacity_target[k])||catalog.enterprise_capacity_target[k]<100)errors.push("below_100_site_target:"+k);
      });
      if(catalog.enterprise_capacity_target.measured!==false)errors.push("scale_unverified_must_not_claim_measured");
      if(catalog.enterprise_capacity_target.hard_limit!==false)errors.push("capacity_target_cannot_be_hard_limit");
    }
    if(!isObj(catalog.invariants)||!catalog.invariants.require_backend_tenant_business_isolation||!catalog.invariants.preserve_existing_location_ids||!catalog.invariants.never_toggle_org_scope_on_automatically||!catalog.invariants.unknown_module_is_unavailable||!catalog.invariants.quick_setup_same_feature_catalog)errors.push("missing_core_safety_invariants");
    var hierarchy=Array.isArray(catalog.canonical_hierarchy)?catalog.canonical_hierarchy.map(function(x){return x&&x.kind}):[];
    if(HIERARCHY.some(function(k,i){return hierarchy[i]!==k}))errors.push("noncanonical_target_hierarchy");
    var seen=new Set();
    var src=new Set();
    var templates=Array.isArray(catalog.templates)?catalog.templates:[];
    templates.forEach(function(t,i){
      var prefix="templates[" + i + "]";
      if(!isObj(t)){errors.push(prefix+":not_object");return}
      if(!txt(t.id)||seen.has(t.id)){errors.push(prefix+":duplicate_or_invalid_id");return}
      seen.add(t.id);
      if(!txt(t.name_en))errors.push(prefix+":missing_name");
      if(!has(VALID_SOURCE,t.source_status))errors.push(prefix+":invalid_source_status");
      if(!has(VALID_STATUS,t.readiness))errors.push(prefix+":invalid_readiness");
      if(t.source_status==="unregistered"&&t.source_code!==null)errors.push(prefix+":unregistered_has_live_code");
      if(t.source_status!=="unregistered"&&!txt(t.source_code))errors.push(prefix+":registered_missing_live_code");
      if(txt(t.source_code)){if(src.has(t.source_code))errors.push(prefix+":duplicate_live_code");src.add(t.source_code)}
      if(!Array.isArray(t.modules))errors.push(prefix+":modules_not_array");
      var mods=new Set();
      (Array.isArray(t.modules)?t.modules:[]).forEach(function(m,j){
        if(!isObj(m)||!txt(m.id)||mods.has(m.id)){errors.push(prefix+":invalid_or_duplicate_module_"+j);return}
        mods.add(m.id);
        if(!has(VALID_STATUS,m.status))errors.push(prefix+":invalid_module_status_"+m.id);
        if(m.status==="supported_and_tested"&&!certified(m))errors.push(prefix+":uncertified_module_"+m.id);
      });
      if(t.readiness==="supported_and_tested"&&!certified(t))errors.push(prefix+":uncertified_template");
      if(t.readiness==="supported_and_tested"&&t.source_status!=="available")errors.push(prefix+":cannot_certify_unavailable_template");
      if(t.readiness==="supported_and_tested"&&Array.isArray(t.modules)&&t.modules.some(function(m){return m.status!=="supported_and_tested"}))errors.push(prefix+":module_not_certified");
    });
    EXPECTED.forEach(function(id){if(!seen.has(id))errors.push("missing_primary_template:"+id)});
    if(!Array.isArray(catalog.optional_packs))errors.push("missing_optional_packs");
    if(!Array.isArray(catalog.enterprise_capability_coverage)||catalog.enterprise_capability_coverage.length<10)errors.push("insufficient_enterprise_capability_coverage");
    return{ok:errors.length===0,errors:errors};
  }
  function findTemplate(catalog,id){
    if(!isObj(catalog)||!Array.isArray(catalog.templates)||!txt(id))return null;
    return catalog.templates.find(function(t){return isObj(t)&&t.id===id})||null;
  }
  function findTemplateByLiveCode(catalog,code){
    if(!isObj(catalog)||!Array.isArray(catalog.templates)||!txt(code))return null;
    return catalog.templates.find(function(t){return isObj(t)&&t.source_code===code})||null;
  }
  function assessReadiness(catalog,id){
    var validation=validateCatalog(catalog);
    if(!validation.ok)return{eligible:false,template_id:id||null,reasons:["INVALID_CATALOG"].concat(validation.errors)};
    var template=findTemplate(catalog,id);
    if(!template)return{eligible:false,template_id:id||null,reasons:["UNKNOWN_TEMPLATE"]};
    var reasons=[];
    if(template.source_status!=="available")reasons.push("BACKEND_NOT_AVAILABLE");
    if(template.readiness!=="supported_and_tested")reasons.push("TEMPLATE_NOT_CERTIFIED");
    if(!certified(template))reasons.push("MISSING_E2E_EVIDENCE");
    template.modules.forEach(function(m){
      if(m.status!=="supported_and_tested"||!certified(m))reasons.push("MODULE_NOT_CERTIFIED:"+m.id);
    });
    return{eligible:reasons.length===0,template_id:template.id,reasons:reasons,source_status:template.source_status,readiness:template.readiness};
  }
  function listTemplateSummaries(catalog){
    if(!validateCatalog(catalog).ok)return[];
    return catalog.templates.map(function(t){
      var gate=assessReadiness(catalog,t.id);
      return{id:t.id,name_en:t.name_en,live_code:t.source_code,live_status:t.source_status,readiness:t.readiness,eligible:gate.eligible,blocking_reasons:gate.reasons.slice()};
    });
  }
  return Object.freeze({
    VALID_STATUS:Object.freeze(VALID_STATUS.slice()),
    EXPECTED_PRIMARY_TEMPLATES:Object.freeze(EXPECTED.slice()),
    CANONICAL_HIERARCHY:Object.freeze(HIERARCHY.slice()),
    validateCatalog:validateCatalog,
    findTemplate:findTemplate,
    findTemplateByLiveCode:findTemplateByLiveCode,
    assessReadiness:assessReadiness,
    listTemplateSummaries:listTemplateSummaries
  });
});
