/**
 * CORE 10 GOV-002 — local projections of ALREADY server-RLS-scoped approval rows.
 * Non-authoritative, one-business, first-page-only report contracts.  In
 * particular, these are not all-business totals, immutable export receipts,
 * signed audit proofs, posting results or replacements for GOV-003.
 */
import { approvalState, validBusinessId, verifiedBusinessRows } from './c10_gov002_review_ui_model_v1.mjs';

export const GOV002_REPORT_COVERAGE = 'SERVER_SCOPED_FIRST_PAGE_ONLY';
const MAX_LIMIT = 1000;
const VALID_STORED = new Set(['pending','approved','rejected','deferred','withdrawn']);
const VALID_ACTIVITY = new Set(['approval','exception']);

function pageSize(value) {
  if (!Number.isSafeInteger(value) || value < 1 || value > MAX_LIMIT) {
    throw new Error('invalid_report_page_limit');
  }
  return value;
}
function safeId(value) {
  const text = String(value ?? '');
  if (!/^[1-9][0-9]{0,18}$/u.test(text)) throw new Error('invalid_report_source_id');
  return text;
}
function clean(value, max=240) {
  const text = String(value ?? '').replace(/[\u0000-\u001f\u007f\u2028\u2029]/gu, ' ');
  if (text.length > max) throw new Error('report_source_field_over_limit');
  return text;
}
function date(value) {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) {
    throw new Error('invalid_report_timestamp');
  }
  return value;
}
function optionalHash(value) {
  if (value == null) return null;
  if (typeof value !== 'string' || !/^[a-f0-9]{64}$/u.test(value))
    throw new Error('invalid_report_fingerprint');
  return value;
}
function frozenList(items) { return Object.freeze(items.map(item=>Object.freeze(item))); }

/**
 * Every input page must originate from the existing signed-user review
 * adapter, which calls security_invoker server projections and rechecks RLS.
 * Caller-supplied rows are never sufficient evidence of authorization.
 * This validates bounds and scope to prevent accidental mixed-business output.
 */
