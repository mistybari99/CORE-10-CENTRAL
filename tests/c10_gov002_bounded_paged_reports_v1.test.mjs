import test from 'node:test';
import assert from 'node:assert/strict';
import {createGov002BoundedReportPager,GOV002_PAGED_COVERAGE} from '../internal/enterprise-client/c10_gov002_bounded_paged_reports_v1.mjs';
const activity=(id,b=101)=>({activity_id:`approval:${id}`,business_id:b,request_id:id,domain:'demo',action_code:'adjust',source_key:'=SUM(A1)',event_actor:'reviewer',activity_type:'approval',action:'approve'});
function fake(rows){let calls=[];const obj={};for(const [kind,fn] of Object.entries({status:'listStatusPage',exceptions:'listExceptionsPage',activity:'listActivityPage'})){
  obj[fn]=async ({businessId,offset,limit})=>{
    calls.push({kind,businessId,offset,limit});const items=rows.slice(offset,offset+limit);
    return {business_id:businessId,offset,limit,rows:items,has_more:items.length===limit,coverage:GOV002_PAGED_COVERAGE};
  };
 }return {client:obj,calls};}
test('bounded CSV traverses several RLS-scoped pages but never claims audit completeness',async()=>{
 const x=fake([activity(1),activity(2),activity(3),activity(4),activity(5)]);
 const pager=createGov002BoundedReportPager(x.client);
 const exportData=await pager.exportBoundedActivityCsv({businessId:101,pageSize:2});
 assert.deepEqual(x.calls.map(v=>v.offset),[0,2,4]);
 assert.equal(exportData.rows_exported,5);assert.equal(exportData.pages_read,3);
 assert.equal(exportData.is_consistent_snapshot,false);assert.equal(exportData.full_audit_archive,false);
 assert.equal(exportData.coverage,'SIGNED_RLS_OFFSET_WINDOW_NOT_ATOMIC');
 assert.ok(exportData.csv.startsWith('\ufeff'));
 assert.ok(exportData.csv.includes("'=SUM(A1)"));
});
test('scoped pages are frozen, range-limited and not source of authorization',async()=>{
 const x=fake([activity(5)]);const p=createGov002BoundedReportPager(x.client);
 const v=await p.readScopedPage({businessId:101,kind:'activity',offset:0,limit:2});
 assert.equal(v.is_consistent_snapshot,false);assert.ok(Object.isFrozen(v.rows[0]));
 assert.equal(v.may_have_more,false);assert.equal(v.offset,0);
 for(const offset of [-1,1.3,50001,'0']) await assert.rejects(p.readScopedPage({businessId:101,kind:'activity',offset,limit:2}),/invalid_paged_offset/);
 for(const limit of [0,1001,'2'])await assert.rejects(p.readScopedPage({businessId:101,kind:'activity',limit}),/invalid_paged_limit/);
 await assert.rejects(p.readScopedPage({businessId:0,kind:'activity'}),/invalid_paged_scope/);
 await assert.rejects(p.readScopedPage({businessId:101,kind:'finance'}),/invalid_paged_scope/);
});
test('other-business rows, mismatched metadata and repeated event IDs deny whole export',async()=>{
 for(const rows of [[activity(1,201)],[activity(1),activity(1)]]){
  const p=createGov002BoundedReportPager(fake(rows).client);
  await assert.rejects(p.exportBoundedActivityCsv({businessId:101,pageSize:1}),/server_scope_or_identity_mismatch|paged_duplicate_or_invalid_event/);
 }
 const x=fake([]);x.client.listStatusPage=async()=>({business_id:202,offset:0,limit:2,coverage:GOV002_PAGED_COVERAGE,rows:[],has_more:false});
 await assert.rejects(createGov002BoundedReportPager(x.client).readScopedPage({businessId:101,kind:'status',limit:2}),/paged_server_contract_mismatch/);
});
test('export cap prevents indefinite scans and labels all partial windows as non-atomic',async()=>{
 const x=fake(Array.from({length:6},(_,i)=>activity(i+1)));
 const r=await createGov002BoundedReportPager(x.client).exportBoundedActivityCsv({businessId:101,pageSize:2,maxRows:3});
 assert.equal(r.rows_exported,3);assert.equal(r.may_have_more,true);assert.equal(r.production_certified,false);
 assert.deepEqual(x.calls.map(v=>v.limit),[2,1]);
});
test('network errors fail closed without returning partial CSV',async()=>{
 const x=fake([activity(1)]);
 x.client.listActivityPage=async()=>{throw new Error('permission_denied')};
 await assert.rejects(createGov002BoundedReportPager(x.client).exportBoundedActivityCsv({businessId:101}),/permission_denied/);
 assert.throws(()=>createGov002BoundedReportPager({}),/signed_scoped_paged_client_required/);
});