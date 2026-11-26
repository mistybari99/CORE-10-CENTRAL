'use strict';
/* R01-01. Frozen original food-safety and temperature source-field
 * conditions are pinned. This is a synthetic nonposting review candidate,
 * NOT a food temperature specification, HACCP sign-off, physical inspection,
 * signed ERP incident/Stock write, or Owner-approved policy.
 */
const {createHash}=require('node:crypto');
const source=require('./source-helper-conditions.cjs');
const manifest=require('../ownership-246-1000.json');
const FIELDS=Object.freeze(['R-01:safety','R-01:safety_defect','R-01:expired_shown',
 'R-01:expired_removed','R-01:expired_informed','R-01:temp','R-01:temp_ok',
 'R-01:day_type','R-01:t2_1','R-01:t2_2']);
const owned=new Set([...manifest.lane_B_chatgpt.critical_86_keys,
 ...manifest.lane_B_chatgpt.mapped_150_keys,...manifest.lane_B_chatgpt.reserved_next_10_keys]);
if(FIELDS.some(x=>!owned.has(x)))throw Error('R01_SAFETY_OUTSIDE_246_LANE');
const RE=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$/;
const id=(x,label)=>{if(typeof x!=='string'||!RE.test(x))throw Error('R01_SAFETY_INVALID_REF:'+label);return x;};
function scoped(x,s,label){
 if(!x||x.tenantId!==s.tenantId||x.businessId!==s.businessId||x.siteId!==s.siteId)
  throw Error('R01_SAFETY_CROSS_TENANT_BUSINESS_SITE:'+label);
}
function temperature(x,label){
 const v=typeof x==='number'&&Number.isFinite(x)?String(x):x;
 if(typeof v!=='string'||! /^-?(?:0|[1-9]\d*)(?:\.\d{1,2})?$/.test(v))
  throw Error('R01_SAFETY_INVALID_CELSIUS:'+label);
 const n=Number(v);
 if(!Number.isFinite(n)||Math.abs(n)>1000)throw Error('R01_SAFETY_UNSAFE_CELSIUS:'+label);
 return Math.round(n*100);
}
function assertSource(){
 const text=source.readFrozen('forms');source.verifyEvidence();
 const st=text.indexOf('e.forms["R-01"]='),end=text.indexOf('e.forms[',st+1);
 if(st<0)throw Error('R01_SAFETY_ORIGINAL_FORM_NOT_FOUND');
 const body=text.slice(st,end<0?text.length:end);
 for(const frag of [
  '"safety_defect",t("ত্রুটির বিবরণ","Defect"),{show:e=>"no"===e.d.safety,req:e=>"no"===e.d.safety}',
  '"expired_removed",t("সরানো হয়েছে","Removed"),{show:e=>"yes"===e.d.expired_shown}',
  '"expired_informed",t("ব্যবস্থাপনাকে জানানো হয়েছে","Management informed"),{show:e=>"yes"===e.d.expired_shown}',
  '"t2_1",t("দ্বিতীয়বার তাপমাত্রা ১ °C (ব্যস্ত দিনে)","Second temperature 1 °C (busy day)"),{show:e=>"busy"===e.d.day_type}',
  '"t2_2",t("দ্বিতীয়বার তাপমাত্রা ২ °C","Second temperature 2 °C"),{show:e=>"busy"===e.d.day_type}',
  '"fridge"+o+"_min"','"fridge"+o+"_max"','x("temp_out_"+o,"red"'
 ])if(!body.includes(frag))throw Error('R01_SAFETY_PINNED_FORM_DRIFT:'+frag);
 return Object.freeze({originalBlob:source.PIN.forms,fields:FIELDS,
  oldCodeExecuted:false,sourceTemperatureLimits:'Control settings fridgeN_min/fridgeN_max',
  secondReadingsVisibleOn:'day_type=busy',sourceSecondReadingsRequired:false});
}
function reviewSafety({scope:s,day,policy,fridgeReadings,followups=[]}={}){
 const pin=assertSource();
 if(!s||s.synthetic_only!==true||![s.tenantId,s.businessId,s.siteId].every(x=>
  typeof x==='string'&&x.startsWith('DEMO-')&&RE.test(x)))
  throw Error('R01_SAFETY_SYNTHETIC_ONLY');
 scoped(day,s,'DAY');scoped(policy,s,'CONTROL_POLICY');
 if(!Array.isArray(policy.units)||policy.units.length<1||policy.units.length>20||
    !Array.isArray(fridgeReadings)||fridgeReadings.length>50||
    !Array.isArray(followups)||followups.length>40)
  throw Error('R01_SAFETY_SOURCE_COLLECTION_REQUIRED');
 id(day.sourceRef,'DAILY_R01');id(policy.sourceRef,'POLICY_SOURCE');
 if(!/^\d{4}-\d{2}-\d{2}$/.test(day.businessDate||'')||policy.businessDate!==day.businessDate)
  throw Error('R01_SAFETY_POLICY_DAY_MISMATCH');
 if(!['normal','busy'].includes(day.day_type))throw Error('R01_SAFETY_DAY_TYPE_UNKNOWN');
 if(!['yes','no'].includes(day.safety)||!['yes','no'].includes(day.expired_shown))
  throw Error('R01_SAFETY_UNKNOWN_HAZARD_STATUS');
 const blockers=[],flag=x=>{if(!blockers.includes(x))blockers.push(x);};
 const seen=new Set([day.sourceRef,policy.sourceRef]),units=new Map(),readingMap=new Map();
 for(const u of policy.units){
  scoped(u,s,'POLICY_UNIT');id(u.unitId,'FRIDGE_UNIT');id(u.sourceRef,'UNIT_POLICY_SOURCE');
  if(units.has(u.unitId)||seen.has(u.sourceRef))throw Error('R01_SAFETY_DUPLICATE_UNIT_OR_SOURCE');
  seen.add(u.sourceRef);units.set(u.unitId,u);
  if(u.minC==null||u.maxC==null){flag('R01_FRIDGE_CONTROL_LIMIT_MISSING:'+u.unitId);continue;}
  if(temperature(u.minC,'MIN')>temperature(u.maxC,'MAX'))
   throw Error('R01_FRIDGE_INVALID_CONTROL_RANGE');
  if(u.policyStatus!=='ACTIVE')
   flag('R01_FRIDGE_CONTROL_POLICY_NOT_ACTIVE:'+u.unitId);
 }
 function checked(r,label){
  scoped(r,s,label);id(r.sourceRef,label+'_SOURCE');
  if(seen.has(r.sourceRef))throw Error('R01_SAFETY_REPLAYED_SOURCE_REFERENCE');
  seen.add(r.sourceRef);
  if(!RE.test(r.observedBy||'')||!RE.test(r.checkedBy||'')||
    r.observedBy===r.checkedBy)flag('R01_FRIDGE_INDEPENDENT_CHECK_REQUIRED:'+label);
 }
 function checkTemp(unitId,raw,tag){
  const u=units.get(unitId);
  if(!u)throw Error('R01_SAFETY_UNKNOWN_FRIDGE_UNIT');
  const v=temperature(raw,tag);
  if(u.minC==null||u.maxC==null)return;
  if(v<temperature(u.minC,'MIN')||v>temperature(u.maxC,'MAX')){
   flag('R01_FRIDGE_ORIGINAL_RED_TEMPERATURE_OUT_OF_RANGE:'+tag);
   flag('R01_TEMPERATURE_EXCEPTION_NEEDS_SIGNED_QUALITY_REVIEW');
  }
 }
 for(const r of fridgeReadings){
  checked(r,'OPEN_FRIDGE');
  id(r.unitId,'OPEN_UNIT');
  if(readingMap.has(r.unitId))throw Error('R01_SAFETY_DUPLICATE_OPEN_READING');
  readingMap.set(r.unitId,r);
  checkTemp(r.unitId,r.tempC,'OPEN:'+r.unitId);
 }
 for(const id of units.keys())if(!readingMap.has(id))
  flag('R01_FRIDGE_INITIAL_TEMPERATURE_REQUIRED:'+id);
 if(day.day_type==='busy'){
  if(!Array.isArray(policy.secondReadingUnits)||policy.secondReadingUnits.length!==2)
   flag('R01_BUSY_SECOND_UNIT_MAPPING_POLICY_MISSING');
  if(!Array.isArray(day.secondReadings)||day.secondReadings.length!==2)
   flag('R01_BUSY_SECOND_TEMPERATURES_REQUIRED_BY_REVIEW');
  else for(const [i,r] of day.secondReadings.entries()){
   checked(r,'BUSY_SECOND_'+(i+1));
   if(Array.isArray(policy.secondReadingUnits)&&policy.secondReadingUnits.length===2&&
      r.unitId!==policy.secondReadingUnits[i])
    flag('R01_BUSY_SECOND_POLICY_UNIT_MISMATCH:'+(i+1));
   checkTemp(r.unitId,r.tempC,'BUSY_SECOND_'+(i+1));
  }
 }else if(day.secondReadings?.length)
  flag('R01_SECOND_TEMPERATURE_SOURCE_FIELD_HIDDEN_ON_NORMAL_DAY');
 if(day.safety==='no'){
  if(typeof day.safety_defect!=='string'||!day.safety_defect.trim())
   flag('R01_SAFETY_DEFECT_REQUIRED_BY_ORIGINAL_FORM');
  flag('R01_GAS_POWER_FIRE_HAZARD_NEEDS_SIGNED_ESCALATION');
 }else if(day.safety_defect)flag('R01_HIDDEN_SAFETY_DEFECT_REQUIRES_REVIEW');
 if(day.expired_shown==='yes'){
  if(day.expired_removed!==true)flag('R01_EXPIRED_PRODUCT_REMOVAL_NOT_ATTESTED');
  if(day.expired_informed!==true)flag('R01_EXPIRED_PRODUCT_MANAGEMENT_NOTICE_NOT_ATTESTED');
  flag('R01_EXPIRED_STOCK_DISPOSITION_NEEDS_SIGNED_QUALITY_AND_STOCK');
 }else if(day.expired_removed===true||day.expired_informed===true)
  flag('R01_EXPIRED_GOODS_ACTION_WITHOUT_SOURCE_OCCURRENCE');
 const types=new Set();
 for(const f of followups){
  scoped(f,s,'FOLLOWUP');id(f.sourceRef,'FOLLOWUP_SOURCE');
  if(seen.has(f.sourceRef))throw Error('R01_SAFETY_REPLAYED_SOURCE_REFERENCE');
  seen.add(f.sourceRef);
  if(!['SAFETY_ESCALATION','EXPIRED_QUARANTINE','MANAGEMENT_NOTICE',
       'TEMPERATURE_EXCEPTION'].includes(f.kind))throw Error('R01_SAFETY_UNKNOWN_FOLLOWUP');
  if(types.has(f.kind))throw Error('R01_SAFETY_DUPLICATE_FOLLOWUP_KIND');
  types.add(f.kind);
  if(!RE.test(f.maker||'')||!RE.test(f.checker||'')||f.maker===f.checker)
   flag('R01_SAFETY_INDEPENDENT_FOLLOWUP_REVIEW_REQUIRED:'+f.kind);
 }
 if(day.safety==='no'&&!types.has('SAFETY_ESCALATION'))
  flag('R01_MISSING_SAFETY_INCIDENT_EVIDENCE');
 if(day.expired_shown==='yes'&&(!types.has('EXPIRED_QUARANTINE')||
    !types.has('MANAGEMENT_NOTICE')))
  flag('R01_EXPIRED_DISPOSITION_SOURCE_INCOMPLETE');
 if(blockers.some(x=>x.startsWith('R01_FRIDGE_ORIGINAL_RED_'))&&
    !types.has('TEMPERATURE_EXCEPTION'))
  flag('R01_MISSING_TEMPERATURE_CORRECTIVE_ACTION_EVIDENCE');
 return Object.freeze({fieldIDs:pin.fields,status:blockers.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
  blockers:Object.freeze(blockers),evidence:Object.freeze({
   originalBlob:pin.originalBlob,fridgeUnits:units.size,openingReadings:readingMap.size,
   requiredBusySecondReadings:day.day_type==='busy'?2:0,
   sourceDigest:createHash('sha256').update(JSON.stringify({s,day,policy,fridgeReadings,followups})).digest('hex')}),
  syntheticOnly:true,sourceOnly:true,canonicalQualityVerified:false,
  canonicalStockVerified:false,controlPolicySignedVerified:false,
  temperatureFoodSafetyPolicyCertified:false,physicalInspectionVerified:false,
  ownerPolicyAccepted:false,canPost:false});
}
module.exports={assertSource,reviewSafety};
