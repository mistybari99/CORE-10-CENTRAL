/* CORE 10 · Owner Site Operations read-only workspace.
 * Reuses current authenticated BOS business context; no direct data writes.
 */
(function(w){
 "use strict";
 var d=w.document;
 function esc(v){return String(v==null?"":v).replace(/[&<>"']/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]})}
 function tr(bn,en){return w.BOS_APP&&w.BOS_APP.S&&w.BOS_APP.S.lang==="en"?en:bn}
 function owner(){var a=w.BOS_APP;return !!(a&&a.S&&a.S.ctx&&a.S.ctx.is_owner)}
 function places(){var e=w.BOS&&w.BOS.ENV;return e&&Array.isArray(e.locsAll)?e.locsAll:e&&Array.isArray(e.locs)?e.locs:[]}
 function group(p){var k=String(p.kind||p.place_kind||"").toLowerCase();
  if(["showroom","branch","retail","retail_shop"].includes(k))return "showroom";
  if(["factory","production","production_house"].includes(k))return "factory";
  if(["godown","warehouse","store","storehouse","storage"].includes(k))return "godown";
  return "other";
 }
 function render(){
  var host=d.getElementById("ph_overview");
  if(!host||!owner()){var old=d.getElementById("c10-site-workspace");if(old)old.remove();return}
  var section=d.getElementById("c10-site-workspace");
  if(!section){section=d.createElement("section");section.id="c10-site-workspace";section.className="c10-site-workspace";host.appendChild(section)}
  var all=places(),groups={showroom:[],factory:[],godown:[],other:[]};
  all.forEach(function(p){groups[group(p)].push(p)});
  var entries=[["showroom","শোরুম / ব্রাঞ্চ","Showrooms / Branches"],["factory","ফ্যাক্টরি","Factories"],["godown","গোডাউন","Godowns"],["other","অন্যান্য","Other"]];
  var signature=all.map(function(p){return [p.id,p.kind,p.place_kind,p.name_bn,p.name_en].join(":")}).join("|")+"|"+(w.BOS_APP.S.lang||"");
  if(section.dataset.signature===signature)return;
  section.dataset.signature=signature;
  section.innerHTML='<div class="c10-site-heading"><div><small>CORE 10 · SITE OPERATIONS</small><h3>'+esc(tr("অপারেটিং সাইট ও লোকেশন","Operating Sites & Locations"))+'</h3><p>'+esc(tr("বিদ্যমান লোকেশনের রিড-অনলি সারাংশ। নতুন Site mapping এখনো সার্ভারে চালু হয়নি।","Read-only overview of existing locations. New site mapping is not yet active on the server."))+'</p></div><button type="button" id="c10-site-open">'+esc(tr("লোকেশন পরিচালনা","Manage locations"))+'</button></div><div class="c10-site-grid">'+entries.map(function(x){return '<article><strong>'+groups[x[0]].length+'</strong><span>'+esc(tr(x[1],x[2]))+'</span></article>'}).join("")+'</div><details><summary>'+esc(tr("সব লোকেশন দেখুন","View all locations"))+'</summary><div class="c10-site-list">'+entries.map(function(x){return groups[x[0]].map(function(p){return '<div><span>'+esc(p.name_bn||p.name_en||p.code||p.id)+'</span><small>'+esc(tr(x[1],x[2]))+'</small></div>'}).join("")}).join("")+'</div></details>';
  var button=d.getElementById("c10-site-open");
  if(button)button.addEventListener("click",function(){w.location.hash="#/locations"});
 }
 function start(){
  if(!d.body)return;
  var pending=false;
  var observer=new MutationObserver(function(){if(pending)return;pending=true;Promise.resolve().then(function(){pending=false;render()})});
  observer.observe(d.getElementById("app")||d.body,{childList:true,subtree:true});
  w.addEventListener("hashchange",render);
  render();
 }
 if(d.readyState==="loading")d.addEventListener("DOMContentLoaded",start,{once:true});else start();
})(window);
