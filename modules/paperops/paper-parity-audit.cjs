'use strict';
/* A reproducible control trace gate. This never executes historical application code.
 * Mapping is a candid draft: no positive parity or approval conclusions are permitted.
 */
const fs=require('node:fs'),path=require('node:path');
const root=__dirname;
const old=require('./legacy-rule-candidates.json');
const obligations=require('./control-obligations.json');
const trace=require('./control-trace.json');
const paperops=require('./paperops.js');
require('./form-packs.js');
const math=require('./paper-math.js');
const controls=require('./paper-controls.js');
function unique(arr){return new Set(arr).size===arr.length;}
function audit(){
 const problems=[],forms=old.forms,targets=paperops.TEMPLATES,records=trace.records;
 if(records.length!==20)problems.push('EXPECTED_20_CRITICAL_TRACES');
 if(!unique(records.map(r=>r.obligation_id)))problems.push('DUPLICATE_OBLIGATION_TRACE');
 if(!unique(targets.map(f=>f.id)))problems.push('DUPLICATE_PRINT_TEMPLATE_ID');
 const mapped=new Set();
 let withGate=0;
 for(const src of obligations.records){
  const r=records.find(x=>x.obligation_id===src.id);
  if(!r){problems.push('MISSING_TRACE:'+src.id);continue;}
  const original=forms.find(f=>f.legacy_code===src.legacy_form);
  const target=targets.find(f=>f.id===r.print_form);
  if(!original||!target){problems.push('BROKEN_SOURCE_OR_TARGET:'+src.id);continue;}
  if(r.legacy_form!==src.legacy_form||r.print_form!==src.draft_target)
    problems.push('OBLIGATION_SOURCE_DRIFT:'+src.id);
  if(!Array.isArray(r.legacy_field_keys)||!unique(r.legacy_field_keys)||!r.legacy_field_keys.length)
    problems.push('INVALID_SOURCE_FIELDS:'+src.id);
  const knownLegacy=new Set(original.fields.map(f=>f.key));
  for(const key of r.legacy_field_keys){
   mapped.add(original.legacy_code+':'+key);
   if(!knownLegacy.has(key))problems.push('UNKNOWN_ORIGINAL_FIELD:'+src.id+':'+key);
  }
  for(const key of src.legacy_field_keys)
   if(!r.legacy_field_keys.includes(key))problems.push('DROPPED_OBLIGATION_FIELD:'+src.id+':'+key);
  const targetFields=new Set(target.sections.flatMap(x=>x.fields.map(f=>f.key)));
  if(!r.print_field_keys?.length||!unique(r.print_field_keys))problems.push('INVALID_PRINT_FIELDS:'+src.id);
  for(const key of r.print_field_keys||[])
   if(!targetFields.has(key))problems.push('MISSING_PRINT_FIELD:'+src.id+':'+key);
  const sourceFlags=new Set(original.flag_candidates.map(f=>f.code));
  for(const code of r.legacy_flag_codes||[])
   if(!sourceFlags.has(code))problems.push('UNTRACEABLE_OLD_BLOCKER:'+src.id+':'+code);
  if(r.candidate_gate){
   withGate++;
   if(typeof math[r.candidate_gate]!=='function'&&typeof controls[r.candidate_gate]!=='function')
    problems.push('MISSING_EXECUTABLE_CANDIDATE:'+src.id+':'+r.candidate_gate);
  }
  if(!r.unresolved||r.parity!=='NOT_PROVEN'||r.owner_acceptance!=='NOT_REQUESTED'||
    r.can_release!==false)problems.push('UNAPPROVED_RELEASE_CLAIM:'+src.id);
  if(!['gap','partial'].includes(src.coverage)||src.release_gate!=='FIELD_PARITY_PLUS_OWNER_PRACTICAL_ACCEPTANCE')
    problems.push('UNAUTHORIZED_OBLIGATION_COMPLETION:'+src.id);
 }
 const sourceTotal=old.totals.field_keys;
 const untraced=sourceTotal-mapped.size;
 if(untraced<0)problems.push('TRACED_KEYS_EXCEED_SOURCE');
 const result={
  ok:problems.length===0,
  source_forms:forms.length,
  old_field_candidates:sourceTotal,
  uniquely_traced_critical_fields:mapped.size,
  source_fields_without_critical_trace:untraced,
  critical_obligations:records.length,
  mapped_gates:withGate,
  gaps_still_open:obligations.records.filter(x=>x.coverage==='gap').length,
  partial_still_open:obligations.records.filter(x=>x.coverage==='partial').length,
  release_ready:false,owner_accepted:false,problems
 };
 return result;
}
if(require.main===module){
 const r=audit();console.log(JSON.stringify(r,null,2));
 if(!r.ok)process.exitCode=1;
}
module.exports={audit};
