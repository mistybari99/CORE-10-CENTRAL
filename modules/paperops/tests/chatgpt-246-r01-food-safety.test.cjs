'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {assertSource,reviewSafety}=require('../field-review/chatgpt-246/r01-food-safety-review.cjs');
const owned=require('../field-review/ownership-246-1000.json');
const S={tenantId:'DEMO-TENANT-1',businessId:'DEMO-BIZ-1',siteId:'DEMO-SITE-1'};
const r=x=>({...S,...x});
function sample(){
 return {scope:{...S,synthetic_only:true},
  day:r({sourceRef:'DEMO-R01-SHEET-1',businessDate:'2026-11-23',
   day_type:'normal',safety:'yes',safety_defect:'',expired_shown:'no',
   expired_removed:false,expired_informed:false,secondReadings:[]}),
  policy:r({sourceRef:'DEMO-FRIDGE-POLICY',businessDate:'2026-11-23',
   secondReadingUnits:['DEMO-FRIDGE1','DEMO-FRIDGE2'],units:[
    r({sourceRef:'DEMO-UNIT-CONTROL-1',unitId:'DEMO-FRIDGE1',
     minC:'2',maxC:'8',policyStatus:'ACTIVE'}),
    r({sourceRef:'DEMO-UNIT-CONTROL-2',unitId:'DEMO-FRIDGE2',
     minC:'2',maxC:'8',policyStatus:'ACTIVE'})]}),
  fridgeReadings:[
   r({sourceRef:'DEMO-FRIDGE-READ1',unitId:'DEMO-FRIDGE1',
    tempC:'4.5',observedBy:'DEMO-OBSERVER',checkedBy:'DEMO-CHECKER'}),
   r({sourceRef:'DEMO-FRIDGE-READ2',unitId:'DEMO-FRIDGE2',
    tempC:'6',observedBy:'DEMO-OBSERVER',checkedBy:'DEMO-CHECKER'})],
  followups:[]};
}
const edit=fn=>{const v=sample();fn(v);return reviewSafety(v);};
function busy(v){
 v.day.day_type='busy';
 v.day.secondReadings=[
  r({sourceRef:'DEMO-BUSY-READ1',unitId:'DEMO-FRIDGE1',tempC:'5',
   observedBy:'DEMO-OBS2',checkedBy:'DEMO-CHECK2'}),
  r({sourceRef:'DEMO-BUSY-READ2',unitId:'DEMO-FRIDGE2',tempC:'7',
   observedBy:'DEMO-OBS2',checkedBy:'DEMO-CHECK2'})];
}
test('R01 frozen exact safety, expired and busy-day visibility plus temperature red severity is pinned',()=>{
 const p=assertSource();
 assert.equal(p.oldCodeExecuted,false);assert.equal(p.sourceSecondReadingsRequired,false);
 const allowed=new Set([...owned.lane_B_chatgpt.critical_86_keys,
  ...owned.lane_B_chatgpt.mapped_150_keys,...owned.lane_B_chatgpt.reserved_next_10_keys]);
 assert.ok(p.fields.every(x=>allowed.has(x)));
 assert.ok(!p.fields.includes('R-01:refund'));
 const ok=edit(()=>{});
 assert.equal(ok.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(ok.blockers));
 assert.equal(ok.evidence.fridgeUnits,2);assert.equal(ok.evidence.openingReadings,2);
 assert.equal(ok.evidence.sourceDigest,edit(()=>{}).evidence.sourceDigest);
 assert.equal(ok.canPost,false);assert.equal(ok.temperatureFoodSafetyPolicyCertified,false);
});
test('R01 busy day gets two original second values and independent externally defined unit mapping',()=>{
 const ok=edit(busy);
 assert.equal(ok.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(ok.blockers));
 assert.equal(ok.evidence.requiredBusySecondReadings,2);
 assert.ok(edit(v=>{v.day.day_type='busy';v.day.secondReadings=[]})
  .blockers.includes('R01_BUSY_SECOND_TEMPERATURES_REQUIRED_BY_REVIEW'));
 assert.ok(edit(v=>{busy(v);v.policy.secondReadingUnits=[]})
  .blockers.includes('R01_BUSY_SECOND_UNIT_MAPPING_POLICY_MISSING'));
 assert.ok(edit(v=>{busy(v);v.day.secondReadings[1].unitId='DEMO-FRIDGE1'})
  .blockers.includes('R01_BUSY_SECOND_POLICY_UNIT_MISMATCH:2'));
 assert.ok(edit(v=>{busy(v);v.day.secondReadings[1].tempC='9'})
  .blockers.includes('R01_FRIDGE_ORIGINAL_RED_TEMPERATURE_OUT_OF_RANGE:BUSY_SECOND_2'));
 assert.ok(edit(v=>{busy(v);v.day.day_type='normal'})
  .blockers.includes('R01_SECOND_TEMPERATURE_SOURCE_FIELD_HIDDEN_ON_NORMAL_DAY'));
});
test('R01 fridge limit is supplied by Control, missing or inactive policy fails closed',()=>{
 assert.ok(edit(v=>{v.fridgeReadings[0].tempC='8.01'})
  .blockers.includes('R01_FRIDGE_ORIGINAL_RED_TEMPERATURE_OUT_OF_RANGE:OPEN:DEMO-FRIDGE1'));
 assert.ok(edit(v=>{v.policy.units[0].minC=null})
  .blockers.includes('R01_FRIDGE_CONTROL_LIMIT_MISSING:DEMO-FRIDGE1'));
 assert.ok(edit(v=>{v.policy.units[0].policyStatus='RETIRED'})
  .blockers.includes('R01_FRIDGE_CONTROL_POLICY_NOT_ACTIVE:DEMO-FRIDGE1'));
 assert.ok(edit(v=>{v.fridgeReadings=[]})
  .blockers.includes('R01_FRIDGE_INITIAL_TEMPERATURE_REQUIRED:DEMO-FRIDGE1'));
 assert.throws(()=>edit(v=>{v.policy.units[0].minC='9'}),/R01_FRIDGE_INVALID_CONTROL_RANGE/);
 assert.throws(()=>edit(v=>{v.fridgeReadings[0].tempC='4.567'}),/R01_SAFETY_INVALID_CELSIUS/);
});
test('R01 gas fire safety and expired stock require escalation, quarantine and approved quality hold',()=>{
 const hazard=edit(v=>{v.day.safety='no';v.day.safety_defect='gas smell'});
 assert.ok(hazard.blockers.includes('R01_GAS_POWER_FIRE_HAZARD_NEEDS_SIGNED_ESCALATION'));
 assert.ok(hazard.blockers.includes('R01_MISSING_SAFETY_INCIDENT_EVIDENCE'));
 assert.ok(edit(v=>{v.day.safety='no';v.day.safety_defect=''})
  .blockers.includes('R01_SAFETY_DEFECT_REQUIRED_BY_ORIGINAL_FORM'));
 const expired=edit(v=>{v.day.expired_shown='yes';v.day.expired_removed=true;v.day.expired_informed=true});
 assert.ok(expired.blockers.includes('R01_EXPIRED_STOCK_DISPOSITION_NEEDS_SIGNED_QUALITY_AND_STOCK'));
 assert.ok(expired.blockers.includes('R01_EXPIRED_DISPOSITION_SOURCE_INCOMPLETE'));
 assert.ok(edit(v=>{v.day.expired_shown='yes'})
  .blockers.includes('R01_EXPIRED_PRODUCT_REMOVAL_NOT_ATTESTED'));
 assert.ok(edit(v=>{v.day.expired_shown='yes'})
  .blockers.includes('R01_EXPIRED_PRODUCT_MANAGEMENT_NOTICE_NOT_ATTESTED'));
 assert.ok(edit(v=>{v.day.expired_removed=true})
  .blockers.includes('R01_EXPIRED_GOODS_ACTION_WITHOUT_SOURCE_OCCURRENCE'));
});
test('R01 source follow-up references are append-only and cannot falsely authorize exceptions',()=>{
 const held=edit(v=>{v.day.safety='no';v.day.safety_defect='power outage';
  v.followups=[r({kind:'SAFETY_ESCALATION',sourceRef:'DEMO-INCIDENT1',
   maker:'DEMO-MGR1',checker:'DEMO-MGR2'})]});
 assert.ok(held.blockers.includes('R01_GAS_POWER_FIRE_HAZARD_NEEDS_SIGNED_ESCALATION'));
 assert.ok(!held.blockers.includes('R01_MISSING_SAFETY_INCIDENT_EVIDENCE'));
 assert.equal(held.canonicalQualityVerified,false);
 assert.throws(()=>edit(v=>{v.followups=[r({kind:'SAFETY_ESCALATION',
  sourceRef:v.fridgeReadings[0].sourceRef,maker:'DEMO-1',checker:'DEMO-2'})]}),
  /R01_SAFETY_REPLAYED_SOURCE_REFERENCE/);
 assert.throws(()=>edit(v=>{v.followups=[
  r({kind:'SAFETY_ESCALATION',sourceRef:'DEMO-EVENT1',maker:'DEMO-1',checker:'DEMO-2'}),
  r({kind:'SAFETY_ESCALATION',sourceRef:'DEMO-EVENT2',maker:'DEMO-3',checker:'DEMO-4'})]}),
  /R01_SAFETY_DUPLICATE_FOLLOWUP_KIND/);
});
test('R01 safety site isolation, unit replay, observer role conflict and hidden day info held',()=>{
 assert.throws(()=>edit(v=>{v.scope.synthetic_only=false}),/R01_SAFETY_SYNTHETIC_ONLY/);
 assert.throws(()=>edit(v=>{v.policy.tenantId='OTHER'}),/R01_SAFETY_CROSS_TENANT_BUSINESS_SITE/);
 assert.throws(()=>edit(v=>{v.fridgeReadings[1].siteId='DEMO-OTHER'}),/R01_SAFETY_CROSS_TENANT_BUSINESS_SITE/);
 assert.throws(()=>edit(v=>{v.fridgeReadings[1].sourceRef=v.fridgeReadings[0].sourceRef}),
  /R01_SAFETY_REPLAYED_SOURCE_REFERENCE/);
 assert.throws(()=>edit(v=>{v.fridgeReadings[1].unitId=v.fridgeReadings[0].unitId}),
  /R01_SAFETY_DUPLICATE_OPEN_READING/);
 assert.ok(edit(v=>{v.fridgeReadings[0].checkedBy=v.fridgeReadings[0].observedBy})
  .blockers.includes('R01_FRIDGE_INDEPENDENT_CHECK_REQUIRED:OPEN_FRIDGE'));
});
