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
 var allowed=assignedIds();return allLocations().filter(function(loc){return allowed.has(Number(loc.id))})
}
/* Server-verified mapping only. Never trust bizctx's first-business fallback. */
var verifiedLocations=new Map(),verifiedKey="",verifyPromise=null;
function ensureVerifiedLocations(){
 var ctx=A.S.ctx;if(!ctx||ctx.is_owner||!ctx.profile||!ctx.profile.id||!A.sb||typeof A.sb.rpc!=="function")return;
 var ids=Array.from(assignedIds()).sort(function(a,b){return a-b});
 var key=String(ctx.profile.id)+":"+ids.join(",");
 if(key===verifiedKey)return;
 verifiedKey=key;verifiedLocations=new Map();
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
  synchronizeStaff();schedule()
 },function(){/* fail closed */});
}
function allowedBusinesses(){
 if(!isStaff())return originalList();
 ensureVerifiedLocations();
 var ids=new Set();
 assignedIds().forEach(function(id){if(verifiedLocations.has(id))ids.add(verifiedLocations.get(id))});
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
 if(isStaff()&&!assignedIds().has(Number(locId)))return PRIVATE;
 return originalBrandFor(locId)
};
B.biz.switcherHTML=function(){return isStaff()?"":originalSwitcher()};
function redirectNonOwnerFromOwnerPortal(){
 if(!isStaff()||!document.body||document.body.dataset.core10Owner!=="1")return;
 try{
  var next=new URL("index.html",window.location.href);
  next.hash=window.location.hash||"#/home";
  window.location.replace(next.href);
 }catch(_){}
}
function currentName(){
 if(isOwner())return MASTER;
 if(!isStaff())return null;
 var brand=B.biz.brand();
 return brand&&brand.bn&&brand.en?brand:PRIVATE
}
function isIslamia(name){return /islam[iy]a|ইসলামি/gi.test(String(name&&name.bn||"")+" "+String(name&&name.en||""))}
function branding(){
 redirectNonOwnerFromOwnerPortal();
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
  if(isOwner()&&img){img.replaceWith(createMonogram());img=null}
  if(isStaff()&&!isIslamia(identity)){
    var profileLogo=B.biz.logo&&B.biz.logo();
    if(profileLogo&&img&&img.getAttribute("src")!==profileLogo)img.setAttribute("src",profileLogo);
    if(!profileLogo&&img){img.replaceWith(createStaffMonogram(identity))}
  }
 }
 var top=document.querySelector("header.top");
 if(top){
  var mainImg=top.querySelector("img.brand");
  if(isOwner()&&mainImg)mainImg.replaceWith(createMonogram());
  if(isStaff()&&!isIslamia(identity)&&mainImg)mainImg.replaceWith(createStaffMonogram(identity))
 }
 var titleText=isOwner()?"CORE 10 · Business Management":identity.en||brandName;
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
 return Promise.resolve(result).then(function(value){synchronizeStaff();schedule();return value})
};
function protectOrganization(){
 if(!window.BOS_PAGES||typeof window.BOS_PAGES.organization!=="function"||
 window.BOS_PAGES.organization.__core10Protected)return;
 var prev=window.BOS_PAGES.organization;
 var wrapped=function(){
   if(!isOwner()){location.hash="#/home";return Promise.resolve()}
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
  if(item&&item.route==="organization"&&!isOwner())return false;
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
 '.core10-emblem,.core10-tenant-emblem{display:inline-flex;align-items:center;justify-content:center;flex:none;width:34px;height:34px;border-radius:10px;font:800 14px/1 system-ui,sans-serif;background:#182537;color:#f5d18a;border:1px solid #b89c62}'+
 '.core10-tenant-emblem{background:var(--card,#fff);color:var(--text,#333);border-color:var(--line,#ccc)}'+
 '.dr-head .core10-emblem,.dr-head .core10-tenant-emblem{width:36px;height:44px;margin-right:4px}';
document.head.appendChild(style);
schedule();
window.CORE10_SHELL={isOwner:isOwner,allowedBusinesses:allowedBusinesses,scopedLocations:scopedLocations,refresh:schedule};
})();