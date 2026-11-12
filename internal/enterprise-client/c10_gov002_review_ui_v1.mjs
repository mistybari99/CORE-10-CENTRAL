/**
 * CORE 10 CENTRAL — GOV-002 Approval Management (additive Draft component).
 * Mount only in an explicitly authorized new workspace; NEVER replace Islamiya
 * ERP or mount automatically into the protected legacy owner dashboard.
 *
 * The provided reviewClient must be the existing createGov002ReviewClient
 * authenticated Supabase adapter. Every call rechecks auth.getUser, then the
 * backend enforces RLS and maker-checker. No local role or authority claims.
 * This UI DOES NOT execute inventory, payments, finance or real stock posting.
 */
import {
  APPROVAL_TABS, validBusinessId, safeText, verifiedBusinessRows,
  approvalState, approvalStageText, filteredApprovals, summaryCounts,
  canOfferApprovalAction, canOfferExceptionAction, readableError
} from './c10_gov002_review_ui_model_v1.mjs';

const STATE_NAMES = Object.freeze({
  pending: 'অপেক্ষমাণ', approved: 'অনুমোদিত', rejected: 'বাতিল',
  deferred: 'স্থগিত', withdrawn: 'প্রত্যাহার', expired: 'মেয়াদোত্তীর্ণ',
  all: 'সব'
});
const DETAILS = [
  ['request_id','Request ID'],['domain','ডোমেইন (Domain)'],
  ['action_code','কাজের ধরন (Action)'],['source_key','উৎস (Source reference)'],
  ['source_version','Source version'],['policy_version','Policy version'],['source_fingerprint','Source fingerprint'],['requested_by','আবেদনকারী'],
  ['requested_at','আবেদনের সময়'],['expires_at','মেয়াদ'],
  ['required_checks','যাচাই প্রয়োজন'],['completed_checks','সম্পন্ন ধাপ'],
  ['stored_status','Server status'],['movement_id','Synthetic movement ID'],
  ['original_movement_id','Synthetic original movement']
];

function el(tag, className = '', text = null) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== null) node.textContent = safeText(text, 1500);
  return node;
}
function button(label, klass, handler, disabled = false) {
  const b = el('button', klass, label);b.type = 'button';b.disabled=disabled;
  b.addEventListener('click', handler);return b;
}
function add(parent, ...children) {
  for (const child of children) if(child != null) parent.append(child);
  return parent;
}
function formatDate(value) {
  const d = Date.parse(value || '');
  return Number.isFinite(d) ? new Intl.DateTimeFormat('bn-BD', {
    year:'numeric', month:'short', day:'numeric', hour:'2-digit', minute:'2-digit', timeZone:'Asia/Dhaka'
  }).format(new Date(d)) : '—';
}
function makeIdempotencyKey() {
  if (!globalThis.crypto?.randomUUID) throw new Error('secure_random_required');
  return 'c10_' + globalThis.crypto.randomUUID().replaceAll('-', '');
}

/**
 * @param {object} options
 * @param {HTMLElement} options.root - Dedicated element; cannot be a live legacy app root.
 * @param {object} options.reviewClient - Signed review client from PR #83.
 * @param {number} options.businessId - One explicitly selected business; NOT an authorization claim.
 * @param {Array<{id:number,name:string}>} options.businesses - UI suggestions only.
 * @param {boolean} options.actionsEnabled - false for synthetic preview; true only after signed staging host gate.
 * @param {string} options.environmentLabel - Display-only environment identification.
 * @returns {{refresh:Function,destroy:Function,selectBusiness:Function,getState:Function}}
 */
