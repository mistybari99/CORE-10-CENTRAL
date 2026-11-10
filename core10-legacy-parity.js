/* CORE 10 CENTRAL | Existing Islamia ERP no-loss release contract
 * This checks static/module/report compatibility. It is not an RLS or production E2E certificate.
 */
(function(root,factory){"use strict";var api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.CORE10_LEGACY_PARITY=api;})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 const ranks=Object.freeze({unavailable:0,incomplete:1,unverified:2,implemented:3});
 const own=(o,k)=>Object.prototype.hasOwnProperty.call(o,k);
 function check(baseline,registry,catalog,filePaths){
  const errors=[];
  if(!baseline||baseline.schema_version!==1||!Array.isArray(baseline.legacy_reports)||
    !Array.isArray(baseline.legacy_files)||!Array.isArray(baseline.sweets_module_ids)){
    return {ok:false,errors:["INVALID_BASELINE"]};
  }
  if(!registry||!Array.isArray(registry.reports))return {ok:false,errors:["INVALID_CURRENT_REPORT_REGISTRY"]};
  if(!catalog||!Array.isArray(catalog.templates))return {ok:false,errors:["INVALID_CURRENT_TEMPLATE_CATALOG"]};
  const reports=new Map(),reportNos=new Set();
  for(const row of registry.reports){
   if(!row||!row.id||reports.has(row.id)||!Number.isInteger(row.no)||reportNos.has(row.no)){
    errors.push("DUPLICATE_OR_INVALID_REPORT");continue;
   }
   reportNos.add(row.no);reports.set(row.id,row);
  }
  for(const row of baseline.legacy_reports){
   const found=reports.get(row.id);
   if(!found){errors.push("MISSING_REPORT:"+row.id);continue}
   if(found.no!==row.no)errors.push("REPORT_NUMBER_CHANGED:"+row.id);
   if(!found.name||found.name.bn!==row.name_bn||found.name.en!==row.name_en)
     errors.push("REPORT_NAME_CHANGED:"+row.id);
   if(found.route!==row.route)errors.push("REPORT_ROUTE_CHANGED:"+row.id);
   if(found.area!==row.area)errors.push("REPORT_AREA_CHANGED:"+row.id);
   if(!own(ranks,found.status)||ranks[found.status]<ranks[row.status])
     errors.push("REPORT_STATUS_REGRESSED:"+row.id);
  }
  if(registry.total!==registry.reports.length||
      registry.reports.length<baseline.legacy_reports.length)
    errors.push("REPORT_TOTAL_INVALID");
  // The legacy app/report contract stays private to its own Business Workspace.
  // Never require a generic industry template to point at the legacy template/backend.
  const shared=catalog.templates.find(x=>x.id==="sweets_bakery");
  if(!shared||!Array.isArray(shared.modules))errors.push("INVALID_SHARED_INDUSTRY_TEMPLATE");
  else{
   if(shared.source_code===baseline.legacy_food_template_code)
     errors.push("LEGACY_BACKEND_BOUND_TO_SHARED_TEMPLATE");
   if(shared.readiness==="supported_and_tested"&&shared.source_status!=="available")
     errors.push("UNVERIFIED_SHARED_TEMPLATE_CLAIM");
  }
  if(filePaths!==undefined&&filePaths!==null){
   if(!Array.isArray(filePaths))errors.push("INVALID_FILE_LIST");
   else{
    const present=new Set(filePaths);
    for(const path of baseline.legacy_files)if(!present.has(path))errors.push("LEGACY_FILE_REMOVED:"+path);
    for(const path of baseline.protected_entry_routes||[])if(!present.has(path))errors.push("LEGACY_ENTRY_REMOVED:"+path);
   }
  }
  return Object.freeze({ok:errors.length===0,errors,
   checked:Object.freeze({reports:baseline.legacy_reports.length,legacyFiles:filePaths==null?null:baseline.legacy_files.length,
    protectedModules:baseline.sweets_module_ids.length}),
   registryStatusCounts:registry.status_counts||null});
 }
 return Object.freeze({check});
});