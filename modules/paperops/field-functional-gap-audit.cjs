'use strict';
/* No false-completeness gate after deep rechecking historic 150 source fields. */
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const data=require('./field-review/functional-gaps-001-003.json');
const deep=require('./field-review/deep-source-recheck-001-003.json');
function audit(report=data,source=deep){
 const problems=[],known=new Map(source.entries.map(x=>[x.source_id,x]));
 if(report.status!=='EVIDENCE_BACKED_OPEN_GAPS_NOT_OWNER_APPROVED')problems.push('FALSE_COMPLETE_STATUS');
 if(report.summary?.ready_for_live!==false||report.summary?.ready_for_trunk!==false||
  report.summary?.owner_accepted!==0)problems.push('UNAUTHORIZED_RELEASE_CLAIM');
 if(report.old_candidate_field_ids!==source.entries.length||report.old_candidate_field_ids!==150)
  problems.push('SOURCE_SCOPE_MISMATCH');
 const seen=new Set();
 for(const gap of report.gaps||[]){
  if(!gap.id||seen.has(gap.id))problems.push('DUPLICATE_GAP_ID');
  seen.add(gap.id);
  if(!Array.isArray(gap.field_ids)||!gap.field_ids.length)problems.push('UNREFERENCED_GAP:'+gap.id);
  if(!gap.next||!gap.status||!gap.finding||!gap.source_fragment)problems.push('UNSPECIFIED_REMEDIATION:'+gap.id);
  if(gap.field_ids.some(id=>!known.has(id)))problems.push('UNCONFIRMED_SOURCE_KEY:'+gap.id);
  if(!gap.field_ids.some(id=>known.get(id)?.source_call.includes(gap.source_fragment)))
   problems.push('ORIGINAL_FIELD_CALL_PROOF_MISSING:'+gap.id);
 }
 if(report.summary?.open_functional_gaps!==seen.size)
  problems.push('INCORRECT_OPEN_GAP_TOTAL');
 return {ok:problems.length===0,source_fields_rechecked:known.size,
  open_gaps:seen.size,release_authorized:false,parity_approved:0,problems};
}
if(require.main===module){
 const r=audit();console.log(JSON.stringify(r,null,2));
 if(!r.ok)process.exitCode=1;
}
module.exports={audit};
