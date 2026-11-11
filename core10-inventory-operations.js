/* A048 live UI asks server, never keeps shadow quantity or grants in the browser. */
(function(){"use strict";
const root=document.getElementById("inventory");if(!root)return;
const apiState={api:null,biz:null,businesses:[],catalog:null,commands:[]};
const $=id=>document.getElementById(id);
const esc=v=>String(v??"").replace(/[&<>"']/g,s=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[s]));
const makeKey=()=>{if(!crypto?.randomUUID)throw Error("SECURE_UUID_REQUIRED");return "a048-"+crypto.randomUUID().replaceAll("-","")};
function status(message,error){$("iv-status").textContent=message;$("iv-status").dataset.error=error?"true":"false"}
function shell(){root.innerHTML='<div class="studio-layout"><aside class="studio-rail"><div class="brand">CORE <b>10</b><small>CENTRAL · OPERATIONS</small></div>'+
 '<nav><a href="./core10-owner-portfolio.html">Portfolio</a><a class="active" href="./core10-inventory-operations.html">Inventory</a><a href="./index.html">Business</a></nav><div class="rail-note">D047/A048 · Canonical A018 ledger</div></aside>'+
 '<main><div class="topline"><span>STOCK / RECEIVE · ISSUE · TRANSFER · ADJUST</span><span class="version">A048 · DRAFT</span></div>'+
 '<div class="headline"><div><h1>Inventory Commands</h1><p>Draft, confirm and post safely through the server</p></div><a class="return-link" href="./owner.html#/organization">← Owner</a></div>'+
 '<div class="safety">Posting requires effective site-level authorization. Negative stock, unknown sites and duplicate movements are rejected. This isolated source is not a production Supabase release.</div>'+
 '<div class="selector-line"><label>Authorized business<select id="iv-business"><option value="">Verifying…</option></select></label>'+
 '<button type="button" class="outline" id="iv-refresh">Refresh</button></div>'+
 '<div id="iv-status" class="iv-status" role="status" aria-live="polite"></div>'+
 '<div class="iv-grid"><section class="iv-panel"><h2>Current commands</h2><div id="iv-list"></div></section>'+
 '<section class="iv-panel"><h2>New stock command</h2>'+
 '<form class="iv-form" id="iv-form"><label>Action<select name="kind">'+
 ['receive','issue','transfer','adjust_in','adjust_out'].map(k=>'<option value="'+k+'">'+k.replace("_"," ")+'</option>').join("")+'</select></label>'+
 '<label>Source location<select name="source"><option value="">Not applicable</option></select></label>'+
 '<label>Destination location<select name="destination"><option value="">Not applicable</option></select></label>'+
 '<label>Item<select name="item"></select></label>'+
 '<label>Quantity<input type="number" min=".001" max="1000000" step=".001" name="quantity" required placeholder="0.000"></label>'+
 '<button class="primary" type="submit">Create draft</button></form><p class="iv-meta">Adjustments require Owner approval. Staff privileges come from server grants, not page buttons.</p></section></div>'+
 '<footer>CORE 10 CENTRAL · Not live · A034 governance integration and actual GoTrue verification pending</footer></main></div>';
}
function itemLocOptions(){return '<option value="">Not applicable</option>'+apiState.catalog.locations.map(l=>
 '<option value="'+l.id+'">#'+l.id+' / site '+l.site_id+' / '+esc(l.code)+'</option>').join("")}
async function load(){
 apiState.catalog=await apiState.api.catalog(apiState.biz);
 const data=await apiState.api.read(apiState.biz);apiState.commands=data.items;
 const src=$("iv-form").elements.source,dst=$("iv-form").elements.destination,item=$("iv-form").elements.item;
 src.innerHTML=itemLocOptions();dst.innerHTML=itemLocOptions();
 item.innerHTML=apiState.catalog.items.map(i=>'<option value="'+i.id+'">'+esc(i.sku)+' #'+i.id+'</option>').join("");
 const cards=apiState.commands.map(x=>'<article class="iv-card" data-id="'+x.id+'" data-version="'+x.version+'">'+
 '<strong>'+esc(x.kind)+' · '+esc(x.quantity)+' units</strong>'+
 '<small>#'+x.id+' / '+esc(x.status)+' · item '+x.item_id+' · location '+esc(x.source_location||x.destination_location)+'</small>'+
 (x.status==='draft'?'<div class="buttons"><button class="outline" data-action="confirm">Confirm</button></div>':
 x.status==='confirmed'?'<div class="buttons"><button class="primary" data-action="post">Post to stock</button></div>':'')+'</article>');
 $("iv-list").innerHTML=cards.join("")||'<p class="iv-meta">No commands for this authorized business.</p>';
 status("Server-confirmed commands loaded.");
}
async function init(){
 shell();$("iv-business").addEventListener("change",async ev=>{
  apiState.biz=Number(ev.target.value);try{await load()}catch(e){status("Scope denied: "+String(e.code||e.message),true)}});
 $("iv-refresh").addEventListener("click",async()=>{try{await load()}catch(e){status(String(e.code||e.message),true)}});
 $("iv-form").addEventListener("submit",async e=>{
  e.preventDefault();const f=e.target,btn=f.querySelector("button");btn.disabled=true;
  try{
   const kind=f.elements.kind.value;
   const source=["issue","transfer","adjust_out"].includes(kind)?f.elements.source.value:null;
   const dest=["receive","transfer","adjust_in"].includes(kind)?f.elements.destination.value:null;
   const r=await apiState.api.draft(apiState.biz,kind,source,dest,f.elements.item.value,f.elements.quantity.value,makeKey());
   await load();status("Draft #"+r.command_id+" created on server.");
  }catch(err){status("Rejected: "+String(err.code||err.message),true)}finally{btn.disabled=false}
 });
 $("iv-list").addEventListener("click",async e=>{
  const btn=e.target.closest("button[data-action]");if(!btn)return;
  const card=btn.closest("[data-id]");btn.disabled=true;
  try{
   const result=await apiState.api.advance(Number(card.dataset.id),btn.dataset.action,Number(card.dataset.version),makeKey());
   await load();status("Server confirmed "+result.status+" for #"+result.command_id);
  }catch(err){status("Denied or stale: "+String(err.code||err.message),true)}finally{btn.disabled=false}
 });
 try{
  const cfg=window.BOS_CONFIG,lib=window.supabase;
  if(!cfg?.url||!cfg?.key||!lib?.createClient)throw Error("SIGNED_CLIENT_CONFIG_MISSING");
  apiState.api=window.CORE10_INVENTORY_API.create({client:lib.createClient(cfg.url,cfg.key)});
  apiState.businesses=await apiState.api.businesses();
  const requested=new URLSearchParams(location.search).get("biz");
  const allowed=apiState.businesses.filter(b=>!requested||String(b.id)===requested);
  if(!allowed.length)throw Error("NO_AUTHORIZED_BUSINESS");
  $("iv-business").innerHTML=allowed.map(b=>'<option value="'+b.id+'">'+esc(b.slug)+' #'+b.id+'</option>').join("");
  apiState.biz=allowed[0].id;await load();
 }catch(err){status("Cannot open signed Inventory: "+String(err.code||err.message),true)}
}
init();
})();
