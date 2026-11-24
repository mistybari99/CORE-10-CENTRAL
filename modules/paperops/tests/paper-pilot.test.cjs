'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {audit}=require('../paper-parity-audit.cjs');
const {runPilots}=require('../paper-pilot.cjs');
const trace=require('../control-trace.json');
const obligations=require('../control-obligations.json');
const source=require('../legacy-rule-candidates.json');
test('every critical source obligation traces exact old keys and flags into real printable fields',()=>{
 const x=audit();
 assert.equal(x.ok,true,x.problems.join(' | '));
 assert.equal(x.critical_obligations,20);
 assert.equal(x.gaps_still_open,11);
 assert.equal(x.partial_still_open,9);
 assert.equal(x.release_ready,false);
 assert.equal(x.owner_accepted,false);
 assert.equal(x.old_field_candidates,1246);
 assert.ok(x.uniquely_traced_critical_fields>=70);
 assert.ok(x.source_fields_without_critical_trace>1000,
  'do not pretend 1246 old source fields are all represented');
 assert.ok(x.mapped_gates>=15);
 for(const record of trace.records){
   assert.ok(record.unresolved.length>10,record.obligation_id);
   assert.equal(record.parity,'NOT_PROVEN');
   assert.equal(record.owner_acceptance,'NOT_REQUESTED');
   assert.equal(record.can_release,false);
 }
});
test('all 163 old warning-flag candidates remain indexed; draft mapping cannot erase them',()=>{
 assert.equal(source.totals.flag_candidates,163);
 assert.equal(source.forms.reduce((n,f)=>n+f.flag_candidates_count,0),163);
 const original=new Set(source.forms.flatMap(f=>f.flag_candidates.map(x=>f.legacy_code+':'+x.code)));
 for(const record of trace.records){
  const id=obligations.records.find(r=>r.id===record.obligation_id);
  assert.ok(id);
  for(const flag of record.legacy_flag_codes){
    assert.ok(original.has(record.legacy_form+':'+flag),'Untraceable flag '+flag);
  }
 }
});
test('eight synthetic operational scenarios reduce mandatory prints without dropping event documents',()=>{
 const r=runPilots();
 assert.equal(r.caseCount,8);
 assert.equal(r.allPass,true,JSON.stringify(r.cases.filter(x=>!x.passed)));
 const byId=new Map(r.cases.map(x=>[x.id,x]));
 assert.equal(byId.get('sweet_quiet').total,2);
 assert.equal(byId.get('sweet_quiet').siteCount,3);
 assert.equal(byId.get('sweet_jalebi_dispatch').total,4);
 assert.equal(byId.get('goods_mismatch_inbound').daily,0);
 assert.equal(byId.get('ecommerce_return_recon').event,3);
 assert.equal(byId.get('paint_color_mix').total,2);
 assert.equal(byId.get('construction_progress').daily,0);
 assert.ok(r.cases.every(x=>!x.ownerApproved&&!x.offlineAccountingComplete));
});
test('pilot outcomes are deterministic and never contain real business data',()=>{
 const a=runPilots(),b=runPilots();
 assert.deepEqual(a,b);
 assert.equal(a.synthetic_only,true);
 assert.equal(a.cases.length,8);
 assert.ok(a.cases.every(x=>x.issues.length===0));
});
