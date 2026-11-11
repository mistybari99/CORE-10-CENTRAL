/* C10-A045 Owner Micro-Engine Workshop UI.
 * Real signed RPC only (core10-engine-workshop-client.js). Never fakes persistence: every success message
 * is rendered from a server receipt. Descriptors are DATA; the single executable handler is the
 * registered, advisory, non-mutating threshold_rule_v1. Placement/visibility never grants any operation.
 */
(function(){"use strict";
const W=window.CORE10_ENGINE_WORKSHOP_API,root=document.getElementById("ew-root");
const $=(id)=>document.getElementById(id);
const esc=(v)=>String(v==null?"":v).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const L={central_only:"Central only",business_only:"Business only",both:"Both",hidden_from_menus:"Hidden from menus",
 business_owner:"Business Owner may edit",request_approval:"Business Owner requests approval",
 lt:"<",lte:"≤",gt:">",gte:"≥",eq:"=",allow:"Allow",warn:"Warn",block:"Block (advisory)",approval_required:"Approval required (advisory)"};
const qs=new URLSearchParams(location.search),bizParam=qs.get("biz");
const S={api:null,businesses:[],tenantId:null,registry:null,selected:null,audit:[],pending:[],busy:false};
function rk(){const a=new Uint8Array(12);crypto.getRandomValues(a);return "ew_"+Array.from(a,x=>x.toString(16).padStart(2,"0")).join("")}
function status(msg,err){const n=$("ew-status");if(n){n.textContent=msg;n.dataset.tone=err?"error":"ok"}}
function fmtErr(e){return String((e&&(e.code&&e.code.length<60?e.code+": ":"")+(e.message||""))||"RPC_UNAVAILABLE")}
function opts(list,sel){return list.map(([v,t])=>'<option value="'+esc(v)+'"'+(String(v)===String(sel)?" selected":"")+'>'+esc(t)+'</option>').join("")}
async function run(label,fn){
 if(S.busy)return;S.busy=true;status(label+"…");
 try{const m=await fn();if(m)status(m)}catch(e){status("Denied or failed — "+fmtErr(e),true)}finally{S.busy=false}
}
function shell(){
 const biz=!!bizParam;
 root.innerHTML='<div class="ew-top"><div><div class="ew-kicker">OWNER GOVERNANCE · C10-A045 · D033/D045/R124</div>'+
 '<h1>'+(biz?"Business Engines":"Micro-Engine Workshop")+'</h1></div>'+
 '<nav class="ew-nav"><a href="./core10-control-studio.html">Control Studio</a><a href="./owner.html#/organization">Portfolio</a>'+
 (biz?'<a href="./core10-business-controls.html?biz='+encodeURIComponent(bizParam)+'">Business Controls</a>':'')+'</nav></div>'+
 '<div class="ew-safety" role="note"><strong>Advisory only, not operational authorization.</strong> Engines are declarative descriptors. '+
 'Only the registered <code>threshold_rule_v1</code> handler can be previewed; it never posts stock, finance, payments or sales, and a '+
 '“would block” result is advice, not a server permission. Placement is visibility only. Server RPC/RLS is the sole authority. '+
 'Disposable c10_demo build — not applied to production Supabase.</div>'+
 '<div id="ew-status" role="status" aria-live="polite">Connecting with verified session…</div>'+
 '<div id="ew-body"></div>';
}
/* ------------------------------ OWNER SURFACE ------------------------------ */
function ownerShell(){
 $("ew-body").innerHTML='<div class="ew-grid">'+
 '<section class="ew-panel"><h2>Engine registry <small id="ew-count"></small></h2>'+
 '<label>Tenant<select id="ew-tenant"></select></label>'+
 '<div class="ew-actions"><button id="ew-new" class="outline" type="button">+ New engine</button></div>'+
 '<div id="ew-list" class="ew-list" role="listbox" aria-label="Engines"></div></section>'+
 '<section class="ew-panel"><h2>Definition <small id="ew-ident"></small></h2><div class="ew-form two">'+
 '<label>Engine key (immutable id)<input id="ew-key" maxlength="60" autocomplete="off" placeholder="stock_low_threshold_advisory"><small class="err" id="ew-err-key"></small></label>'+
 '<label>Display name<input id="ew-name" maxlength="80" autocomplete="off" placeholder="Stock Low Threshold Advisory"><small class="err" id="ew-err-name"></small></label>'+
 '<label>Handler<select id="ew-handler"></select></label>'+
 '<label>Field<select id="ew-field">'+opts(W.FIELDS.map(x=>[x,x]),"on_hand")+'</select></label>'+
 '<label>Comparison<select id="ew-op">'+opts(W.OPS.map(x=>[x,L[x]]),"lt")+'</select></label>'+
 '<label>Threshold<input id="ew-threshold" type="number" step="any" value="12"><small class="err" id="ew-err-threshold"></small></label>'+
 '<label>Outcome when matched<select id="ew-outcome">'+opts(W.OUTCOMES.map(x=>[x,L[x]]),"warn")+'</select></label>'+
 '<label>Advisory message (optional)<input id="ew-message" maxlength="200" autocomplete="off"></label></div>'+
 '<label style="margin-top:12px">Reason for this change (required)<textarea id="ew-reason" rows="2" maxlength="500" placeholder="Why is this version being saved / published?"></textarea><small class="err" id="ew-err-reason"></small></label>'+
 '<div class="ew-actions"><button id="ew-save" class="primary" type="button">Save new immutable version</button>'+
 '<button id="ew-validate" class="outline" type="button">Mark latest version VALIDATED</button></div>'+
 '<div id="ew-nonexec" class="ew-muted" hidden>This handler type is DRAFT / NOT IMPLEMENTED (canExecute=false): descriptors are stored inert and can never be validated or published.</div>'+
 '<div id="ew-versions" class="ew-table" style="margin-top:12px"></div>'+
 '<h2 style="margin-top:16px">Preview <small>advisory · non-mutating · server evaluated</small></h2>'+
 '<div class="ew-form two"><label>Sample value for selected field<input id="ew-preview-input" type="number" step="any" value="8"></label>'+
 '<div class="ew-actions" style="align-self:end"><button id="ew-preview" class="outline" type="button">Preview rule</button></div></div>'+
 '<div id="ew-preview-result" class="ew-result" aria-live="polite">No preview yet.</div></section>'+
 '<section class="ew-panel ew-wide"><h2>Publish to businesses <small>independent per business</small></h2><div class="ew-form three">'+
 '<label>Business<select id="ew-pub-business"></select></label>'+
 '<label>Version<select id="ew-pub-version"></select></label>'+
 '<label>Lifecycle state<select id="ew-pub-state">'+opts(W.STATES.map(x=>[x,x]),"PUBLISHED")+'</select></label>'+
 '<label>Threshold override (blank = use descriptor)<input id="ew-pub-threshold" type="number" step="any"><small class="err" id="ew-err-pub"></small></label>'+
 '<label>Placement<select id="ew-pub-placement">'+opts(W.PLACEMENTS.map(x=>[x,L[x]]),"both")+'</select></label>'+
 '<label>Local edit authority<select id="ew-pub-edit">'+opts(W.MODES.map(x=>[x,L[x]]),"central_only")+'</select></label></div>'+
 '<div id="ew-diff" class="ew-diff" aria-label="Before and after">Select an engine and business to see the before → after diff.</div>'+
 '<div class="ew-actions"><button id="ew-pub-save" class="primary" type="button">Apply to this business only</button></div>'+
 '<h2 style="margin-top:16px">Assignments <small id="ew-assign-count"></small></h2><div id="ew-assignments" class="ew-table"></div></section>'+
 '<section class="ew-panel ew-wide"><h2>Pending business requests</h2><div id="ew-requests" class="ew-table"><p class="ew-muted">None.</p></div></section>'+
 '<section class="ew-panel ew-wide"><h2>Audit &amp; configuration rollback <small>rollback changes configuration only, never posted transactions</small></h2><div id="ew-audit" class="ew-table"><p class="ew-muted">Select an engine.</p></div></section></div>';
 $("ew-tenant").innerHTML=opts(tenants().map(t=>[t,"Tenant #"+t]),S.tenantId);
 $("ew-handler").innerHTML=opts(S.registry.handlers.map(h=>[h.handler_id,h.handler_id+(h.can_execute?" · executable (advisory)":" · DRAFT / not implemented")]),"threshold_rule_v1");
 wireOwner();
}
const tenants=()=>[...new Set(S.businesses.map(b=>b.tenant_id))];
const bizOfTenant=()=>S.businesses.filter(b=>b.tenant_id===S.tenantId);
const engine=()=>S.registry.engines.find(e=>e.engine_id===S.selected)||null;
const handlerOf=(id)=>S.registry.handlers.find(h=>h.handler_id===id)||{can_execute:false};
function descriptorFromForm(){
 const d={field:$("ew-field").value,op:$("ew-op").value,threshold:$("ew-threshold").value===""?NaN:Number($("ew-threshold").value),outcome:$("ew-outcome").value};
 const m=$("ew-message").value.trim();if(m)d.message=m;return d;
}
function formErrors(){
 const key=$("ew-key").value.trim(),name=$("ew-name").value.trim(),reason=$("ew-reason").value.trim();
 const e={key:"",name:"",threshold:"",reason:""};
 if(!/^[a-z][a-z0-9]*(_[a-z0-9]+)*$/.test(key)||key.length>60)e.key="Required: lowercase letters, digits, underscores (e.g. stock_low_threshold_advisory).";
 if(name.length<3)e.name="Required: at least 3 characters.";
 if($("ew-handler").value==="threshold_rule_v1"){const v=W.validateDescriptor(descriptorFromForm());if(!v.ok)e.threshold=v.errors.join("; ")}
 if(reason.length<5)e.reason="Required: at least 5 characters.";
 for(const k of Object.keys(e)){const n=$("ew-err-"+k);if(n)n.textContent=e[k]}
 return Object.values(e).some(Boolean);
}
function fillForm(e){
 const nonNew=!!e;
 $("ew-key").value=nonNew?e.engine_key:"";$("ew-key").disabled=nonNew;
 $("ew-name").value=nonNew?e.display_name:"";
 $("ew-handler").value=nonNew?e.handler_id:"threshold_rule_v1";$("ew-handler").disabled=nonNew;
 const v=nonNew?e.versions[e.versions.length-1]:null,d=v&&v.descriptor||{field:"on_hand",op:"lt",threshold:12,outcome:"warn"};
 if(W.FIELDS.includes(d.field))$("ew-field").value=d.field;if(W.OPS.includes(d.op))$("ew-op").value=d.op;
 $("ew-threshold").value=typeof d.threshold==="number"?d.threshold:"";
 if(W.OUTCOMES.includes(d.outcome))$("ew-outcome").value=d.outcome;$("ew-message").value=d.message||"";
 $("ew-ident").textContent=nonNew?"#"+e.engine_id+" · latest v"+e.current_version:"new engine · version 1 on save";
 const exec=handlerOf($("ew-handler").value).can_execute;
 $("ew-nonexec").hidden=exec;
 for(const id of ["ew-field","ew-op","ew-threshold","ew-outcome","ew-message","ew-preview","ew-validate"])$(id).disabled=!exec&&id!=="ew-validate"&&id!=="ew-message"?true:$(id).disabled;
}
function drawList(){
 const es=S.registry.engines;$("ew-count").textContent=es.length+" engine"+(es.length===1?"":"s");
 $("ew-list").innerHTML=es.length?es.map(e=>'<button type="button" class="ew-engine" role="option" data-engine="'+e.engine_id+'" aria-selected="'+(e.engine_id===S.selected)+'">'+
  '<b>'+esc(e.display_name)+'</b><small>'+esc(e.engine_key)+' · '+esc(e.handler_id)+' · v'+e.current_version+' · '+e.assignments.length+' business'+(e.assignments.length===1?"":"es")+'</small></button>').join(""):
  '<p class="ew-muted">No engines yet. Create the first descriptor with “New engine”.</p>';
}
function drawVersions(){
 const e=engine(),h=$("ew-versions");
 if(!e){h.innerHTML="";return}
 const can=handlerOf(e.handler_id);
 h.innerHTML=e.versions.map(v=>'<div class="ew-row" data-version="'+v.version+'"><div><span class="k">Version</span>v'+v.version+' <span class="ew-pill" data-s="'+esc(v.state)+'">'+esc(v.state)+'</span></div>'+
  '<div><span class="k">Immutable hash</span>'+esc(v.hash.slice(0,12))+'…</div>'+
  '<div><span class="k">Descriptor</span>'+esc(JSON.stringify(v.descriptor))+'</div>'+
  '<div><span class="k">Readiness</span>'+(v.state==="VALIDATED"&&can.can_execute?"Ready to publish (certified handler)":can.can_execute?"Needs validation":"NOT IMPLEMENTED · canExecute=false")+'</div></div>').join("");
}
function drawPublish(){
 const e=engine(),bs=bizOfTenant();
 $("ew-pub-business").innerHTML=opts(bs.map(b=>[b.id,"Business #"+b.id+(b.slug?" · "+b.slug:"")]),$("ew-pub-business").value||(bs[0]&&bs[0].id));
 const vs=e?e.versions.filter(v=>v.state==="VALIDATED"):[];
 $("ew-pub-version").innerHTML=vs.length?opts(vs.map(v=>[v.version,"v"+v.version+" (validated)"]),vs[vs.length-1].version):'<option value="">No validated version</option>';
 const ex=e&&handlerOf(e.handler_id).can_execute;
 $("ew-pub-save").disabled=!e||!ex||!vs.length;
 const a=$("ew-assignments"),rows=e?e.assignments:[];
 $("ew-assign-count").textContent=rows.length+" assigned";
 a.innerHTML=rows.length?rows.map(r=>'<div class="ew-row" data-assigned="'+r.business_id+'"><div><span class="k">Business</span>#'+r.business_id+'</div>'+
  '<div><span class="k">State</span><span class="ew-pill" data-s="'+esc(r.state)+'">'+esc(r.state)+'</span> v'+r.pinned_version+'</div>'+
  '<div><span class="k">Effective threshold</span>'+esc(r.params&&r.params.threshold!==undefined?r.params.threshold:"descriptor default")+'</div>'+
  '<div><span class="k">Placement · edit · cfg version</span>'+esc(L[r.placement])+' · '+esc(L[r.local_edit_mode])+' · '+r.version+'</div>'+
  '<div class="ew-actions" style="grid-column:1/-1"><button class="outline" data-act="pause" data-biz="'+r.business_id+'" type="button"'+(r.state==="PUBLISHED"?"":" disabled")+'>Pause</button>'+
  '<button class="danger" data-act="revoke" data-biz="'+r.business_id+'" type="button"'+(r.state==="REVOKED"?" disabled":"")+'>Revoke</button>'+
  '<button class="outline" data-act="prev" data-biz="'+r.business_id+'" type="button"'+(r.state==="PUBLISHED"?"":" disabled")+'>Preview as this business</button></div></div>').join(""):
  '<p class="ew-muted">Not published to any business yet.</p>';
 loadAssignmentIntoForm();drawDiff();
}
function currentAssignment(){const e=engine(),b=Number($("ew-pub-business").value);return e&&e.assignments.find(a=>a.business_id===b)||null}
function loadAssignmentIntoForm(){
 const a=currentAssignment();
 if(a){$("ew-pub-placement").value=a.placement;$("ew-pub-edit").value=a.local_edit_mode;
  $("ew-pub-threshold").value=a.params&&a.params.threshold!==undefined?a.params.threshold:"";
  $("ew-pub-state").value=a.state==="REVOKED"?"PUBLISHED":a.state;if(a.pinned_version)$("ew-pub-version").value=String(a.pinned_version)}
}
function pubParams(){const t=$("ew-pub-threshold").value;return t===""?{}:{threshold:Number(t)}}
function drawDiff(){
 const a=currentAssignment(),n=$("ew-diff");if(!engine()){n.textContent="Select an engine and business to see the before → after diff.";return}
 const after={state:$("ew-pub-state").value,version:Number($("ew-pub-version").value)||null,threshold:$("ew-pub-threshold").value===""?"descriptor default":Number($("ew-pub-threshold").value),
  placement:L[$("ew-pub-placement").value],edit:L[$("ew-pub-edit").value]};
 const before=a?{state:a.state,version:a.pinned_version,threshold:a.params&&a.params.threshold!==undefined?a.params.threshold:"descriptor default",placement:L[a.placement],edit:L[a.local_edit_mode]}:null;
 const line=(k)=>(before?String(before[k]):"—")+"  →  "+String(after[k]);
 n.textContent="Business #"+$("ew-pub-business").value+(before?" (config v"+a.version+")":" (new)")+"\nstate      : "+line("state")+"\nversion    : "+line("version")+"\nthreshold  : "+line("threshold")+"\nplacement  : "+line("placement")+"\nedit auth. : "+line("edit")+"\nOther businesses are not changed.";
 const p=W.validateParams(pubParams());$("ew-err-pub").textContent=p.ok?"":p.errors.join("; ");
}
async function drawAudit(){
 const e=engine(),h=$("ew-audit");
 if(!e){h.innerHTML='<p class="ew-muted">Select an engine.</p>';return}
 try{S.audit=await S.api.readAudit(e.engine_id)}catch(err){h.innerHTML='<p class="ew-muted">Audit unavailable: '+esc(fmtErr(err))+'</p>';return}
 h.innerHTML=S.audit.length?S.audit.map(x=>{
  const can=["assignment_changed","params_edited","request_approved","assignment_rolled_back"].includes(x.event)&&x.business_id&&x.event!=="request_approved";
  return '<div class="ew-row" data-audit="'+x.audit_id+'"><div><span class="k">#'+x.audit_id+' · '+esc(new Date(x.created_at).toISOString().slice(0,16).replace("T"," "))+'</span>'+esc(x.event)+'</div>'+
  '<div><span class="k">Business</span>'+esc(x.business_id==null?"engine-wide":"#"+x.business_id)+'</div>'+
  '<div><span class="k">Before</span>'+esc(x.before?JSON.stringify(x.before).slice(0,120):"—")+'</div>'+
  '<div><span class="k">After</span>'+esc(x.after?JSON.stringify(x.after).slice(0,120):"—")+
  (can?'<div class="ew-actions"><button class="outline" data-rollback="'+x.audit_id+'" data-biz="'+x.business_id+'" type="button">Rollback config to before this</button></div>':'')+'</div></div>'}).join(""):'<p class="ew-muted">No history.</p>';
}
async function drawPending(){
 try{S.pending=await S.api.pending(S.tenantId)}catch(err){$("ew-requests").innerHTML='<p class="ew-muted">Queue unavailable: '+esc(fmtErr(err))+'</p>';return}
 $("ew-requests").innerHTML=S.pending.length?S.pending.map(r=>'<div class="ew-row"><div><span class="k">Request #'+r.request_id+'</span>engine #'+r.engine_id+' · business #'+r.business_id+'</div>'+
  '<div><span class="k">Proposed</span>'+esc(JSON.stringify(r.target_params))+'</div><div><span class="k">Reason</span>'+esc(r.reason)+'</div>'+
  '<div class="ew-actions"><button class="primary" data-decide="approve" data-id="'+r.request_id+'" type="button">Approve</button><button class="danger" data-decide="reject" data-id="'+r.request_id+'" type="button">Reject</button></div></div>').join(""):
  '<p class="ew-muted">None.</p>';
}
async function reload(keep){
 S.registry=await S.api.readRegistry(S.tenantId);
 if(keep===undefined)keep=S.selected;
 S.selected=S.registry.engines.some(e=>e.engine_id===keep)?keep:null;
 drawList();fillForm(engine());drawVersions();drawPublish();await Promise.all([drawAudit(),drawPending()]);
}
function wireOwner(){
 $("ew-tenant").addEventListener("change",()=>{S.tenantId=Number($("ew-tenant").value);S.selected=null;run("Loading tenant",async()=>{await reload(null);return "Registry loaded · tenant #"+S.tenantId})});
 $("ew-new").addEventListener("click",()=>{S.selected=null;drawList();fillForm(null);drawVersions();drawPublish();drawAudit();status("New engine: define, preview, then save as version 1.")});
 $("ew-list").addEventListener("click",ev=>{const b=ev.target.closest("[data-engine]");if(!b)return;S.selected=Number(b.dataset.engine);
  drawList();fillForm(engine());drawVersions();drawPublish();drawAudit();status("Engine #"+S.selected+" selected")});
 for(const id of ["ew-pub-business","ew-pub-version","ew-pub-state","ew-pub-threshold","ew-pub-placement","ew-pub-edit"])
  $(id).addEventListener(id==="ew-pub-business"?"change":"input",()=>{if(id==="ew-pub-business")loadAssignmentIntoForm();drawDiff()});
 $("ew-handler").addEventListener("change",()=>fillForm(engine()));
 $("ew-preview").addEventListener("click",()=>run("Previewing on server",async()=>{
  const d=descriptorFromForm(),v=W.validateDescriptor(d);if(!v.ok){$("ew-err-threshold").textContent=v.errors.join("; ");throw Object.assign(new Error("Fix the highlighted field"),{code:"INVALID_INPUT"})}
  const val=Number($("ew-preview-input").value);if(!Number.isFinite(val))throw Object.assign(new Error("Enter a numeric sample value"),{code:"INVALID_INPUT"});
  const r=await S.api.previewDraft({tenantId:S.tenantId,descriptor:d,params:{},inputs:{[d.field]:val}});
  $("ew-preview-result").innerHTML='<b>'+esc(d.field)+' = '+esc(val)+'</b> → '+(r.matched?'rule matched':'rule not matched')+' · outcome <b>'+esc(r.outcome)+'</b> · wouldBlock (advisory): <b>'+esc(r.wouldBlock)+'</b> · requires approval (advisory): '+esc(r.requiresApproval)+
   '<br><span class="ew-muted">Advisory only · no data written · canAuthorizeOperation = '+esc(r.canAuthorizeOperation)+'</span>';
  return "Preview evaluated by server · nothing saved"}));
 $("ew-save").addEventListener("click",()=>{if(formErrors()){status("Fix the highlighted fields first.",true);return}
  run("Saving version",async()=>{const e=engine(),d=$("ew-handler").value==="threshold_rule_v1"?descriptorFromForm():{note:$("ew-message").value.trim()||"draft"};
   const r=await S.api.saveDraft({tenantId:S.tenantId,key:$("ew-key").value.trim(),name:$("ew-name").value.trim(),handler:$("ew-handler").value,descriptor:d,
    expectedVersion:e?e.current_version:0,requestKey:rk(),reason:$("ew-reason").value});
   await reload(r.engine_id);return "Saved immutable version "+r.version+" (DRAFT) for engine #"+r.engine_id+" · server receipt"})});
 $("ew-validate").addEventListener("click",()=>{const e=engine();if(!e){status("Select a saved engine first.",true);return}
  if($("ew-reason").value.trim().length<5){$("ew-err-reason").textContent="Required: at least 5 characters.";status("Reason required.",true);return}
  run("Validating",async()=>{const v=e.versions[e.versions.length-1];const r=await S.api.validateVersion({engineId:e.engine_id,version:v.version,requestKey:rk(),reason:$("ew-reason").value});
   await reload(e.engine_id);return "Version "+r.version+" is now VALIDATED"})});
 $("ew-pub-save").addEventListener("click",()=>{const e=engine();if(!e)return;
  if($("ew-reason").value.trim().length<5){$("ew-err-reason").textContent="Required: at least 5 characters.";status("Reason required (shared field above).",true);return}
  const p=W.validateParams(pubParams());if(!p.ok){status(p.errors.join("; "),true);return}
  run("Applying to business #"+$("ew-pub-business").value,async()=>{const a=currentAssignment();
   const r=await S.api.assign({engineId:e.engine_id,businessId:Number($("ew-pub-business").value),version:Number($("ew-pub-version").value),state:$("ew-pub-state").value,
    params:pubParams(),placement:$("ew-pub-placement").value,localEditMode:$("ew-pub-edit").value,expected:a?a.version:0,requestKey:rk(),reason:$("ew-reason").value});
   await reload(e.engine_id);return "Business #"+r.business_id+" → "+r.state+" · config version "+r.version+" · other businesses unchanged"})});
 $("ew-assignments").addEventListener("click",ev=>{const b=ev.target.closest("[data-act]");if(!b)return;const e=engine(),bid=Number(b.dataset.biz),a=e.assignments.find(x=>x.business_id===bid);
  if(b.dataset.act==="prev"){run("Previewing as business #"+bid,async()=>{const f=e.versions.find(v=>v.version===a.pinned_version).descriptor.field;
    const val=Number($("ew-preview-input").value);const r=await S.api.previewBusiness({engineId:e.engine_id,businessId:bid,inputs:{[f]:val}});
    $("ew-preview-result").innerHTML='<b>Business #'+bid+'</b> v'+esc(r.version)+' · '+esc(f)+' = '+esc(val)+' → <b>'+esc(r.outcome)+'</b> (threshold '+esc(r.effective.threshold)+') · wouldBlock (advisory): '+esc(r.wouldBlock)+'<br><span class="ew-muted">Advisory only · canAuthorizeOperation = '+esc(r.canAuthorizeOperation)+'</span>';
    return "Business #"+bid+" evaluated with its own configuration"});return}
  if($("ew-reason").value.trim().length<5){$("ew-err-reason").textContent="Required: at least 5 characters.";status("Reason required.",true);return}
  const state=b.dataset.act==="pause"?"PAUSED":"REVOKED";
  run(state==="PAUSED"?"Pausing":"Revoking",async()=>{const r=await S.api.assign({engineId:e.engine_id,businessId:bid,version:a.pinned_version,state,params:a.params||{},
    placement:a.placement,localEditMode:a.local_edit_mode,expected:a.version,requestKey:rk(),reason:$("ew-reason").value});
   await reload(e.engine_id);return "Business #"+bid+" is now "+r.state+" · other businesses unchanged"})});
 $("ew-audit").addEventListener("click",ev=>{const b=ev.target.closest("[data-rollback]");if(!b)return;const e=engine(),bid=Number(b.dataset.biz),a=e.assignments.find(x=>x.business_id===bid);
  if($("ew-reason").value.trim().length<5){$("ew-err-reason").textContent="Required: at least 5 characters.";status("Reason required.",true);return}
  run("Rolling back configuration",async()=>{const r=await S.api.rollback({engineId:e.engine_id,businessId:bid,auditId:Number(b.dataset.rollback),expected:a.version,requestKey:rk(),reason:$("ew-reason").value});
   await reload(e.engine_id);return "Configuration rolled back (config only) · new config version "+r.version})});
 $("ew-requests").addEventListener("click",ev=>{const b=ev.target.closest("[data-decide]");if(!b)return;
  run("Recording decision",async()=>{const r=await S.api.decide(Number(b.dataset.id),b.dataset.decide);await reload(S.selected);return "Request "+r.status})});
}
/* ----------------------------- BUSINESS SURFACE ----------------------------- */
async function businessView(){
 const id=Number(bizParam);
 $("ew-body").innerHTML='<div class="ew-grid"><section class="ew-panel ew-wide"><h2>Engines for business #'+esc(id)+' <small>server-scoped · same canonical service as the Owner Workshop</small></h2><div id="ew-biz-list" class="ew-table"></div></section>'+
 '<section class="ew-panel ew-wide"><h2>Preview</h2><div class="ew-form two"><label>Sample value<input id="ew-preview-input" type="number" step="any" value="8"></label></div><div id="ew-preview-result" class="ew-result">Choose “Preview” on an engine.</div></section></div>';
 async function load(){
  const d=await S.api.readBusiness(id);
  $("ew-biz-list").innerHTML=d.items.length?d.items.map(x=>'<div class="ew-row" data-engine-row="'+x.engine_id+'"><div><span class="k">'+esc(x.control_id)+'</span><b>'+esc(x.display_name)+'</b></div>'+
   '<div><span class="k">State · version</span><span class="ew-pill" data-s="'+esc(x.state)+'">'+esc(x.state)+'</span> v'+x.pinned_version+' · cfg '+x.version+'</div>'+
   '<div><span class="k">Effective rule</span>'+esc(x.effective?x.effective.field+" "+L[x.effective.op]+" "+x.effective.threshold+" → "+x.effective.outcome:"not executable")+'</div>'+
   '<div><span class="k">Placement · edit authority</span>'+esc(L[x.placement])+' · '+esc(L[x.local_edit_mode])+'</div>'+
   '<label style="grid-column:1/-1">Threshold for this business<input data-th="'+x.engine_id+'" type="number" step="any" '+(x.local_edit_mode==="central_only"||x.state!=="PUBLISHED"?"disabled":"")+' value="'+esc(x.effective?x.effective.threshold:"")+'"></label>'+
   '<label style="grid-column:1/-1">Reason<input data-why="'+x.engine_id+'" maxlength="500" '+(x.local_edit_mode==="central_only"||x.state!=="PUBLISHED"?"disabled":"")+'></label>'+
   '<div class="ew-actions" style="grid-column:1/-1"><button class="primary" data-save="'+x.engine_id+'" data-ver="'+x.version+'" type="button" '+(x.local_edit_mode==="central_only"||x.state!=="PUBLISHED"?"disabled":"")+'>'+(x.local_edit_mode==="request_approval"?"Request approval":"Save for this business")+'</button>'+
   '<button class="outline" data-prev="'+x.engine_id+'" data-field="'+esc(x.effective&&x.effective.field)+'" type="button" '+(x.state==="PUBLISHED"&&x.can_execute?"":"disabled")+'>Preview</button></div></div>').join(""):
   '<p class="ew-muted">No engine is published to this business menu. Hidden or central-only engines remain with the Owner.</p>';
 }
 $("ew-body").addEventListener("click",ev=>{
  const s=ev.target.closest("[data-save]"),p=ev.target.closest("[data-prev]");
  if(s){const eid=Number(s.dataset.save),th=document.querySelector('[data-th="'+eid+'"]').value,why=document.querySelector('[data-why="'+eid+'"]').value;
   if(th===""||why.trim().length<5){status("Enter a threshold and a reason (min 5 characters).",true);return}
   run("Submitting",async()=>{const r=await S.api.editParams({engineId:eid,businessId:id,params:{threshold:Number(th)},expected:Number(s.dataset.ver),requestKey:rk(),reason:why});
    await load();return r.status==="pending"?"Approval request submitted · nothing changed yet":"Saved for business #"+id+" · config version "+r.version})}
  if(p){const eid=Number(p.dataset.prev),val=Number($("ew-preview-input").value);
   run("Previewing",async()=>{const r=await S.api.previewBusiness({engineId:eid,businessId:id,inputs:{[p.dataset.field]:val}});
    $("ew-preview-result").innerHTML=esc(p.dataset.field)+' = '+esc(val)+' → <b>'+esc(r.outcome)+'</b> (advisory · canAuthorizeOperation = '+esc(r.canAuthorizeOperation)+')';return "Preview evaluated by server"})}});
 await load();status("Server-authorized engines loaded · business #"+id);
}
/* ---------------------------------- BOOT ---------------------------------- */
async function boot(){
 shell();
 try{
  if(!W||!window.supabase||!window.BOS_CONFIG)throw Object.assign(new Error("Supabase client/config not available"),{code:"SIGNED_SUPABASE_CLIENT_REQUIRED"});
  const client=window.supabase.createClient(window.BOS_CONFIG.url,window.BOS_CONFIG.key);
  S.api=W.create({client});
  S.businesses=await S.api.listBusinesses();
  if(bizParam){await businessView();return}
  const ts=tenants();if(!ts.length)throw Object.assign(new Error("No authorized tenant"),{code:"NO_SCOPE"});
  S.tenantId=ts[0];S.registry=await S.api.readRegistry(S.tenantId);
  ownerShell();drawList();fillForm(null);drawVersions();drawPublish();await Promise.all([drawAudit(),drawPending()]);
  status("Server-authorized registry loaded · tenant #"+S.tenantId);
 }catch(err){
  status("Workshop unavailable or server authorization denied — "+fmtErr(err),true);
  if(!$("ew-body").innerHTML)$("ew-body").innerHTML='<p class="ew-muted">Sign in with an authorized Owner account. Nothing is simulated.</p>';
 }
}
boot();
})();
