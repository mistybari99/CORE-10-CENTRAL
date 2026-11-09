/* CORE 10 portfolio view: presentation layer on existing org122, places135, bizctx. No database mutations. */
(function(){
"use strict";
var B=window.BOS,A=window.BOS_APP,L=window.BOS_LAZY;
if(!B||!A||!A.H||!L)return;
var categories=[
 {key:"sweets",bn:"ইসলামিয়া মিষ্টি ঘর",en:"Islamia Misty Ghar",sym:"◈",rx:/food|sweet|misty|mishti|bakery|cake|dessert|islamia|মিষ্টি|বেকারি|ইসলামিয়া|ইসলামিয়া/i},
 {key:"paint",bn:"রং ও হার্ডওয়্যার",en:"Paints & Hardware",sym:"◐",rx:/paint|colour|color|hardware|asian|berger|classic|রং|কালার|হার্ডওয়্যার/i},
 {key:"construction",bn:"কনস্ট্রাকশন",en:"Construction",sym:"▥",rx:/construct|building|civil|pwd|jabeda|নির্মাণ|কনস্ট্রাকশন/i},
 {key:"online",bn:"অনলাইন ও ডিজিটাল",en:"Online & Digital",sym:"⌘",rx:/e.?commerce|online|digital|tech|internet|web|অনলাইন|ডিজিটাল/i}
];
var other={key:"other",bn:"অন্যান্য ব্যবসা",en:"Other Businesses",sym:"▦"};
function escape(v){return String(v==null?"":v).replace(/[&<>"']/g,function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]})}
function tr(bn,en){return B.lab&&B.L?B.lab(B.L(bn,en)):bn}
function name(r){return String((A.S.lang==="en"?(r.name_en||r.name_bn):(r.name_bn||r.name_en))||r.code||"")}
function units(){var m=window.BOS_ORG122&&window.BOS_ORG122.flat();return m&&m.values?Array.from(m.values()):[]}
function chain(u,map){var a=[],seen=new Set;for(var i=0;u&&i<30&&!seen.has(String(u.id));i++){a.push(u);seen.add(String(u.id));u=u.parent_id==null?null:map.get(String(u.parent_id))}return a}
function businessFor(place,map){var n=place&&place.org_unit_id!=null?map.get(String(place.org_unit_id)):null;var found=chain(n,map).find(function(x){return x.kind==="business"});return found?String(found.id):null}
function categoryFor(biz){var s=[biz.code,biz.template_code,biz.name_bn,biz.name_en].join(" ");var f=categories.find(function(x){return x.rx.test(s)});return f?f.key:"other"}
function places(){var x=B.ENV&&(B.ENV.locsAll||B.ENV.locs);return Array.isArray(x)?x:[]}
function owner(){return !!(A.S.ctx&&A.S.ctx.is_owner)}
function groupHTML(locations){
 var groups=B.locGroups&&B.locGroups.grouped?B.locGroups.grouped(locations):[];
 var names=[["showrooms","শোরুম / ব্রাঞ্চ","Showrooms / Branches"],["factories","কারখানা","Factories"],["stores","গোডাউন / স্টোরহাউস","Godowns / Storehouses"],["other","অন্যান্য লোকেশন","Other Locations"]];
 return names.map(function(row){
   var g=groups.find(function(x){return x.key===row[0]}),items=g?g.items:[];
   if(row[0]==="other"&&!items.length)return "";
   return '<details class="ph-location" data-kind="'+row[0]+'"><summary><span>'+escape(tr(row[1],row[2]))+'</span><span class="ph-num">'+items.length+'</span></summary><div class="ph-locations">'+
     (items.length?items.map(function(p){return '<div class="ph-place"><span>'+escape(name(p))+'</span><small>'+escape(p.code||"")+'</small></div>'}).join(""):'<div class="ph-empty">'+escape(tr("এই গ্রুপে এখনো লোকেশন নেই","No locations here yet"))+'</div>')+
     '</div></details>'
 }).join("")
}
function businessHTML(biz,map,assigned){
 var linked=assigned.get(String(biz.id))||[],legal=chain(biz,map).find(function(x){return x.kind==="legal_entity"});
 return '<div class="ph-business ph-business-direct" data-biz="'+escape(biz.id)+'"><button type="button" class="ph-business-launch" data-act="ph_enter" data-v="'+escape(biz.id)+'" aria-label="'+escape(tr("ব্যবসা খুলুন","Open business")+': '+name(biz))+'">'+
 '<span class="ph-business-title"><strong>'+escape(name(biz))+'</strong>'+
 (legal?'<small>'+escape(name(legal))+'</small>':'')+'</span>'+
 '<span class="ph-business-count">'+linked.length+' '+escape(tr("লোকেশন","locations"))+'　›</span></button></div>'
}
function categoryHTML(cat,businesses,map,assigned){
 // The existing Islamia ERP is a business workspace, not a generic industry accordion.
 // Keep the business ID for navigation; the visible name does NOT mutate org_units.
 if(cat.key==="sweets"&&businesses.length===1){
   var target=businesses[0],linked=assigned.get(String(target.id))||[];
   return '<section class="ph-category ph-islamia" data-category="sweets"><button type="button" class="ph-brand-entry" data-act="ph_enter" data-v="'+escape(target.id)+'" aria-label="'+escape(tr("ইসলামিয়া মিষ্টি ঘরের ERP ও সব ব্রাঞ্চ খুলুন","Open Islamia Misty Ghar ERP and all branches"))+'">'+
     '<span class="ph-brand-head"><span class="ph-symbol" aria-hidden="true">◈</span><span class="ph-brand-name"><strong>'+escape(tr("ইসলামিয়া মিষ্টি ঘর","Islamia Misty Ghar"))+'</strong><small>'+linked.length+' '+escape(tr("টি সংযুক্ত লোকেশন","linked locations"))+'</small></span><span class="ph-brand-chevron" aria-hidden="true">›</span></span>'+
     '<span class="ph-brand-foot">'+escape(tr("সম্পূর্ণ ERP ও সব ব্রাঞ্চ খুলুন","Open full ERP and all branches"))+' <span aria-hidden="true">→</span></span></button></section>'
 }
 return '<section class="ph-category" data-category="'+cat.key+'"><div class="ph-category-top"><span class="ph-symbol" aria-hidden="true">'+cat.sym+'</span><div><h3>'+escape(cat.key==="sweets"?tr("মিষ্টি ও বেকারি ব্যবসাসমূহ","Sweets & Bakery Businesses"):tr(cat.bn,cat.en))+'</h3><small>'+businesses.length+' '+escape(tr("টি ব্যবসা","businesses"))+'</small></div></div>'+
 (businesses.length?businesses.map(function(b){return businessHTML(b,map,assigned)}).join(""):'<div class="ph-empty">'+
 escape(tr("এখনো এই বিভাগের ব্যবসা যুক্ত হয়নি","No business is configured in this category"))+
 (owner()?'<button type="button" class="ph-set" data-act="ph_addbusiness">'+escape(tr("+ ব্যবসা যোগ করুন","+ Add business"))+'</button>':"")+'</div>')+'</section>'
}
function render(){if(!owner())return;
 var host=document.getElementById("ph_overview");if(!host||!document.getElementById("og_body"))return;
 var expanded=Array.from(host.querySelectorAll(".ph-business[open]")).map(function(x){return x.dataset.biz});
 var expandedGroups=Array.from(host.querySelectorAll(".ph-location[open]")).map(function(x){return x.closest(".ph-business").dataset.biz+"|"+x.dataset.kind});
 var all=units(),map=new Map(all.map(function(x){return [String(x.id),x]}));
 var groups=all.filter(function(x){return x.kind==="group"&&x.status!=="inactive"});
 var legals=all.filter(function(x){return x.kind==="legal_entity"&&x.status!=="inactive"});
 var businesses=all.filter(function(x){return x.kind==="business"&&x.status!=="inactive"});
 var assigned=new Map;businesses.forEach(function(b){assigned.set(String(b.id),[])});
 var unlinked=0;places().forEach(function(p){var id=businessFor(p,map);if(id&&assigned.has(id))assigned.get(id).push(p);else unlinked++});
 var title="CORE 10";
 var cards=categories.map(function(cat){return categoryHTML(cat,businesses.filter(function(b){return categoryFor(b)===cat.key}),map,assigned)}).join("");
 var misc=businesses.filter(function(b){return categoryFor(b)==="other"});if(misc.length)cards+=categoryHTML(other,misc,map,assigned);
 host.innerHTML='<header class="ph-hero"><span class="ph-kicker">'+escape(tr("মাস্টার বিজনেস পোর্টফোলিও","Master Business Portfolio"))+'</span><h2>'+escape(title)+'</h2><p>'+
 escape(groups.length||legals.length?tr("সব ব্যবসার কাঠামো এক জায়গায়","All businesses under one organization"):tr("মূল প্রতিষ্ঠান এখনো সেটআপ করা হয়নি","Master organization is not configured yet"))+
 '</p><div class="ph-stats"><span><b>'+businesses.length+'</b> '+escape(tr("ব্যবসা","businesses"))+'</span><span><b>'+(places().length-unlinked)+'</b> '+escape(tr("সংযুক্ত লোকেশন","linked locations"))+'</span></div></header>'+
 (unlinked?'<div class="ph-warning">'+unlinked+" "+escape(tr("টি লোকেশন এখনো কোনো ব্যবসার সঙ্গে নিশ্চিতভাবে যুক্ত নয়। কোনো ডেটা সরানো হয়নি।","locations are not explicitly linked to a business. No data was moved."))+'</div>':"")+
 '<div class="ph-master-actions"><button type="button" class="ph-new-business" data-act="ph_addbusiness">'+escape(tr("+ নতুন ব্যবসা যোগ করুন","+ Add a business"))+'</button></div><div class="ph-grid">'+cards+'</div><div class="ph-footer-tools"><button type="button" class="ph-manage-link" data-act="ph_manage">⚙ '+escape(tr("ব্যবসার কাঠামো পরিচালনা","Manage business structure"))+'</button></div>';
 host.querySelectorAll(".ph-business").forEach(function(d){if(expanded.includes(d.dataset.biz))d.open=true});
 host.querySelectorAll(".ph-location").forEach(function(d){if(expandedGroups.includes(d.closest(".ph-business").dataset.biz+"|"+d.dataset.kind))d.open=true})
}
var observer,pending=false;
function rerender(){if(pending)return;pending=true;Promise.resolve().then(function(){pending=false;render()})}
// Portfolio and technical management are separate owner-only routes.
function managing(){return String(location.hash||"")==="#/organization/manage"}
function syncView(){
 var portfolio=document.getElementById("ph_overview"),management=document.getElementById("ph_admin");
 if(!owner()||!portfolio||!management)return;
 var manage=managing();
 portfolio.hidden=manage;management.hidden=!manage;
 if(document.body&&document.body.classList){
  document.body.classList.toggle("core10-portfolio",!manage);
  document.body.classList.toggle("core10-manage-structure",manage)
 }
 var title=document.querySelector("#app > header.top h1");
 if(title)title.textContent=manage?tr("ব্যবসার কাঠামো পরিচালনা","Business Structure Settings"):tr("CORE 10 · ব্যবসাসমূহ","CORE 10 · Businesses")
}
function enhance(){if(!owner())return;
 var top=document.getElementById("og_top"),body=document.getElementById("og_body");if(!top||!body)return;
 if(document.getElementById("ph_overview")){syncView();rerender();return}
 var parent=top.parentNode;if(!parent)return;
 var portfolio=document.createElement("section");portfolio.id="ph_overview";portfolio.setAttribute("aria-label",tr("সব ব্যবসা","All businesses"));
 var management=document.createElement("section");management.id="ph_admin";management.className="ph-admin ph-management-view";
 var toolbar=document.createElement("div");toolbar.className="ph-manage-toolbar";
 toolbar.innerHTML='<button type="button" class="ph-back" data-act="ph_portfolio">← '+escape(tr("সব ব্যবসায় ফিরুন","Back to all businesses"))+'</button><p>'+
  escape(tr("প্রতিষ্ঠান, Legal Entity ও ব্যবসার সেটআপ এখানে পরিচালনা করুন।","Manage organization, legal entities and business setup here."))+'</p>';
 management.appendChild(toolbar);
 parent.insertBefore(portfolio,top);parent.insertBefore(management,top);management.appendChild(top);management.appendChild(body);
 if(observer)observer.disconnect();observer=new MutationObserver(rerender);observer.observe(body,{childList:true});
 syncView();render()
}
function attach(){
 var pages=window.BOS_PAGES,old=pages&&pages.organization;
 if(typeof old!=="function"||old.__portfolio)return;
 var newer=async function(){var result=await old.apply(this,arguments);enhance();return result};
 newer.__portfolio=true;pages.organization=newer
}
var oldLoad=L.load;
if(typeof oldLoad==="function")L.load=function(){var route=arguments[0],value=oldLoad.apply(this,arguments);return Promise.resolve(value).then(function(v){if(route==="organization")attach();return v})};
attach();
A.H.ph_manage=function(){if(owner())location.hash="#/organization/manage"};
A.H.ph_addbusiness=function(){
 if(!owner()||!A.H.og_add)return;
 var legal=units().filter(function(x){return x.kind==="legal_entity"&&x.status!=="inactive"});
 var old=document.getElementById("ph_legal_chooser");if(old)old.remove();
 if(!legal.length){
  if(A.toast)A.toast(tr("প্রথমে Group-এর অধীনে Legal Entity তৈরি করুন।","First create a Legal Entity under your Group."));
  location.hash="#/organization/manage";return
 }
 if(legal.length===1){
  A.H.og_add({dataset:{v:String(legal[0].id)}});return
 }
 var host=document.querySelector("#ph_overview .ph-master-actions");if(!host)return;
 var chooser=document.createElement("div");chooser.id="ph_legal_chooser";chooser.className="ph-add-chooser";
 chooser.innerHTML='<label for="ph_legal_parent">'+escape(tr("কোন Legal Entity-এর অধীনে?","Which legal entity?"))+'</label>'+
  '<select id="ph_legal_parent">'+legal.map(function(x){return '<option value="'+escape(x.id)+'">'+escape(name(x))+'</option>'}).join("")+'</select>'+
  '<button type="button" class="ph-legal-confirm" data-act="ph_add_legal">'+escape(tr("পরবর্তী ধাপ","Continue"))+'</button>';
 host.appendChild(chooser)
};
A.H.ph_add_legal=function(){
 if(!owner()||!A.H.og_add)return;
 var chooser=document.getElementById("ph_legal_chooser");
 var field=chooser&&chooser.querySelector("#ph_legal_parent");
 var id=Number(field&&field.value);
 if(!Number.isSafeInteger(id)||id<=0)return;
 var legal=units().find(function(x){return Number(x.id)===id&&x.kind==="legal_entity"&&x.status!=="inactive"});
 if(!legal)return;
 chooser.remove();A.H.og_add({dataset:{v:String(legal.id)}})
};
A.H.ph_portfolio=function(){if(owner())location.hash="#/organization"};
A.H.ph_enter=async function(button){
 if(!owner()||!B.biz||!B.biz.setCur)return;
 var id=Number(button&&button.dataset&&button.dataset.v);
 if(!Number.isSafeInteger(id)||id<=0)return;
 var business=(B.biz.list?B.biz.list():[]).find(function(x){return Number(x.id)===id});
 if(!business&&typeof B.biz.reload==="function"){
  await B.biz.reload();business=(B.biz.list?B.biz.list():[]).find(function(x){return Number(x.id)===id})
 }
 if(!business||!B.biz.setCur(id))return;
 var url=new URL("index.html",window.location.href);
 url.searchParams.set("workspace",categoryFor(business)==="sweets"?"islamia":"business");
 url.searchParams.set("biz",String(id));
 url.hash="#/locations";
 window.location.assign(url.href)
};
A.H.ph_open=function(button){
 var id=Number(button.dataset.v);if(!Number.isFinite(id)||!B.biz||!B.biz.setCur||!B.biz.setCur(id))return;
 if(location.hash==="#/locations"){if(window.BOS_NAV)window.BOS_NAV.afterBiz()}else location.hash="#/locations"
};
if(B.biz&&typeof B.biz.switcherHTML==="function"&&!B.biz.__portfolio){
 var oldSwitcher=B.biz.switcherHTML;
 B.biz.switcherHTML=function(){var html=oldSwitcher.apply(this,arguments);return owner()?'<div class="ph-nav"><button type="button" data-act="go" data-v="organization">'+escape(tr("প্রতিষ্ঠান ও সব ব্যবসা","Organization & All Businesses"))+' ↗</button></div>'+html:html};
 B.biz.__portfolio=true
}
window.addEventListener("hashchange",function(){if(!/^#\/?organization(?:\/|$)/.test(location.hash)&&observer){observer.disconnect();observer=null}});
var css=[
'.ph-hero{padding:22px;border-radius:16px;background:linear-gradient(125deg,var(--ruby-deep,#61131c),var(--ruby,#a1111e));color:white;margin-bottom:14px}',
'.ph-kicker{color:#f3d6a4;font-size:.72rem;letter-spacing:.1em;text-transform:uppercase;font-weight:700}',
'.ph-hero h2{font-size:1.35rem;margin:6px 0;color:white;line-height:1.4}.ph-hero p{font-size:.86rem;color:#ffebe8;margin:0}',
'.ph-stats{display:flex;gap:17px;flex-wrap:wrap;margin-top:13px;padding-top:12px;border-top:1px solid #ffffff45;font-size:.8rem}.ph-stats b{font-size:1.1rem}',
'.ph-grid{display:grid;grid-template-columns:minmax(0,1fr);gap:12px;margin:15px 0 20px}',
'.ph-category{background:var(--card,#fff);border:1px solid var(--line,#ddd);border-radius:14px;padding:12px;min-width:0}',
'.ph-category-top{display:flex;gap:11px;align-items:center;margin:0 0 10px}.ph-category-top h3{font-size:.98rem;margin:0;color:var(--text,inherit)}',
'.ph-category-top small{display:block;font-size:.73rem;color:var(--muted,#777)}',
'.ph-symbol{width:37px;height:37px;display:flex;align-items:center;justify-content:center;flex:none;font-size:1.3rem;border-radius:10px;color:var(--ruby,#a1111e);background:color-mix(in srgb,var(--ruby,#a1111e) 9%,transparent)}',
'.ph-business,.ph-location{border:1px solid var(--line,#ddd);border-radius:10px;overflow:hidden;margin-top:7px}',
'.ph-business>summary,.ph-location>summary{list-style:none;cursor:pointer;display:flex;justify-content:space-between;align-items:center;gap:10px;padding:10px;min-height:47px}',
'.ph-business>summary::-webkit-details-marker,.ph-location>summary::-webkit-details-marker{display:none}',
'.ph-business>summary b{display:block;font-size:.86rem;overflow-wrap:anywhere}.ph-business>summary small{display:block;font-size:.72rem;color:var(--muted,#777)}',
'.ph-business-count{white-space:nowrap;color:var(--muted,#777);font-size:.81rem}.ph-business[open] .ph-business-count>span{display:inline-block;transform:rotate(180deg)}',
'.ph-business-body{padding:8px;border-top:1px solid var(--line,#ddd)}',
'.ph-location>summary{min-height:42px;font-size:.82rem;font-weight:700}',
'.ph-num{border-radius:20px;min-width:24px;padding:1px 6px;text-align:center;background:var(--bg,#eee);color:var(--muted,#777)}',
'.ph-locations{border-top:1px solid var(--line,#ddd);padding:5px 8px}.ph-place{display:flex;justify-content:space-between;gap:10px;padding:8px 0;font-size:.8rem}',
'.ph-place small{color:var(--muted,#777)}.ph-empty{padding:10px;border-radius:9px;background:var(--bg,#fafafa);font-size:.82rem;color:var(--muted,#777)}',
'.ph-set{display:block;margin-top:8px;font-size:.8rem;min-height:39px;padding:6px 10px}',
'.ph-open{display:block;width:100%;margin-top:9px;min-height:43px;padding:6px 10px;font-size:.85rem}',
'.ph-warning{margin:10px 0;padding:10px 13px;border-left:3px solid var(--gold,#bb8b30);font-size:.81rem;background:var(--card,#fff)}',
'.ph-admin{margin-top:10px;border-top:1px solid var(--line,#ddd);padding-top:9px}.ph-admin>summary{cursor:pointer;min-height:47px;padding:10px;font-weight:700;font-size:.9rem}',
'.ph-admin>#og_top,.ph-admin>#og_body{margin-top:12px}.ph-nav{padding:7px 12px 2px}.ph-nav button{display:block;width:100%;text-align:left;border:1px solid var(--line,#ddd);border-radius:9px;padding:9px 12px;min-height:45px;font-size:.86rem;font-weight:700}',
'.ph-business>summary:focus-visible,.ph-location>summary:focus-visible,.ph-admin>summary:focus-visible{outline:2px solid var(--ruby,#a1111e);outline-offset:-2px}',
'@media(min-width:900px){.ph-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.ph-hero{padding:27px}}'
].join("");
try{var style=document.createElement("style");style.id="ph-css";style.textContent=css;document.head.appendChild(style)}catch(_){}
window.BOS_PORTFOLIO={render:render,categoryFor:categoryFor,businessFor:businessFor};
})();