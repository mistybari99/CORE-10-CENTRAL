'use strict';
// A007: original-source attribution only. Frozen JS is read as bytes, never loaded/executed.
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../../..');
const index=require('../legacy-field-index.json');
const extracted=require('../legacy-rule-candidates.json');
const route=require('../field-routing-report.json');
const ownership=require('../field-review/ownership-246-1000.json');
const blob=data=>{const b=Buffer.isBuffer(data)?data:Buffer.from(data);
 return crypto.createHash('sha1').update('blob '+b.length+'\0').update(b).digest('hex');};
const frozen=p=>{const old=path.join(root,'legacy/islamia-erp',p),original=path.join(root,p);
 return fs.readFileSync(fs.existsSync(old)?old:original);};
const find=(forms,id)=>forms.find(f=>f.legacy_code===id);
const sourceEvidence={source_file:'forms_cash.js',source_form:'R-01',
 source_order_after_form:'S-04',key:'cashier',offset_utf16:44009,guarded:true};

test('frozen original exact R-01 header mutation is nonexecutably proven',()=>{
 const cash=frozen('forms_cash.js');
 assert.equal(blob(cash),'9ea4fff512c709b6e28f9ab6613c3797b306b4f2');
 assert.equal(blob(frozen('forms.js')),'f2cb1c5e09210496106ace1bf33ddc40d2d6df1d');
 const s=cash.toString('utf8');
 const oldForm=s.indexOf('e.forms["S-04"]='),mutation=s.indexOf('e.forms["R-01"].head.push(');
 assert.ok(oldForm>0&&mutation>oldForm);
 assert.equal(mutation,44009);
 assert.equal(s.slice(oldForm,mutation).includes('u("cashier"'),false);
 assert.match(s.slice(mutation),/^e\.forms\["R-01"\]\.head\.push\(u\("cashier",t\("ক্যাশিয়ার \(Cashier\)","Cashier"\)\)\)/);
 assert.match(s.slice(mutation-105,mutation),/e\.forms\["R-01"\].*head\.some/);
});

test('extractor and source field index attribute the mutation to R-01, not S-04',()=>{
 const r=find(extracted.forms,'R-01'),s=find(extracted.forms,'S-04');
 const ri=find(index.forms,'R-01'),si=find(index.forms,'S-04');
 const cashier=r.fields.filter(f=>f.key==='cashier');
 assert.equal(cashier.length,1);
 assert.equal(cashier[0].source_order_after_form,'S-04');
 assert.equal(cashier[0].source_declaration_kind,'GUARDED_CROSS_FORM_HEADER_PUSH');
 assert.equal(cashier[0].source_mutation_file,'forms_cash.js');
 assert.equal(cashier[0].source_mutation_offset_utf16,44009);
 assert.equal(s.fields.some(f=>f.key==='cashier'),false);
 assert.ok(ri.extracted_field_keys.includes('cashier'));
 assert.equal(si.extracted_field_keys.includes('cashier'),false);
 assert.equal(ri.count_extracted,154);
 assert.equal(si.count_extracted,31);
 assert.equal(index.forms.reduce((n,f)=>n+f.count_extracted,0),1246);
 assert.deepEqual(extracted.late_header_mutations,[sourceEvidence]);
 assert.deepEqual(index.late_header_mutations,[sourceEvidence]);
});

test('routing retains original audit-order slot but uses actual R-01 policy',()=>{
 const flattened=route.forms.flatMap(f=>f.source_fields);
 const f=flattened[498];
 assert.equal(f.id,'R-01:cashier');
 assert.equal(f.form_cadence,'DAILY_CLOSE');
 assert.equal(f.form_trigger,'showroom_open');
 assert.equal(f.proof_route,'OPS-DAILY');
 assert.deepEqual(f.source_mutation,{kind:'GUARDED_CROSS_FORM_HEADER_PUSH',
  source_file:'forms_cash.js',source_order_after_form:'S-04',offset_utf16:44009});
 assert.deepEqual(route.source_late_header_mutations,[sourceEvidence]);
 assert.equal(new Set(flattened.map(x=>x.id)).size,1246);
 assert.equal(route.summary.by_route.DAILY_CLOSE,154);
 assert.equal(route.summary.by_route.CONTINUOUS_LEDGER,194);
 assert.equal(blob(fs.readFileSync(path.join(root,'modules/paperops/field-routing-report.json'))),ownership.source_of_truth.order_blob_sha);
});

test('the 304th Codex entry is corrected and the original order remains pinned with the A019 source correction reversed',()=>{
 const a=ownership.lane_A_codex.ownership_keys,b=ownership.lane_B_chatgpt;
 const prior=[...a];
 for(const [i,key] of ['name','qty','unit'].entries()){
  assert.equal(a[919+i],'F-03:'+key);
  prior[919+i]='F-02:'+key;
 }
 const other999=prior.filter((_,i)=>i!==303);
 const protected246=[...b.critical_86_keys,...b.mapped_150_keys,...b.reserved_next_10_keys];
 assert.equal(a.length,1000);assert.equal(a[303],'R-01:cashier');
 assert.equal(a.includes('S-04:cashier'),false);
 assert.equal(blob(JSON.stringify(other999)),'84710db56860ec9429ad94f7a585974c79874e60');
 assert.equal(blob(JSON.stringify(protected246)),'fa9bfcc9ad986275a77aa3b8ad65d5be272dafb3');
 assert.equal(new Set([...a,...protected246]).size,1246);
 assert.deepEqual(a,route.forms.flatMap(f=>f.source_fields).filter(x=>x.review_state==='FIELD_SPECIFIC_MAPPING_OUTSTANDING').map(x=>x.id).filter(x=>!new Set(b.mapped_150_keys).has(x)).slice(10));
});
