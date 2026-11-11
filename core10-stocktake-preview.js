/* CORE 10 CENTRAL · C10-A038 Owner + Staff physical stocktake PREVIEW.
 * ALL actions are in-memory synthetic demonstrations, NOT ERP mutations.
 * Optional explicit staging mode supports signed SUPABASE READS only; no posting.
 * Local demo inventory is not stored, persisted or sent to any external service.
 */
(function(root,factory){
 "use strict";
 var api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root&&root.document){
  root.CORE10_STOCKTAKE_PREVIEW=api;
  var begin=function(){api.mount(root.document,root)};
  if(root.document.readyState==="loading")root.document.addEventListener("DOMContentLoaded",begin,{once:true});
  else begin();
 }
})(typeof window!=="undefined"?window:(typeof globalThis!=="undefined"?globalThis:null),function(){
"use strict";
var SCREENS=["overview","count","review","audit"],STATUSES=["draft","submitted","approved","posted","voided"];
var SITES=[
 {id:5001,code:"SM-01",label:"Main Showroom",kind:"showroom"},
 {id:5002,code:"CF-01",label:"Cake Factory",kind:"factory"},
 {id:5003,code:"GD-01",label:"Central Godown",kind:"godown"}
];
var ITEMS=[
 {id:8001,name:"Rasgolla",sku:"FOOD-001",unit:"pcs"},
 {id:8002,name:"Cake",sku:"BAKE-002",unit:"lb"},
 {id:8003,name:"Packaging Box",sku:"PACK-003",unit:"pcs"}
];
var BASE_STOCK={
 5001:{8001:240,8002:28,8003:60},
 5002:{8001:110,8002:42,8003:72},
 5003:{8001:500,8002:5,8003:190}
};
function copy(x){return JSON.parse(JSON.stringify(x))}
function fail(code){var e=new Error(code);e.code=code;throw e}
function qty(value){
 if(typeof value!=="number"&&typeof value!=="string")fail("INVALID_COUNT_QUANTITY");
 if(typeof value==="string"&&!/^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,3})?$/.test(value))
  fail("INVALID_COUNT_QUANTITY");
 var n=Number(value);
 if(!Number.isFinite(n)||n<0||n>999999999999.999||Math.round(n*1000)!==n*1000)
  fail("INVALID_COUNT_QUANTITY");
 return n;
}
function positiveId(value){
 var n=Number(value);
 if((typeof value==="string"&&!/^[1-9][0-9]*$/.test(value))||
  (typeof value!=="string"&&typeof value!=="number")||
  !Number.isSafeInteger(n)||n<1)fail("INVALID_DEMO_ID");
 return n;
}
function validateCounts(siteId,counts){
 var id=positiveId(siteId);
 if(!SITES.some(function(site){return site.id===id}))fail("UNKNOWN_DEMO_SITE");
 if(!Array.isArray(counts)||counts.length<1||counts.length>ITEMS.length)fail("INVALID_COUNT_MANIFEST");
 var seen=new Set();
 var result=counts.map(function(line){
  if(!line||typeof line!=="object"||Array.isArray(line)||
   Object.keys(line).sort().join(",")!=="counted,itemId")fail("INVALID_COUNT_MANIFEST");
  var item=positiveId(line.itemId);
  if(!ITEMS.some(function(x){return x.id===item})||seen.has(item))
   fail("INVALID_COUNT_MANIFEST");
  seen.add(item);
  return {itemId:item,counted:qty(line.counted)};
 });
 return {siteId:id,lines:result};
}
function makeDemo(){
 var state={role:"staff",screen:"overview",filter:"all",siteId:5001,docs:[
  {id:4101,siteId:5001,actor:"staff",status:"submitted",lines:[
   {itemId:8001,expected:240,counted:237},
   {itemId:8002,expected:28,counted:28},
   {itemId:8003,expected:60,counted:59}],reviewedBy:null},
  {id:4102,siteId:5002,actor:"staff",status:"approved",lines:[
   {itemId:8001,expected:110,counted:110},
   {itemId:8002,expected:42,counted:40},
   {itemId:8003,expected:72,counted:72}],reviewedBy:"owner"},
  {id:4103,siteId:5003,actor:"staff",status:"posted",lines:[
   {itemId:8003,expected:193,counted:190}],reviewedBy:"owner"}
 ],stock:copy(BASE_STOCK),audit:[],next:4104,seq:0};
 function event(doc,kind,who){
  state.seq+=1;
  state.audit.push({seq:state.seq,docId:doc.id,siteId:doc.siteId,kind:kind,actor:who});
 }
 state.docs.forEach(function(d){
  event(d,"draft",d.actor);event(d,"submitted",d.actor);
  if(d.status==="approved"||d.status==="posted")event(d,"approved","owner");
  if(d.status==="posted")event(d,"posted","owner");
 });
 function find(id){
  var n=positiveId(id),d=state.docs.find(function(doc){return doc.id===n});
  if(!d)fail("DEMO_STOCKTAKE_NOT_FOUND");
  return d;
 }
 function owner(){if(state.role!=="owner")fail("OWNER_REVIEW_REQUIRED")}
 function snapshot(){return copy(state)}
 function role(value){if(value!=="staff"&&value!=="owner")fail("INVALID_DEMO_ROLE");state.role=value;return snapshot()}
 function screen(value){if(!SCREENS.includes(value))fail("INVALID_DEMO_SCREEN");state.screen=value;return snapshot()}
 function filter(value){if(value!=="all"&&!STATUSES.includes(value))fail("INVALID_DEMO_FILTER");state.filter=value;return snapshot()}
 function site(value){var id=positiveId(value);if(!SITES.some(function(x){return x.id===id}))fail("UNKNOWN_DEMO_SITE");state.siteId=id;return snapshot()}
 function submit(siteId,counts){
  if(state.role!=="staff")fail("STAFF_COUNT_REQUIRED");
  var validated=validateCounts(siteId,counts),doc={
   id:state.next++,siteId:validated.siteId,actor:state.role,status:"submitted",
   lines:validated.lines.map(function(line){return{
    itemId:line.itemId,expected:state.stock[validated.siteId][line.itemId],
    counted:line.counted};}),reviewedBy:null
  };
  state.docs.unshift(doc);event(doc,"draft",state.role);event(doc,"submitted",state.role);
  return doc.id;
 }
 function approve(id){
  owner();var doc=find(id);
  if(doc.status!=="submitted")fail("COUNT_NOT_SUBMITTED");
  if(doc.actor===state.role)fail("OWN_COUNT_APPROVAL_DENIED");
  doc.status="approved";doc.reviewedBy=state.role;event(doc,"approved",state.role);
  return snapshot();
 }
 function post(id){
  owner();var doc=find(id);
  if(doc.status!=="approved")fail("COUNT_NOT_APPROVED");
  if(doc.lines.some(function(line){return state.stock[doc.siteId][line.itemId]!==line.expected}))
   fail("STALE_COUNT_RECOUNT_REQUIRED");
  doc.lines.forEach(function(line){state.stock[doc.siteId][line.itemId]=line.counted});
  doc.status="posted";event(doc,"posted",state.role);
  return snapshot();
 }
 function voidCount(id,reason){
  owner();var doc=find(id);
  if(doc.status==="posted")fail("POSTED_STOCKTAKE_IMMUTABLE");
  if(doc.status==="voided")fail("ALREADY_VOIDED");
  if(typeof reason!=="string"||reason.trim().length<5)fail("VOID_REASON_REQUIRED");
  doc.status="voided";doc.reason=reason.trim();event(doc,"voided",state.role);
  return snapshot();
 }
 function simulateMovement(siteId,itemId,delta){
  // Only to test stale-count handling inside synthetic memory; no remote writes.
  owner();var site=positiveId(siteId),item=positiveId(itemId),n=Number(delta);
  if(!state.stock[site]||!Object.prototype.hasOwnProperty.call(state.stock[site],item)||
   !Number.isFinite(n)||n===0||Math.round(n*1000)!==n*1000||
   state.stock[site][item]+n<0)fail("INVALID_DEMO_MOVEMENT");
  state.stock[site][item]+=n;
  return snapshot();
 }
 return Object.freeze({snapshot:snapshot,setRole:role,setScreen:screen,setFilter:filter,
  setSite:site,submit:submit,approve:approve,post:post,voidCount:voidCount,
  simulateMovement:simulateMovement,locations:copy(SITES),items:copy(ITEMS)});
}
function htmlEscape(v){return String(v==null?"":v).replace(/[&<>"']/g,function(ch){
 return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch];
});}
function itemLabel(id){var v=ITEMS.find(function(x){return x.id===id});return v?v.name:"Item "+id}
function siteLabel(id){var v=SITES.find(function(x){return x.id===id});return v?v.label:"Site "+id}
function fmt(n){return Number(n).toLocaleString("en-US",{maximumFractionDigits:3})}
function diff(doc){return doc.lines.reduce(function(s,l){return s+(l.counted-l.expected)},0)}
function niceStatus(s){return s.charAt(0).toUpperCase()+s.slice(1)}
function badge(status){return '<span class="c10-pill '+htmlEscape(status)+'">'+htmlEscape(niceStatus(status))+'</span>'}
function metric(label,number,caption,accent){
 return '<div class="c10-metric" data-accent="'+(accent||"navy")+'"><span class="c10-metric-label">'+htmlEscape(label)+
  '</span><strong class="c10-metric-amount">'+htmlEscape(number)+'</strong><span class="c10-metric-caption">'+htmlEscape(caption)+'</span></div>';
}
function mount(doc,root){
 var panel=doc.getElementById("screen-content"),feedback=doc.getElementById("feedback");
 if(!panel||!feedback)return null;
 var demo=makeDemo(),mode="demo",remote=[],stageAPI=null,selected=null;
 function message(text,isError){feedback.textContent=text||"";feedback.dataset.error=isError?"true":"false"}
 function renderMetrics(){
  var docs=mode==="demo"?demo.snapshot().docs:remote;
  var open=docs.filter(function(x){return x.status==="submitted"||x.status==="approved"}).length;
  var approved=docs.filter(function(x){return x.status==="approved"}).length;
  var posted=docs.filter(function(x){return x.status==="posted"}).length;
  var variance=mode==="demo"?docs.filter(function(x){return x.status!=="voided"}).reduce(function(n,d){
   return n+Math.abs(diff(d));},0):"—";
  doc.getElementById("metrics").innerHTML=
   metric("Open stocktakes",fmt(open),"Submitted and approved","navy")+
   metric("Awaiting posting",fmt(approved),"Owner-reviewed counts","amber")+
   metric("Completed",fmt(posted),"Posted stocktakes","teal")+
   metric("Count variance",variance==="—"?variance:fmt(variance),"Demo units, not financial value","navy");
 }
 function renderOverview(s){
  var entries=(mode==="demo"?s.docs:remote).filter(function(d){
   return s.filter==="all"||d.status===s.filter;
  });
  var menu=['<option value="all">All statuses</option>'].concat(STATUSES.map(function(status){
   return '<option value="'+status+'" '+(s.filter===status?'selected':'')+'>'+niceStatus(status)+'</option>';
  })).join("");
  var rows=entries.map(function(d){
   var id=d.id,loc=d.siteId==null?d.location_id:d.siteId,lines=Array.isArray(d.lines)?d.lines.length:"—";
   return '<tr><td><strong>#'+htmlEscape(id)+'</strong><small>'+htmlEscape(mode==="demo"?"Sample count":"Staging · read-only")+'</small></td>'+
    '<td><strong>'+htmlEscape(siteLabel(loc))+'</strong><small>'+htmlEscape(loc)+'</small></td>'+
    '<td>'+htmlEscape(lines)+'</td><td>'+badge(d.status)+'</td>'+
    '<td class="c10-right"><button class="c10-button c10-compact" type="button" data-act="inspect" data-id="'+htmlEscape(id)+'">Details</button></td></tr>';
  }).join("");
  return '<div class="c10-section-head"><div><h2>Stocktake register</h2>'+
   '<p>Every physical count stays separate from book stock until approved and posted.</p></div>'+
   '<div class="c10-toolbar"><select id="status-filter" aria-label="Filter stocktake status">'+menu+'</select></div></div>'+
   '<section class="c10-card"><div class="c10-table-wrap"><table class="c10-table"><thead><tr>'+
   '<th>Reference</th><th>Site / location</th><th>Lines</th><th>Status</th><th class="c10-right">Details</th>'+
   '</tr></thead><tbody>'+ (rows||'<tr><td colspan="5" class="c10-empty">No matching counts in this view.</td></tr>')+
   '</tbody></table></div></section>'+
   '<div class="c10-small-note">Simulation statuses are local to this browser tab. No real ERP document or journal was created.</div>';
 }
 function renderCount(s){
  if(mode!=="demo")return '<div class="c10-card pad"><h2>Staging is read-only</h2><p class="c10-form-help">Counting and posting are locked until real Auth, stock RLS and Owner release gates are approved.</p></div>';
  var options=SITES.map(function(x){return '<option value="'+x.id+'" '+(s.siteId===x.id?'selected':'')+'>'+htmlEscape(x.label)+" · "+htmlEscape(x.code)+'</option>';}).join("");
  var lines=ITEMS.map(function(x){
   var expected=s.stock[s.siteId][x.id];
   return '<tr><td><strong>'+htmlEscape(x.name)+'</strong><small>'+htmlEscape(x.sku)+'</small></td>'+
    '<td>'+htmlEscape(x.unit)+'</td><td class="c10-qty">'+fmt(expected)+'</td><td>'+
    '<input class="c10-line-input" type="number" min="0" step=".001" required inputmode="decimal" name="item-'+x.id+
    '" data-item="'+x.id+'" value="'+htmlEscape(expected)+'" aria-label="'+htmlEscape(x.name)+' counted amount"></td></tr>';
  }).join("");
  return '<div class="c10-section-head"><div><h2>New physical count</h2><p>Record observed quantity. The demo captures book balance as an expected snapshot.</p></div></div>'+
   '<div class="c10-pane-grid"><section class="c10-card pad"><form id="physical-count-form"><label class="c10-field">Site / physical location'+
   '<select id="count-site" name="site" required>'+options+'</select></label>'+
   '<div class="c10-table-wrap"><table class="c10-table"><thead><tr><th>Item</th><th>Unit</th><th>Book qty</th><th>Counted qty</th></tr></thead><tbody>'+
   lines+'</tbody></table></div>'+
   '<div class="c10-total"><span>Preview only · submitted count needs separate owner approval</span><strong>No ERP write</strong></div>'+
   '<button type="submit" class="c10-button primary" '+(s.role!=="staff"?'disabled':'')+'>Submit demo count</button>'+
   '</form></section><aside class="c10-card pad"><h2>Control sequence</h2><ol class="c10-steps">'+
   '<li data-n="1"><strong>Staff counts</strong>Measure each item at the selected site.</li>'+
   '<li data-n="2"><strong>Snapshot recorded</strong>The backend will check actual stock when live integration is certified.</li>'+
   '<li data-n="3"><strong>Owner approves</strong>The person who counted cannot self-approve.</li>'+
   '<li data-n="4"><strong>Adjustment posted</strong>Stale counts cannot overwrite later sales or transfers.</li>'+
   '</ol><p class="c10-small-note">Current control: '+(s.role==="staff"?"Staff demo count enabled.":"Switch to Staff role to enter a demo count.")+'</p></aside></div>';
 }
 function renderReview(s){
  if(mode!=="demo")return '<div class="c10-card pad"><h2>Owner review is release-locked</h2><p class="c10-form-help">Real approval and posting RPCs are intentionally unavailable in this preview.</p></div>';
  var pending=s.docs.filter(function(x){return x.status==="submitted"||x.status==="approved"});
  var parts=pending.map(function(d){
   var delta=diff(d),kind=d.status,actions=kind==="submitted"?
    '<button type="button" class="c10-button primary c10-compact" data-act="approve" data-id="'+d.id+'" '+(s.role!=="owner"?'disabled':'')+'>Approve demo</button>':
    '<button type="button" class="c10-button primary c10-compact" data-act="post" data-id="'+d.id+'" '+(s.role!=="owner"?'disabled':'')+'>Post demo</button>';
   return '<article class="c10-review-card"><div class="c10-review-head"><h3>Count #'+d.id+' · '+htmlEscape(siteLabel(d.siteId))+'</h3>'+badge(kind)+'</div>'+
    '<p class="c10-review-sub">'+d.lines.length+' counted items · Submitted by demo '+htmlEscape(d.actor)+'</p>'+
    '<div class="c10-review-bottom"><span class="c10-review-values">Net quantity difference <strong>'+htmlEscape(delta>0?("+"+fmt(delta)):fmt(delta))+'</strong></span>'+
    '<div class="c10-actions">'+actions+
    '<button type="button" class="c10-button danger c10-compact" data-act="void" data-id="'+d.id+'" '+(s.role!=="owner"?'disabled':'')+'>Void demo</button></div></div></article>';
  }).join("");
  return '<div class="c10-section-head"><div><h2>Owner review queue</h2><p>Approval and posting are separate actions; only simulated local changes occur.</p></div></div>'+
   '<div class="c10-review-list">'+(parts||'<div class="c10-card pad c10-empty"><strong>All clear</strong>No counts are awaiting approval or posting.</div>')+'</div>'+
   '<p class="c10-small-note">'+(s.role==="owner"?"Demo Owner can approve and post these synthetic records.":"Staff perspective: review buttons are intentionally disabled.")+'</p>';
 }
 function renderAudit(s){
  if(mode!=="demo")return '<div class="c10-card pad"><h2>Audit preview</h2><p class="c10-form-help">Live audit history requires a specific stocktake ID and signed staging read permission.</p></div>';
  var logs=s.audit.slice().reverse().map(function(e){
   return '<div class="c10-audit-row"><div><strong>'+htmlEscape(niceStatus(e.kind))+' · Count #'+e.docId+'</strong>'+
    '<small>'+htmlEscape(siteLabel(e.siteId))+' · '+htmlEscape(e.actor)+' (synthetic)</small></div><small>Event '+e.seq+'</small></div>';
  }).join("");
  return '<div class="c10-section-head"><div><h2>Audit history</h2><p>Every simulated transition is recorded in this page session only.</p></div></div>'+
   '<section class="c10-card"><div class="c10-activity">'+(logs||'<p class="c10-empty">No activity.</p>')+'</div></section>';
 }
 function render(){
  var s=demo.snapshot();
  doc.querySelectorAll("[data-role]").forEach(function(btn){
   btn.setAttribute("aria-pressed",String(btn.dataset.role===s.role));
  });
  doc.querySelectorAll("[data-screen]").forEach(function(btn){
   if(btn.dataset.screen===s.screen)btn.setAttribute("aria-current","page");
   else btn.removeAttribute("aria-current");
  });
  renderMetrics();
  if(s.screen==="overview")panel.innerHTML=renderOverview(s);
  else if(s.screen==="count")panel.innerHTML=renderCount(s);
  else if(s.screen==="review")panel.innerHTML=renderReview(s);
  else panel.innerHTML=renderAudit(s);
 }
 function inspect(id){
  var s=demo.snapshot();
  if(mode==="demo"){
   var d=s.docs.find(function(x){return x.id===Number(id)});
   if(!d){message("Count not found",true);return}
   var detail=d.lines.map(function(l){return itemLabel(l.itemId)+": "+fmt(l.expected)+" → "+fmt(l.counted)}).join(" · ");
   message("Demo #"+d.id+" ("+d.status+"): "+detail);return;
  }
  message("Staging source is read-only; use the signed adapter to request individual discrepancy details.");
 }
 async function stagedRead(){
  // Only explicitly approved separate STAGING refs may be used. No public config,
  // no automatic remote attempt, no writes, and production SG is rejected.
  var cfg=root.CORE10_STOCKTAKE_STAGE_READ;
  if(!cfg||cfg.enabled!==true||cfg.approved!==true||
    !/^[a-z0-9]{20}$/.test(String(cfg.projectRef||""))||
    cfg.projectRef==="kbuhnpqooycqbzrfejcs"||
    !Number.isSafeInteger(cfg.businessId)||cfg.businessId<1||!cfg.client||
    !root.CORE10_ENTERPRISE_CLIENT) {
   fail("READ_ONLY_STAGING_NOT_APPROVED");
  }
  var api=root.CORE10_ENTERPRISE_CLIENT.create({
   client:cfg.client,experimentalRead:true,experimentalWrite:false});
  var list=await api.listStocktakes(cfg.businessId);
  if(!Array.isArray(list))fail("INVALID_STAGE_READ_RESPONSE");
  stageAPI=api;remote=list;mode="stage";selected=cfg.businessId;
  doc.getElementById("data-source").textContent="Source: authorized staging READ ONLY";
  demo.setScreen("overview");message("Signed staging read completed. No writes are available.");render();
 }
 var stageButton=doc.getElementById("stage-read"),config=root.CORE10_STOCKTAKE_STAGE_READ;
 if(stageButton&&config&&config.enabled===true&&config.approved===true&&
  config.projectRef!=="kbuhnpqooycqbzrfejcs"&&/^[a-z0-9]{20}$/.test(String(config.projectRef||""))){
  stageButton.disabled=false;stageButton.textContent="Load signed staging READ";
  stageButton.addEventListener("click",function(){
   stagedRead().catch(function(e){message(e.code||"STAGING_READ_UNAVAILABLE",true)});
  });
 }
 doc.addEventListener("click",function(e){
  var role=e.target.closest("[data-role]"),nav=e.target.closest("[data-screen]"),
   action=e.target.closest("[data-act]");
  try{
   if(role){demo.setRole(role.dataset.role);message("");render();return}
   if(nav){demo.setScreen(nav.dataset.screen);message("");render();return}
   if(!action)return;
   var which=action.dataset.act,id=action.dataset.id;
   if(which==="inspect"){inspect(id);return}
   if(mode!=="demo")fail("STAGING_WRITES_LOCKED");
   if(which==="approve"){demo.approve(id);message("Demo approval recorded in browser memory.");}
   else if(which==="post"){demo.post(id);message("Demo adjustment posted in browser memory only.");}
   else if(which==="void"){demo.voidCount(id,"Synthetic owner void; recount required");message("Demo count voided without changing real ERP.");}
   else return;
   render();
  }catch(err){message(err.code||"DEMO_ACTION_FAILED",true)}
 });
 panel.addEventListener("change",function(e){
  if(e.target.id==="status-filter"){try{demo.setFilter(e.target.value);render()}catch(err){message(err.code,true)}}
  if(e.target.id==="count-site"){try{demo.setSite(e.target.value);render()}catch(err){message(err.code,true)}}
 });
 panel.addEventListener("submit",function(e){
  if(e.target.id!=="physical-count-form")return;
  e.preventDefault();
  try{
   if(mode!=="demo")fail("STAGING_WRITES_LOCKED");
   var site=demo.snapshot().siteId,lines=[];
   e.target.querySelectorAll("[data-item]").forEach(function(field){
    lines.push({itemId:Number(field.dataset.item),counted:field.value});
   });
   var id=demo.submit(site,lines);
   demo.setScreen("overview");
   message("Demo count #"+id+" submitted locally. Switch to Owner to approve.");
   render();
  }catch(err){message(err.code||"DEMO_COUNT_FAILED",true)}
 });
 render();
 return Object.freeze({demo:demo,render:render,stageRead:stagedRead,
  releaseStatus:function(){return Object.freeze({liveWritesEnabled:false,mode:mode,stageBusinessId:selected})}});
}
return Object.freeze({createDemo:makeDemo,validateCounts:validateCounts,mount:mount,
 sites:copy(SITES),items:copy(ITEMS),escape:htmlEscape});
});
