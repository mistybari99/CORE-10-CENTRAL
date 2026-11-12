import test from 'node:test';
import assert from 'node:assert/strict';
import {summarizeScopedApprovalPages,createGov002ReportReader,GOV002_REPORT_COVERAGE} from '../internal/enterprise-client/c10_gov002_scoped_reports_v1.mjs';
import {describeGov002OperationPort,GOV002_OPERATION_PORTS} from '../internal/enterprise-client/c10_gov002_domain_adapters_contract_v1.mjs';

const F='b'.repeat(64);
const now='2026-11-12T14:00:00Z';
function req(n,status,display=status,overrides={}) {return {
 request_id:n,business_id:101,domain:'inventory',action_code:'adjust',source_key:`ADJ-${n}`,
 source_version:2,policy_version:3,source_fingerprint:F,requested_by:'maker-101',
 requested_at:now,expires_at:'2026-11-13T14:00:00Z',stored_status:status,
 display_status:display,execution_kind:null,movement_id:null,original_movement_id:null,
 ...overrides
};}
function exc(n,status='pending',overrides={}) {return {
 escalation_id:n,request_id:n,business_id:101,stored_status:status,display_status:status,
 parent_approval_status:'pending',severity:'urgent',created_at:now,expires_at:'2026-11-13T14:00:00Z',
 reason:'sensitive reason must not appear in report',...overrides
};}
function activity(id,actor,action='approve',type='approval') {return {
 activity_id:`${type}:${id}`,business_id:101,request_id:id,event_actor:actor,
 action,activity_type:type,occurred_at:now,source_key:'=MALICIOUS()',
 original_payload:{secret:'never include'}
};}
const fixture={businessId:101,requestedLimit:100,now:Date.parse(now),
 statusRows:[req(1,'pending','awaiting_stage_1'),req(2,'pending','expired',{expires_at:'2026-11-11T00:00:00Z'}),
  req(3,'approved','executed',{execution_kind:'post',movement_id:5}),req(4,'rejected'),req(5,'withdrawn'),req(6,'deferred')],
 exceptionRows:[exc(7),exc(8,'acknowledged',{severity:'normal'})],
 activityRows:[activity(1,'reviewer-one','approve'),activity(2,'reviewer-one','reject'),activity(3,'reviewer-two','declined','exception')]
};

