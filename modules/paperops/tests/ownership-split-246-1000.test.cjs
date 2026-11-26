'use strict';
/* Immutable disjoint owner-assigned PaperOps source field sets.
 * From frozen original candidate order, not inferred from daily data-entry counts.
 */
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.join(__dirname,'..');
const manifest=require('../field-review/ownership-246-1000.json');
const report=require('../field-routing-report.json');
const batches=[1,2,3].map(n=>require('../field-review/batch-'+String(n).padStart(3,'0')+'.json'));
const gitBlob=(p)=>{
 const b=fs.readFileSync(p);
 return crypto.createHash('sha1').update('blob '+b.length+'\0').update(b).digest('hex');
};
function sourceSets(){
 const all=report.forms.flatMap(f=>f.source_fields);
 const previouslyLinked=all.filter(f=>f.review_state!=='FIELD_SPECIFIC_MAPPING_OUTSTANDING').map(f=>f.id);
 const pending=all.filter(f=>f.review_state==='FIELD_SPECIFIC_MAPPING_OUTSTANDING').map(f=>f.id);
 const previouslyMapped=batches.flatMap(b=>b.entries.map(e=>e.source_id));
 const reviewed=new Set(previouslyMapped);
 const rest=pending.filter(id=>!reviewed.has(id));
 return {all,previouslyLinked,pending,previouslyMapped,rest};
}
function check(x=manifest){
 const s=sourceSets();
 const owners=[x.lane_B_chatgpt.critical_86_keys,x.lane_B_chatgpt.mapped_150_keys,
  x.lane_B_chatgpt.reserved_next_10_keys,x.lane_A_codex.ownership_keys];
 const expected=[s.previouslyLinked,s.previouslyMapped,s.rest.slice(0,10),s.rest.slice(10)];
 assert.equal(s.all.length,1246);
 assert.equal(new Set(s.all.map(f=>f.id)).size,1246);
 assert.deepEqual(owners.map(a=>a.length),[86,150,10,1000]);
 assert.deepEqual(expected.map(a=>a.length),[86,150,10,1000]);
 for(let i=0;i<owners.length;i++)assert.deepEqual(owners[i],expected[i],'original source field order/assignment drift lane '+i);
 const allKeys=owners.flat();
 assert.equal(allKeys.length,1246);
 assert.equal(new Set(allKeys).size,1246,'no duplicate owners');
 assert.deepEqual(new Set(allKeys),new Set(s.all.map(f=>f.id)),'no abandoned field');
 assert.equal(s.pending.length,1160);
 assert.equal(s.rest.length,1010);
 assert.equal(x.verified_counts.chatgpt_total,246);
 assert.equal(x.verified_counts.codex_total,1000);
 assert.equal(x.verified_counts.field_parity_approved,0);
 assert.equal(x.lane_A_codex.original_first,s.rest[10]);
 assert.equal(x.lane_A_codex.original_last,s.rest.at(-1));
 for(let i=0;i<20;i++){
  const slice=x.lane_A_codex.ownership_keys.slice(i*50,(i+1)*50);
  assert.equal(slice.length,50,'codex batch '+(i+1));
  assert.deepEqual(slice,s.rest.slice(10+i*50,10+(i+1)*50));
 }
 assert.equal(gitBlob(path.join(root,'field-routing-report.json')),x.source_of_truth.order_blob_sha);
 for(let i=0;i<3;i++)
  assert.equal(gitBlob(path.join(root,'field-review/batch-'+String(i+1).padStart(3,'0')+'.json')),
   x.source_of_truth.prior_batch_blobs[i]);
 assert.equal(x.global_guards.frozen_source_unchanged,true);
 assert.equal(x.global_guards.no_real_erp_posting_or_database_mutation_from_audit,true);
 return true;
}
test('owner 246/1000 ownership covers every one of 1246 old field IDs exactly once and source blob is frozen',()=>assert.equal(check(),true));
test('Codex owns exactly twenty immutable consecutive 50 field blocks, excluding reserved 10',()=>{
 assert.equal(manifest.lane_A_codex.ownership_keys[0],'R-01:board_recon');
 assert.equal(manifest.lane_A_codex.ownership_keys.at(-1),'F-01:owner');
 assert.deepEqual(manifest.lane_B_chatgpt.reserved_next_10_keys,
  ['R-01:drawer_none','R-01:ho_count','R-01:ho_range','R-01:ho_written','R-01:stock_locked',
   'R-01:orders_taken','R-01:order_range','R-01:delivered_n','R-01:pending_next','R-01:advance_taken']);
});
test('A007 source-correct cashier keeps the Codex 304th slot and never reassigns 999 neighbors',()=>{
 assert.equal(manifest.lane_A_codex.ownership_keys[303],'R-01:cashier');
 assert.equal(manifest.lane_A_codex.ownership_keys.includes('S-04:cashier'),false);
 assert.equal(report.forms.flatMap(f=>f.source_fields)[498].id,'R-01:cashier');
});
test('tampering with an ownership set or swapping a field is caught even when totals remain unchanged',()=>{
 const copy=structuredClone(manifest),tmp=copy.lane_A_codex.ownership_keys[0];
 copy.lane_A_codex.ownership_keys[0]=copy.lane_B_chatgpt.reserved_next_10_keys[0];
 copy.lane_B_chatgpt.reserved_next_10_keys[0]=tmp;
 assert.throws(()=>check(copy),/original source field order|duplicate owners/);
});
test('cannot accidentally declare unfinished old source rechecks accepted or shrink the protected 246',()=>{
 const a=structuredClone(manifest);a.verified_counts.field_parity_approved=246;
 assert.throws(()=>check(a));
 const b=structuredClone(manifest);b.lane_B_chatgpt.mapped_150_keys.pop();
 assert.throws(()=>check(b));
 const c=structuredClone(manifest);c.lane_A_codex.ownership_keys.pop();
 assert.throws(()=>check(c));
});
