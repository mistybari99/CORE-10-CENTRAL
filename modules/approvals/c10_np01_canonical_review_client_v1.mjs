/**
 * CORE 10 S1-c canonical GOV-002 signed-user review adapter.
 * Uses ONLY core10 RPC ports (0008–0012). No direct table, service_role,
 * c10_demo fixture, stock/finance posting or original Islamiya UI writes.
 *
 * auth.getUser checks the connected signed identity. SQL RPC/RLS remains the
 * final authorization authority. Mock tests are NOT a real GoTrue certification.
 */
const SCHEMA='core10';
const KEY=/^[A-Za-z0-9_-]{8,128}$/u;
const POSITIVE=/^[1-9][0-9]{0,18}$/u;
const ACTIONS=new Set(['approve','reject','defer']);
const VALID_STATUS=new Set(['pending','approved','rejected','deferred','withdrawn']);
const INVALIDATION=new Set(['SIGNED_OUT','USER_DELETED','PASSWORD_RECOVERY','MFA_CHALLENGE_VERIFIED']);
const strictBusiness=x=>Number.isSafeInteger(x)&&x>0?x:(()=>{throw Error('invalid_business_id')})();
const strictLimit=x=>Number.isSafeInteger(x)&&x>=1&&x<=100?x:(()=>{throw Error('invalid_page_limit')})();
const strictKey=x=>typeof x==='string'&&KEY.test(x)?x:(()=>{throw Error('invalid_idempotency_key')})();
const canonicalId=x=>{
 const s=typeof x==='number'&&Number.isSafeInteger(x)?String(x):x;
 if(typeof s!=='string'||!POSITIVE.test(s)||BigInt(s)>9223372036854775807n)throw Error('invalid_positive_id');
 return s;
};
const signedId=x=>{
 if(!x?.data?.user?.id||x.error||typeof x.data.user.id!=='string')throw Error('signed_auth_required');
 return x.data.user.id;
};
const currentStage=x=>Number.isSafeInteger(x)&&x>=1&&x<=5;
const escCsv=x=>{
 let s=String(x??'').replace(/[\u0000-\u001f\u007f]/gu,' ');
 if(/^[=+\-@]/u.test(s))s="'"+s;
 return '"'+s.replace(/"/gu,'""')+'"';
};

export function createCanonicalGov002ReviewClient(supabase,{allowMutations=false}={}){
 if(!supabase?.auth||typeof supabase.auth.getUser!=='function'
  ||typeof supabase.auth.onAuthStateChange!=='function'
  ||typeof supabase.schema!=='function')throw Error('signed_supabase_client_required');
 let actor=null,revision=0,invalidated=false,closed=false;
 const subscription=supabase.auth.onAuthStateChange((event,session)=>{
  if(closed||event==='INITIAL_SESSION')return;
  if(INVALIDATION.has(event)||(actor!==null&&event==='SIGNED_IN')
   ||(actor!==null&&event==='USER_UPDATED')
   ||(actor&&session?.user?.id&&session.user.id!==actor)){
   invalidated=true;revision++;
  }
 })?.data?.subscription;
 if(!subscription||typeof subscription.unsubscribe!=='function')
  throw Error('signed_session_change_subscription_required');
 const active=()=>{if(closed||invalidated)throw Error('signed_session_invalidated');};
 async function getActor(){
  active();
  let uid;
  try{uid=signedId(await supabase.auth.getUser());}catch{
   invalidated=true;revision++;throw Error('signed_session_invalidated');
  }
  if(actor!==null&&actor!==uid){
   invalidated=true;revision++;throw Error('signed_session_invalidated');
  }
  actor=uid;active();return uid;
 }
 async function rpc(name,params){
  const before=await getActor(),revisionBefore=revision;
  let result,thrown;
  try{result=await supabase.schema(SCHEMA).rpc(name,params);}
  catch(error){thrown=error;}
  const after=await getActor();
  if(before!==after||revisionBefore!==revision)throw Error('signed_session_invalidated');
  if(thrown)throw thrown;
  if(result?.error)throw result.error;
  if(result?.data==null)throw Error('canonical_approval_rpc_no_receipt');
  return result.data;
 }
 const checkedRows=(rows,b,limit,kind)=>{
  if(!Array.isArray(rows)||rows.length>limit)throw Error('canonical_approval_invalid_rows');
  const seen=new Set();
  return Object.freeze(rows.map(row=>{
   if(!row||typeof row!=='object'||Array.isArray(row)||Number(row.business_id)!==b)
    throw Error('canonical_approval_scope_mismatch');
   const id=canonicalId(kind==='tasks'?row.request_id:kind==='activity'?row.event_id:row.request_id);
   if(seen.has(id))throw Error('canonical_approval_duplicate_id');seen.add(id);
   if(kind==='status'){
    if(!VALID_STATUS.has(row.stored_status)
      ||!Number.isSafeInteger(row.completed_checks)||row.completed_checks<0
      ||!Number.isSafeInteger(row.required_checks)||row.required_checks<0
      ||row.required_checks>5||row.completed_checks>row.required_checks
      ||(row.required_checks===0&&(row.stored_status!=='approved'||row.can_review_now!==false))
      ||typeof row.can_review_now!=='boolean'||typeof row.is_maker!=='boolean'
      ||typeof row.display_status!=='string'||row.display_status.length>36)
     throw Error('canonical_approval_invalid_status');
   }else if(kind==='tasks'){
    if(!currentStage(row.stage_no)||!currentStage(row.stage_total)
     ||row.stage_no>row.stage_total)
     throw Error('canonical_approval_invalid_task');
   }else if(kind==='activity'){
    canonicalId(row.audit_event_id);
    if(!['approve','reject','defer','withdraw','delegate','revoke'].includes(row.action))
     throw Error('canonical_approval_invalid_event');
    canonicalId(row.request_id);
    if(row.stage_no!=null&&!currentStage(row.stage_no))throw Error('canonical_approval_invalid_stage');
   }
   return Object.freeze({...row});
  }));
 };
 const listStatus=async({businessId,limit=100})=>{
  const b=strictBusiness(businessId),n=strictLimit(limit);
  const data=await rpc('my_approval_status_v1',{p_business:b,p_limit:n});
  return checkedRows(data,b,n,'status');
 };
 const listActivity=async({businessId,limit=100})=>{
  const b=strictBusiness(businessId),n=strictLimit(limit);
  const data=await rpc('my_approval_activity_v1',{p_business:b,p_limit:n});
  return checkedRows(data,b,n,'activity');
 };
 const listReviewerTasks=async({businessId})=>{
  const b=strictBusiness(businessId);
  const data=await rpc('my_routed_review_tasks_v1',{p_business:b});
  return checkedRows(data,b,100,'tasks');
 };
 const enabled=()=>{
  if(allowMutations!==true)throw Error('approval_mutations_disabled');
 };
 const decideApproval=async({businessId,requestId,action,idempotencyKey})=>{
  enabled();const b=strictBusiness(businessId),id=canonicalId(requestId);
  if(!ACTIONS.has(action))throw Error('invalid_approval_action');
  const k=strictKey(idempotencyKey);
  // A task list is a useful preflight, never authorization: the server
  // re-evaluates membership, source, stage and maker/checker under a row lock.
  const tasks=await listReviewerTasks({businessId:b});
  if(!tasks.some(t=>canonicalId(t.request_id)===id))throw Error('reviewer_task_not_available');
  const data=await rpc('decide_approval',{p_request:id,p_action:action,p_key:k});
  return canonicalId(data);
 };
 const withdrawApproval=async({businessId,requestId,idempotencyKey})=>{
  enabled();const b=strictBusiness(businessId),id=canonicalId(requestId);
  const k=strictKey(idempotencyKey);
  const rows=await listStatus({businessId:b});
  const q=rows.find(x=>canonicalId(x.request_id)===id);
  if(!q||q.is_maker!==true||q.stored_status!=='pending'||q.completed_checks!==0)
   throw Error('maker_withdraw_not_available');
  const data=await rpc('withdraw_typed_approval_v1',{p_request:id,p_key:k});
  return canonicalId(data);
 };
 const exportActivityCsv=async({businessId,limit=100})=>{
  const b=strictBusiness(businessId),n=strictLimit(limit);
  const rows=await listActivity({businessId:b,limit:n});
  const cols=['event_id','business_id','request_id','action','occurred_at','stage_no','approval_status','audit_event_id'];
  return cols.join(',')+'\r\n'+rows.map(row=>cols.map(c=>escCsv(row[c])).join(',')).join('\r\n');
 };
 return Object.freeze({
  listStatus,listActivity,listReviewerTasks,decideApproval,withdrawApproval,exportActivityCsv,
  getState:()=>Object.freeze({connected:!closed&&!invalidated,mutationsEnabled:allowMutations===true,actorBound:actor!==null}),
  destroy:()=>{if(!closed){closed=true;revision++;subscription.unsubscribe();}}
 });
}