export function summarizeScopedApprovalPages({businessId,statusRows,exceptionRows,activityRows,requestedLimit=100,now=Date.now()}) {
  if (!validBusinessId(businessId)) throw new Error('invalid_report_business');
  const limit=pageSize(requestedLimit);
  if (!Number.isFinite(now)) throw new Error('invalid_report_snapshot_clock');
  const tables=[statusRows,exceptionRows,activityRows];
  if (tables.some(v=>!Array.isArray(v) || v.length>limit))throw new Error('invalid_report_page');
  const statuses=verifiedBusinessRows(statusRows,businessId,'status');
  const exceptions=verifiedBusinessRows(exceptionRows,businessId,'exceptions');
  const activities=verifiedBusinessRows(activityRows,businessId,'activity');
  const counts={pending:0,approved:0,rejected:0,deferred:0,withdrawn:0,expired:0,unknown:0};
  const stages={awaiting_stage_1:0,awaiting_stage_2:0};
  const sources=[];
  const approvalHistory=[];
  for(const r of statuses){
    const state=approvalState(r,now);
    if(!VALID_STORED.has(String(r.stored_status||'')))throw new Error('invalid_report_approval_status');
    counts[state]++;
    const display=clean(r.display_status||'',64);
    if(state==='pending' && display in stages) stages[display]++;
    sources.push({
      request_id:safeId(r.request_id),business_id:businessId,
      domain:clean(r.domain,80),action_code:clean(r.action_code,80),
      source_key:clean(r.source_key,128),source_version:safeId(r.source_version),
      policy_version:r.policy_version==null?null:safeId(r.policy_version),
      source_fingerprint:optionalHash(r.source_fingerprint),
      expires_at:date(r.expires_at),
      execution_kind:r.execution_kind==null?null:clean(r.execution_kind,48),
      movement_id:r.movement_id==null?null:safeId(r.movement_id),
      original_movement_id:r.original_movement_id==null?null:safeId(r.original_movement_id),
      state,
      // Receipt fields are *reference information*. Presence does not prove
      // canonical business execution or let GOV-002 reverse a real ledger.
      execution_proof:'SYNTHETIC_OR_UNCERTIFIED_SOURCE_VIEW'
    });
    approvalHistory.push({
      request_id:safeId(r.request_id),state,display_status:display,
      requested_at:date(r.requested_at),requested_by:clean(r.requested_by,80)
    });
  }
  const exceptionCounts={pending:0,acknowledged:0,declined:0,withdrawn:0,expired:0,parent_closed:0,unknown:0,urgent:0};
  const exceptionCases=[];
  for(const r of exceptions){
    const stored=String(r.stored_status||'');
    if(!['pending','acknowledged','declined','withdrawn'].includes(stored))throw new Error('invalid_report_exception_status');
    const display=String(r.display_status||'');
    const state=['expired','parent_closed'].includes(display)?display:stored;
    exceptionCounts[state]++;
    if(r.severity==='urgent')exceptionCounts.urgent++;
    else if(r.severity!=='normal')throw new Error('invalid_report_exception_severity');
    exceptionCases.push({
      escalation_id:safeId(r.escalation_id),request_id:safeId(r.request_id),
      severity:r.severity,state,
      expires_at:date(r.expires_at),created_at:date(r.created_at),
      parent_approval_status:clean(r.parent_approval_status,48)
      // Intentionally excludes raw exception reasons, other tenants and
      // hypothetical waiver/override authority.
    });
  }
  const reviewers=new Map();
  for(const r of activities){
    if(!VALID_ACTIVITY.has(String(r.activity_type||'')))throw new Error('invalid_report_activity_type');
    if(!/^(approval|exception):[1-9][0-9]*$/u.test(String(r.activity_id||'')))
      throw new Error('invalid_report_activity_id');
    const actor=clean(r.event_actor,80);
    const event=clean(r.action,80);
    // "submitted" etc are an event history, not proof that reviewer held a
    // role or that a decision was authorized outside the underlying RPC.
    const current=reviewers.get(actor)||{event_actor:actor,events:0,approvals:0,rejections:0,deferrals:0,exception_triage:0};
    current.events++;
    if(r.activity_type==='approval'){
      if(event==='approve') current.approvals++;
      if(event==='reject') current.rejections++;
      if(event==='defer') current.deferrals++;
    }else current.exception_triage++;
    reviewers.set(actor,current);
    date(r.occurred_at);
  }
  const pageCounts=Object.freeze({...counts});
  return Object.freeze({
    kind:'gov002-scoped-page-report-v1',business_id:businessId,
    coverage:GOV002_REPORT_COVERAGE,requested_limit:limit,
    page_sizes:Object.freeze({approvals:statuses.length,exceptions:exceptions.length,activity:activities.length}),
    may_have_more:tables.some(arr=>arr.length===limit),
    status_summary:pageCounts,
    pending_summary:Object.freeze({pending:counts.pending,expired:counts.expired,...stages}),
    rejection_withdrawal:Object.freeze({rejected:counts.rejected,withdrawn:counts.withdrawn}),
    exception_escalation:Object.freeze({...exceptionCounts}),
    reviewer_activity:frozenList([...reviewers.values()].sort((a,b)=>b.events-a.events)),
    business_approval_history:frozenList(approvalHistory),
    source_linked_evidence:frozenList(sources),
    exception_cases:frozenList(exceptionCases),
    not_a_certified_audit:true
  });
}

/** Host must provide the already-built signed review adapter from PR #83. */
export function createGov002ReportReader(signedReviewClient) {
  if(!signedReviewClient || ['listStatus','listExceptions','listActivity'].some(k=>typeof signedReviewClient[k]!=='function')) {
    throw new Error('signed_review_client_required');
  }
  return Object.freeze({
    async readScopedReportPage({businessId,limit=100}) {
      if(!validBusinessId(businessId))throw new Error('invalid_report_business');
      pageSize(limit);
      // Calls reauthenticate independently; every SQL view has server-side RLS.
      // Failure of *any* source denies the whole report (no stale fallback).
      const statusRows=await signedReviewClient.listStatus({businessId,limit});
      const exceptionRows=await signedReviewClient.listExceptions({businessId,limit});
      const activityRows=await signedReviewClient.listActivity({businessId,limit});
      return summarizeScopedApprovalPages({businessId,statusRows,exceptionRows,activityRows,requestedLimit:limit});
    }
  });
}