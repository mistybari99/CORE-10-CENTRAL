'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const report=require('../field-review/batch-001.json');
const {auditBatch,run}=require('../field-batch-audit.cjs');
const registry=require('../paperops.js');
require('../form-packs.js');
const kit=require('../paper-kit.js');
const clone=o=>JSON.parse(JSON.stringify(o));
test('first batch contains exactly 50 originally unmapped fields and no repeated keys',()=>{
 const result=auditBatch(report);
 assert.equal(result.ok,true,result.problems.join(' | '));
 assert.equal(result.source_to_print_checked,50);
 assert.equal(result.expected_fields,50);
 assert.equal(result.original_flag_categories_checked,12);
 assert.equal(result.source_parity_approved,0);
 assert.equal(result.remaining_unmapped_review_queue,1110);
 assert.equal(new Set(report.entries.map(x=>x.source_id)).size,50);
 assert.equal(report.entries.filter(x=>x.source_form==='C-02').length,19);
 assert.equal(report.entries.filter(x=>x.source_form==='C-01').length,16);
 assert.equal(report.entries.filter(x=>x.source_form==='W-02').length,15);
 assert.equal(result.release_authorized,false);
});
test('persistent batch queue advances by exactly 50 and does not recheck the same fields',()=>{
 const result=run();
 assert.equal(result.checked_batches,1);
 assert.equal(result.checked_field_count,50);
 assert.equal(result.original_unmapped_candidates,1160);
 assert.equal(result.remaining_first_pass,1110);
 assert.equal(result.flag_categories_checked,12);
 assert.equal(result.next_batch_number,2);
 assert.equal(result.next_50.length,50);
 const seen=new Set(report.entries.map(x=>x.source_id));
 assert.ok(result.next_50.every(x=>!seen.has(x)));
 assert.equal(result.ready_for_release,false);
});
test('audit refuses false release, changed original label, missing print field, missing legacy flag and reordered fields',()=>{
 let b=clone(report);b.entries[0].parity_certified=true;
 assert.ok(auditBatch(b).problems.includes('FALSE_FIELD_PARITY_CLAIM:C-02:time'));
 b=clone(report);b.entries[0].label_en='Invented field';
 assert.ok(auditBatch(b).problems.includes('ORIGINAL_FIELD_METADATA_DRIFT:C-02:time'));
 b=clone(report);b.entries[0].target_field_key='not_real';
 assert.ok(auditBatch(b).problems.includes('MISSING_OR_MISMATCHED_PRINT_FIELD:C-02:time'));
 b=clone(report);b.forms[0].original_flags=[];
 assert.ok(auditBatch(b).problems.includes('HISTORIC_FLAG_NOT_MAPPED:C-02'));
 b=clone(report);[b.entries[0],b.entries[1]]=[b.entries[1],b.entries[0]];
 assert.ok(auditBatch(b).problems.some(x=>x.startsWith('OUT_OF_ORDER_BATCH_SELECTION')));
});
test('first 50 preserve original required/conditional metadata and only draft templates',()=>{
 const ids=['EXP-VOUCHER','CASH-HANDOVER','STK-TRANSFER'];
 assert.equal(registry.TEMPLATES.length,30);
 for(const id of ids){
  const t=registry.TEMPLATES.find(x=>x.id===id);
  assert.ok(t&&t.status==='draft');
  const x=report.entries.filter(e=>e.target_form===id);
  const fs=t.sections.flatMap(x=>x.fields||[]);
  for(const r of x){
   const matches=fs.filter(f=>f.key===r.target_field_key);
   assert.equal(matches.length,1,r.source_id);
   assert.equal(matches[0].label.bn,r.label_bn);
   assert.equal(matches[0].label.en,r.label_en);
   assert.equal(r.parity_certified,false);
   assert.equal(r.owner_accepted,false);
  }
 }
 assert.equal(report.entries.filter(x=>x.required_candidate==='CONDITIONAL').length,3);
 assert.ok(report.entries.filter(x=>x.visibility_candidate==='CONDITIONAL').length>=4);
});
test('expense voucher prints only on a qualifying event and is not silently merged into daily sale close',()=>{
 const base={date:'2026-11-22',industry:'sweets_bakery',businessName:'SYNTHETIC DEMO',
  sites:[{id:'shop',name:'Demo Shop',kind:'showroom'},{id:'factory',name:'Demo Factory',kind:'factory'}]};
 const quiet=kit.planDay({...base,events:[]});
 assert.deepEqual(quiet.forms.map(x=>x.formId),['OPS-DAILY']);
 const active=kit.planDay({...base,events:[{type:'expense_voucher',siteId:'shop',eventId:'EXP-01'}]});
 assert.deepEqual(active.forms.map(x=>x.formId),['OPS-DAILY','EXP-VOUCHER']);
 const html=kit.printKit(active,{lang:'bn',tableRows:4});
 assert.match(html,/ব্যয় ভাউচার/);
 assert.equal((html.match(/class="paperops-kit-sheet"/g)||[]).length,2);
 assert.equal(active.coverageStatus,'INCOMPLETE_DRAFT_DO_NOT_USE_AS_A_COMPLETE_OFFLINE_ACCOUNTING_KIT');
});
