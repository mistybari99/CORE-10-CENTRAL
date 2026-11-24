'use strict';
const assert=require('node:assert/strict');
const {test}=require('node:test');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const candidates=require('../legacy-rule-candidates.json');
const routing=require('../field-routing-report.json');
const index=require('../legacy-field-index.json');
const ownership=require('../field-review/ownership-246-1000.json');
const root=path.resolve(__dirname,'../../..');
const keys=['name','qty','unit'];
const pins={
 'forms.js':'f2cb1c5e09210496106ace1bf33ddc40d2d6df1d',
 'forms_cash.js':'9ea4fff512c709b6e28f9ab6613c3797b306b4f2',
 'forms_factory.js':'1c52dc8b8bc87adbb91f5811d45e6dc1b10e23d6',
 'forms_sales.js':'8bdf649f159593882f7e415a366688f6e3f45145',
 'forms_stock.js':'59849dc51819243c5cd83b8f2246301daceebdb1'
};
const frozen=file=>{
 const quarantined=path.join(root,'legacy/islamia-erp',file);
 return fs.readFileSync(fs.existsSync(quarantined)?quarantined:path.join(root,file));
};
const form=(report,code)=>report.forms.find(f=>f.legacy_code===code);

test('A019 distinct row declarations and contexts match the five frozen sources',()=>{
 for(const [file,expected] of Object.entries(pins)){
  const bytes=frozen(file);
  assert.equal(crypto.createHash('sha1').update('blob '+bytes.length+'\0').update(bytes).digest('hex'),expected);
 }
 const text=frozen('forms_factory.js').toString('utf8');
 const specStart=text.indexOf('e.forms["F-02"]={');
 const specEnd=text.indexOf(';const F=[',specStart);
 assert.doesNotMatch(text.slice(specStart,specEnd),/\bO\(/);
 assert.equal(form(candidates,'F-02').fields.some(f=>keys.includes(f.key)),false);
 const recipe=form(candidates,'F-03').fields;
 const item=recipe.find(f=>f.key==='item');
 assert.equal(item.label_en,'Item code & product name');
 assert.equal(item.recipe_row_source.label_en,'Raw material name & item code');
 assert.equal(recipe.filter(f=>f.key==='item').length,1);
 for(const field of recipe.filter(f=>['item',...keys].includes(f.key))){
  const row=field.recipe_row_source;
  assert.equal(text.slice(row.offset_utf16,row.offset_utf16+row.literal.length),row.literal);
  assert.deepEqual(row.row_contexts.map(x=>[x.collection,x.min_rows_declared,x.offset_utf16]),[
   ['a',4,18046],['b',5,18345],['c',2,18511]
  ]);
  for(const context of row.row_contexts){
   const call='b("'+context.collection+'",null,O(),{min:'+context.min_rows_declared+'})';
   assert.equal(text.slice(context.offset_utf16,context.offset_utf16+call.length),call);
  }
 }
 assert.match(item.recipe_row_source.literal,/req:e=>!a\(e\.row\.name\)/);
 assert.match(recipe.find(f=>f.key==='name').recipe_row_source.literal,/req:e=>!a\(e\.row\.item\)/);
 for(const key of ['qty','unit'])assert.match(recipe.find(f=>f.key===key).recipe_row_source.literal,/req:!0/);
});

test('A019 source index and routing preserve order, actual ownership and no signoff',()=>{
 const lane=ownership.lane_A_codex.ownership_keys;
 const rows=routing.forms.flatMap(f=>f.source_fields);
 assert.deepEqual(lane.slice(919,922),keys.map(key=>'F-03:'+key));
 assert.equal(lane[303],'R-01:cashier');
 for(const key of keys){
  assert.ok(form(index,'F-03').extracted_field_keys.includes(key));
  assert.ok(!form(index,'F-02').extracted_field_keys.includes(key));
  const row=rows.find(f=>f.id==='F-03:'+key);
  assert.equal(row.form_cadence,'VERSIONED_MASTER');
  assert.equal(row.owner_accepted,false);
  assert.deepEqual(row.recipe_row_source.row_contexts,index.recipe_row_helper.row_contexts);
 }
 assert.equal(rows.length,1246);
 assert.equal(new Set(rows.map(f=>f.id)).size,1246);
});
