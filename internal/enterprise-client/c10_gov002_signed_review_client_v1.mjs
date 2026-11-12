/**
 * CORE 10 GOV-002: UI-independent signed-user review adapter (DRAFT).
 * Only non-posting approval review, escalation triage, scoped read projections
 * and local CSV formatting. NO service_role or direct table writes.
 *
 * Must receive an authenticated Supabase client in a future authorized staging
 * UI. auth.getUser is only a frontend guard; backend RLS/RPC is final authority.
 * Never use this adapter to post stock, finance, payments or bypass approvals.
 */
import { makeApprovalActivityCsv } from "./c10_gov002_activity_csv_v1.mjs";

const SCHEMA = "c10_demo";
const KEY = /^[A-Za-z0-9_-]{8,128}$/u;
const VIEWS = Object.freeze({
  status: Object.freeze({
    name: "approval_status_report_v1",
    columns: "request_id,business_id,domain,action_code,source_key,source_version,policy_version,source_fingerprint,requested_by,requested_at,expires_at,stored_status,display_status,required_checks,completed_checks,execution_kind,movement_id,original_movement_id",
    order: "requested_at"
  }),
  exceptions: Object.freeze({
    name: "approval_exception_inbox_v1",
    columns: "escalation_id,request_id,business_id,created_by,severity,reason,created_at,expires_at,stored_status,display_status,parent_approval_status,decided_by,decided_at",
    order: "created_at"
  }),
  activity: Object.freeze({
    name: "approval_activity_feed_v1",
    columns: "activity_id,business_id,request_id,domain,action_code,source_key,source_version,request_maker,event_actor,activity_type,action,severity,occurred_at,approval_status",
    order: "occurred_at"
  })
});
function positiveId(v) {
 if (typeof v === "number" && Number.isSafeInteger(v) && v>0) return v;
 if (typeof v === "string" && /^[1-9][0-9]{0,18}$/u.test(v)) return v;
 throw new Error("invalid_positive_id");
}
function businessId(v) {
 if (!Number.isSafeInteger(v) || v<=0) throw new Error("invalid_business_id");
 return v;
}
function key(v) { if (typeof v!=="string" || !KEY.test(v)) throw new Error("invalid_idempotency_key");return v; }
function eventText(v) { if(typeof v!=="string" || v.trim().length<12 || v.trim().length>400)throw new Error("invalid_escalation_reason");return v.trim(); }
function boundedLimit(v) { if(!Number.isSafeInteger(v) || v<1 || v>1000)throw new Error("invalid_page_limit");return v; }

