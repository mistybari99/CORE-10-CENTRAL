/* CORE 10: owner-only master shell. Tenant-specific identity for assigned staff.
   Presentation-level isolation; authorization and RLS must also be enforced server-side. */
(function(){
"use strict";
var B=window.BOS,A=window.BOS_APP,L=window.BOS_LAZY;
if(!B||!A||!A.S||!B.biz||!B.ENV)return;
var MASTER={bn:"CORE 10",en:"CORE 10"},PRIVATE={bn:"আপনার ব্যবসা",en:"Your Business"};
var isOwner=function(){return !!(A.S.ctx&&A.S.ctx.is_owner)};
var isStaff=function(){return !!(A.S.ctx&&!A.S.ctx.is_owner)};
var originalBrand=B.biz.brand.bind(B.biz);
var originalList=B.biz.list.bind(B.biz);
var originalCur=B.biz.cur.bind(B.biz);
var originalSetCur=B.biz.setCur.bind(B.biz);
var originalSwitcher=B.biz.switcherHTML.bind(B.biz);
var originalBrandFor=typeof B.biz.brandFor==="function"?B.biz.brandFor.bind(B.biz):null;
var descLocs=Object.getOwnPropertyDescriptor(B.ENV,"locs");
var descAll=Object.getOwnPropertyDescriptor(B.ENV,"locsAll");
function allLocations(){
 try{return descAll&&descAll.get?descAll.get.call(B.ENV):[]}catch(_){return []}
}
function assignedIds(){
 var ctx=A.S.ctx;return new Set((ctx&&Array.isArray(ctx.locations)?ctx.locations:[]).map(function(v){return Number(v&&typeof v==="object"?v.id:v)}).filter(Number.isFinite))
}
function scopedLocations(){
 if(!isStaff())return allLocations();
 ensureVerifiedLocations();
 // Wait for every location mapping, not just the first successful RPC.
 // One missing or conflicting assignment invalidates the entire staff scope.
 if(!verifyReady||verifiedLocations.size!==assignedIds().size)return [];
 var distinct=new Set(verifiedLocations.values());
 if(distinct.size!==1)return [];
 return allLocations().filter(function(loc){return verifiedLocations.has(Number(loc.id))})
}
/* Server-verified mapping only. Never trust bizctx's first-business fallback. */
var verifiedLocations=new Map(),verifiedKey="",verifyPromise=null,verifyReady=false;
function ensureVerifiedLocations(){
 var ctx=A.S.ctx;if(!ctx||ctx.is_owner||!ctx.profile||!ctx.profile.id||!A.sb||typeof A.sb.rpc!=="function")return;
 var ids=Array.from(assignedIds()).sort(function(a,b){return a-b});
 var key=String(ctx.profile.id)+":"+ids.join(",");
 if(key===verifiedKey)return;
 verifiedKey=key;verifiedLocations=new Map();verifyReady=false;
 verifyPromise=Promise.all(ids.map(function(id){
  return Promise.resolve().then(function(){return A.sb.rpc("org_unit_scope",{p_location:id})})
   .then(function(reply){
    var data=reply&&!reply.error?reply.data:null;
    if(data&&data.mapped===true&&data.business_id!==null&&data.business_id!==undefined){
      var businessId=Number(data.business_id);
      if(Number.isSafeInteger(businessId)&&businessId>0&&verifiedKey===key)verifiedLocations.set(id,businessId)
    }
   },function(){/* denied/unavailable => no assignment */})
 })).then(function(){
  if(verifiedKey!==key)return;
  verifyReady=true;
  synchronizeStaff();schedule();
  // Re-check visible location UI only after server verification completes.
  // Do not read another business when a mapping is absent or ambiguous.
  if(window.location&&/^#\/?locations(?:\/|$)/.test(window.location.hash||"")){
   try{window.dispatchEvent(new Event("bos:biz"))}catch(_){}
  }
 },function(){/* fail closed */});
}
function allowedBusinesses(){
 if(!isStaff())return originalList();
 ensureVerifiedLocations();
 if(!verifyReady||verifiedLocations.size!==assignedIds().size)return [];
 var ids=new Set();
 assignedIds().forEach(function(id){if(verifiedLocations.has(id))ids.add(verifiedLocations.get(id))});
 // One staff scope cannot mix unrelated businesses. Multiple branches within one
 // business are valid, but cross-business mappings must fail closed.
 if(ids.size!==1)return [];
 return originalList().filter(function(biz){return ids.has(Number(biz.id))});
}
function synchronizeStaff(){
 if(!isStaff())return;
 var permitted=allowedBusinesses();
 if(permitted.length&&permitted.every(function(item){return String(item.id)!==String(originalCur())})){
   originalSetCur(permitted[0].id);
 }
}
if(descLocs&&descLocs.configurable){
 Object.defineProperty(B.ENV,"locs",{configurable:true,enumerable:true,
  get:function(){return isStaff()?scopedLocations():descLocs.get.call(B.ENV)},
  set:function(value){if(descLocs.set)descLocs.set.call(B.ENV,value)}
 });
}
if(descAll&&descAll.configurable){
 Object.defineProperty(B.ENV,"locsAll",{configurable:true,enumerable:true,
  get:function(){return isStaff()?scopedLocations():allLocations()}
 });
}
B.biz.list=function(){return allowedBusinesses()};
B.biz.multi=function(){return isOwner()&&originalList().length>1};
B.biz.isAll=function(){return isStaff()?false:B.biz.cur()==="all"};
B.biz.setCur=function(value){return isStaff()?false:originalSetCur(value)};
B.biz.brand=function(){
 if(isOwner())return originalBrand();
 if(!isStaff())return originalBrand();
 var permitted=allowedBusinesses();
 if(!permitted.length)return PRIVATE;
 if(permitted.length&&permitted.every(function(x){return String(x.id)!==String(originalCur())}))synchronizeStaff();
 return originalBrand()
};
if(originalBrandFor)B.biz.brandFor=function(locId){
 if(isStaff()&&!scopedLocations().some(function(loc){return Number(loc.id)===Number(locId)}))return PRIVATE;
 return originalBrandFor(locId)
};
B.biz.switcherHTML=function(){return isStaff()||isOwnerBusinessWorkspace()?"":originalSwitcher()};
function ownerWorkspaceKind(){
 if(!isOwner()||!document.body||document.body.dataset.core10Owner==="1")return "";
 var search=window.location&&window.location.search||"";
 var match=search.match(/(?:^|[?&])workspace=(islamia|business)(?:&|$)/);
 return match?match[1]:""
}
function isIslamiaOwnerWorkspace(){return ownerWorkspaceKind()==="islamia"}
function isOwnerBusinessWorkspace(){return !!ownerWorkspaceKind()}
function requestedIslamiaBusiness(){
 var search=window.location&&window.location.search||"";
 var matched=search.match(/(?:^|[?&])biz=([1-9][0-9]*)(?:&|$)/);
 return matched?Number(matched[1]):null
}
function synchronizeOwnerWorkspace(){
 if(!isOwnerBusinessWorkspace())return;
 var id=requestedIslamiaBusiness();
 var business=originalList().find(function(b){return Number(b.id)===id});
 var detail=business?[business.template_code,business.name_bn,business.name_en,business.code].join(" "):"";
 var sweets=/food|sweet|misty|mishti|bakery|cake|dessert|islamia|মিষ্টি|বেকারি|ইসলামিয়া|ইসলামিয়া/i.test(detail);
 if(!business||(isIslamiaOwnerWorkspace()&&!sweets)){
  try{var main=new URL("owner.html",window.location.href);main.search="";main.hash="#/organization";window.location.replace(main.href)}catch(_){}
  return
 }
 if(String(originalCur())!==String(id))originalSetCur(id)
}
function syncMasterNavigation(){
 if(!document.body||!document.body.classList)return;
 var isMaster=isOwner()&&document.body.dataset.core10Owner==="1"&&/^#\/?organization(?:\/|$)/.test(location.hash||"");
 document.body.classList.toggle("core10-master",isMaster)
}
function ensureWorkspaceReturn(){
 if(!isOwnerBusinessWorkspace()||!document.body)return;
 document.body.dataset.core10Business=isIslamiaOwnerWorkspace()?"islamia":"other";
 var app=document.getElementById("app"),header=app&&app.querySelector("header.top");
 if(!header||app.querySelector(".core10-return-bar"))return;
 var bar=document.createElement("nav");
 bar.className="core10-return-bar";
 bar.setAttribute("aria-label","CORE 10 owner navigation");
 var btn=document.createElement("button");btn.type="button";btn.className="core10-return-btn";
 btn.textContent="← CORE 10";
 btn.addEventListener("click",function(){
   var url=new URL("owner.html",window.location.href);
   url.search="";url.hash="#/organization";window.location.assign(url.href)
 });
 var caption=document.createElement("span");
 caption.textContent=isIslamiaOwnerWorkspace()?"ইসলামিয়া মিষ্টি ঘর · ERP":(B.biz.text?B.biz.text():"Business ERP");
 bar.appendChild(btn);bar.appendChild(caption);
 header.insertAdjacentElement("afterend",bar)
}
function redirectNonOwnerFromOwnerPortal(){
 if(!isStaff()||!document.body||document.body.dataset.core10Owner!=="1")return;
 try{
  var next=new URL("index.html",window.location.href);
  next.hash=window.location.hash||"#/home";
  window.location.replace(next.href);
 }catch(_){}
}
function redirectStaffToOwnBusinessPortal(){
 if(!isStaff()||!document.body)return;
 var permitted=allowedBusinesses();
 if(permitted.length!==1)return;
 var identity=B.biz.brand();
 var islamia=isIslamia(identity);
 var neutral=document.body.dataset.businessTenant==="1";
 if((islamia&&neutral)||(!islamia&&!neutral)){
  try{
   var next=new URL(islamia?"index.html":"business.html",window.location.href);
   next.search="";next.hash=window.location.hash||"#/home";
   window.location.replace(next.href)
  }catch(_){}
 }
}
function redirectOwnerFromBusinessPortal(){
 if(isOwnerBusinessWorkspace())return;
 if(!isOwner()||!document.body||document.body.dataset.core10Owner==="1")return;
 try{
  var next=new URL("owner.html",window.location.href);
  next.hash=window.location.hash||"#/home";
  window.location.replace(next.href);
 }catch(_){}
}
function currentName(){
 if(isIslamiaOwnerWorkspace())return B.biz.legacy||{bn:"ইসলামিয়া মিষ্টি ঘর",en:"ISLAMIYA MISTY GHAR"};
 if(isOwnerBusinessWorkspace())return originalBrand();
 if(isOwner())return MASTER;
 if(!isStaff())return null;
 var brand=B.biz.brand();
 return brand&&brand.bn&&brand.en?brand:PRIVATE
}
function isIslamia(name){return /islam[iy]a|ইসলামি/gi.test(String(name&&name.bn||"")+" "+String(name&&name.en||""))}
function branding(){
 syncMasterNavigation();
 redirectNonOwnerFromOwnerPortal();
 redirectOwnerFromBusinessPortal();
 redirectStaffToOwnBusinessPortal();
 if(isOwnerBusinessWorkspace())ensureWorkspaceReturn();
 var identity=currentName();if(!identity)return;
 var brandName=identity.bn||identity.en;
 var heads=document.querySelectorAll("h1.brandh");
 heads.forEach(function(h){
  var bn=h.querySelector(".bn"),en=h.querySelector(".lat");
  if(bn&&bn.textContent!==brandName)bn.textContent=brandName;
  if(en&&en.textContent!==(identity.en||brandName))en.textContent=identity.en||brandName
 });
 var drawer=document.querySelector(".dr-head");
 if(drawer){
  var title=drawer.querySelector(".nm b"),subtitle=drawer.querySelector(".nm i");
  if(title&&title.textContent!==brandName)title.textContent=brandName;
  if(subtitle&&subtitle.textContent!==(identity.en||brandName))subtitle.textContent=identity.en||brandName;
  var img=drawer.querySelector("img");
  if(isOwner()&&!isOwnerBusinessWorkspace()&&img){img.replaceWith(createMonogram());img=null}
  if(isOwnerBusinessWorkspace()&&!isIslamiaOwnerWorkspace()&&img){
   var profileLogo=B.biz.logo&&B.biz.logo();
   if(profileLogo)img.src=profileLogo;else img.replaceWith(createStaffMonogram(identity))
  }
  if(isStaff()&&!isIslamia(identity)){
    var profileLogo=B.biz.logo&&B.biz.logo();
    if(profileLogo&&img&&img.getAttribute("src")!==profileLogo)img.setAttribute("src",profileLogo);
    if(!profileLogo&&img){img.replaceWith(createStaffMonogram(identity))}
  }
 }
 var top=document.querySelector("header.top");
 if(top){
  var mainImg=top.querySelector("img.brand");
  if(isOwner()&&!isOwnerBusinessWorkspace()&&mainImg)mainImg.replaceWith(createMonogram());
  if(isOwnerBusinessWorkspace()&&!isIslamiaOwnerWorkspace()&&mainImg){
   var profileLogo=B.biz.logo&&B.biz.logo();
   if(profileLogo)mainImg.src=profileLogo;else mainImg.replaceWith(createStaffMonogram(identity))
  }
  if(isStaff()&&!isIslamia(identity)&&mainImg)mainImg.replaceWith(createStaffMonogram(identity))
 }
 var titleText=isOwner()&&!isOwnerBusinessWorkspace()?"CORE 10 · Business Management":identity.en||brandName;
 if(document.title!==titleText)document.title=titleText;
}
function createMonogram(){
 var span=document.createElement("span");span.className="core10-emblem";
 span.setAttribute("aria-label","CORE 10");span.textContent="10";return span
}
function createStaffMonogram(brand){
 var span=document.createElement("span");span.className="core10-tenant-emblem";
 var t=String(brand.en||brand.bn||"?").trim();
 span.setAttribute("aria-hidden","true");span.textContent=t.slice(0,1).toUpperCase();
 return span
}
var pending=false;
function schedule(){
 if(pending)return;pending=true;
 Promise.resolve().then(function(){pending=false;branding()})
}
var previousLoad=B.loadStatic;
if(typeof previousLoad==="function")B.loadStatic=function(){
 var result=previousLoad.apply(this,arguments);
 return Promise.resolve(result).then(function(value){synchronizeStaff();synchronizeOwnerWorkspace();schedule();return value})
};
function protectOrganization(){
 if(!window.BOS_PAGES||typeof window.BOS_PAGES.organization!=="function"||
 window.BOS_PAGES.organization.__core10Protected)return;
 var prev=window.BOS_PAGES.organization;
 var wrapped=function(){
   if(!isOwner()){location.hash="#/home";return Promise.resolve()}
   if(isOwnerBusinessWorkspace()){
    var url=new URL("owner.html",window.location.href);
    url.search="";url.hash="#/organization";window.location.assign(url.href);
    return Promise.resolve()
   }
   return prev.apply(this,arguments)
 };
 wrapped.__core10Protected=true;
 window.BOS_PAGES.organization=wrapped
}
if(L&&typeof L.load==="function"){
 var prevLazy=L.load;
 L.load=function(){
  var route=arguments[0],promise=prevLazy.apply(this,arguments);
  return Promise.resolve(promise).then(function(v){if(route==="organization")protectOrganization();return v})
 }
}
protectOrganization();
if(B.ia&&typeof B.ia.visible==="function"){
 var oldVisible=B.ia.visible;
 B.ia.visible=function(item){
  if(item&&item.route==="organization"&&(!isOwner()||isOwnerBusinessWorkspace()))return false;
  return oldVisible.apply(this,arguments)
 }
}
var oldPortfolio=B.BOS_PORTFOLIO||window.BOS_PORTFOLIO;
if(oldPortfolio&&typeof oldPortfolio.render==="function"){
 var oldRender=oldPortfolio.render;
 oldPortfolio.render=function(){if(!isOwner())return;return oldRender.apply(this,arguments)}
}
A.H.ph_open=(function(old){return function(btn){if(isOwner()&&typeof old==="function")return old(btn)}})(A.H.ph_open);
A.H.ph_manage=(function(old){return function(btn){if(isOwner()&&typeof old==="function")return old(btn)}})(A.H.ph_manage);
document.addEventListener("DOMContentLoaded",schedule);
window.addEventListener("hashchange",schedule);
window.addEventListener("bos:biz",schedule);
if(typeof MutationObserver==="function"&&document.body){
 var observer=new MutationObserver(function(mutations){
  if(mutations.some(function(x){return x.type==="childList" || x.type==="characterData"}))schedule()
 });
 observer.observe(document.body,{subtree:true,childList:true,characterData:true});
}
var style=document.createElement("style");style.id="core10-shell-css";style.textContent=
 '.core10-emblem,.core10-tenant-emblem{display:inline-flex;align-items:center;justify-content:center;flex:none;width:34px;height:34px;border-radius:10px;font:800 14px/1 system-ui,sans-serif;background:var(--ruby,#a1111e);color:var(--gold-lt,#f1d27c);border:1px solid #b89c62}'+
 '.core10-tenant-emblem{background:var(--card,#fff);color:var(--text,#333);border-color:var(--line,#ccc)}'+
 '.dr-head .core10-emblem,.dr-head .core10-tenant-emblem{width:36px;height:44px;margin-right:4px}'+
 'body[data-core10-business] .core10-return-bar{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:6px 0 11px;border-bottom:1px solid var(--line);margin-bottom:13px;font-size:.82rem;color:var(--muted)}'+
 'body[data-core10-business] .core10-return-btn{min-height:38px;padding:4px 12px;border:1px solid var(--line);border-radius:9px;background:var(--card);color:var(--ruby);font-size:.82rem;font-weight:700}';
document.head.appendChild(style);
schedule();
window.CORE10_SHELL={isOwner:isOwner,allowedBusinesses:allowedBusinesses,scopedLocations:scopedLocations,refresh:schedule,isOwnerBusinessWorkspace:isOwnerBusinessWorkspace};
})();