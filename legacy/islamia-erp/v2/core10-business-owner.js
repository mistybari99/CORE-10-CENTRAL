/* CORE 10 · Contextual Business Owner landing.
 * This only runs for the authenticated global owner who entered one
 * explicitly selected Business Workspace from the CORE 10 portfolio.
 *
 * Existing ERP approvals, Owner Board and report routes stay unchanged.
 * Cross-business metric scoping is NOT assumed until backend audited.
 */
(function(){
 "use strict";
 var B=window.BOS,A=window.BOS_APP;
 if(!B||!A||!A.H||!B.biz||!window.BOS_LAZY)return;
 function active(){
  return !!(A.S&&A.S.ctx&&A.S.ctx.is_owner&&document.body&&
   document.body.dataset.core10Owner!=="1"&&
   /(?:^|[?&])workspace=(?:islamia|business)(?:&|$)/.test(window.location.search||""));
 }
 function bizId(){
  var m=(window.location.search||"").match(/(?:^|[?&])biz=([1-9]\d*)(?:&|$)/);
  return m?Number(m[1]):null
 }
 function tr(bn,en){return B.L&&B.lab?B.lab(B.L(bn,en)):bn}
 function esc(x){return String(x==null?"":x).replace(/[&<>"']/g,function(c){
  return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]})}
 function currentBusiness(){
  var id=bizId(),list=B.biz.list();
  if(!Number.isSafeInteger(id)||!Array.isArray(list))return null;
  return list.find(function(x){return Number(x.id)===id})||null
 }
 function card(label,detail,route,icon){
  return '<button type="button" class="bo-card" data-act="go" data-v="'+esc(route)+'">'+
    '<span class="bo-symbol" aria-hidden="true">'+icon+'</span>'+
    '<span class="bo-card-copy"><b>'+esc(label)+'</b><small>'+esc(detail)+'</small></span>'+
    '<span class="bo-arr" aria-hidden="true">›</span></button>'
 }
 async function ownerHome(){
  if(!active())return originalHome.apply(this,arguments);
  try{await B.loadStatic()}catch(_){}
  var business=currentBusiness();
  if(!business||String(B.biz.cur())!==String(business.id)){
   A.shell(tr("ব্যবসার পরিচয় যাচাই","Verify business context"),
    '<div class="notice warn">'+esc(tr("এই ব্যবসার পরিচয় এখনো নিশ্চিত হয়নি। ভুল ব্যবসার তথ্য দেখানো হচ্ছে না।","Business context is not yet verified. No other business data is shown."))+
    '</div><button type="button" class="primary" data-act="bo_master">'+esc(tr("CORE 10-এ ফিরুন","Back to CORE 10"))+'</button>');
   return
  }
  var identity=B.biz.brand(),bn=identity&&identity.bn||business.name_bn||business.name_en||business.code;
  var en=identity&&identity.en||business.name_en||bn;
  var title=tr("ব্যবসার মালিক ড্যাশবোর্ড","Business Owner Dashboard");
  var body='<div class="bo-wrap">'+
   '<section class="bo-hero"><div class="bo-kicker">'+esc(tr("ব্যবসাভিত্তিক মালিকের ওয়ার্কস্পেস","BUSINESS OWNER WORKSPACE"))+'</div>'+
   '<h2>'+esc(bn)+'</h2><p>'+esc(en)+'</p>'+
   '<div class="bo-role">'+esc(tr("তোমার ভূমিকা: এই ব্যবসার Full Owner","Your role: Full Owner of this business"))+'</div></section>'+
   '<section class="bo-attention"><div class="bo-attention-head"><b>'+esc(tr("তোমার সিদ্ধান্ত ও অনুমোদন","Your Decisions & Approvals"))+'</b>'+
   '<span class="bo-role-tag">'+esc(tr("এই ব্যবসা","This business"))+'</span></div>'+
   '<p>'+esc(tr("অনুমোদনের পুরোনো মডিউলগুলো ব্যবহারযোগ্য রয়েছে। তবে এই ব্যবসার সঠিক Pending সংখ্যা দেখাতে Server-side Business Scope Audit সম্পন্ন হওয়া প্রয়োজন। তাই এখানে ভুল সংখ্যা দেখানো হচ্ছে না।","Existing approval modules are available. Business-specific pending counts require a server-side scope audit; unverified numbers are deliberately not displayed."))+'</p>'+
   '<div class="bo-quick">'+
   card(tr("Pending Approvals","Pending Approvals"),tr("অনুমোদনের অপেক্ষার কাজ","Items awaiting approval"),"pending","✓")+
   card(tr("সমস্যা ও ব্যতিক্রম","Exceptions & Issues"),tr("যাচাই ও সিদ্ধান্ত","Investigate and decide"),"exceptions","!")+
   card(tr("Owner Board","Owner Board"),tr("আগের মালিকের বোর্ড খুলুন","Open existing owner board"),"owner","▤")+
   '</div></section>'+
   '<section class="bo-section"><h3>'+esc(tr("ব্যবসার পরিচালনা","Manage this business"))+'</h3><div class="bo-actions">'+
   card(tr("শোরুম, ব্রাঞ্চ ও লোকেশন","Branches & Locations"),tr("শোরুম, কারখানা, গোডাউন ও অন্যান্য লোকেশন","Showrooms, factories, stores and other places"),"locations","⌂")+
   card(tr("স্টাফ ও অনুমতি","Staff & Access"),tr("ব্যবসার কর্মী ও দায়িত্ব","Employees and assignments"),"staff","♙")+
   card(tr("স্টক ও ইনভেন্টরি","Stock & Inventory"),tr("পরিচালনাগত স্টক","Operational stock"),"stock","▣")+
   card(tr("বিজনেস রিপোর্ট","Business Reports"),tr("রিপোর্ট ও বিশ্লেষণ","Reports & analysis"),"reports/hub","▥")+
   '</div></section>'+
   '<div class="bo-footer"><button type="button" data-act="bo_master">'+esc(tr("← CORE 10 Master Dashboard","← CORE 10 Master Dashboard"))+'</button></div></div>';
  A.shell(title,body);
 }
 var originalHome=null,wrapped=false;
 function install(){
  if(!window.BOS_NAV||typeof window.BOS_NAV.home!=="function"||wrapped)return;
  if(window.BOS_NAV.home.__bo_context)return;
  originalHome=window.BOS_NAV.home;
  var next=function(){return active()?ownerHome.apply(this,arguments):originalHome.apply(this,arguments)};
  next.__bo_context=true;
  window.BOS_NAV.home=next;
  wrapped=true
 }
 A.H.bo_master=function(){
  if(!A.S||!A.S.ctx||!A.S.ctx.is_owner)return;
  var next=new URL("owner.html",window.location.href);
  next.search="";next.hash="#/organization";
  window.location.assign(next.href)
 };
 install();
 var oldLoad=B.loadStatic;
 if(typeof oldLoad==="function")B.loadStatic=function(){
  var result=oldLoad.apply(this,arguments);
  return Promise.resolve(result).then(function(x){install();return x})
 };
 var load=window.BOS_LAZY.load;
 if(typeof load==="function")window.BOS_LAZY.load=function(){
  var result=load.apply(this,arguments);
  return Promise.resolve(result).then(function(v){install();return v})
 };
 document.addEventListener("DOMContentLoaded",install);
 window.addEventListener("hashchange",install);
 var style=document.createElement("style");
 style.id="business-owner-css";
 style.textContent=[
 'body[data-core10-business] .bo-wrap{display:grid;gap:15px;margin:5px 0 26px}',
 'body[data-core10-business] .bo-hero{padding:20px;border-radius:15px;border:1px solid var(--line);background:var(--card);box-shadow:var(--shadow-sm,none)}',
 'body[data-core10-business] .bo-kicker{font-size:.7rem;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:var(--ruby)}',
 'body[data-core10-business] .bo-hero h2{font-size:1.33rem;color:var(--ink);margin:6px 0 1px;line-height:1.35}',
 'body[data-core10-business] .bo-hero p{font-size:.8rem;color:var(--muted);margin:0}',
 'body[data-core10-business] .bo-role{margin-top:13px;padding-top:12px;border-top:1px solid var(--line);font-size:.84rem;font-weight:700;color:var(--ink)}',
 'body[data-core10-business] .bo-attention{padding:17px;border-radius:15px;background:var(--card);border:1px solid var(--line)}',
 'body[data-core10-business] .bo-attention-head{display:flex;align-items:center;justify-content:space-between;gap:8px;flex-wrap:wrap;font-size:.97rem}',
 'body[data-core10-business] .bo-role-tag{padding:3px 9px;border-radius:22px;background:var(--s2);color:var(--muted);font-size:.71rem}',
 'body[data-core10-business] .bo-attention p{font-size:.81rem;color:var(--muted);line-height:1.6;margin:9px 0 12px}',
 'body[data-core10-business] .bo-section h3{font-size:1rem;color:var(--ink);margin:2px 0 10px}',
 'body[data-core10-business] .bo-actions,body[data-core10-business] .bo-quick{display:grid;grid-template-columns:minmax(0,1fr);gap:9px}',
 'body[data-core10-business] .bo-card{display:flex;width:100%;align-items:center;gap:11px;text-align:start;min-height:67px;background:var(--card);color:var(--ink);border:1px solid var(--line);border-radius:12px;padding:10px 12px;box-shadow:none}',
 'body[data-core10-business] .bo-card:focus-visible{outline:2px solid var(--ruby);outline-offset:2px}',
 'body[data-core10-business] .bo-symbol{display:flex;flex:none;justify-content:center;align-items:center;width:36px;height:36px;background:var(--s2);color:var(--ruby);border-radius:10px;font-weight:800}',
 'body[data-core10-business] .bo-card-copy{display:flex;flex:1;flex-direction:column;gap:3px;min-width:0}',
 'body[data-core10-business] .bo-card-copy b{font-size:.9rem;line-height:1.3}',
 'body[data-core10-business] .bo-card-copy small{font-size:.76rem;line-height:1.4;color:var(--muted)}',
 'body[data-core10-business] .bo-arr{font-size:1.5rem;font-weight:400;color:var(--ruby)}',
 'body[data-core10-business] .bo-footer{display:flex;justify-content:flex-start}',
 'body[data-core10-business] .bo-footer button{min-height:44px;border:1px solid var(--line);border-radius:10px;background:var(--card);color:var(--ruby);font-size:.86rem;font-weight:750;padding:8px 15px}',
 '@media(min-width:880px){body[data-core10-business] .bo-actions,body[data-core10-business] .bo-quick{grid-template-columns:repeat(2,minmax(0,1fr))}}'
 ].join("");
 document.head.appendChild(style);
 window.CORE10_BUSINESS_OWNER={active:active,install:install,render:ownerHome};
})();