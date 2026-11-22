/**
 * Standalone CORE10 GOV-002 reviewer workspace. Dedicated root only.
 * UI state is never an authorization decision: server RPCs remain final.
 * No changes to protected Islamia ERP view, routes or data.
 */
import {createCanonicalGov002ReviewClient} from './c10_np01_canonical_review_client_v1.mjs';
const TABS=[
 ['tasks','আমার পর্যালোচনা','My Review Tasks'],
 ['status','অনুমোদনের অবস্থা','Approval Status'],
 ['activity','অডিট কার্যক্রম','Audit Activity']
];
const EVENTS=new Set(['SIGNED_OUT','USER_DELETED','PASSWORD_RECOVERY','MFA_CHALLENGE_VERIFIED']);
const ACTIONS=[['approve','অনুমোদন','Approve'],['reject','প্রত্যাখ্যান','Reject'],['defer','স্থগিত','Defer']];
const clean=(x,max=130)=>String(x??'—').replace(/[\u0000-\u001f\u007f]/gu,' ').slice(0,max);
const date=(x,language)=>{
 const d=new Date(x);return Number.isFinite(+d)
  ?d.toLocaleString(language,{dateStyle:'medium',timeStyle:'short'}):'—';
};
const errorLabel=(e,t)=>{
 const message=String(e?.message||'').toLowerCase();
 if(message.includes('session')||message.includes('auth'))return t('সেশন শেষ। আবার লগইন করুন।','Your session ended. Sign in again.');
 if(message.includes('denied')||message.includes('permission'))return t('বর্তমান ব্যবহারকারীর অনুমতি নেই।','You do not have permission.');
 if(message.includes('stale')||message.includes('conflict')||message.includes('transition'))return t('Request বদলেছে। Refresh করুন।','The request changed. Refresh and try again.');
 return t('Server request সম্পন্ন হয়নি। আবার চেষ্টা করুন।','The server request failed. Try again.');
};
export function mountCanonicalGov002ReviewerWorkspace({
 root,supabaseClient,businessId,businessLabel='Business',
 allowMutations=false,environmentLabel='SYNTHETIC · NOT LIVE',lang='en',embedded=false
}={}){
 if(!root?.ownerDocument||typeof root.replaceChildren!=='function')throw Error('dedicated_review_root_required');
 if(!Number.isSafeInteger(businessId)||businessId<1)throw Error('invalid_business_id');
 const doc=root.ownerDocument;
 const t=(bn,en)=>lang==='bn'?bn:en;
 const formatDate=x=>date(x,t('bn-BD','en-GB'));
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
   loading:false,busy:false,confirm:null,error:t('সেশন পরিবর্তন হয়েছে। আবার লগইন করুন।','Your session changed. Sign in again.')};
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
  if(!uuid){state.error=t('নিরাপদ request key পাওয়া যায়নি।','No secure request key was available.');draw();return;}
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
   state.note=t('সিদ্ধান্ত রেকর্ড হয়েছে। অবস্থা হালনাগাদ হচ্ছে।','Decision recorded. Refreshing status.');
   await refresh();
  }catch(e){
   if(state.closed)return;state.busy=false;
   if(!api.getState().connected){invalidated();return;}
   state.error=errorLabel(e,t);draw();
  }
 }
 function card(r,kind){
  const box=el('article','','c10np-card');
  const head=el('div','','c10np-card-head');
  const label=kind==='activity'?clean(r.action,35):clean(r.action_code,45);
  const id=r.request_id;
  add(head,el('h3',label+' · #'+clean(id,24)),el('span',
   kind==='tasks'?t('ধাপ ','Stage ')+r.stage_no+'/'+r.stage_total:
   kind==='status'?r.display_status:'Audit #'+r.audit_event_id,'c10np-bubble'));
  box.append(head);
  const details=el('div','','c10np-meta-grid');
  if(kind==='tasks')add(details,line(t('উৎস','Source'),r.source_key),line(t('উৎস সংস্করণ','Source version'),r.source_version),
   line(t('নীতি','Policy'),r.policy_version),line(t('মেয়াদ','Expires'),formatDate(r.expires_at)));
  if(kind==='status')add(details,line(t('উৎস','Source'),r.source_key),
   line(t('ধাপ সম্পন্ন','Checks'),String(r.completed_checks)+'/'+String(r.required_checks)),
   line(t('মেয়াদ','Expires'),formatDate(r.expires_at)));
  if(kind==='activity')add(details,line(t('ইভেন্ট ID','Event ID'),r.event_id),
   line(t('ধাপ','Stage'),r.stage_no??'—'),line(t('সময়','Time'),formatDate(r.occurred_at)));
  box.append(details);
  if(kind==='tasks'&&allowMutations===true){
   const actions=el('div','','c10np-actions');
   for(const [action,bn,en] of ACTIONS)actions.append(button(t(bn,en),
    ()=>openDecision(r.request_id,action),action==='reject'?'c10np-danger':''));
   box.append(actions);
  }
  if(kind==='status'&&allowMutations===true&&r.is_maker&&r.stored_status==='pending'
    &&r.completed_checks===0){
   const actions=el('div','','c10np-actions');
   actions.append(button(t('অনুরোধ প্রত্যাহার','Withdraw'),()=>openDecision(r.request_id,'withdraw'),'c10np-danger'));
   box.append(actions);
  }
  return box;
 }
 function announcement(message,role,cls){
  const status=el('p',message,cls);
  status.setAttribute('role',role);
  return status;
 }
 function draw(){
  if(state.closed)return;
  root.classList.add('c10np');
  root.classList.toggle('c10np-embedded',embedded);
  const shell=el('div','','c10np-shell');
  const top=el('header','','c10np-top');
  add(top,el('div','C10  /  CORE 10 CENTRAL','c10np-brand'),
   el('div',environmentLabel,'c10np-env'));
  if(!embedded)shell.append(top);
  const main=el(embedded?'section':'main','','c10np-main');
  const intro=el('div','','c10np-intro');
  const heading=el('div');
  add(heading,el('div','GOV-002  •  APPROVAL + AUDIT','c10np-eyebrow'),
   el(embedded?'h2':'h1',t('অনুমোদন ডেস্ক','Approval Desk')),
   el('p',clean(businessLabel,65)+t(' · ব্যবসা #',' · Business #')+businessId,'c10np-sub'));
  add(intro,heading,button(t('হালনাগাদ','Refresh'),()=>void refresh(),'c10np-outline'));main.append(intro);
  const tabs=el('nav','','c10np-tabs');
  tabs.setAttribute('aria-label',t('পর্যালোচনা বিভাগ','Reviewer sections'));
  for(const [id,bn,en] of TABS){
   const b=button(t(bn,en),()=>{state.tab=id;state.confirm=null;state.error='';draw();},
    state.tab===id?'c10np-active':'');
   b.setAttribute('aria-current',state.tab===id?'page':'false');tabs.append(b);
  }
  main.append(tabs);
  if(state.note)main.append(announcement(state.note,'status','c10np-alert c10np-good'));
  if(state.error)main.append(announcement(state.error,'alert','c10np-alert c10np-error'));
  if(state.loading)main.append(el('p',t('সার্ভার যাচাই করছে…','Checking with the server…'),'c10np-empty'));
  else if(state.dead)main.append(el('p',t('সেশন শেষ। আগের তথ্য মুছে দেওয়া হয়েছে।','Session invalidated. Previous records cleared.'),'c10np-empty'));
  else{
   const list=state.tab==='tasks'?state.tasks:state.tab==='status'?state.status:state.activity;
   const section=el('section','','c10np-section');
   const sub=el('div','','c10np-section-heading');
   add(sub,el('h2',state.tab==='tasks'?t('বর্তমান পর্যালোচনা','Current Review Tasks'):
    state.tab==='status'?t('এই ব্যবসার অবস্থা','Business Status'):t('ক্যাননিকাল অডিট কার্যক্রম','Canonical Audit Activity')),
    el('span',String(list.length)+t('টি রেকর্ড',' records'),'c10np-muted'));section.append(sub);
   if(state.tab==='tasks'&&state.permission)section.append(el('p',state.permission,'c10np-muted'));
   const grid=el('div','','c10np-grid');
   if(!list.length)grid.append(el('p',t('এই অংশে দেখানোর মতো অনুমোদিত তথ্য নেই।','No records available to you here.'),'c10np-empty'));
   else for(const item of list)grid.append(card(item,state.tab));
   section.append(grid);main.append(section);
  }
  if(!embedded)main.append(el('footer',t('অনুমতি, ধাপ ও সিদ্ধান্ত সার্ভার যাচাই করে।','The server validates each permission, stage and decision.'),'c10np-footer'));
  shell.append(main);
  let modal;
  if(state.confirm&&!state.dead){
   modal=el('dialog','','c10np-dialog');
   modal.setAttribute('aria-label',t('সিদ্ধান্ত নিশ্চিত করুন','Confirm reviewer decision'));
   const decision=ACTIONS.find(([action])=>action===state.confirm.action);
   add(modal,el('h2',t('সিদ্ধান্ত নিশ্চিত করুন','Confirm decision')),
    el('p',t('অনুরোধ #','Request #')+clean(state.confirm.id,24)+' · '+
     (decision?t(decision[1],decision[2]):t('প্রত্যাহার','Withdraw'))));
   const cancel=()=>{
    if(state.busy)return;
    state.confirm=null;
    draw();
    root.querySelector('[aria-current="page"]')?.focus();
   };
   modal.addEventListener('cancel',event=>{event.preventDefault();cancel();});
   const actions=el('div','','c10np-actions');
   const back=button(t('ফিরে যান','Cancel'),cancel,'c10np-outline');
   const confirm=button(state.busy?t('যাচাই হচ্ছে…','Checking…'):t('সিদ্ধান্ত নিশ্চিত করুন','Confirm decision'),
    ()=>void sendDecision(),'c10np-active');
   back.disabled=confirm.disabled=state.busy;
   back.autofocus=true;
   add(actions,back,confirm);
   modal.append(actions);
   shell.append(modal);
  }
  root.replaceChildren(shell);
  modal?.showModal();
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
  state.permission=out[0].status==='rejected'?t('পর্যালোচনার অনুমতি বা বর্তমান ধাপের কাজ নেই।','No review tasks are available to you.'):'';
  state.status=out[1].status==='fulfilled'?out[1].value:[];
  state.activity=out[2].status==='fulfilled'?out[2].value:[];
  if(out[1].status==='rejected')state.error=errorLabel(out[1].reason,t);
  else if(out[2].status==='rejected')state.error=errorLabel(out[2].reason,t);
  state.loading=false;draw();
 }
 function destroy(){
  if(state.closed)return;
  state.closed=true;state.epoch++;listener.unsubscribe();api.destroy();
  root.replaceChildren();root.classList.remove('c10np','c10np-embedded');
 }
 draw();void refresh();
 return Object.freeze({
  refresh,destroy,
  requestLeave:leave=>{if(!state.busy)leave();},
  setLanguage:language=>{lang=language;draw();},
  selectTab:id=>{if(!TABS.some(x=>x[0]===id))throw Error('invalid_tab');if(!state.dead&&!state.closed){state.tab=id;draw();}},
  getState:()=>Object.freeze({tab:state.tab,dead:state.dead,loading:state.loading,
   tasks:state.tasks.length,status:state.status.length,activity:state.activity.length,
   mutationsEnabled:allowMutations===true})
 });
}