test('constructs six non-authoritative business-scoped reports from bounded signed server pages',()=>{
 const r=summarizeScopedApprovalPages(fixture);
 assert.equal(r.coverage,GOV002_REPORT_COVERAGE);
 assert.deepEqual(r.status_summary,{pending:1,approved:1,rejected:1,deferred:1,withdrawn:1,expired:1,unknown:0});
 assert.deepEqual(r.pending_summary,{pending:1,expired:1,awaiting_stage_1:1,awaiting_stage_2:0});
 assert.deepEqual(r.rejection_withdrawal,{rejected:1,withdrawn:1});
 assert.equal(r.exception_escalation.pending,1);
 assert.equal(r.exception_escalation.urgent,1);
 assert.equal(r.exception_escalation.acknowledged,1);
 assert.equal(r.reviewer_activity.find(x=>x.event_actor==='reviewer-one').events,2);
 assert.equal(r.source_linked_evidence[2].movement_id,'5');
 assert.equal(r.source_linked_evidence[2].execution_proof,'SYNTHETIC_OR_UNCERTIFIED_SOURCE_VIEW');
 assert.equal(r.source_linked_evidence[0].source_fingerprint,F);
 assert.equal(r.not_a_certified_audit,true);
 assert.equal(JSON.stringify(r).includes('sensitive reason must not appear'),false);
 assert.equal(JSON.stringify(r).includes('never include'),false);
 assert.equal(JSON.stringify(r).includes('=MALICIOUS()'),false);
 assert.ok(Object.isFrozen(r) && Object.isFrozen(r.source_linked_evidence[0]));
});
test('rejects cross-business leakage independently in each SQL report source',()=>{
 for(const key of ['statusRows','exceptionRows','activityRows']) {
  const arr=fixture[key].map((x,i)=>i===0?{...x,business_id:102}:x);
  assert.throws(()=>summarizeScopedApprovalPages({...fixture,[key]:arr}),/server_scope_or_identity_mismatch/);
 }
});
test('rejects duplicate IDs, malformed hash and unknown statuses rather than displaying untrusted report',()=>{
 assert.throws(()=>summarizeScopedApprovalPages({...fixture,statusRows:[req(1,'pending'),req(1,'pending')]}),/server_scope_or_identity_mismatch/);
 assert.throws(()=>summarizeScopedApprovalPages({...fixture,statusRows:[req(1,'approved','approved',{source_fingerprint:'forged'})]}),/invalid_report_fingerprint/);
 assert.throws(()=>summarizeScopedApprovalPages({...fixture,statusRows:[req(1,'payable')]}),/invalid_report_approval_status/);
 assert.throws(()=>summarizeScopedApprovalPages({...fixture,exceptionRows:[exc(1,'approved')]}),/invalid_report_exception_status/);
 assert.throws(()=>summarizeScopedApprovalPages({...fixture,activityRows:[{...activity(2,'admin','execute','approval'),activity_type:'stock'}]}),/invalid_report_activity_type/);
});
test('page boundary is explicit and is never mislabelled all-business totals',()=>{
 const r=summarizeScopedApprovalPages({businessId:101,statusRows:[req(1,'pending')],exceptionRows:[],activityRows:[],requestedLimit:1});
 assert.equal(r.may_have_more,true);
 assert.equal(r.page_sizes.approvals,1);
 assert.equal(r.coverage,'SERVER_SCOPED_FIRST_PAGE_ONLY');
 assert.throws(()=>summarizeScopedApprovalPages({...fixture,requestedLimit:2}),/invalid_report_page/);
 for(const limit of [0,1001,2.4,'25'])assert.throws(()=>summarizeScopedApprovalPages({...fixture,requestedLimit:limit}),/invalid_report_page_limit/);
});
test('authenticated review-client report reader calls only existing three scoped views and fails closed',async()=>{
 const called=[];
 const review={
  async listStatus(args){called.push(['status',args]);return [req(1,'approved')];},
  async listExceptions(args){called.push(['exceptions',args]);return [exc(2)];},
  async listActivity(args){called.push(['activity',args]);return [activity(1,'reviewer-one')];}
 };
 const client=createGov002ReportReader(review);
 const data=await client.readScopedReportPage({businessId:101,limit:25});
 assert.equal(data.status_summary.approved,1);
 assert.deepEqual(called,[['status',{businessId:101,limit:25}],['exceptions',{businessId:101,limit:25}],['activity',{businessId:101,limit:25}]]);
 await assert.rejects(client.readScopedReportPage({businessId:0}),/invalid_report_business/);
 assert.equal(called.length,3);
 const fail={...review,async listExceptions(){throw new Error('permission_denied')}};
 await assert.rejects(createGov002ReportReader(fail).readScopedReportPage({businessId:101}),/permission_denied/);
 assert.throws(()=>createGov002ReportReader({listStatus(){}}),/signed_review_client_required/);
});
test('operation ports are explicit seven-domain typed intents, never executors',()=>{
 assert.equal(GOV002_OPERATION_PORTS.length,7);
 for(const type of GOV002_OPERATION_PORTS){
  const site=['inventory_adjustment','stock_transfer','production_exception'].includes(type)?1:null;
  const unit=['purchase_operation','financial_approval'].includes(type)?'BDT':'KG';
  const desc=describeGov002OperationPort({operation:type,businessId:101,siteId:site,sourceId:'DOC-123',sourceVersion:2,unit});
  assert.equal(desc.status,'BLOCKED_CANONICAL_DOMAIN_ADAPTER_NOT_CERTIFIED');
  assert.equal(desc.side_effects_enabled,false);
  assert.equal(desc.approval_is_not_posting,true);
  assert.ok(desc.integration_requirements.some(v=>v.includes('idempotency')));
  assert.equal(typeof desc.execute,'undefined');
  assert.equal(typeof desc.approve,'undefined');
 }
});
test('domain port rejects client-made authority and unconfigured units/scopes',()=>{
 const x={operation:'financial_approval',businessId:101,sourceId:'INVOICE/22',sourceVersion:2,unit:'BDT'};
 for(const key of ['role','actorId','policyId','tenantId','sourceFingerprint','serviceRole','approvalReceipt','permission']){
   assert.throws(()=>describeGov002OperationPort({...x,[key]:'ADMIN'}),/untrusted_operation_authority/);
 }
 assert.throws(()=>describeGov002OperationPort({...x,unit:'USD'}),/unconfigured_approval_unit/);
 assert.throws(()=>describeGov002OperationPort({...x,sourceVersion:0}),/invalid_operation_source_binding/);
 assert.throws(()=>describeGov002OperationPort({...x,sourceId:'../\nDIFF'}),/invalid_operation_source_binding/);
 assert.throws(()=>describeGov002OperationPort({...x,operation:'pay_now'}),/unsupported_canonical_operation_port/);
 assert.throws(()=>describeGov002OperationPort({...x,operation:'inventory_adjustment'}),/operation_requires_canonical_site/);
 assert.throws(()=>describeGov002OperationPort({...x,businessId:0}),/invalid_operation_business/);
});