/* PACK-02 — Universal Owner / Business Owner / Staff workspace client.
 * Renders ONLY server projections from c10_demo.pack02_workspace_v1 (which
 * derives authority from the canonical PACK-01/Build01 predicates). This file
 * is presentation: it never grants, widens or infers permission, and it fails
 * closed when a projection is malformed or would leak umbrella/sister data.
 */
(function(root,factory){
 "use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_PACK02_WORKSPACE=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 function fail(code){const e=new Error(code);e.code=code;throw e;}
 const obj=x=>!!x&&typeof x==="object"&&!Array.isArray(x);
 const MODES=Object.freeze(["universal_owner","business_owner","staff"]);
 const SITE_KINDS=Object.freeze(["showroom","factory","godown","warehouse","project"]);
 const ACTIONS=Object.freeze(["stock.read","stock.post"]);
 // Bangla-first labels with English secondary text and a short contextual hint (D049).
 const NAV=Object.freeze({
  "owner.portfolio":{bn:"সব ব্যবসার সারাংশ",en:"Portfolio",hint:"আপনার মালিকানাধীন প্রতিটি ব্যবসার সংক্ষিপ্ত অবস্থা।"},
  "owner.businesses":{bn:"ব্যবসাসমূহ",en:"Businesses",hint:"একটি ব্যবসা খুললে সেই ব্যবসার নিজস্ব Owner Board দেখাবে।"},
  "owner.setup":{bn:"নতুন ব্যবসা সেটআপ",en:"Business setup",hint:"Quick বা Advanced — একই পূর্ণ engine; Quick-এ ক্ষমতা কমে না।"},
  "owner.reports":{bn:"মালিকের রিপোর্ট",en:"Owner reports",hint:"প্রতিটি ব্যবসা আলাদা সারিতে; ভিন্ন tenant একত্র হয় না।"},
  "owner.controls":{bn:"নিয়ন্ত্রণ স্টুডিও",en:"Control studio",hint:"Central/Business/Both/Hidden placement একই canonical সেটিং।"},
  "biz.dashboard":{bn:"ব্যবসার ড্যাশবোর্ড",en:"Dashboard",hint:"শুধু এই ব্যবসার তথ্য।"},
  "biz.sites":{bn:"শাখা ও লোকেশন",en:"Sites & locations",hint:"শোরুম, ফ্যাক্টরি, গোডাউন, ওয়্যারহাউস ও প্রজেক্ট।"},
  "biz.site_create":{bn:"নতুন শাখা যোগ",en:"Add site",hint:"একই request key আবার পাঠালে নতুন duplicate তৈরি হয় না।"},
  "biz.access":{bn:"স্টাফ ও অনুমতি",en:"Staff & access",hint:"অনুমতি সার্ভারে যাচাই হয়; মেনু দেখা মানে অনুমতি নয়।"},
  "biz.reports":{bn:"ব্যবসার রিপোর্ট",en:"Business reports",hint:"এই ব্যবসার শাখাভিত্তিক হিসাব।"},
  "biz.controls":{bn:"ব্যবসার নিয়ন্ত্রণ",en:"Business controls",hint:"Owner-অনুমোদিত সেটিং এখানে দেখা যায়।"},
  "staff.home":{bn:"আমার কাজ",en:"My work",hint:"আপনাকে দেওয়া শাখার কাজ।"},
  "stock.view":{bn:"স্টক দেখুন",en:"View stock",hint:"শুধু অনুমোদিত শাখার স্টক।"},
  "stock.post":{bn:"স্টক এন্ট্রি",en:"Post stock",hint:"পোস্ট করার আগে সার্ভার আবার অনুমতি যাচাই করে।"},
  "staff.reports":{bn:"আমার শাখার রিপোর্ট",en:"My site reports",hint:"অন্য শাখা বা ব্যবসার তথ্য এখানে নেই।"}
 });
 const MODE_NAV=Object.freeze({
  universal_owner:["owner.portfolio","owner.businesses","owner.setup","owner.reports","owner.controls"],
  business_owner:["biz.dashboard","biz.sites","biz.site_create","biz.access","biz.reports","biz.controls"],
  staff:["staff.home","stock.view","staff.reports","stock.post"]
 });
 const KIND_BN=Object.freeze({showroom:"শোরুম",factory:"ফ্যাক্টরি",godown:"গোডাউন",warehouse:"ওয়্যারহাউস",project:"প্রজেক্ট"});
 const MODE_BN=Object.freeze({universal_owner:"CORE 10 মালিক",business_owner:"ব্যবসার মালিক",staff:"স্টাফ"});
 function id(x){if(!Number.isSafeInteger(x)||x<1)fail("PACK02_PROJECTION_INVALID");return x;}
 function str(x,max=120){if(typeof x!=="string"||!x.trim()||x.length>max)fail("PACK02_PROJECTION_INVALID");return x;}
 function hex(x){if(typeof x!=="string"||!/^#[0-9A-Fa-f]{6}$/.test(x))fail("PACK02_PROJECTION_INVALID");return x.toUpperCase();}
 function only(x,keys){if(!obj(x)||Object.keys(x).some(k=>!keys.includes(k)))fail("PACK02_PROJECTION_UNSAFE");}
 function brand(b,staff){
  only(b,staff?["display_name","brand_hex","setup_status"]:["display_name","brand_hex","brand_source","setup_mode","setup_status"]);
  return {name:str(b.display_name),hex:hex(b.brand_hex)};
 }
 function sites(list){
  if(!Array.isArray(list)||list.length>2000)fail("PACK02_PROJECTION_INVALID");
  const seen=new Set();
  return list.map(s=>{
   only(s,["id","kind","label","allowed_actions"]);
   if(seen.has(s.id))fail("PACK02_PROJECTION_DUPLICATE_SITE");seen.add(id(s.id));
   if(!SITE_KINDS.includes(s.kind))fail("PACK02_PROJECTION_INVALID");
   if(!Array.isArray(s.allowed_actions)||s.allowed_actions.some(a=>!ACTIONS.includes(a))||new Set(s.allowed_actions).size!==s.allowed_actions.length)fail("PACK02_PROJECTION_INVALID");
   return {id:s.id,kind:s.kind,kindLabel:KIND_BN[s.kind],label:str(s.label),actions:[...s.allowed_actions]};
  });
 }
 function nav(mode,keys){
  if(!Array.isArray(keys)||!keys.length)fail("PACK02_PROJECTION_INVALID");
  if(keys.some(k=>!MODE_NAV[mode].includes(k))||new Set(keys).size!==keys.length)fail("PACK02_PROJECTION_UNSAFE");
  return keys.map(k=>({key:k,...NAV[k]}));
 }
 // Readable foreground for the brand colour (WCAG relative luminance).
 function onBrand(h){
  const c=[1,3,5].map(i=>parseInt(h.slice(i,i+2),16)/255).map(v=>v<=0.03928?v/12.92:((v+0.055)/1.055)**2.4);
  const L=0.2126*c[0]+0.7152*c[1]+0.0722*c[2];
  return (1.05/(L+0.05))>=((L+0.05)/0.05)?"#FFFFFF":"#111111";
 }
 function view(p){
  if(!obj(p)||p.contract!=="C10_PACK02_WORKSPACE_V1"||!MODES.includes(p.mode)||p.production_certified!==false)fail("PACK02_PROJECTION_INVALID");
  const mode=p.mode;
  if(mode==="universal_owner"){
   only(p,["contract","mode","actor_uid","umbrella","tenants","businesses","nav","production_certified","data_mode"]);
   if(!obj(p.umbrella)||p.umbrella.visible!==true)fail("PACK02_PROJECTION_INVALID");
   if(!Array.isArray(p.businesses))fail("PACK02_PROJECTION_INVALID");
   const businesses=p.businesses.map(b=>{
    only(b,["id","tenant_id","slug","status","brand","site_count"]);
    return {id:id(b.id),tenantId:id(b.tenant_id),status:str(b.status,24),siteCount:Number.isSafeInteger(b.site_count)?b.site_count:fail("PACK02_PROJECTION_INVALID"),brand:brand(b.brand,false)};
   });
   return {mode,modeLabel:MODE_BN[mode],title:"CORE 10",umbrella:true,theme:{brand:"#0F766E",onBrand:onBrand("#0F766E")},nav:nav(mode,p.nav),businesses,sites:[]};
  }
  if(mode==="business_owner"){
   only(p,["contract","mode","actor_uid","umbrella","business","sites","nav","production_certified","data_mode"]);
   if(!obj(p.umbrella)||typeof p.umbrella.visible!=="boolean"||Object.keys(p.umbrella).length!==1)fail("PACK02_PROJECTION_INVALID");
   only(p.business,["id","brand"]);
   const b=brand(p.business.brand,false);
   return {mode,modeLabel:MODE_BN[mode],title:b.name,umbrella:p.umbrella.visible,businessId:id(p.business.id),theme:{brand:b.hex,onBrand:onBrand(b.hex)},nav:nav(mode,p.nav),businesses:[],sites:sites(p.sites)};
  }
  // Staff: any umbrella, tenant, actor or sister field is treated as a leak.
  only(p,["contract","mode","umbrella","business","sites","nav","production_certified"]);
  if(!obj(p.umbrella)||p.umbrella.visible!==false||Object.keys(p.umbrella).length!==1)fail("PACK02_PROJECTION_UNSAFE");
  only(p.business,["id","brand"]);
  const b=brand(p.business.brand,true);
  const list=sites(p.sites);
  if(!list.length)fail("PACK02_PROJECTION_INVALID");
  const permitted=new Set(list.flatMap(s=>s.actions));
  const keys=nav(mode,p.nav);
  // The nav must not offer more than the projected site actions permit.
  if(keys.some(k=>(k.key==="stock.post"&&!permitted.has("stock.post"))||((k.key==="stock.view"||k.key==="staff.reports")&&!permitted.has("stock.read"))))fail("PACK02_PROJECTION_UNSAFE");
  const text=JSON.stringify(p);
  if(/CORE\s*10/i.test(text))fail("PACK02_PROJECTION_UNSAFE");
  return {mode,modeLabel:"",title:b.name,umbrella:false,businessId:id(p.business.id),theme:{brand:b.hex,onBrand:onBrand(b.hex)},nav:keys,businesses:[],sites:list};
 }
 function el(doc,tag,cls,text){const e=doc.createElement(tag);if(cls)e.className=cls;if(text!=null)e.textContent=String(text);return e;}
 // DOM rendering uses textContent only; server strings never become markup.
 // Without an onNavigate handler, nav items render disabled: no inert button
 // may look like a working function (AGENTS.md / D049).
 // wiredKeys (optional array) limits live items to those the host has connected.
 function render(rootEl,v,onNavigate,wiredKeys){
  const doc=rootEl.ownerDocument;
  rootEl.replaceChildren();
  rootEl.style.setProperty("--c10-brand",v.theme.brand);
  rootEl.style.setProperty("--c10-on-brand",v.theme.onBrand);
  rootEl.setAttribute("data-mode",v.mode);
  const head=el(doc,"header","p2-head");
  head.append(el(doc,"h1","p2-title",v.title));
  if(v.modeLabel)head.append(el(doc,"span","p2-mode",v.modeLabel));
  if(v.umbrella&&v.mode!=="universal_owner"){const a=el(doc,"a","p2-umbrella","← CORE 10");a.href="#core10";head.append(a);}
  const navEl=el(doc,"nav","p2-nav");navEl.setAttribute("aria-label","প্রধান মেনু");
  for(const n of v.nav){
   const b=el(doc,"button","p2-nav-item");b.type="button";b.dataset.key=n.key;
   if(typeof onNavigate==="function"&&(!Array.isArray(wiredKeys)||wiredKeys.includes(n.key)))b.addEventListener("click",()=>onNavigate(n.key));
   else{b.disabled=true;b.setAttribute("aria-disabled","true");b.title="এই অংশটি এখনো সংযুক্ত হয়নি (not connected yet)";}
   b.append(el(doc,"span","p2-bn",n.bn),el(doc,"span","p2-en",n.en),el(doc,"small","p2-hint",n.hint));
   navEl.append(b);
  }
  const main=el(doc,"main","p2-main");
  if(v.businesses.length){
   const ul=el(doc,"ul","p2-cards");
   for(const b of v.businesses){const li=el(doc,"li","p2-card");li.style.borderColor=b.brand.hex;
    li.append(el(doc,"strong",null,b.brand.name),el(doc,"span",null,`শাখা: ${b.siteCount} · অবস্থা: ${b.status}`));ul.append(li);}
   main.append(ul);
  }
  if(v.sites.length){
   const ul=el(doc,"ul","p2-cards");
   for(const s of v.sites){const li=el(doc,"li","p2-card");
    li.append(el(doc,"strong",null,s.label),el(doc,"span",null,`${s.kindLabel} · ${s.actions.includes("stock.post")?"দেখা ও এন্ট্রি":"শুধু দেখা"}`));ul.append(li);}
   main.append(ul);
  }
  rootEl.append(head,navEl,main);
  return rootEl;
 }
 // Adapter: rpc MUST be the signed Build01 client's RPC (fresh getUser first).
 function create({rpc}){
  if(typeof rpc!=="function")fail("PACK02_SIGNED_RPC_REQUIRED");
  let seq=0;
  return {
   async load(mode,business){
    if(!MODES.includes(mode))fail("PACK02_MODE_INVALID");
    if(mode!=="universal_owner")id(business);else if(business!=null)fail("PACK02_MODE_INVALID");
    const mine=++seq;
    const p=await rpc("pack02_workspace_v1",{p_mode:mode,p_business:mode==="universal_owner"?null:business});
    if(mine!==seq)fail("PACK02_STALE_RESPONSE");
    const v=view(p);
    if(v.mode!==mode||(mode!=="universal_owner"&&v.businessId!==business))fail("PACK02_PROJECTION_UNSAFE");
    return v;
   }
  };
 }
 return Object.freeze({MODES,NAV,view,render,create,onBrand});
});
