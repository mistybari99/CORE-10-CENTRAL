/**
 * Standalone CORE10 GOV-002 reviewer workspace. Dedicated root only.
 * UI state is never an authorization decision: server RPCs remain final.
 * No changes to protected Islamia ERP view, routes or data.
 */
import {createCanonicalGov002ReviewClient} from './c10_np01_canonical_review_client_v1.mjs';
const TABS=[['tasks','আমার যাচাই'],['status','Approval Status'],['activity','Audit Activity']];
const EVENTS=new Set(['SIGNED_OUT','USER_DELETED','PASSWORD_RECOVERY','MFA_CHALLENGE_VERIFIED']);
const ACTIONS=[['approve','Approve'],['reject','Reject'],['defer','Defer']];
const clean=(x,max=130)=>String(x??'—').replace(/[\u0000-\u001f\u007f]/gu,' ').slice(0,max);
const date=x=>{
 const d=new Date(x);return Number.isFinite(+d)
  ?d.toLocaleString('bn-BD',{dateStyle:'medium',timeStyle:'short'}):'—';
};
const errorLabel=e=>{
 const t=String(e?.message||'').toLowerCase();
 if(t.includes('session')||t.includes('auth'))return 'সেশন শেষ। আবার লগইন করুন।';
 if(t.includes('denied')||t.includes('permission'))return 'বর্তমান ব্যবহারকারীর অনুমতি নেই।';
 if(t.includes('stale')||t.includes('conflict')||t.includes('transition'))return 'Request বদলেছে। Refresh করুন।';
 return 'Server request সম্পন্ন হয়নি। আবার চেষ্টা করুন।';
};
export function mountCanonicalGov002ReviewerWorkspace({
 root,supabaseClient,businessId,businessLabel='Business',
 allowMutations=false,environmentLabel='SYNTHETIC · NOT LIVE'
}={}){
 if(!root?.ownerDocument||typeof root.replaceChildren!=='function')throw Error('dedicated_review_root_required');
 if(!Number.isSafeInteger(businessId)||businessId<1)throw Error('invalid_business_id');
 const doc=root.ownerDocument;
 const api=createCanonicalGov002ReviewClient(supabaseClient,{allowMutations});
 let state={tab:'tasks',tasks:[],status:[],activity:[],loading:true,
  error:'',note:'',permission:'',confirm:null,busy:false,dead:false,closed:false,epoch:0};
 const el=(tag,text='',cls='')=>{
  const x=doc.createElement(tag);if(cls)x.className=cls;x.textContent=clean(text,500);return x;
 };
 const button=(text,click,cls='')=>{
  const b=el('button',text,'c10np-btn '+cls);b.type='button';b.addEventListener('click',click);return b;
 };
 const add=(parent,...children)=>{for(const c of children)parent.append(c);return parent;};
 function invalidated(){
  if(state.closed)return;
  state={...state,dead:true,epoch:state.epoch+1,tasks:[],status:[],activity:[],
   loading:false,busy:false,confirm:null,error:'সেশন পরিবর্তন হয়েছে। আবার লগইন করুন।'};
  draw();
 }
 const listener=supabaseClient.auth.onAuthStateChange(event=>{
  if(EVENTS.has(event)||(event==='SIGNED_IN'&&api.getState().actorBound)
    ||(event==='USER_UPDATED'&&api.getState().actorBound))invalidated();
 })?.data?.subscription;
 if(!listener?.unsubscribe){api.destroy();throw Error('auth_change_subscription_required');}
 function line(k,v){
  const x=el('div','','c10np-meta');add(x,el('span',k),el('strong',v));return x;
 }
 function openDecision(id,action){
  if(state.busy||state.dead||allowMutations!==true)return;
  const uuid=globalThis.crypto?.randomUUID?.();
  if(!uuid){state.error='নিরাপদ request key পাওয়া যায়নি।';draw();return;}
  state.confirm={id,action,key:'c10np_'+uuid};
  draw();
 }
 async function sendDecision(){
  if(!state.confirm||state.busy||state.dead||state.closed||!allowMutations)return;
  const c=state.confirm;state.busy=true;state.error='';draw();
  try{
   if(c.action==='withdraw')await api.withdrawApproval({
    businessId,requestId:c.id,idempotencyKey:c.key});
   else await api.decideApproval({
    businessId,requestId:c.id,action:c.action,idempotencyKey:c.key});
   if(state.dead||state.closed)return;
   state.confirm=null;state.busy=false;
   state.note='Server receipt পাওয়া গেছে। বর্তমান status আবার যাচাই হচ্ছে।';
   await refresh();
  }catch(e){
   if(state.closed)return;state.busy=false;
   if(!api.getState().connected){invalidated();return;}
   state.error=errorLabel(e);draw();
  }
 }
 function card(r,kind){
  const box=el('article','','c10np-card');
  const head=el('div','','c10np-card-head');
  const label=kind==='activity'?clean(r.action,35):clean(r.action_code,45);
  const id=kind==='activity'?r.request_id:r.request_id;
  add(head,el('h3',label+' · #'+clean(id,24)),el('span',
   kind==='tasks'?'ধাপ '+r.stage_no+'/'+r.stage_total:
   kind==='status'?r.display_status:'Audit #'+r.audit_event_id,'c10np-bubble'));
  box.append(head);
  const details=el('div','','c10np-meta-grid');
  if(kind==='tasks')add(details,line('উৎস',r.source_key),line('Policy',r.policy_version),
   line('মেয়াদ',date(r.expires_at)));
  if(kind==='status')add(details,line('Source',r.source_key),
   line('Checks',String(r.completed_checks)+'/'+String(r.required_checks)),
   line('Expires',date(r.expires_at)));
  if(kind==='activity')add(details,line('Event ID',r.event_id),
   line('Stage',r.stage_no??'—'),line('Time',date(r.occurred_at)));
  box.append(details);
  if(kind==='tasks'&&allowMutations===true){
   const actions=el('div','','c10np-actions');
   for(const [action,text] of ACTIONS)actions.append(button(text,
    ()=>openDecision(r.request_id,action),action==='reject'?'c10np-danger':''));
   box.append(actions);
  }
  if(kind==='status'&&allowMutations===true&&r.is_maker&&r.stored_status==='pending'
    &&r.completed_checks===0){
   const actions=el('div','','c10np-actions');
   actions.append(button('Withdraw',()=>openDecision(r.request_id,'withdraw'),'c10np-danger'));
   box.append(actions);
  }
  return box;
 }
 function draw(){
  if(state.closed)return;
  root.classList.add('c10np');
  const shell=el('div','','c10np-shell');
  const top=el('header','','c10np-top');
  add(top,el('div','C10  /  CORE 10 CENTRAL','c10np-brand'),
   el('div',environmentLabel,'c10np-env'));shell.append(top);
  const main=el('main','','c10np-main');
  const intro=el('div','','c10np-intro');
  const heading=el('div');
  add(heading,el('div','GOV-002  •  APPROVAL + AUDIT','c10np-eyebrow'),
   el('h1','Approval Desk'),el('p',clean(businessLabel,65)+' · Business #'+businessId,'c10np-sub'));
  add(intro,heading,button('Refresh',()=>void refresh(),'c10np-outline'));main.append(intro);
  const tabs=el('nav','','c10np-tabs');
  tabs.setAttribute('aria-label','Reviewer sections');
  for(const [id,text] of TABS){
   const b=button(text,()=>{state.tab=id;state.confirm=null;state.error='';draw();},
    state.tab===id?'c10np-active':'');
   b.setAttribute('aria-current',state.tab===id?'page':'false');tabs.append(b);
  }
  main.append(tabs);
  if(state.note)main.append(el('p',state.note,'c10np-alert c10np-good'));
  if(state.error)main.append(el('p',state.error,'c10np-alert c10np-error'));
  if(state.loading)main.append(el('p','Server RPC যাচাই চলছে…','c10np-empty'));
  else if(state.dead)main.append(el('p','Session invalidated · পুরোনো তথ্য মুছে দেওয়া হয়েছে।','c10np-empty'));
  else{
   const list=state.tab==='tasks'?state.tasks:state.tab==='status'?state.status:state.activity;
   const section=el('section','','c10np-section');
   const sub=el('div','','c10np-section-heading');
   add(sub,el('h2',state.tab==='tasks'?'বর্তমান Reviewer Tasks':
    state.tab==='status'?'Scoped Status':'Canonical Audit Activity'),
    el('span',String(list.length)+' records','c10np-muted'));section.append(sub);
   if(state.tab==='tasks'&&state.permission)section.append(el('p',state.permission,'c10np-muted'));
   const grid=el('div','','c10np-grid');
   if(!list.length)grid.append(el('p','এই অংশে দেখানোর মতো অনুমোদিত তথ্য নেই।','c10np-empty'));
   else for(const item of list)grid.append(card(item,state.tab));
   section.append(grid);main.append(section);
  }
  main.append(el('footer','সকল role, stage, scope ও decision সার্ভার যাচাই করে। এই UI নিজে Stock বা Money POST করে না।','c10np-footer'));
  shell.append(main);
  if(state.confirm&&!state.dead){
   const overlay=el('div','','c10np-overlay');
   const modal=el('section','','c10np-dialog');
   modal.setAttribute('role','dialog');
   modal.setAttribute('aria-modal','true');
   modal.setAttribute('aria-label','Confirm reviewer decision');
   add(modal,el('h2','Confirm · Server RPC'),
    el('p','Request #'+clean(state.confirm.id,24)+' · '+state.confirm.action),
    el('p','Final permission server-side যাচাই হবে।','c10np-muted'));
   const actions=el('div','','c10np-actions');
   add(actions,button('Cancel',()=>{if(!state.busy){state.confirm=null;draw();}},'c10np-outline'),
    button(state.busy?'Checking…':'Confirm decision',()=>void sendDecision(),'c10np-active'));
   modal.append(actions);overlay.append(modal);shell.append(overlay);
  }
  root.replaceChildren(shell);
 }
 async function refresh(){
  if(state.closed||state.dead)return;
  const seq=++state.epoch;state.loading=true;state.error='';draw();
  const out=await Promise.allSettled([
   api.listReviewerTasks({businessId}),
   api.listStatus({businessId}),
   api.listActivity({businessId})
  ]);
  if(state.closed||state.dead||seq!==state.epoch)return;
  if(!api.getState().connected){invalidated();return;}
  state.tasks=out[0].status==='fulfilled'?out[0].value:[];
  state.permission=out[0].status==='rejected'?'Reviewer access নেই বা বর্তমান stage-এ task নেই।':'';
  state.status=out[1].status==='fulfilled'?out[1].value:[];
  state.activity=out[2].status==='fulfilled'?out[2].value:[];
  if(out[1].status==='rejected')state.error=errorLabel(out[1].reason);
  else if(out[2].status==='rejected')state.error=errorLabel(out[2].reason);
  state.loading=false;draw();
 }
 function destroy(){
  if(state.closed)return;
  state.closed=true;state.epoch++;listener.unsubscribe();api.destroy();
  root.replaceChildren();root.classList.remove('c10np');
 }
 draw();void refresh();
 return Object.freeze({
  refresh,destroy,
  selectTab:id=>{if(!TABS.some(x=>x[0]===id))throw Error('invalid_tab');if(!state.dead&&!state.closed){state.tab=id;draw();}},
  getState:()=>Object.freeze({tab:state.tab,dead:state.dead,loading:state.loading,
   tasks:state.tasks.length,status:state.status.length,activity:state.activity.length,
   mutationsEnabled:allowMutations===true})
 });
}
