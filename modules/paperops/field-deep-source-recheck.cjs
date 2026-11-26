'use strict';
/* Source-backed exact declaration recheck for first three 50-field batches. Never executes legacy JS. */
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
function scanBalanced(s,index,left,right){let depth=0,q=null,escaped=false;for(let i=index;i<s.length;i++){const c=s[i];if(q){if(escaped){escaped=false;continue;}if(c==='\\'){escaped=true;continue;}if(c===q){q=null;}continue;}if(c===left){depth++;continue;}if(c===right){depth--;if(depth===0)return s.slice(index,i+1);}}return ""}
function redoSourceEvidence(src,semantic,batches){
 const names=[...src.matchAll(/e\.forms\["([A-Z]-\d{2})"\]\s*=\s*\{\s*title:/g)].map(x=>({code:x[1],index:x.index}));
 const blocks=new Map(names.map((a,i)=>[a.code,src.slice(a.index,names[i+1]?.index||src.length)]));
 const ordered=batches.flatMap(b=>b.entries);
 if(ordered.length!==150||semantic.fields.length!==150)throw Error("WRONG_SCOPE");
 const entries=ordered.map((f,i)=>{
  if(semantic.fields[i]?.source_id!==f.source_id)throw Error('SEMANTIC_BATCH_ORDER_MISMATCH:'+f.source_id);
  const body=blocks.get(f.source_form);
  if(!body)throw Error('OLD_FORM_SOURCE_MISSING:'+f.source_form);
  const r=new RegExp('\\b([A-Za-z_$][A-Za-z0-9_$]*)\\(\\s*"'+f.source_key+'"\\s*,\\s*t\\("([^"]{1,180})"\\s*,\\s*"([^"]{1,180})"\\)');
  const m=r.exec(body);
  if(!m)throw Error('OLD_DECLARATION_NOT_FOUND:'+f.source_id);
  const call=scanBalanced(body,body.indexOf('(',m.index),'(',')');
  if(!call)throw Error('UNBALANCED_SOURCE_FIELD:'+f.source_id);
  if(m[2]!==f.label_bn||m[3]!==f.label_en)throw Error('OLD_LABEL_DRIFT:'+f.source_id);
  if(m[1]!==semantic.fields[i].legacy_constructor_alias)throw Error('OLD_CONSTRUCTOR_DRIFT:'+f.source_id);
  const req=/\breq\s*:\s*!0/.test(call)?'ALWAYS':/\breq\s*:/.test(call)?'CONDITIONAL':'NOT_DECLARED';
  const visible=/\bshow\s*:/.test(call)?'CONDITIONAL':'NOT_DECLARED';
  const who=/\bwho\s*:\s*"checker"/.test(call)?'CHECKER':'DEFAULT_OR_UNDECLARED';
  if(req!==f.required_candidate||visible!==f.visibility_candidate||who!==f.role_candidate)
   throw Error('OLD_BRANCH_METADATA_DRIFT:'+f.source_id);
  const hasCalc=/\bcalc\s*\(\s*e\s*\)\s*\{/.exec(body);
  const calc=hasCalc?scanBalanced(body,body.indexOf('{',hasCalc.index),'{','}'):'';
  const inCalc=calc.includes('"'+f.source_key+'"')||calc.includes('.'+f.source_key)||
    calc.includes('["'+f.source_key+'"]')||calc.includes('["'+f.source_key+'"]');
  const oldDynamic=/\b(show|req)\s*:\s*/.test(call);
  const reqShowFragment=oldDynamic?
   call.slice(call.search(/\b(?:show|req)\s*:/),Math.min(call.length,call.search(/\b(?:show|req)\s*:/)+320)):'';
  return {
   source_id:f.source_id,batch_number:Math.floor(i/50)+1,source_form:f.source_form,
   field_key:f.source_key,original_constructor_alias:m[1],source_call:call,
   field_required_source:req,field_visibility_source:visible,field_role_source:who,
   exact_conditional_fragment:reqShowFragment||null,
   candidate_calculation_body_contains_field_ref:inCalc,
   printed_destination:f.target_form+':'+f.target_field_key,
   candidate_semantic_class:semantic.fields[i].proposed_semantic_class,
   type_of_evidence:oldDynamic?'ORIGINAL_CONDITION_SYNTAX_EXTRACTED__BRANCH_RUNTIME_NOT_PROVEN':
     inCalc?'SOURCE_CALCULATOR_FIELD_REFERENCE_FOUND__FORMULA_PARITY_NOT_PROVEN':
     'SOURCE_FIELD_DECLARATION_EXACT__BUSINESS_RULE_PARITY_NOT_PROVEN',
   requires_full_historical_rule_test:true,
   source_branches_approved:false,source_formula_approved:false,
   source_to_live_ERP_verified:false,owner_accepted:false
  };
 });
 const group=entries.reduce((a,f)=>(a[f.source_form]=(a[f.source_form]||0)+1,a),{});
 return {
  schema_version:1,status:'RECHECKED_150_EXACT_SOURCE_DECLARATIONS__NOT_FULL_LOGIC_PARITY',
  caution:'This evidence binds literal old field constructor calls and static show/req/who metadata, not an executed historic app. Dynamic rule expression semantics, helper functions, accounting policies, QC and ledger outcomes still require separate tested proofs. Nothing is Owner accepted.',
  source_file:'legacy/islamia-erp/forms.js',source_operationally_executed:false,
  summary:{source_field_declarations_relocated:entries.length,forms:group,
   conditional_visibility_source_count:entries.filter(x=>x.field_visibility_source==='CONDITIONAL').length,
   conditional_required_source_count:entries.filter(x=>x.field_required_source==='CONDITIONAL').length,
   required_source_count:entries.filter(x=>x.field_required_source==='ALWAYS').length,
   entries_referencing_calc_body:entries.filter(x=>x.candidate_calculation_body_contains_field_ref).length,
   source_business_rule_parity_approved:0,owner_accepted:0},
  entries
 }
}
function generate(){
 const src=require('./field-review/chatgpt-246/source-helper-conditions.cjs').readFrozen('forms');
 const semantic=require('./field-review/semantic-triage-001-003.json');
 const batches=[1,2,3].map(n=>require('./field-review/batch-'+String(n).padStart(3,'0')+'.json'));
 return redoSourceEvidence(src,semantic,batches);
}
function audit(){const report=generate();const saved=JSON.parse(fs.readFileSync(path.join(__dirname,'field-review','deep-source-recheck-001-003.json'),'utf8'));
 assert.deepEqual(saved,report,'DEEP_150_SOURCE_RECHECK_STALE');
 assert.equal(report.summary.source_field_declarations_relocated,150);
 assert.equal(report.summary.source_business_rule_parity_approved,0);
 return report;
}
if(require.main===module){const x=process.argv.includes('--check')?audit():generate();console.log(JSON.stringify(x.summary,null,2));}
module.exports={scanBalanced,redoSourceEvidence,generate,audit};
