/**
 * GOV-002 signed-user session-bound guard, additive staging-only adapter.
 * Server remains authority; this guards an existing UI against stale cross-user
 * results and never authorizes, signs, retries or executes operational commands.
 * A result arriving after signout/switch cannot be delivered to the old UI.
 */
const METHODS=Object.freeze([
  'listStatus','listExceptions','listActivity',
  'decideApproval','withdrawApproval','requestException',
  'decideException','withdrawException','exportActivityCsv',
  'listStatusPage','listExceptionsPage','listActivityPage'
]);
const INVALIDATING_EVENTS=new Set([
  'SIGNED_OUT','USER_DELETED','PASSWORD_RECOVERY','MFA_CHALLENGE_VERIFIED'
]);

export function createGov002SessionBoundReviewClient({supabaseClient,reviewClient,onInvalidated=()=>{}}={}){
  const auth=supabaseClient?.auth;
  if(!auth||typeof auth.getUser!=='function'||typeof auth.onAuthStateChange!=='function')
    throw new Error('signed_session_change_subscription_required');
  if(!reviewClient||METHODS.some(k=>typeof reviewClient[k]!=='function'))
    throw new Error('existing_signed_review_adapter_required');
  if(typeof onInvalidated!=='function')throw new Error('invalid_session_callback');
  let actor=null,epoch=0,invalidated=false,closed=false,reason=null;
  function invalidate(why='session_changed'){
    if(closed||invalidated)return;
    invalidated=true;reason=why;epoch++;
    try{onInvalidated(why);}catch{ /* notification is not authority */ }
  }
  function ensureActive(){
    if(closed||invalidated)throw new Error('gov002_session_invalidated');
  }
  const response=auth.onAuthStateChange((event,session)=>{
    if(event==='INITIAL_SESSION'||closed||invalidated)return;
    if(INVALIDATING_EVENTS.has(event)||(actor!==null&&event==='SIGNED_IN')||(actor!==null&&event==='USER_UPDATED')){
      invalidate('session_changed');return;
    }
    // Same user token refresh is safe; a subject switch is never safe.
    if(actor&&session?.user?.id&&session.user.id!==actor)invalidate('actor_changed');
    if(actor&&event==='SIGNED_IN'&&!session?.user?.id)invalidate('session_changed');
  });
  const subscription=response?.data?.subscription;
  if(!subscription||typeof subscription.unsubscribe!=='function'){
    invalidate('subscription_missing');
    throw new Error('signed_session_change_subscription_required');
  }
  async function checkActor(){
    ensureActive();
    const token=epoch;
    let result;
    try{result=await auth.getUser();}catch{invalidate('session_unavailable');throw new Error('gov002_session_invalidated');}
    if(token!==epoch){throw new Error('gov002_session_invalidated');}
    const uid=result?.data?.user?.id;
    if(result?.error||typeof uid!=='string'||!uid){
      invalidate('session_unavailable');throw new Error('gov002_session_invalidated');
    }
    if(actor===null)actor=uid;
    else if(actor!==uid){invalidate('actor_changed');throw new Error('gov002_session_invalidated');}
    ensureActive();return token;
  }
  async function invoke(method,args){
    const token=await checkActor();
    // Underlying signed adapter reauthenticates and all SQL RPC/RLS decisions
    // are server-owned; never attempt to substitute an offline receipt.
    let result;
    try{result=await reviewClient[method](args);}
    catch(error){
      if(token!==epoch||invalidated||closed)throw new Error('gov002_session_invalidated');
      // Invalidate on authentication failures instead of keeping stale rows.
      if(error?.status===401||/auth_required|jwt.expired|session.missing/u.test(String(error?.message||''))){
        invalidate('session_unavailable');throw new Error('gov002_session_invalidated');
      }
      throw error;
    }
    await checkActor();
    if(token!==epoch||invalidated||closed)throw new Error('gov002_session_invalidated');
    return result;
  }
  const wrapper={};
  for(const method of METHODS)wrapper[method]=(args)=>invoke(method,args);
  return Object.freeze({
    ...wrapper,
    getState:()=>Object.freeze({invalidated,closed,reason,actorBound:actor!==null}),
    destroy:()=>{
      if(closed)return;
      closed=true;epoch++;
      subscription.unsubscribe();
    }
  });
}