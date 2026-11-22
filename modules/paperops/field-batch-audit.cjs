'use strict';
/* PaperOps original-source candidate fields in deterministic blocks of 50.
 * This audits real printable keys + source metadata; never certifies operational parity.
 */
const fs=require('node:fs'),path=require('node:path');
const index=require('./field-routing-report.json');
const old=require('./legacy-rule-candidates.json');
const paperops=require('./paperops.js');
require('./form-packs.js');
const checks=require('./field-batch-001-checks.js');
const laterChecks=require('./field-batch-002-003-checks.js');
const dir=path.join(__dirname,'field-review');
const SIZE=50;
const all=index.forms.flatMap(f=>f.source_fields);
const pending=all.filter(f=>f.review_state==='FIELD_SPECIFIC_MAPPING_OUTSTANDING');
function reviewedFiles(){
 return fs.readdirSync(dir).filter(x=>/^batch-\d{3}\.json$/.test(x)).sort();
}
function auditBatch(batch, alreadyReviewed=[]) {
 const problems=[];
 const previous=new Set(alreadyReviewed);
 const next=pending.filter(f=>!previous.has(f.id)).slice(0,SIZE);
 const expectedNumber=previous.size/SIZE+1;
 if(batch.batch_number!==expectedNumber||!Number.isInteger(expectedNumber))
   problems.push('BATCH_SEQUENCE_NOT_CONTIGUOUS');
 if(batch.batch_size!==SIZE||batch.fields_checked_in_this_batch!==SIZE||batch.entries?.length!==SIZE)
   problems.push('NOT_EXACTLY_50_FIELDS');
 if(batch.entries?.some(x=>previous.has(x.source_id)))problems.push('REVIEWED_FIELD_REPEATED');
 const selectedFormIds=new Set(next.map(x=>x.id.split(':')[0]));
 if((batch.forms||[]).length!==selectedFormIds.size||
    new Set((batch.forms||[]).map(x=>x.legacy_code)).size!==selectedFormIds.size||
    (batch.forms||[]).some(x=>!selectedFormIds.has(x.legacy_code)))
   problems.push('SOURCE_FORM_COVERAGE_MISMATCH');
 if(batch.entries?.length!==new Set((batch.entries||[]).map(x=>x.source_id)).size)
   problems.push('DUPLICATE_FIELD_ID');
 const orig=new Map(all.map(f=>[f.id,f]));
 const formsByCode=new Map(old.forms.map(f=>[f.legacy_code,f]));
 const newForms=new Map(paperops.TEMPLATES.map(f=>[f.id,f]));
 for(let i=0;i<(batch.entries||[]).length;i++){
   const item=batch.entries[i],source=orig.get(item.source_id),selected=next[i];
   if(item.number!==i+1||!selected||selected.id!==item.source_id)
     problems.push('OUT_OF_ORDER_BATCH_SELECTION:'+i);
   if(!source||item.source_id!==item.source_form+':'+item.source_key||
      item.source_key!==source.key||item.source_form!==source.id.split(':')[0])
     {problems.push('SOURCE_FIELD_ID_MISMATCH:'+i);continue;}
   if(item.label_bn!==source.label_bn||item.label_en!==source.label_en||
      item.required_candidate!==source.required_candidate||
      item.visibility_candidate!==source.visible_candidate||
      item.role_candidate!==source.role_candidate||
      item.source_cadence!==source.form_cadence)
     problems.push('ORIGINAL_FIELD_METADATA_DRIFT:'+item.source_id);
   const template=newForms.get(item.target_form);
   const match=template?.sections.flatMap(s=>s.fields||[]).filter(f=>f.key===item.target_field_key)||[];
   if(!template||!template.legacyRefs.includes(item.source_form)||
      match.length!==1||match[0].label.bn!==source.label_bn||match[0].label.en!==source.label_en)
     problems.push('MISSING_OR_MISMATCHED_PRINT_FIELD:'+item.source_id);
   if(item.target_field_key!==item.source_key)problems.push('UNEXPLAINED_RENAMED_FIELD:'+item.source_id);
   if(item.result!=='FIELD_LOCATION_PROTOTYPE_ONLY'||item.owner_accepted!==false||
      item.parity_certified!==false||!item.outstanding)
      problems.push('FALSE_FIELD_PARITY_CLAIM:'+item.source_id);
 }
 for(const f of batch.forms||[]){
   const s=formsByCode.get(f.legacy_code),template=newForms.get(f.print_form);
   if(!s||!template||!template.legacyRefs.includes(f.legacy_code))
     {problems.push('SOURCE_OR_PRINT_FORM_MISSING:'+f.legacy_code);continue;}
   if(typeof checks[f.check_function]!=='function'&&typeof laterChecks[f.check_function]!=='function')
     problems.push('CANDIDATE_CALCULATOR_MISSING:'+f.legacy_code);
   const srcFlags=s.flag_candidates.map(x=>x.code).sort();
   const mapped=(f.original_flags||[]).map(x=>x.source_flag).sort();
   if(JSON.stringify(srcFlags)!==JSON.stringify(mapped))
     problems.push('HISTORIC_FLAG_NOT_MAPPED:'+f.legacy_code);
   const knownFlags=f.legacy_code==='W-03'?laterChecks.COUNT_FLAGS:
     f.legacy_code==='R-01'?laterChecks.DAILY_FLAGS:null;
   if(knownFlags&&(f.original_flags||[]).some(x=>knownFlags[x.new_blocker]!==x.source_flag))
     problems.push('CANDIDATE_FLAG_EXECUTION_MAPPING_DRIFT:'+f.legacy_code);
   if((f.original_flags||[]).some(x=>!x.new_blocker||x.new_blocker.length<6))
     problems.push('FLAG_HAS_NO_CANDIDATE_CHECK:'+f.legacy_code);
   if(f.status!=='SOURCE_FLAGS_REPRODUCED_BY_CANDIDATE_TESTS_NO_PARITY_SIGNOFF')
     problems.push('FALSE_CALCULATOR_PARITY_CLAIM:'+f.legacy_code);
 }
 const expectedStatus=batch.batch_number===1?
   'FIRST_50_SOURCE_TO_PRINT_MAPPED_NOT_PARITY_CERTIFIED':
   'BATCH_50_SOURCE_TO_PRINT_MAPPED_NOT_PARITY_CERTIFIED';
 if(batch.status!==expectedStatus||
    batch.result_summary?.parity_approved!==0||
    batch.result_summary?.erp_write_or_signoff_allowed!==false)
   problems.push('UNAUTHORIZED_RELEASE_OR_PARITY_CLAIM');
 const verifiedKeys=new Set((batch.entries||[]).map(x=>x.source_id));
 if(batch.result_summary?.original_flag_candidates_tested!==(batch.forms||[]).reduce((n,f)=>n+(f.original_flags||[]).length,0))
   problems.push('SOURCE_FLAG_COUNT_MISMATCH');
 if(batch.result_summary?.original_field_keys_located!==SIZE||
    batch.result_summary?.printable_fields_added_or_matched!==SIZE||
    batch.result_summary?.remaining_first_pass_unchecked!==pending.length-previous.size-SIZE)
   problems.push('INACCURATE_BATCH_COMPLETION_COUNTS');
 const remaining=pending.filter(x=>!previous.has(x.id)&&!verifiedKeys.has(x.id));
 return {ok:problems.length===0,batch_number:batch.batch_number,
   expected_fields:next.length,source_to_print_checked:batch.entries?.length||0,
   original_flag_categories_checked:(batch.forms||[]).reduce((n,x)=>n+(x.original_flags?.length||0),0),
   source_parity_approved:0,remaining_unmapped_review_queue:remaining.length,
   remaining_next_50:remaining.slice(0,SIZE).map(x=>x.id),release_authorized:false,
   problems};
}
function run(){
 let reviewed=[],results=[];
 for(const file of reviewedFiles()){
  const batch=JSON.parse(fs.readFileSync(path.join(dir,file),'utf8'));
  const result=auditBatch(batch,reviewed);
  if(!result.ok)throw Error('PAPEROPS_FIELD_BATCH_FAILED:'+file+':'+result.problems.join('|'));
  reviewed.push(...batch.entries.map(x=>x.source_id));
  results.push(result);
 }
 const outstanding=pending.filter(x=>!new Set(reviewed).has(x.id));
 return {checked_batches:results.length,checked_field_count:reviewed.length,
  original_unmapped_candidates:pending.length,
  remaining_first_pass:outstanding.length,
  next_batch_number:results.length+1,
  next_50:outstanding.slice(0,SIZE).map(x=>x.id),
  flag_categories_checked:results.reduce((n,x)=>n+x.original_flag_categories_checked,0),
  unique_source_flag_categories:new Set(results.flatMap((x,i)=>{
    const batch=JSON.parse(fs.readFileSync(path.join(dir,reviewedFiles()[i]),'utf8'));
    return batch.forms.flatMap(f=>f.original_flags.map(w=>f.legacy_code+':'+w.source_flag));
  })).size,
  results,ready_for_release:false};
}
if(require.main===module){
 const x=run();
 if(process.argv.includes('--next'))console.log(JSON.stringify({
  next_batch_number:x.next_batch_number,remaining_first_pass:x.remaining_first_pass,next_50:x.next_50},null,2));
 else console.log(JSON.stringify({
  checked_batches:x.checked_batches,checked_field_count:x.checked_field_count,
  source_flags_checked:x.flag_categories_checked,remaining:x.remaining_first_pass,
  source_parity_approved:0,release_authorized:false,errors:[]},null,2));
}
module.exports={auditBatch,run};