export function createGov002ReviewClient(supabase) {
 if(!supabase || typeof supabase.schema!=="function" ||
   !supabase.auth || typeof supabase.auth.getUser!=="function") {
  throw new Error("signed_supabase_client_required");
 }
 async function currentUser() {
  const result=await supabase.auth.getUser();
  if(result?.error || !result?.data?.user?.id)throw new Error("auth_required");
  return result.data.user.id;
 }
 async function list(view,requestedBusiness,limit=50) {
  const b=businessId(requestedBusiness), n=boundedLimit(limit), v=VIEWS[view];
  if(!v)throw new Error("invalid_approval_view");
  await currentUser();
  const q=supabase.schema(SCHEMA).from(v.name);
  const result=await q.select(v.columns)
    .eq("business_id",b).order(v.order,{ascending:false}).limit(n);
  if(result?.error)throw result.error;
  if(!Array.isArray(result?.data))throw new Error("approval_read_invalid_response");
  // Defence in depth: never render/export a wrong-business projection.
  if(result.data.some(x=>Number(x.business_id)!==b))throw new Error("server_scope_mismatch");
  return result.data;
 }
 async function listPage(view,requestedBusiness,offset=0,limit=250) {
  const b=businessId(requestedBusiness),n=boundedLimit(limit),v=VIEWS[view];
  if(!v||!Number.isSafeInteger(offset)||offset<0||offset>50000)
   throw new Error("invalid_page_offset_or_view");
  // Each page is a signed server-RLS read, never service_role. Timestamp +
  // identifier ordering is deterministic inside each single response; offset
  // windows are NOT a frozen transactional snapshot.
  const actor=await currentUser();
  const tie=view==="status"?"request_id":view==="exceptions"?"escalation_id":"activity_id";
  const result=await supabase.schema(SCHEMA).from(v.name).select(v.columns)
   .eq("business_id",b).order(v.order,{ascending:false})
   .order(tie,{ascending:false}).range(offset,offset+n-1);
  const after=await currentUser();
  if(after!==actor)throw new Error("signed_actor_changed");
  if(result?.error)throw result.error;
  if(!Array.isArray(result?.data)||result.data.length>n)
   throw new Error("paged_approval_read_invalid_response");
  if(result.data.some(x=>Number(x?.business_id)!==b))
   throw new Error("server_scope_mismatch");
  return Object.freeze({business_id:b,offset,limit:n,rows:result.data,
   has_more:result.data.length===n,
   coverage:"SIGNED_RLS_OFFSET_WINDOW_NOT_ATOMIC"});
 }
 async function rpc(name,params) {
  await currentUser();
  const result=await supabase.schema(SCHEMA).rpc(name,params);
  if(result?.error)throw result.error;
  if(result?.data==null)throw new Error("approval_rpc_missing_receipt");
  return result.data;
 }
 return Object.freeze({
  listStatus:({businessId:b,limit=50})=>list("status",b,limit),
  listExceptions:({businessId:b,limit=50})=>list("exceptions",b,limit),
  listActivity:({businessId:b,limit=50})=>list("activity",b,limit),
  listStatusPage:({businessId:b,offset=0,limit=250})=>listPage("status",b,offset,limit),
  listExceptionsPage:({businessId:b,offset=0,limit=250})=>listPage("exceptions",b,offset,limit),
  listActivityPage:({businessId:b,offset=0,limit=250})=>listPage("activity",b,offset,limit),
  listReviewerTasks:async({businessId:b})=>{
    const business=businessId(b),actor=await currentUser();
    const result=await supabase.schema(SCHEMA).rpc("my_routed_review_tasks_v2",{p_business:business});
    const after=await currentUser();
    if(after!==actor)throw new Error("signed_actor_changed");
    if(result?.error)throw result.error;
    if(!Array.isArray(result?.data)||result.data.length>100)
      throw new Error("reviewer_task_invalid_response");
    if(result.data.some(x=>!x||Number(x.business_id)!==business||
       !/^[1-9][0-9]*$/u.test(String(x.request_id??""))||
       !Number.isSafeInteger(x.stage_no)||x.stage_no<1||
       !Number.isSafeInteger(x.stage_total)||x.stage_total<2||x.stage_total>5||
       x.stage_no>x.stage_total))
      throw new Error("reviewer_task_invalid_response");
    return result.data;
  },
  decideApproval:({requestId,action,idempotencyKey})=>{
   if(!["approve","reject","defer"].includes(action))throw new Error("invalid_approval_action");
   return rpc("decide_approval",{
    p_request:positiveId(requestId),p_action:action,p_key:key(idempotencyKey)
   });
  },
  withdrawApproval:({requestId,idempotencyKey})=>
   rpc("withdraw_typed_approval_v1",{
    p_request:positiveId(requestId),p_key:key(idempotencyKey)
   }),
  requestException:({requestId,reason,severity="normal",ttlMinutes=30,idempotencyKey})=>{
   if(!["normal","urgent"].includes(severity) ||
      !Number.isSafeInteger(ttlMinutes) || ttlMinutes<5 || ttlMinutes>1440)
     throw new Error("invalid_escalation_policy");
   return rpc("request_approval_exception_v1",{
    p_request:positiveId(requestId),
    p_reason:eventText(reason),p_severity:severity,
    p_minutes:ttlMinutes,p_key:key(idempotencyKey)
   });
  },
  decideException:({escalationId,action,idempotencyKey})=>{
   if(!["acknowledged","declined"].includes(action))throw new Error("invalid_escalation_decision");
   return rpc("decide_approval_exception_v1",{
    p_escalation:positiveId(escalationId),
    p_action:action,p_key:key(idempotencyKey)
   });
  },
  withdrawException:({escalationId,idempotencyKey})=>
   rpc("withdraw_approval_exception_v1",{
    p_escalation:positiveId(escalationId),p_key:key(idempotencyKey)
   }),
  /**
   * Exports ONLY the first requested authorized page, not a full audit archive.
   * Signed server-side RLS and scoped business filter remain mandatory.
   */
  exportActivityCsv:async({businessId:b,limit=1000})=>{
   const business=businessId(b),n=boundedLimit(limit);
   const rows=await list("activity",business,n);
   return makeApprovalActivityCsv(rows,{businessId:business});
  }
 });
}
