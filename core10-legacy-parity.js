/* CORE 10 | Historical business app regression. Isolated from the neutral industry catalog. */
(function(root,factory){"use strict";const api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.CORE10_LEGACY_PARITY=api;})(typeof window!=="undefined"?window:globalThis,function(){
"use strict";
const ranks=Object.freeze({unavailable:0,incomplete:1,unverified:2,implemented:3});
const own=(o,k)=>Object.prototype.hasOwnProperty.call(o,k);
function check(baseline,registry,filePaths){
 const errors=[];
 if(!baseline||baseline.schema_version!==1||!Array.isArray(baseline.legacy_reports)||
    !Array.isArray(baseline.legacy_files)||!Array.isArray(baseline.sweets_module_ids)||
    !baseline.legacy_module_assets||typeof baseline.legacy_module_assets!=="object"){
   return {ok:false,errors:["INVALID_BASELINE"]};
 }
 if(!registry||!Array.isArray(registry.reports))return {ok:false,errors:["INVALID_CURRENT_REPORT_REGISTRY"]};
 const seen=new Map(),numbers=new Set();
 for(const r of registry.reports){
  if(!r||!r.id||seen.has(r.id)||!Number.isInteger(r.no)||numbers.has(r.no)){errors.push("DUPLICATE_OR_INVALID_REPORT");continue}
  seen.set(r.id,r);numbers.add(r.no);
 }
 for(const r of baseline.legacy_reports){
  const present=seen.get(r.id);
  if(!present){errors.push("MISSING_REPORT:"+r.id);continue}
  if(present.no!==r.no)errors.push("REPORT_NUMBER_CHANGED:"+r.id);
  if(!present.name||present.name.bn!==r.name_bn||present.name.en!==r.name_en)errors.push("REPORT_NAME_CHANGED:"+r.id);
  if(present.route!==r.route)errors.push("REPORT_ROUTE_CHANGED:"+r.id);
  if(present.area!==r.area)errors.push("REPORT_AREA_CHANGED:"+r.id);
  if(!own(ranks,present.status)||ranks[present.status]<ranks[r.status])errors.push("REPORT_STATUS_REGRESSED:"+r.id);
 }
 if(registry.total!==registry.reports.length||registry.reports.length<baseline.legacy_reports.length)
   errors.push("REPORT_TOTAL_INVALID");
 const expected=new Set(baseline.sweets_module_ids);
 if(Object.keys(baseline.legacy_module_assets).length!==expected.size)
   errors.push("LEGACY_MODULE_MAP_INCONSISTENT");
 for(const moduleId of expected){
  const assets=baseline.legacy_module_assets[moduleId];
  if(!Array.isArray(assets)||!assets.length)errors.push("LEGACY_MODULE_MAP_INCOMPLETE:"+moduleId);
 }
 if(filePaths!==undefined&&filePaths!==null){
  if(!Array.isArray(filePaths))errors.push("INVALID_FILE_LIST");
  else{
   const present=new Set(filePaths);
   for(const path of baseline.legacy_files)if(!present.has(path))errors.push("LEGACY_FILE_REMOVED:"+path);
   for(const path of baseline.protected_entry_routes||[])if(!present.has(path))errors.push("LEGACY_ENTRY_REMOVED:"+path);
   for(const moduleId of expected){
    for(const p of baseline.legacy_module_assets[moduleId]||[])
     if(!present.has(p))errors.push("LEGACY_MODULE_FILE_REMOVED:"+moduleId+":"+p);
   }
  }
 }
 return Object.freeze({ok:errors.length===0,errors,checked:Object.freeze({
  reports:baseline.legacy_reports.length,
  legacyFiles:filePaths==null?null:baseline.legacy_files.length,
  protectedModules:baseline.sweets_module_ids.length
 }),registryStatusCounts:registry.status_counts||null});
}
return Object.freeze({check});
});