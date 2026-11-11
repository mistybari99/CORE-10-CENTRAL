/* C10-A049: real signed workflow page, production plan cannot fake stock output. */
(function(){"use strict";
const root=document.getElementById("operations");if(!root)return;
const st={api:null,biz:null,businesses:[],catalog:null,orders:[]};
const $=x=>document.getElementById(x);
const esc=x=>String(x??"").replace(/[&<>"']/g,s=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[s]));
const key=()=>{if(!crypto?.randomUUID)throw Error("SECURE_ID_REQUIRED");return "a049-"+crypto.randomUUID().replaceAll("-","")};
function status(s,error){$("op-status").textContent=s;$("op-status").dataset.error=error?"true":"false"}
function shell(){root.innerHTML='<div class="studio-layout"><aside class="studio-rail"><div class="brand">CORE <b>10</b><small>CENTRAL · OPERATIONS</small></div>'+
 '<nav><a href="./core10-owner-portfolio.html">Portfolio</a><a href="./core10-inventory-operations.html">Inventory</a><a class="active" href="./core10-operational-flow.html">Purchase & Sales</a></nav>'+
 '<div class="rail-note">A049 · Same A048 stock command ledger, no shadow accounting</div></aside><main>'+
 '<div class="topline"><span>ENTERPRISE / PURCHASE · STOCK · SALES</span><span class="version">A049 · DRAFT</span></div>'+
 '<div class="headline"><div><h1>Operational Orders</h1><p>One connected purchase, receiving and sales flow per Business</p></div>'+
 '<a class="return-link" href="./owner.html#/organization">← Owner</a></div>'+
 '<div class="safety"><b>Financial figures are estimates only.</b> Production plans cannot be posted until the A027 BOM engine is integrated. No certified COGS, tax, revenue or accounting ledger is posted here.</div>'+
 '<div class="selector-line"><label>Authorized Business<select id="op-business"><option>Connecting…</option></select></label>'+
 '<button class="outline" id="op-reload" type="button">Refresh</button></div>'+
 '<div id="op-status" class="op-status" role="status" aria-live="polite"></div>'+
 '<div class="op-grid"><section class="op-panel"><h2>Orders</h2><div id="op-orders"></div></section>'+
 '<section class="op-panel"><h2>Create order</h2><form id="op-form" class="op-form">'+
 '<label>Workflow<select name="kind"><option value="purchase_receive">Purchase / Receive</option>'+
 '<option value="sale_issue">Sale / Issue</option><option value="production_plan">Production plan (preview)</option></select></label>'+
 '<label>Site / Location<select name="location"></select></label><label>Item<select name="item"></select></label>'+
 '<label>Quantity<input type="number" name="quantity" min=".001" step=".001" required></label>'+
 '<label>Estimated unit value (BDT)<input type="number" name="unit" min="0" step=".01" value="0" required></label>'+
 '<label>External reference<input name="external" maxlength="120" placeholder="PO-001 / SALE-001"></label>'+
 '<button type="submit" class="primary">Save draft</button></form>'+
 '<p class="op-muted">Stock movements are committed only by the server after confirm + post.</p></section></div>'+
 '<footer>CORE 10 CENTRAL · Operational sources in Draft PR only · not live Supabase</footer></main></div>';
}
async function load(){
 const p=await st.api.catalog(st.biz);st.catalog=p;
 const o=await st.api.read(st.biz);st.orders=o.items;
 $("op-form").elements.location.innerHTML=p.locations.map(l=>'<option value="'+l.id+'">Site '+l.site_id+' / Location '+l.id+'</option>').join("");
 $("op-form").elements.item.innerHTML=p.items.map(i=>'<option value="'+i.id+'">'+esc(i.sku)+' #'+i.id+'</option>').join("");
 $("op-orders").innerHTML=o.items.length?o.items.map(order=>
  '<article class="op-record" data-order="'+order.id+'" data-version="'+order.version+'">'+
  '<strong>'+esc(order.kind)+' · '+esc(order.quantity)+' units</strong>'+
  '<small>#'+order.id+' · '+esc(order.status)+' · Estimate ৳'+esc(order.estimate_total)+'</small>'+
  (order.status==="draft"?'<button class="outline" data-action="confirm" type="button">Confirm</button>':
  order.status==="confirmed"&&order.kind!=="production_plan"?'<button class="primary" data-action="post" type="button">Post stock</button>':
  order.kind==="production_plan"&&order.status==="confirmed"?'<small>Awaiting A027 production integration</small>':'')+
  '</article>').join(""):'<p class="op-muted">No orders in this Business scope.</p>';
 status("Signed server workflow loaded. Financial posting remains disabled.");
}
async function init(){
 shell();
 $("op-business").addEventListener("change",async e=>{st.biz=Number(e.target.value);
  try{await load()}catch(err){status(String(err.code||err.message),true)}});
 $("op-reload").addEventListener("click",async()=>{try{await load()}catch(err){status(String(err.code||err.message),true)}});
 $("op-form").addEventListener("submit",async e=>{
  e.preventDefault();const f=e.target,btn=f.querySelector("button");btn.disabled=true;
  try{
   const r=await st.api.draft(st.biz,f.elements.location.value,f.elements.item.value,
    f.elements.kind.value,f.elements.quantity.value,f.elements.unit.value,f.elements.external.value,key());
   await load();status("Draft #"+r.order_id+" persisted by server.");
  }catch(err){status("Server rejected: "+String(err.code||err.message),true)}finally{btn.disabled=false}
 });
 $("op-orders").addEventListener("click",async e=>{
  const b=e.target.closest("button[data-action]");if(!b)return;
  const rec=b.closest("[data-order]");b.disabled=true;
  try{
   const r=await st.api.advance(Number(rec.dataset.order),b.dataset.action,Number(rec.dataset.version),key());
   await load();status("Server returned "+r.status+" for order #"+r.order_id);
  }catch(err){status("Server refused: "+String(err.code||err.message),true)}finally{b.disabled=false}
 });
 try{
  const cfg=window.BOS_CONFIG,lib=window.supabase;
  if(!cfg?.url||!cfg?.key||!lib?.createClient)throw Error("SIGNED_CONFIG_REQUIRED");
  st.api=window.CORE10_OPERATIONS_API.create({client:lib.createClient(cfg.url,cfg.key)});
  const list=await st.api.businesses(),want=new URLSearchParams(location.search).get("biz");
  st.businesses=list.filter(b=>!want||String(b.id)===want);
  if(!st.businesses.length)throw Error("NO_AUTHORIZED_BUSINESS");
  $("op-business").innerHTML=st.businesses.map(x=>'<option value="'+x.id+'">'+esc(x.slug)+' #'+x.id+'</option>').join("");
  st.biz=st.businesses[0].id;await load();
 }catch(err){status("Cannot load signed operations: "+String(err.code||err.message),true)}
}
init();
})();
