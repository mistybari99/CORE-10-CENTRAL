'use strict';
// Deterministic source-only extraction from frozen historical forms. Never evaluate old code.
const fs=require('node:fs');
const path=require('node:path');
function scanBalanced(s,index,left,right){
  let depth=0,q=null,escaped=false;
  for(let i=index;i<s.length;i++){
    const c=s[i];
    if(q){if(escaped){escaped=false;continue;}if(c==='\\'){escaped=true;continue;}if(c===q){q=null;}continue;}
    if(c==='"'||c==="'"||c==='`'){q=c;continue;}
    if(c===left){depth++;continue;}if(c===right){depth--;if(depth===0)return s.slice(index,i+1);}
  }
  return "";
}
function uniqueMatches(s,re){return [...new Set([...s.matchAll(re)].map(m=>m[1]))].sort();}
function attributeRecipeRows(entries,source){
  const spec=entries.find(x=>x.legacy_code==='F-02');
  const recipe=entries.find(x=>x.legacy_code==='F-03');
  const text=source.content;
  const specStart=text.indexOf('e.forms["F-02"]={');
  const specEnd=text.indexOf(';const F=[',specStart);
  const recipeStart=text.indexOf('e.forms["F-03"]={',specEnd);
  const recipeEnd=text.indexOf('e.forms["F-04"]={',recipeStart);
  const marker='O=()=>[';
  const offset=text.indexOf(marker,specEnd);
  if(!spec||!recipe||specStart<0||specEnd<=specStart||offset<=specEnd||
      recipeStart<=offset||recipeEnd<=recipeStart||/\bO\(/.test(text.slice(specStart,specEnd)))
    throw Error('RECIPE_HELPER_SOURCE_BOUNDARY');
  const helper=scanBalanced(text,offset+marker.length-1,'[',']');
  const matches=[...helper.matchAll(/\b([A-Za-z_$][\w$]*)\("([a-z][a-z0-9_]*)",t\("([^"]+)","([^"]+)"\)/g)];
  if(matches.map(m=>m[2]).join(',')!=='item,name,qty,unit')
    throw Error('RECIPE_HELPER_DECLARATIONS_CHANGED');
  const block=text.slice(recipeStart,recipeEnd);
  const consumes=[...block.matchAll(/title:t\("([^"]+)","([^"]+)"\),fields:\[b\("([abc])",null,O\(\),\{min:(\d+)\}\)/g)];
  if(consumes.map(m=>m[3]+':'+m[4]).join(',')!=='a:4,b:5,c:2'||
      [...block.matchAll(/\bO\(\)/g)].length!==3)
    throw Error('RECIPE_HELPER_CONSUMERS_CHANGED');
  const rowContexts=consumes.map(m=>({collection:m[3],section_bn:m[1],section_en:m[2],
    min_rows_declared:Number(m[4]),offset_utf16:recipeStart+m.index+m[0].indexOf('b("')}));
  for(const m of matches){
    const key=m[2];
    const call=m[1]+scanBalanced(helper,m.index+m[1].length,'(',')');
    const provenance={kind:'SHARED_RECIPE_ROW_HELPER',source_file:source.path,
      helper_offset_utf16:offset,offset_utf16:offset+marker.length-1+m.index,
      literal:call,constructor_alias:m[1],label_bn:m[3],label_en:m[4],row_contexts:rowContexts};
    if(key==='item'){
      const header=recipe.fields.find(f=>f.key===key);
      if(!header||header.label_en===m[4])throw Error('RECIPE_HEADER_ITEM_NOT_DISTINCT');
      header.recipe_row_source=provenance;
      continue;
    }
    const misplaced=spec.fields.find(f=>f.key===key);
    if(!misplaced||misplaced.constructor_alias!==m[1]||misplaced.label_bn!==m[3]||
        misplaced.label_en!==m[4]||recipe.fields.some(f=>f.key===key))
      throw Error('RECIPE_ATTRIBUTION_DRIFT:'+key);
    spec.fields.splice(spec.fields.indexOf(misplaced),1);
    recipe.fields.push({...misplaced,source_order_after_form:'F-02',recipe_row_source:provenance});
  }
}
function inspectSources(sources){
  const entries=[];
  for(const source of sources){
    const starts=[...source.content.matchAll(/e\.forms\[\s*"([A-Z]-\d{2})"\s*\]\s*=\s*\{\s*title:/g)].map(x=>({id:x[1],pos:x.index}));
    for(let z=0;z<starts.length;z++){
      const block=source.content.slice(starts[z].pos,starts[z+1]?.pos??source.content.length);
      const found=new Map();
      const regex=/\b([A-Za-z_$][A-Za-z0-9_$]*)\(\s*"([a-z][a-z0-9_]*)"\s*,\s*t\("([^"]{1,180})"\s*,\s*"([^"]{1,180})"\)/g;
      for(const m of block.matchAll(regex)){
        if(found.has(m[2]))continue;
        const open=block.indexOf("(",m.index);
        const call=scanBalanced(block,open,"(",")");
        const required=/\breq\s*:\s*!0/.test(call)?'ALWAYS':/\breq\s*:/.test(call)?'CONDITIONAL':'NOT_DECLARED';
        const visibility=/\bshow\s*:/.test(call)?'CONDITIONAL':'NOT_DECLARED';
        const role=/\bwho\s*:\s*"checker"/.test(call)?'CHECKER':'DEFAULT_OR_UNDECLARED';
        found.set(m[2],{key:m[2],label_bn:m[3],label_en:m[4],constructor_alias:m[1],
          required_candidate:required,visible_candidate:visibility,role_candidate:role});
      }
      const calcRegex=/\bcalc\s*\(\s*e\s*\)\s*\{/g;
      const calcMatch=calcRegex.exec(block);
      const body=calcMatch?scanBalanced(block,block.indexOf("{",calcMatch.index),"{","}"):"";
      const flags=[...block.matchAll(/\b[A-Za-z_$][A-Za-z0-9_$]*\(\s*"([a-z][a-z0-9_]*)"\s*,\s*"(red|yellow|green|amber)"/g)];
      const uniqueFlags=[...new Map(flags.map(x=>[x[1],{code:x[1],severity:x[2]}])).values()];
      entries.push({legacy_code:starts[z].id,source:source.path,
        fields:[...found.values()],calc_candidate:{
          body_found:!!body,body_chars:body.length,head_sample:body.slice(0,480),
          settings:uniqueMatches(body,/\be\.s\.([a-z][a-z0-9_]*)/g),
          inputs:uniqueMatches(body,/\be\.d\.([a-z][a-z0-9_]*)/g),
          table_refs:uniqueMatches(body,/\be\.rows(?:C)?\(\s*"([^"]+)"/g)
        },flag_candidates:uniqueFlags,flag_candidates_count:uniqueFlags.length,
        source_caution:'HEURISTIC: compiled/minified source may append dynamic overrides; not executable rules; no automatic signoff.'
      });
    }
  }
  // Later files may append a guarded field to a previously declared form.
  // Do not treat such a push as a declaration belonging to the last form in that file.
  const lateHeaderMutations=[];
  const factory=sources.find(x=>x.path==='forms_factory.js');
  if(factory)attributeRecipeRows(entries,factory);
  const headerPush=/e\.forms\["([A-Z]-\d{2})"\]\.head\.push\(\s*([A-Za-z_$][A-Za-z0-9_$]*)\("([a-z][a-z0-9_]*)",t\("([^"]{1,180})","([^"]{1,180})"\)\)\)/g;
  for(const source of sources){
    const declarations=[...source.content.matchAll(/e\.forms\["([A-Z]-\d{2})"\]\s*=\s*\{\s*title:/g)];
    for(const match of source.content.matchAll(headerPush)){
      const headerForm=match[1],alias=match[2],key=match[3],bn=match[4],en=match[5];
      const preceding=declarations.filter(x=>x.index<match.index).at(-1);
      if(!preceding)throw Error('UNANCHORED_HEADER_MUTATION:'+source.path+':'+key);
      const anchor=entries.find(x=>x.legacy_code===preceding[1]);
      const owner=entries.find(x=>x.legacy_code===headerForm);
      if(!anchor||!owner)throw Error('HEADER_MUTATION_FORM_MISSING:'+headerForm+':'+key);
      if(anchor===owner)continue; // Same-form header pushes remain in their original block.
      const matches=anchor.fields.filter(f=>f.key===key&&f.constructor_alias===alias&&f.label_bn===bn&&f.label_en===en);
      if(matches.length!==1||owner.fields.some(f=>f.key===key))
        throw Error('AMBIGUOUS_CROSS_FORM_HEADER_MUTATION:'+headerForm+':'+key);
      const field=matches[0];
      anchor.fields.splice(anchor.fields.indexOf(field),1);
      owner.fields.push({...field,source_order_after_form:anchor.legacy_code,
        source_declaration_kind:'GUARDED_CROSS_FORM_HEADER_PUSH',
        source_mutation_file:source.path,source_mutation_offset_utf16:match.index});
      lateHeaderMutations.push({source_file:source.path,source_form:headerForm,
        source_order_after_form:anchor.legacy_code,key,offset_utf16:match.index,guarded:true});
    }
  }
  const totals={forms:entries.length,field_keys:entries.reduce((n,x)=>n+x.fields.length,0),
    always_required_candidate_fields:entries.reduce((n,x)=>n+x.fields.filter(f=>f.required_candidate==='ALWAYS').length,0),
    conditionally_required_candidate_fields:entries.reduce((n,x)=>n+x.fields.filter(f=>f.required_candidate==='CONDITIONAL').length,0),
    conditional_visibility_candidate_fields:entries.reduce((n,x)=>n+x.fields.filter(f=>f.visible_candidate==='CONDITIONAL').length,0),
    calculator_candidates:entries.filter(x=>x.calc_candidate.body_found).length,
    flag_candidates:entries.reduce((n,x)=>n+x.flag_candidates_count,0)};
  return {schema_version:1,kind:'SOURCE_DERIVED_HEURISTIC_RULE_CANDIDATES',status:'REQUIRES_FIELD_BY_FIELD_OWNER_VALIDATION',sources:sources.map(x=>x.path),
  notice:'Do not execute legacy JS. Parsed minified constructors, first calc block and straightforward flag constructors; calculations are excerpts, not validated formulas. All thresholds remain unapproved. Field absence never means safe to omit.',
  totals,forms:entries,late_header_mutations:lateHeaderMutations};
}
const root=path.resolve(__dirname,'../..');
const legacyPaths=["forms.js","forms_cash.js","forms_stock.js","forms_sales.js","forms_factory.js"];
const sources=legacyPaths.map(p=>{
 const atRoot=path.join(root,p),quarantined=path.join(root,'legacy/islamia-erp',p);
 const location=fs.existsSync(quarantined)?quarantined:atRoot;
 if(!fs.existsSync(location))throw Error('FROZEN_SOURCE_MISSING:'+p);
 return {path:p,content:fs.readFileSync(location,'utf8')};
});
const report=inspectSources(sources);
if(process.argv.includes('--check')){
 const actual=JSON.parse(fs.readFileSync(path.join(__dirname,'legacy-rule-candidates.json'),'utf8'));
 const assert=require('node:assert/strict');
 assert.deepEqual(report,actual,'rule candidate report stale: regenerate and review source deltas');
 console.log('PaperOps legacy rule extraction checked:',report.totals);
}else if(process.argv.includes('--write')){
 fs.writeFileSync(path.join(__dirname,'legacy-rule-candidates.json'),JSON.stringify(report,null,2)+'\n');
 console.log('Wrote PaperOps heuristic source candidate report:',report.totals);
}else{
 console.log(JSON.stringify(report.totals,null,2));
}
