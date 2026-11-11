/* A047 actual signed Owner/Staff site topology UI. No mock fallback. */
(function(){"use strict";
const root=document.getElementById("topology");
if(!root)return;
const state={api:null,businesses:[],biz:null,topology:null,audit:[]};
const get=id=>document.getElementById(id);
const esc=x=>String(x==null?"":x).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const kinds={showroom:"Showrooms",factory:"Factories",godown:"Godowns",warehouse:"Warehouses",project:"Projects"};
function key(){if(!crypto||typeof crypto.randomUUID!=="function")throw Error("SECURE_REQUEST_ID_REQUIRED");return "a047-"+crypto.randomUUID().replace(/-/g,"").slice(0,25)}
function status(msg,error){const e=get("topology-status");if(e){e.textContent=msg;e.dataset.tone=error?"error":"ok"}}
function shell(){
 root.innerHTML='<div class="studio-layout"><aside class="studio-rail">'+
  '<div class="brand">CORE <b>10</b><small>CENTRAL · ENTERPRISE</small></div>'+
  '<nav aria-label="ERP navigation"><a href="./owner.html#/organization">Portfolio</a><a href="./core10-control-studio.html">Control Studio</a><a class="active" href="./core10-site-topology.html">Business & Sites</a><a href="./index.html">Business workspace</a></nav>'+
  '<div class="rail-note">A047 · D047/R126<br>Canonical Site IDs only · read and write via signed server RPC</div></aside>'+
  '<main><div class="topline"><span>ENTERPRISE / ORGANIZATION STRUCTURE</span><span class="version">A047 · DRAFT</span></div>'+
  '<div class="headline"><div><h1>Business & Site Groups</h1><p>Showrooms · Factories · Godowns · Warehouses · Projects</p></div>'+
  '<a class="return-link" href="./owner.html#/organization">← Owner workspace</a></div>'+
  '<div class="safety" role="note"><strong>Topology is not stock permission.</strong> Existing site/location IDs stay intact; grouping cannot activate or authorize stock posting. Production backend deployment and real signed staging certification remain separate.</div>'+
  '<div class="selector-line"><label>Authorized Business<select id="topology-business"><option value="">Verifying…</option></select></label>'+
  '<div class="topology-actions" style="align-items:end"><button id="topology-reload" class="outline" type="button">Refresh</button><button id="topology-bootstrap" class="primary" type="button" hidden>Initialize groups</button></div></div>'+
  '<div id="topology-status" role="status" aria-live="polite">Verifying signed session…</div>'+
  '<div class="topology-grid"><section class="topology-panel"><div class="panel-title"><h2>Operating Sites</h2><span id="topology-count">0 sites</span></div><div id="topology-list" class="topology-list"><p class="topology-empty">Select a business.</p></div></section>'+
  '<aside><section id="topology-owner-section" class="topology-panel" hidden><div class="panel-title"><h2>Create Business Group</h2></div>'+
  '<div class="topology-inner"><form id="topology-group-form" class="topology-create">'+
  '<label>Group type<select name="kind"><option value="showroom">Showroom</option><option value="factory">Factory</option><option value="godown">Godown</option><option value="warehouse">Warehouse</option><option value="project">Project</option></select></label>'+
  '<label>Group key<input name="key" pattern="[a-z][a-z0-9_]{1,39}" maxlength="40" required placeholder="north_showrooms"></label>'+
  '<label>Group label<input name="label" minlength="2" maxlength="90" required placeholder="North Zone Showrooms"></label>'+
  '<button class="primary" type="submit">Create group</button></form></div></section>'+
  '<section id="topology-audit-panel" class="topology-panel" style="margin-top:16px" hidden><div class="panel-title"><h2>Change history</h2></div><div id="topology-audit" class="topology-inner"></div></section></aside></div>'+
  '<footer>CORE 10 CENTRAL · One canonical A018 Site record · Server-scoped A047 groups · A034 authorization reconciliation pending · No live Supabase changes.</footer></main></div>';
}
function draw(){
 const data=state.topology,main=get("topology-list"),owner=data&&data.can_manage===true;
 get("topology-bootstrap").hidden=!owner;
 get("topology-owner-section").hidden=!owner;
 get("topology-audit-panel").hidden=!owner;
 if(!data){main.innerHTML='<p class="topology-empty">No signed business data loaded.</p>';return}
 const total=data.groups.reduce((a,g)=>a+g.sites.length,0);
 get("topology-count").textContent=total+" accessible sites · "+data.groups.length+" groups";
 const content=[];
 for(const g of data.groups){
  let row='<article class="topology-group"><div class="topology-heading"><div><strong>'+esc(g.label)+'</strong><small>'+esc(kinds[g.kind]||g.kind)+' · '+esc(g.group_key)+'</small></div>'+
   '<span class="topology-count">'+g.sites.length+' sites</span></div><div class="topology-sites">';
  for(const s of g.sites){
   row+='<div class="topology-site" data-site="'+s.site_id+'" data-version="'+s.version+'"><div class="line"><div><strong>'+esc(s.label)+'</strong>'+
    '<small> · #'+s.site_id+' · Version '+s.version+'</small></div><small>Location IDs: '+esc(s.locations.map(l=>l.id).join(", ")||"none")+'</small></div>';
   if(owner){
    const targets=data.groups.filter(a=>a.kind===s.kind&&a.group_id!==g.group_id);
    if(targets.length){
     row+='<div class="topology-move"><label>Move to<select class="move-target">'+
      targets.map(a=>'<option value="'+a.group_id+'">'+esc(a.label)+'</option>').join("")+
      '</select></label><label>Reason<input class="move-reason" maxlength="300" value="Owner regrouped operating site"></label>'+
      '<button type="button" class="outline" data-act="move">Move</button></div>';
    }
   }
   row+='</div>';
  }
  row+='</div>';
  if(owner)row+='<form class="topology-join" data-group="'+g.group_id+'">'+
   '<input required minlength="2" maxlength="120" name="site_name" placeholder="New '+esc(g.kind)+' site name" aria-label="New '+esc(g.kind)+' site name">'+
   '<button class="outline" type="submit">Add Site</button></form>';
  row+='</article>';
  content.push(row);
 }
 if(owner&&data.ungrouped.length)content.push('<p class="topology-empty">'+data.ungrouped.length+' existing sites not yet grouped; initialize groups to preserve their IDs.</p>');
 main.innerHTML=content.join("")||'<p class="topology-empty">No accessible groups. Only authorized owners may initialize them.</p>';
 const audit=get("topology-audit");
 if(audit&&owner)audit.innerHTML=state.audit.map(x=>
  '<p><b>'+esc(x.event_kind)+'</b> · Site '+esc(x.site_id||"—")+
  ' · v'+esc(x.before_version??"—")+' → '+esc(x.after_version??"—")+
  '<br>'+esc(x.reason)+'</p>').join("")||'<p class="topology-empty">No change history.</p>';
}
async function busy(action,button){
 if(button)button.disabled=true;
 status("Saving through signed server RPC…");
 try{await action();await reload();status("Saved and confirmed by server.");}
 catch(e){status("Server rejected or unavailable: "+String(e.code||e.message||"UNKNOWN_ERROR"),true)}
 finally{if(button)button.disabled=false}
}
async function reload(){
 if(!state.api||!state.biz)return;
 state.topology=await state.api.read(state.biz);
 state.audit=state.topology.can_manage?await state.api.audit(state.biz):[];
 draw();status("Authorized structure loaded. Site IDs are canonical.");
}
async function init(){
 shell();
 get("topology-business").addEventListener("change",async e=>{
  state.biz=Number(e.target.value)||null;state.topology=null;draw();
  try{await reload()}catch(err){status("Read denied or server not deployed: "+String(err.code||err.message),true)}
 });
 get("topology-reload").addEventListener("click",async()=>{try{await reload()}catch(e){status(String(e.code||e.message),true)}});
 get("topology-bootstrap").addEventListener("click",e=>busy(()=>state.api.bootstrap(state.biz,key()),e.target));
 get("topology-group-form").addEventListener("submit",e=>{
  e.preventDefault();const f=new FormData(e.target);
  busy(()=>state.api.addGroup(state.biz,String(f.get("kind")),String(f.get("key")),String(f.get("label")),key()),e.target.querySelector("button"));
 });
 get("topology-list").addEventListener("submit",e=>{
  const form=e.target.closest("form[data-group]");if(!form)return;
  e.preventDefault();const f=new FormData(form);
  busy(()=>state.api.addSite(state.biz,Number(form.dataset.group),String(f.get("site_name")),key()),form.querySelector("button"));
 });
 get("topology-list").addEventListener("click",e=>{
  const button=e.target.closest("button[data-act=move]");if(!button)return;
  const row=button.closest("[data-site]");
  const group=Number(row.querySelector(".move-target").value);
  const reason=row.querySelector(".move-reason").value;
  busy(()=>state.api.move(Number(row.dataset.site),group,Number(row.dataset.version),key(),reason),button);
 });
 try{
  const cfg=window.BOS_CONFIG,lib=window.supabase;
  if(!cfg||!cfg.url||!cfg.key||!lib||typeof lib.createClient!=="function")
   throw Error("SIGNED_CLIENT_CONFIGURATION_MISSING");
  state.api=window.CORE10_SITE_TOPOLOGY_API.create({client:lib.createClient(cfg.url,cfg.key)});
  state.businesses=await state.api.businesses();
  const wanted=new URLSearchParams(location.search).get("biz");
  const list=state.businesses.filter(x=>!wanted||String(x.id)===wanted);
  if(!list.length)throw Error("NO_AUTHORIZED_BUSINESS");
  const select=get("topology-business");select.replaceChildren();
  for(const b of list){const op=document.createElement("option");op.value=String(b.id);
   op.textContent=b.slug+" · #"+b.id;select.appendChild(op)}
  state.biz=list[0].id;await reload();
 }catch(e){status("Cannot start signed topology: "+String(e.code||e.message||"ACCESS_DENIED"),true)}
}
init();
})();
