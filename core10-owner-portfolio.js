/* CORE10 A050: no simulated data in actual app; signed server RPC only. */
(function(){"use strict";
const root=document.getElementById("portfolio");if(!root)return;
const state={api:null,businesses:[],chosen:null};
const el=id=>document.getElementById(id);
const esc=v=>String(v==null?"":v).replace(/[&<>"']/g,s=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[s]));
const labels={sites:"Sites",operations:"Operations",modules:"Modules",governance:"Governance"};
function status(v,bad){if(el("pf-status")){el("pf-status").textContent=v;el("pf-status").dataset.bad=bad?"true":"false"}}
function shell(){root.innerHTML='<div class="studio-layout"><aside class="studio-rail">'+
 '<div class="brand">CORE <b>10</b><small>CENTRAL · ENTERPRISE</small></div>'+
 '<nav aria-label="Owner navigation"><a class="active" href="./core10-owner-portfolio.html">Portfolio</a>'+
 '<a href="./core10-control-studio.html">Control Studio</a><a href="./index.html">Business workspace</a></nav>'+
 '<div class="rail-note">A050 / D047 · Single canonical data scope · Demo built, not production</div></aside>'+
 '<main><div class="topline"><span>MASTER OWNER / BUSINESS PORTFOLIO</span><span class="version">DRAFT · A050</span></div>'+
 '<div class="headline"><div><h1>Enterprise Overview</h1><p>Every authorized Business, Site, module and workflow—one source of truth.</p></div>'+
 '<a class="return-link" href="./owner.html#/organization">← Central</a></div>'+
 '<div class="safety"><strong>Source-built ≠ live.</strong> A048/A049 isolated ERP flows and A045/A047 Draft PRs need integration and production gates. Hidden or pinned navigation never grants server permissions.</div>'+
 '<div class="selector-line"><label>Authorized Business<select id="pf-business"><option>Connecting…</option></select></label>'+
 '<div class="pf-kpis"><div class="pf-kpi"><small>Businesses</small><strong id="pf-business-count">0</strong></div>'+
 '<div class="pf-kpi"><small>Sites</small><strong id="pf-sites-count">0</strong></div>'+
 '<div class="pf-kpi"><small>Operations</small><strong id="pf-orders-count">0</strong></div></div></div>'+
 '<div id="pf-status" class="pf-status" role="status" aria-live="polite"></div>'+
 '<div class="pf-grid"><section class="pf-panel"><div class="pf-head"><h2 id="pf-title">Business View</h2><small id="pf-meta"></small></div>'+
 '<div class="pf-content" id="pf-sections"></div></section>'+
 '<aside><section class="pf-panel"><div class="pf-head"><h2>Workspace Configuration</h2></div>'+
 '<div class="pf-content" id="pf-layout"></div></section>'+
 '<section class="pf-panel" style="margin-top:15px"><div class="pf-head"><h2>Module Status</h2></div>'+
 '<div class="pf-content"><p class="pf-muted">Only actually tested server paths count. Production, GoTrue and live stock release are separate gates.</p>'+
 '<div id="pf-release" class="pf-muted"></div></div></section></aside></div>'+
 '<footer>CORE 10 CENTRAL · Owner Control Studio and site grouping use the same canonical IDs · No live migrations.</footer></main></div>';
}
function render(){
 const b=state.chosen;if(!b)return;
 el("pf-business-count").textContent=state.businesses.length;
 el("pf-sites-count").textContent=b.sites.length;
 el("pf-orders-count").textContent=b.operations_count;
 el("pf-title").textContent=b.name;
 el("pf-meta").textContent="Business #"+b.business_id+" · Tenant "+b.tenant_id;
 const cards={
 sites:()=>'<section class="pf-block"><h3>Operating Sites</h3>'+
 (b.sites.length?b.sites.map(s=>'<div class="pf-group"><h3>'+esc(s.label)+'</h3><div class="pf-place"><span>'+esc(s.kind)+
 ' · Site #'+s.site_id+'</span><small>Canonical locations: '+esc(s.locations.map(l=>l.id).join(", ")||"None")+'</small></div></div>').join(""):
 '<p class="pf-muted">No authorized sites.</p>')+'</section>',
 operations:()=>'<section class="pf-block"><h3>Purchase / Sales Operations</h3><p class="pf-muted">'+
 esc(b.operations_count)+' scoped orders · Isolated SQL only; open operational UI after deployment integration.</p></section>',
 modules:()=>'<section class="pf-block"><h3>Modules</h3>'+
 (b.modules.length?b.modules.map(m=>'<span class="pf-chip">'+esc(m.code)+' · '+esc(m.visibility)+
 (m.operational_enabled?" · enabled":" · not enabled")+'</span>').join(""):
 '<p class="pf-muted">No enabled or authorized modules.</p>')+'</section>',
 governance:()=>'<section class="pf-block"><h3>Governance & Controls</h3><p class="pf-muted">'+
 (b.can_manage?'Owner configuration available. A045 Workshop & A047 Groups are separate unmerged Draft PRs.':'Business scope only. Editing Owner policy is unavailable.')+
 '</p><a href="./core10-control-studio.html">Control Studio</a></section>'
 };
 el("pf-sections").innerHTML=b.layout.sections.map(s=>cards[s]?.()||"").join("");
 el("pf-release").textContent=Object.entries(b.runtime).map(([k,v])=>k+": "+v).join(" · ");
 el("pf-layout").innerHTML=b.can_manage?'<form id="pf-form" class="pf-layout-form">'+
 '<label>View density<select name="mode"><option value="detailed" '+(b.layout.mode==="detailed"?"selected":"")+'>Detailed</option>'+
 '<option value="compact" '+(b.layout.mode==="compact"?"selected":"")+'>Compact</option></select></label>'+
 '<fieldset><legend>Visible sections</legend>'+["sites","operations","modules","governance"].map(k=>
 '<label><input type="checkbox" name="section" value="'+k+'" '+(b.layout.sections.includes(k)?"checked":"")+'>'+labels[k]+'</label>').join("")+
 '</fieldset><button class="primary" type="submit">Save layout</button>'+
 '<p class="pf-muted">Layout is personal to this Business only. Removing a section never removes a permission or record.</p></form>':
 '<p class="pf-muted">Read only: changing this Business layout requires effective Owner permission.</p>';
}
async function read(){
 const result=await state.api.read();state.businesses=result.businesses;
 const query=new URLSearchParams(location.search).get("biz");
 if(query && !state.businesses.some(b=>String(b.business_id)===query))throw Error("BUSINESS_NOT_AUTHORIZED");
 const current=state.chosen&&state.chosen.business_id;
 state.chosen=state.businesses.find(b=>b.business_id===current)||
  state.businesses.find(b=>String(b.business_id)===query)||state.businesses[0]||null;
 const select=el("pf-business");select.replaceChildren();
 for(const b of state.businesses){const o=document.createElement("option");
  o.value=String(b.business_id);o.textContent=b.name+" · #"+b.business_id;select.appendChild(o)}
 if(!state.chosen)throw Error("NO_AUTHORIZED_BUSINESS");
 select.value=String(state.chosen.business_id);render();
 status("Loaded authorized portfolio from server.");
}
async function init(){
 shell();
 el("pf-business").addEventListener("change",e=>{
  state.chosen=state.businesses.find(b=>b.business_id===Number(e.target.value));render()});
 el("pf-layout").addEventListener("submit",async e=>{
  if(e.target.id!=="pf-form")return;e.preventDefault();
  const b=state.chosen,form=e.target;
  const sections=Array.from(form.querySelectorAll("[name=section]:checked")).map(x=>x.value);
  const submit=form.querySelector("button");submit.disabled=true;
  try{
   if(!sections.length)throw Error("SELECT_AT_LEAST_ONE_SECTION");
   const k="a050-"+crypto.randomUUID().replaceAll("-","").slice(0,28);
   await state.api.layout(b.business_id,form.elements.mode.value,sections,b.layout.version,k);
   await read();status("Layout saved and reloaded from server.");
  }catch(err){status("Denied or stale: "+String(err.code||err.message),true)}
  finally{submit.disabled=false}
 });
 try{
  const cfg=window.BOS_CONFIG,lib=window.supabase;
  if(!cfg||!cfg.url||!cfg.key||!lib||typeof lib.createClient!=="function")throw Error("SIGNED_CLIENT_CONFIGURATION_MISSING");
  state.api=window.CORE10_PORTFOLIO_API.create({client:lib.createClient(cfg.url,cfg.key)});
  await read();
 }catch(err){status("Cannot load real portfolio: "+String(err.code||err.message),true)}
}
init();
})();
