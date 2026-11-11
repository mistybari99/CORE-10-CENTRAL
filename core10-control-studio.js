/* C10-A044 Actual Central / Business settings UI, one shared signed RPC client.
 * No demo state, local shadow copy, fake grants or direct Supabase table edits.
 */
(function(){"use strict";
const root=document.getElementById("studio"),isBusiness=document.body.dataset.surface==="business";
const $$=(id)=>document.getElementById(id);
const html=(v)=>String(v==null?"":v).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const labels={central_only:"Central Only",business_only:"Business Only",both:"Both",hidden_from_menus:"Hidden from menus",
 business_owner:"Business Owner may edit",request_approval:"Business Owner requests approval"};
const state={api:null,businesses:[],businessId:null,items:[],selected:null,query:"",loading:false};
const entry=new URLSearchParams(location.search);
const businessParam=entry.get("biz");
function showStatus(message,error){
 const node=$$("studio-status");if(node){node.textContent=message;node.dataset.tone=error?"error":"ok"}
}
function shell(){
 root.innerHTML='<div class="studio-layout"><aside class="studio-rail"><div class="brand">CORE <b>10</b><small> CENTRAL · ENTERPRISE</small></div>'+
 '<nav aria-label="Control navigation"><a href="./owner.html#/organization">Portfolio overview</a>'+
 '<a class="active" href="./core10-control-studio.html">Universal Control Studio</a>'+
 '<a href="./core10-engine-workshop.html">Micro-Engine Workshop</a><a href="./index.html">Business workspace</a></nav><div class="rail-note">D045 · R123 · A042/A043<br>One canonical service. No independent local permissions.</div></aside>'+
 '<main><div class="topline"><span>OWNER GOVERNANCE / CONFIGURATION</span><span class="version">SERVICE V1 · UNRELEASED</span></div>'+
 '<div class="headline"><div><h1>'+ (isBusiness?"Business Controls":"Universal Control Studio")+'</h1>'+
 '<p>'+(isBusiness?"Business App / Settings / Business Controls":"Central registry · business-specific placement · delegated preferences")+'</p></div>'+
 '<a class="return-link" href="'+(isBusiness?"./index.html?workspace=business&biz="+encodeURIComponent(businessParam||"")+"#/home":"./owner.html#/organization")+'">← Back</a></div>'+
 '<div class="safety" role="note"><strong>Settings are not operational authorization.</strong> Preferred ON/OFF and menu position do not activate stock, payments, permissions, audit bypass, or production capabilities. Signed server authorization is required.</div>'+
 '<div class="selector-line"><label>Business context<select id="studio-business"><option value="">Loading authorized businesses…</option></select></label>'+
 '<label>Find controls<input id="studio-search" type="search" placeholder="Search canonical control ID or group" autocomplete="off"></label></div>'+
 '<div id="studio-status" role="status" aria-live="polite">Connecting with verified session…</div>'+
 '<div class="content-grid"><section class="catalog-panel"><div class="panel-title"><h2>Control registry</h2><span id="studio-count">0 controls</span></div>'+
 '<div id="studio-list" class="control-list" role="listbox" aria-label="Available controls"></div></section>'+
 '<section class="detail-panel"><div class="panel-title"><h2>Configuration</h2><span class="tiny">SERVER-SCOPED</span></div>'+
 '<div id="studio-detail"><p class="empty">Choose an authorized business and a control.</p></div></section></div>'+
 '<section class="approval-panel"><div class="panel-title"><h2>Pending change requests</h2><button id="studio-requests-refresh" type="button" class="outline">Refresh</button></div>'+
 '<div id="studio-requests"><p class="muted">Only the authorized tenant owner can review requests.</p></div></section>'+
 '<footer>CORE 10 CENTRAL · Shared canonical settings / A021 Owner Controls and A034 Governance remain authoritative · No live migration or stock release</footer></main></div>';
}
function visibleItems(){
 let items=state.items;
 if(isBusiness)items=items.filter(x=>["both","business_only"].includes(x.placement));
 const q=state.query.toLowerCase().trim();
 if(q)items=items.filter(x=>(x.control_id+" "+x.group).toLowerCase().includes(q));
 return items;
}
function drawList(){
 const entries=visibleItems();$$("studio-count").textContent=entries.length+" / "+state.items.length+" controls";
 $$("studio-list").innerHTML=entries.length?entries.map(x=>{
 const selected=x.control_id===state.selected;
 return '<button type="button" role="option" aria-selected="'+String(selected)+'" class="control-row'+(selected?" selected":"")+'" data-control="'+html(x.control_id)+'">'+
 '<span class="control-icon">'+html(x.group.slice(0,2).toUpperCase())+'</span><span class="control-label"><b>'+html(x.control_id)+'</b>'+
 '<small>'+html(x.group)+" · "+html(labels[x.placement]||x.placement)+'</small></span>'+
 '<span class="dot '+(x.preferred_enabled?"on":"")+'" aria-label="Preferred '+(x.preferred_enabled?"ON":"OFF")+'"></span></button>';
 }).join(""):'<p class="empty">No controls available in this menu. Universal Owners can still discover hidden controls centrally.</p>';
}
function choiceMarkup(field,items,value,disabled){
 return '<select id="studio-'+field+'" '+(disabled?'disabled':'')+'>'+items.map(([v,t])=>
 '<option value="'+html(v)+'"'+(v===value?' selected':'')+'>'+html(t)+'</option>').join("")+'</select>';
}
function drawDetail(){
 const x=state.items.find(v=>v.control_id===state.selected),host=$$("studio-detail");
 if(!x){host.innerHTML='<p class="empty">Select a control from the registry.</p>';return}
 const contextLock=isBusiness,readOnly=contextLock&&x.local_edit_mode==="central_only";
 const placementOpts=window.CORE10_CONTROL_SETTINGS_API.PLACEMENTS.map(v=>[v,labels[v]||v]);
 const modeOpts=window.CORE10_CONTROL_SETTINGS_API.MODES.map(v=>[v,labels[v]||v]);
 host.innerHTML='<div class="detail-title"><span class="detail-group">'+html(x.group)+'</span><h3>'+html(x.control_id)+'</h3>'+
 '<p>Canonical ID · shared across both surfaces</p></div>'+
 '<div class="scope-metrics"><div><small>Current version</small><b>'+x.version+'</b></div>'+
 '<div><small>Audit events</small><b>'+Number(x.audit_count||0)+'</b></div>'+
 '<div><small>Placement</small><b>'+html(labels[x.placement]||x.placement)+'</b></div></div>'+
 '<div class="edit-fields"><label>Menu placement'+choiceMarkup("placement",placementOpts,x.placement,contextLock)+'</label>'+
 '<label>Local edit authority'+choiceMarkup("local-mode",modeOpts,x.local_edit_mode,contextLock)+'</label>'+
 '<label>Preferred setting'+choiceMarkup("enabled",[["false","OFF · preferred"],["true","ON · preferred"]],String(x.preferred_enabled),readOnly)+'</label>'+
 '<label>Reason for change<textarea id="studio-reason" maxlength="500" rows="3" placeholder="Required: explain why this setting is changing." '+(readOnly?'disabled':'')+'></textarea></label>'+
 '<div class="impact"><b>Before → After preview</b><p id="studio-impact">Select new preferences to review impact. Effective execution permission remains SERVER-ONLY.</p></div>'+
 '<button id="studio-save" class="primary" type="button" '+(readOnly?'disabled':'')+'>'+(contextLock&&x.local_edit_mode==="request_approval"?"Request approval":"Confirm & save configuration")+'</button>'+
 '<p class="muted">'+(readOnly?"This control is centrally managed; business-local editing is disabled.":"Optimistic version check, idempotency and server audit are mandatory.")+'</p></div>';
 previewImpact();
}
function previewImpact(){
 const x=state.items.find(v=>v.control_id===state.selected);if(!x||!$$("studio-impact"))return;
 const place=$$("studio-placement").value,loc=$$("studio-local-mode").value,enable=$$("studio-enabled").value==="true";
 $$("studio-impact").textContent="Preferred "+(x.preferred_enabled?"ON":"OFF")+" → "+(enable?"ON":"OFF")+
  " · "+(labels[x.placement]||x.placement)+" → "+(labels[place]||place)+
  " · Edit: "+x.local_edit_mode+" → "+loc+
  " · No new grant, ledger write or production release.";
}
async function loadBusiness(){
 if(!state.businessId)return;
 const wanted=state.businessId;
 state.selected=null;state.items=[];drawList();drawDetail();
 showStatus("Reading canonical settings using signed authenticated session…");
 try{
  const response=await state.api.read(wanted);
  if(state.businessId!==wanted)return;
  state.items=response.items;state.selected=visibleItems()[0]?.control_id||null;
  drawList();drawDetail();showStatus("Server-authorized configuration loaded · business #"+wanted);
  loadPending();
 }catch(err){
  if(state.businessId!==wanted)return;
  showStatus("Settings unavailable or server authorization denied: "+String(err.code||"RPC_UNAVAILABLE"),true);
  $$("studio-requests").innerHTML='<p class="muted">Approval queue unavailable.</p>';
 }
}
async function loadPending(){
 if(!state.businessId||!state.api)return;
 const target=state.businessId;
 try{
  const pending=await state.api.pending(target);
  if(state.businessId!==target)return;
  $$("studio-requests").innerHTML=pending.length?pending.map(x=>
   '<div class="request-row"><div><b>'+html(x.control_id)+'</b><p>'+html(x.reason)+'</p>'+
   '<small>Target preference: '+(x.target_enabled?"ON":"OFF")+' · Expected v'+x.expected_version+'</small></div>'+
   '<div><button class="outline" data-decision="approve" data-request-id="'+x.request_id+'">Approve</button> '+
   '<button class="outline danger" data-decision="reject" data-request-id="'+x.request_id+'">Reject</button></div></div>').join(""):
    '<p class="muted">No pending requests visible to this signed-in Owner.</p>';
 }catch(_){if(state.businessId===target)$$("studio-requests").innerHTML='<p class="muted">No authorized approval queue access. Business Owners cannot approve requests.</p>'}
}
async function save(){
 const x=state.items.find(v=>v.control_id===state.selected);if(!x||state.loading)return;
 const placement=$$("studio-placement").value,mode=$$("studio-local-mode").value,
  enabled=$$("studio-enabled").value==="true",reason=$$("studio-reason").value.trim();
 if(reason.length<5){showStatus("Enter a reason of at least five characters.",true);return}
 if(!window.crypto||typeof window.crypto.randomUUID!=="function"){showStatus("Secure request ID unavailable; no write attempted.",true);return}
 const diff="Business #"+state.businessId+" · "+x.control_id+
  "\nPreferred ON/OFF: "+x.preferred_enabled+" → "+enabled+
  "\nMenu: "+x.placement+" → "+placement+
  "\nEdit authority: "+x.local_edit_mode+" → "+mode+
  "\nVersion: "+x.version+"\nNo stock, finance or role grant changes.";
 if(!window.confirm("Confirm canonical settings change?\n\n"+diff))return;
 const biz=state.businessId,key=x.control_id;state.loading=true;$$("studio-save").disabled=true;
 try{
  const r=await state.api.write(biz,{controlId:key,placement,localEditMode:mode,
   enabled,version:x.version,requestKey:window.crypto.randomUUID(),reason});
  if(state.businessId!==biz)return;
  const confirmation=r.status==="pending"?"Approval request submitted; configuration unchanged.":"Versioned configuration saved in canonical service.";
  await loadBusiness();
  state.selected=key;drawList();drawDetail();
  showStatus(confirmation);
 }catch(e){
  showStatus("Server rejected change: "+String(e.code||"CONTROL_WRITE_FAILED")+
   ". No local setting was stored.",true);
 }finally{state.loading=false;if($$("studio-save"))$$("studio-save").disabled=false}
}
async function decide(button){
 if(!window.confirm("Submit "+button.dataset.decision+" to the server for request #"+button.dataset.requestId+"?"))return;
 button.disabled=true;
 try{const r=await state.api.decide(Number(button.dataset.requestId),button.dataset.decision);
  await loadBusiness();showStatus("Request "+r.status+" by server authority.");
 }catch(e){showStatus("Approval denied or stale: "+String(e.code||"CONTROL_DECISION_FAILED"),true)}
 finally{button.disabled=false}
}
async function init(){
 shell();
 $$("studio-list").addEventListener("click",ev=>{const b=ev.target.closest("[data-control]");if(!b)return;
  state.selected=b.dataset.control;drawList();drawDetail()});
 $$("studio-search").addEventListener("input",ev=>{state.query=ev.target.value;drawList()});
 $$("studio-detail").addEventListener("change",previewImpact);
 $$("studio-detail").addEventListener("click",ev=>{if(ev.target.id==="studio-save")save()});
 $$("studio-requests").addEventListener("click",ev=>{const b=ev.target.closest("[data-decision]");if(b)decide(b)});
 $$("studio-requests-refresh").addEventListener("click",loadPending);
 $$("studio-business").addEventListener("change",ev=>{state.businessId=Number(ev.target.value)||null;loadBusiness()});
 try{
  const cfg=window.BOS_CONFIG,lib=window.supabase;
  if(!cfg||!cfg.url||!cfg.key||!lib||typeof lib.createClient!=="function")
   throw Error("SIGNED_CLIENT_CONFIGURATION_MISSING");
  state.api=window.CORE10_CONTROL_SETTINGS_API.create({client:lib.createClient(cfg.url,cfg.key)});
  state.businesses=await state.api.listBusinesses();
  if(isBusiness){
   if(!/^[1-9][0-9]*$/.test(businessParam||""))throw Error("BUSINESS_ID_REQUIRED");
   const chosen=Number(businessParam);
   if(!state.businesses.some(x=>x.id===chosen))throw Error("BUSINESS_NOT_IN_SESSION_SCOPE");
   state.businesses=state.businesses.filter(x=>x.id===chosen);
  }
  const select=$$("studio-business");select.replaceChildren();
  for(const x of state.businesses){const op=document.createElement("option");
   op.value=String(x.id);op.textContent=x.slug+" · #"+x.id+" (tenant "+x.tenant_id+")";select.appendChild(op)}
  if(!state.businesses.length)throw Error("NO_AUTHORIZED_BUSINESSES");
  state.businessId=state.businesses[0].id;
  await loadBusiness();
 }catch(err){showStatus("Cannot open signed Control Studio: "+String(err.code||err.message||"ACCESS_DENIED"),true)}
}
if(root)init();
})();
