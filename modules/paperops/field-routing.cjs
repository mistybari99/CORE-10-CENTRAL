'use strict';
/* Derived legacy field-cadence inventory, never a validated field-parity or drop list. */
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
function buildRouting(original,policy,trace){
 const formsById=new Map(policy.form_policies.map(p=>[p.legacy_code,p]));
 const traced=new Map();
 for(const row of trace.records)for(const key of row.legacy_field_keys){
  const id=row.legacy_form+':'+key;
  if(!traced.has(id))traced.set(id,{obligations:[],targets:[]});
  const z=traced.get(id);
  z.obligations.push(row.obligation_id);
  if(!z.targets.includes(row.print_form))z.targets.push(row.print_form);
 }
 const all=original.forms.map(form=>{
  const p=formsById.get(form.legacy_code);
  if(!p)throw Error('MISSING_FORM_POLICY:'+form.legacy_code);
  const fields=form.fields.map(f=>{
   const key=form.legacy_code+':'+f.key,critical=traced.get(key);
   return {id:key,key:f.key,label_bn:f.label_bn,label_en:f.label_en,
    form_cadence:p.cadence,form_trigger:p.trigger,
    legacy_constructor:f.constructor_alias,
    required_candidate:f.required_candidate,visible_candidate:f.visible_candidate,
    role_candidate:f.role_candidate,
    proof_route:p.draft_form || 'ORIGINAL_SOURCE_DOCUMENT_REQUIRED',
    critical_trace:critical?critical.obligations:[],
    critical_draft_targets:critical?critical.targets:[],
    review_state:critical?'SOURCE_TO_DRAFT_LINK_NOT_PARITY':'FIELD_SPECIFIC_MAPPING_OUTSTANDING',
    preserve_original:true,auto_delete:false,owner_accepted:false};
  });
  return {legacy_form:form.legacy_code,cadence:p.cadence,trigger:p.trigger,
   proposed_print_target:p.draft_form||null,
   source_flag_candidates:form.flag_candidates,
   incomplete_formula_review:form.calc_candidate.body_found?'CALC_BODY_CANDIDATE_ONLY':'CALC_BODY_NOT_MATCHED',
   source_fields:fields,field_count:fields.length};
 });
 const fields=all.flatMap(f=>f.source_fields);
 const countByCadence=Object.fromEntries([...new Set(all.map(x=>x.cadence))].sort().map(kind=>[kind,all.filter(x=>x.cadence===kind).reduce((n,f)=>n+f.field_count,0)]));
 return {schema_version:1,status:'CLASSIFIED_CANDIDATE_ONLY_NO_FORM_PARITY_OR_RELEASE_APPROVAL',
  notice:'1246 legacy candidate fields are individually preserved and assigned proposed form-level storage cadence. Source-linked critical keys are not field parity. Unmapped keys cannot be deleted, hidden, or assumed optional. Original legal/custody/approval records must be retained.',
  summary:{historical_forms:all.length,fields:fields.length,critically_traced:fields.filter(x=>x.critical_trace.length>0).length,
   awaiting_field_mapping:fields.filter(x=>x.critical_trace.length===0).length,flag_candidates:all.reduce((n,x)=>n+x.source_flag_candidates.length,0),by_route:countByCadence,
   separate_original_source_forms:all.filter(x=>!x.proposed_print_target).map(x=>x.legacy_form)},
  forms:all};
}
function generate(){
 return buildRouting(require('./legacy-rule-candidates.json'),
  require('./field-routing-policy.json'),require('./control-trace.json'));
}
if(require.main===module){
 const report=generate();
 const file=path.join(__dirname,'field-routing-report.json');
 if(process.argv.includes('--check')){
  assert.deepEqual(report,JSON.parse(fs.readFileSync(file,'utf8')),'FIELD_ROUTING_REPORT_STALE');
  console.log('PaperOps preserved field classification:',JSON.stringify(report.summary));
 }else if(process.argv.includes('--write')){
  fs.writeFileSync(file,JSON.stringify(report,null,2)+'\n');
  console.log('Written:',JSON.stringify(report.summary));
 }else{
  console.log(JSON.stringify(report.summary,null,2));
 }
}
module.exports={generate};