export function mountGov002ApprovalUI({
  root, reviewClient, businessId, businesses = [], actionsEnabled = false,
  environmentLabel = 'DRAFT · সংযুক্ত পরিবেশ যাচাই বাকি'
} = {}) {
  if (!root || root.nodeType !== 1 || typeof root.replaceChildren !== 'function')
    throw new Error('dedicated_approval_root_required');
  if (!reviewClient || ['listStatus','listExceptions','listActivity',
      'decideApproval','withdrawApproval','requestException',
      'decideException','withdrawException','exportActivityCsv']
      .some(k => typeof reviewClient[k] !== 'function'))
    throw new Error('signed_review_client_required');
  if (!validBusinessId(businessId)) throw new Error('business_required');
  if (!Array.isArray(businesses) || businesses.length > 100 ||
      businesses.some(x => !validBusinessId(x?.id) || typeof x.name !== 'string'))
    throw new Error('invalid_business_picker');
  const allowedChoices = new Map(businesses.map(b => [b.id, safeText(b.name,100)]));
  if (!allowedChoices.has(businessId)) allowedChoices.set(businessId,`Business #${businessId}`);
  const state = {
    businessId, tab:'pending', section:'approvals', query:'', selected:null,
    approvals:[], exceptions:[], activity:[], loading:false, busy:false,
    dialog:null, notice:'', error:'', sequence:0, destroyed:false
  };
  root.classList.add('c10a');
  root.setAttribute('data-c10-gov002', 'draft');
  root.setAttribute('aria-label', 'CORE 10 Approval Management');

  function setNotice(notice='',error='') {state.notice=notice;state.error=error;draw();}
  function selectBusiness(next) {
    if (state.busy) return;
    if (!validBusinessId(next) || !allowedChoices.has(next)) throw new Error('invalid_business_selection');
    if (next === state.businessId) return;
    state.businessId=next;state.selected=null;state.dialog=null;state.query='';
    state.approvals=[];state.exceptions=[];state.activity=[];state.notice='';
    state.error='';void refresh();
  }
  async function refresh() {
    if (state.destroyed || state.busy) return;
    const token=++state.sequence, business=state.businessId;
    state.loading=true;state.error='';state.notice='';
    state.approvals=[];state.exceptions=[];state.activity=[];draw();
    try {
      // All three projections are server-scoped. A failed or mixed result
      // fails the whole screen closed: no partial cross-business display.
      const [status, exceptions, activity] = await Promise.all([
        reviewClient.listStatus({businessId:business,limit:250}),
        reviewClient.listExceptions({businessId:business,limit:250}),
        reviewClient.listActivity({businessId:business,limit:500})
      ]);
      if (token!==state.sequence || state.destroyed || state.businessId!==business)return;
      const a=verifiedBusinessRows(status,business,'status');
      const e=verifiedBusinessRows(exceptions,business,'exceptions');
      const h=verifiedBusinessRows(activity,business,'activity');
      state.approvals=a;state.exceptions=e;state.activity=h;
      if (!a.some(x=>String(x.request_id)===String(state.selected)))state.selected=null;
    } catch (err) {
      if (token!==state.sequence || state.destroyed)return;
      state.approvals=[];state.exceptions=[];state.activity=[];state.selected=null;
      state.error=readableError(err);
    } finally {
      if (token===state.sequence && !state.destroyed) {state.loading=false;draw();}
    }
  }
  function openDialog(kind, target, action) {
    if (!actionsEnabled || state.busy || state.loading) return;
    if (kind==='approval' && !canOfferApprovalAction(target,action))return;
    if (kind==='exception' && !canOfferExceptionAction(target,action))return;
    state.dialog={kind,target,action,key:null,reason:'',severity:'normal',minutes:30};draw();
  }
  async function confirmDialog() {
    const d=state.dialog;
    if (!d || state.busy || !actionsEnabled) return;
    // Re-check stale UI before invoking canonical RPC. Server rechecks again.
    if (d.kind==='approval' && !canOfferApprovalAction(d.target,d.action))return;
    if (d.kind==='exception' && !canOfferExceptionAction(d.target,d.action))return;
    if (d.action==='request_exception' && (d.reason.trim().length<12 || d.reason.trim().length>400)) {
      state.error='Escalation reason ১২–৪০০ অক্ষরের হতে হবে।';draw();return;
    }
    state.busy=true;state.error='';d.key ??= makeIdempotencyKey();draw();
    try {
      let receipt;
      if (d.kind==='approval' && ['approve','reject','defer'].includes(d.action))
        receipt=await reviewClient.decideApproval({requestId:d.target.request_id,action:d.action,idempotencyKey:d.key});
      else if(d.kind==='approval' && d.action==='withdraw')
        receipt=await reviewClient.withdrawApproval({requestId:d.target.request_id,idempotencyKey:d.key});
      else if(d.kind==='approval' && d.action==='request_exception')
        receipt=await reviewClient.requestException({requestId:d.target.request_id,
          reason:d.reason.trim(),severity:d.severity,ttlMinutes:d.minutes,idempotencyKey:d.key});
      else if(d.kind==='exception' && d.action==='withdrawn')
        receipt=await reviewClient.withdrawException({escalationId:d.target.escalation_id,idempotencyKey:d.key});
      else if(d.kind==='exception')
        receipt=await reviewClient.decideException({escalationId:d.target.escalation_id,
          action:d.action,idempotencyKey:d.key});
      else throw new Error('unknown_action');
      if (receipt == null) throw new Error('approval_rpc_missing_receipt');
      state.dialog=null;state.notice='সার্ভার receipt পেয়েছে। বর্তমান অবস্থা আবার যাচাই হচ্ছে।';
      state.busy=false;
      await refresh();
      // Activity view is a server read: a receipt is not proof of posting.
      if (!state.error) state.notice='সিদ্ধান্তের receipt পাওয়া গেছে; উৎসের কাজ/stock/payment স্বয়ংক্রিয়ভাবে সম্পন্ন হয়েছে এমন দাবি নয়।';
    } catch (err) {
      state.error=readableError(err); // Preserve key for safe explicit retry.
    } finally {state.busy=false;draw();}
  }
  async function exportCsv() {
    if (!actionsEnabled || state.busy || state.loading) return;
    const token=state.sequence, business=state.businessId;
    state.busy=true;draw();
    try {
      const csv=await reviewClient.exportActivityCsv({businessId:business,limit:1000});
      if (token!==state.sequence || business!==state.businessId || state.destroyed)return;
      if(typeof csv!=='string' || !csv.startsWith('\uFEFF'))throw new Error('invalid_export');
      const blob=new Blob([csv],{type:'text/csv;charset=utf-8'});
      const url=URL.createObjectURL(blob);
      try {
        const a=el('a');a.href=url;a.download=`c10-approvals-business-${business}.csv`;
        a.click();
      } finally {URL.revokeObjectURL(url);}
      state.notice='শুধু এই ব্যবসার server-scoped Activity CSV export। সম্পূর্ণ audit archive নয়।';
    }catch(err){state.error=readableError(err);}
    finally {state.busy=false;draw();}
  }
  function top() {
    const header=el('header','c10a-top');
    const mast=el('div','c10a-mast');
    add(mast,el('span','c10a-mark','C10'),el('span','c10a-wordmark','CORE 10 CENTRAL'),el('span','c10a-module','/ Approval Management'));
    const env=el('span','c10a-env',environmentLabel);
    add(header,mast,env);
    const intro=el('section','c10a-intro');
    const left=add(el('div'),el('div','c10a-eyebrow','GOV-002  /  Approval & Segregation of Duties'),el('h1','', 'অনুমোদন ব্যবস্থাপনা'),
      el('p','c10a-lead','আবেদন, সিদ্ধান্ত, Escalation ও audit activity—নির্দিষ্ট ব্যবসার সীমার মধ্যে।'));
    const filters=el('div','c10a-business-select');
    const label=el('label','', 'ব্যবসা (Business)');label.htmlFor='c10a-business-id';
    const select=el('select');select.id='c10a-business-id';select.setAttribute('aria-label','ব্যবসা নির্বাচন');
    for(const [id,name] of allowedChoices){const o=el('option','',name);o.value=String(id);o.selected=id===state.businessId;select.append(o);}
    select.disabled=state.busy;
    select.addEventListener('change',()=>selectBusiness(Number(select.value)));
    add(filters,label,select);
    add(intro,left,filters);
    return [header,intro];
  }
  function summary() {
    const counts=summaryCounts(state.approvals);
    const bar=el('div','c10a-summary');
    for(const key of ['pending','approved','rejected','expired']){
      const card=el('div','c10a-metric');
      add(card,el('span','',STATE_NAMES[key]),el('strong','',String(counts[key] || 0)));
      bar.append(card);
    }
    return bar;
  }
  function toolbar() {
    const bar=el('div','c10a-toolbar');
    const switcher=el('nav','c10a-switcher');switcher.setAttribute('aria-label','Approval sections');
    for (const [k,label] of [['approvals','Approval Inbox'],['exceptions','Escalations'],['activity','Activity']]) {
      const b=button(label,'c10a-pill'+(state.section===k?' is-active':''),()=>{
        state.section=k;state.dialog=null;state.error='';draw();
      });b.setAttribute('aria-current',state.section===k?'page':'false');switcher.append(b);
    }
    const right=el('div','c10a-tools');
    add(right,button('↻ Refresh','c10a-btn c10a-ghost',()=>void refresh(),state.loading||state.busy),
      button('↓ Activity CSV','c10a-btn c10a-ghost',()=>void exportCsv(),!actionsEnabled||state.loading||state.busy));
    add(bar,switcher,right);
    return bar;
  }
  function approvalList() {
    const panel=el('section','c10a-panel c10a-list');
    const tabs=el('div','c10a-tabs');tabs.setAttribute('role','tablist');
    for(const [tab,label] of APPROVAL_TABS) {
      const b=button(label,'c10a-tab'+(state.tab===tab?' is-active':''),()=>{state.tab=tab;draw();});
      b.setAttribute('role','tab');b.setAttribute('aria-selected',String(state.tab===tab));
      tabs.append(b);
    }
    const search=el('input','c10a-search');search.type='search';search.placeholder='Request ID / Source / Action খুঁজুন';
    search.setAttribute('aria-label','অনুরোধ খুঁজুন');search.value=state.query;
    search.addEventListener('input',()=>{
      const cursor=search.selectionStart;
      state.query=search.value;draw();
      const next=root.querySelector('.c10a-search');if(next){next.focus();try{next.setSelectionRange(cursor,cursor);}catch{}}
    });
    add(panel,tabs,search);
    const list=el('div','c10a-requests');
    const items=filteredApprovals(state.approvals,{tab:state.tab,search:state.query});
    if(!items.length)list.append(el('div','c10a-empty','এই ফিল্টারে কোনো অনুরোধ নেই।'));
    for(const row of items){
      const selected=String(state.selected)===String(row.request_id);
      const b=el('button','c10a-request'+(selected?' is-selected':''));b.type='button';
      b.setAttribute('aria-pressed',String(selected));
      const title=el('strong','',`${safeText(row.action_code,80)} · #${row.request_id}`);
      const sub=el('span','c10a-request-sub',`${safeText(row.domain,60)}  /  ${safeText(row.source_key,80)}`);
      const bottom=el('div','c10a-request-foot');
      add(bottom,el('span','c10a-state c10a-state-'+approvalState(row),approvalStageText(row)),
        el('time','',formatDate(row.requested_at)));
      add(b,title,sub,bottom);
      b.addEventListener('click',()=>{state.selected=row.request_id;draw();});list.append(b);
    }
    panel.append(list);
    const detail=el('section','c10a-panel c10a-detail');
    const selected=state.approvals.find(x=>String(x.request_id)===String(state.selected)) || items[0];
    if(!selected){detail.append(el('div','c10a-empty','অনুরোধ নির্বাচন করলে বিস্তারিত ও Timeline দেখা যাবে।'));return [panel,detail];}
    if(state.selected==null)state.selected=selected.request_id;
    add(detail,el('div','c10a-kicker','APPROVAL REQUEST'),el('h2','',`অনুরোধ #${selected.request_id}`),
      el('span','c10a-state c10a-state-'+approvalState(selected),approvalStageText(selected)));
    const dl=el('dl','c10a-detail-grid');
    for(const [key,label] of DETAILS){
      if(selected[key]==null)continue;
      add(dl,el('dt','',label),el('dd','',key.endsWith('_at')?formatDate(selected[key]):safeText(selected[key],250)));
    }
    detail.append(dl);
    const actions=el('div','c10a-actions');
    const actionList=[['approve','Approve'],['reject','Reject'],['defer','Defer'],
      ['withdraw','Withdraw'],['request_exception','Escalate']];
    for(const [key,label] of actionList){
      actions.append(button(label,'c10a-btn '+(key==='approve'?'c10a-primary':'c10a-ghost'),
        ()=>openDialog('approval',selected,key),!actionsEnabled||state.loading||state.busy||!canOfferApprovalAction(selected,key)));
    }
    detail.append(actions);
    if(!actionsEnabled)detail.append(el('p','c10a-note','Synthetic preview: কোনো বাস্তব Approval action চালু নেই।'));
    const history=el('section','c10a-history');
    add(history,el('h3','', 'Approval history · Timeline'));
    const entries=state.activity.filter(x=>String(x.request_id)===String(selected.request_id));
    if(!entries.length)history.append(el('p','c10a-muted','এই অনুরোধের কোনো visible activity নেই।'));
    for(const e of entries){
      const entry=el('div','c10a-activity-row');
      add(entry,el('span','c10a-dot'),add(el('div'),
        el('strong','',`${safeText(e.activity_type,45)} · ${safeText(e.action,60)}`),
        el('div','c10a-muted',`${formatDate(e.occurred_at)} · ${safeText(e.event_actor,60)}`)));
      history.append(entry);
    }
    detail.append(history);
    return [panel,detail];
  }
  function exceptionPanel() {
    const panel=el('section','c10a-panel c10a-wide');
    add(panel,el('h2','', 'Exception & Escalation Inbox'),
      el('p','c10a-muted','Acknowledged মানে approval, waiver বা stock posting নয়।'));
    if(!state.exceptions.length)panel.append(el('div','c10a-empty','এ ব্যবসায় কোনো escalation নেই।'));
    for(const e of state.exceptions){
      const card=el('article','c10a-exception');
      add(card,el('strong','',`Escalation #${e.escalation_id} · Request #${e.request_id}`),
        el('span','c10a-state',safeText(e.display_status,40)),
        el('p','',safeText(e.reason,400)),
        el('div','c10a-muted',`${safeText(e.severity,30)} · ${formatDate(e.created_at)} → ${formatDate(e.expires_at)}`));
      const acts=el('div','c10a-actions');
      for(const [act,label] of [['acknowledged','Acknowledge'],['declined','Decline'],['withdrawn','Withdraw']])
        acts.append(button(label,'c10a-btn c10a-ghost',()=>openDialog('exception',e,act),
          !actionsEnabled||state.loading||state.busy||!canOfferExceptionAction(e,act)));
      card.append(acts);panel.append(card);
    }
    return panel;
  }
  function activityPanel() {
    const panel=el('section','c10a-panel c10a-wide');
    add(panel,el('h2','', 'Business-scoped Activity'),el('p','c10a-muted','Server-filtered event projection; সম্পূর্ণ Audit Engine নয়।'));
    if(!state.activity.length)panel.append(el('div','c10a-empty','Visible activity নেই।'));
    for(const e of state.activity){
      const entry=el('div','c10a-activity-row');
      add(entry,el('span','c10a-dot'),add(el('div'),
        el('strong','',`${safeText(e.action,80)} · Request #${e.request_id}`),
        el('div','c10a-muted',`${safeText(e.activity_type,50)} · ${formatDate(e.occurred_at)} · ${safeText(e.source_key,80)}`)));
      panel.append(entry);
    }
    return panel;
  }
  function modal() {
    const d=state.dialog;
    if(!d)return null;
    const overlay=el('div','c10a-overlay');
    const dialog=el('section','c10a-modal');dialog.setAttribute('role','dialog');
    dialog.setAttribute('aria-modal','true');dialog.setAttribute('aria-label','Approval confirmation');
    add(dialog,el('div','c10a-kicker','SERVER-VERIFIED ACTION'),
      el('h2','', 'সিদ্ধান্ত নিশ্চিত করুন'),
      el('p','',`${safeText(d.action,40)} · ${d.kind==='approval'?'Request #'+d.target.request_id:'Escalation #'+d.target.escalation_id}`),
      el('p','c10a-muted','আপনার বর্তমান অনুমতি, Maker–Checker এবং source-state সার্ভার নতুন করে যাচাই করবে।'));
    if(d.action==='request_exception'){
      const label=el('label','', 'কারণ লিখুন (১২–৪০০ অক্ষর)');
      const area=el('textarea','c10a-reason');area.maxLength=400;area.rows=4;area.value=d.reason;
      area.addEventListener('input',()=>{d.reason=area.value;});
      label.append(area);dialog.append(label);
      const select=el('select');select.setAttribute('aria-label','Severity');
      for(const v of ['normal','urgent']){const o=el('option','',v);o.value=v;select.append(o);}
      select.value=d.severity;select.addEventListener('change',()=>{d.severity=select.value;});
      const mins=el('input');mins.type='number';mins.min='5';mins.max='1440';mins.value=String(d.minutes);
      mins.setAttribute('aria-label','TTL minutes');mins.addEventListener('change',()=>{d.minutes=Number(mins.value);});
      const fields=el('div','c10a-field-row');add(fields,add(el('label','', 'Severity'),select),add(el('label','', 'TTL (minutes)'),mins));dialog.append(fields);
    }
    const footer=el('div','c10a-modal-footer');
    add(footer,button('Cancel','c10a-btn c10a-ghost',()=>{state.dialog=null;draw();},state.busy),
      button(state.busy?'সার্ভারে যাচাই চলছে…':'Confirm · Server RPC','c10a-btn c10a-primary',()=>void confirmDialog(),state.busy));
    dialog.append(footer);overlay.append(dialog);
    return overlay;
  }
  function draw() {
    if(state.destroyed)return;
    const shell=el('div','c10a-shell');
    add(shell,...top());
    const content=el('main','c10a-main');
    add(content,summary(),el('p','c10a-boundary',
      'DRAFT / Synthetic source contracts · No live posting · Backend permission is authoritative'));
    if(state.error) add(content,el('div','c10a-alert c10a-alert-error',state.error));
    if(state.notice) add(content,el('div','c10a-alert c10a-alert-info',state.notice));
    add(content,toolbar());
    if(state.loading) content.append(el('div','c10a-loading','সার্ভার থেকে স্কোপ যাচাই করে ডেটা আনা হচ্ছে…'));
    else if(!state.error || state.approvals.length || state.exceptions.length || state.activity.length){
      if(state.section==='approvals')add(content,add(el('div','c10a-columns'),...approvalList()));
      else content.append(state.section==='exceptions'?exceptionPanel():activityPanel());
    }
    add(content,el('footer','c10a-footer',
      'CORE 10 / GOV-002 — Separate draft interface. Original Islamia ERP is preserved (C10-D051 / R130).'));
    shell.append(content);
    root.replaceChildren(shell);
    const m=modal();if(m)root.append(m);
  }
  draw();void refresh();
  return Object.freeze({
    refresh,selectBusiness,
    getState:()=>Object.freeze({businessId:state.businessId,tab:state.tab,
      section:state.section,loading:state.loading,busy:state.busy,
      rowCount:state.approvals.length,exceptionCount:state.exceptions.length,
      activityCount:state.activity.length,error:state.error}),
    destroy:()=>{state.destroyed=true;state.sequence++;state.dialog=null;root.replaceChildren();root.classList.remove('c10a');}
  });
}