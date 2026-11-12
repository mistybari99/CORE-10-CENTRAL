import test from 'node:test';
import assert from 'node:assert/strict';
import {
  APPROVAL_TABS,verifiedBusinessRows,approvalState,approvalStageText,filteredApprovals,
  summaryCounts,canOfferApprovalAction,canOfferExceptionAction,readableError,safeText
} from '../internal/enterprise-client/c10_gov002_review_ui_model_v1.mjs';
const pending={request_id:1,business_id:101,stored_status:'pending',display_status:'awaiting_stage_1',
  action_code:'STOCK_ADJUST',domain:'demo_stock',source_key:'M-01',expires_at:'2035-01-01T00:00:00Z'};
const approved={...pending,request_id:2,stored_status:'approved',display_status:'approved_pending_execution'};
const expired={...pending,request_id:3,display_status:'expired'};
const rejected={...pending,request_id:4,stored_status:'rejected',display_status:'rejected'};
const withdrawn={...pending,request_id:5,stored_status:'withdrawn',display_status:'withdrawn'};
const deferred={...pending,request_id:6,stored_status:'deferred',display_status:'deferred'};
test('seven required approval tabs including expired and withdrawn',()=>{
  assert.deepEqual(APPROVAL_TABS.map(x=>x[0]),['pending','approved','rejected','deferred','withdrawn','expired','all']);
});
test('never accept another business, malformed IDs, duplicates, fake rows or over-limit read',()=>{
  assert.equal(verifiedBusinessRows([pending],101,'status').length,1);
  for(const rows of [
    [{...pending,business_id:102}], [{...pending,request_id:'0'}],
    [pending,pending], [null], new Array(1001).fill(pending)
  ]) assert.throws(()=>verifiedBusinessRows(rows,101,'status'),/invalid_scoped_projection|server_scope_or_identity_mismatch/);
  assert.throws(()=>verifiedBusinessRows([pending],0,'status'));
  assert.throws(()=>verifiedBusinessRows([],101,'unknown'));
  assert.throws(()=>verifiedBusinessRows([{business_id:101,activity_id:'<script>'}],101,'activity'));
});
test('immutable snapshots, pending stages, display expiry, executed status',()=>{
  const [row]=verifiedBusinessRows([pending],101,'status');
  assert(Object.isFrozen(row));
  assert.equal(approvalStageText(row),'প্রথম ধাপ (Stage 1)');
  assert.equal(approvalState({...pending,display_status:'awaiting_stage_2'}),'pending');
  assert.equal(approvalState({...pending,expires_at:'2020-01-01T00:00:00Z'}),'expired');
  assert.equal(approvalState(expired),'expired');
  assert.equal(approvalState(approved),'approved');
  assert.equal(approvalState({...approved,display_status:'executed'}),'approved');
});
test('business-local counts and status/history filtering do not infer authority',()=>{
  const rows=[pending,approved,expired,rejected,withdrawn,deferred];
  assert.deepEqual(summaryCounts(rows),{
    pending:1,approved:1,rejected:1,deferred:1,withdrawn:1,expired:1,all:6
  });
  assert.deepEqual(filteredApprovals(rows,{tab:'pending'}).map(x=>x.request_id),[1]);
  assert.deepEqual(filteredApprovals(rows,{tab:'all',search:'M-01'}).length,6);
  assert.deepEqual(filteredApprovals(rows,{tab:'all',search:'Stock'}).length,6);
  assert.deepEqual(filteredApprovals(rows,{tab:'withdrawn'}).map(x=>x.request_id),[5]);
  assert.equal(canOfferApprovalAction(pending,'approve'),true);
  assert.equal(canOfferApprovalAction(approved,'approve'),false);
  assert.equal(canOfferApprovalAction(expired,'defer'),false);
  assert.equal(canOfferApprovalAction(pending,'execute_stock'),false);
});
test('exception decisions disabled if parent closed, TTL elapsed, or nonpending',()=>{
  const exception={stored_status:'pending',display_status:'pending',parent_approval_status:'pending',
    expires_at:'2035-01-01T00:00:00Z'};
  assert.equal(canOfferExceptionAction(exception,'acknowledged'),true);
  assert.equal(canOfferExceptionAction({...exception,parent_approval_status:'withdrawn'},'acknowledged'),false);
  assert.equal(canOfferExceptionAction({...exception,expires_at:'2020-01-01T00:00:00Z'},'declined'),false);
  assert.equal(canOfferExceptionAction(exception,'waive_policy'),false);
});
test('error categories show permission, session, stale states without exposing raw internals',()=>{
  assert.match(readableError({status:401,message:'jwt expired'}),/সেশন/);
  assert.match(readableError({code:'42501',message:'permission denied for secret table'}),/অনুমতি নেই/);
  assert.doesNotMatch(readableError(new Error('postgres host secret internal database password')),/password/);
  assert.match(readableError({status:409}),/Refresh/);
});
test('untrusted HTML/script source keys are plain text values, not markup',()=>{
  assert.equal(safeText('<img src=x onerror=alert(1)>'),'<img src=x onerror=alert(1)>');
  assert(!safeText('abc\nscript').includes('\n'));
});