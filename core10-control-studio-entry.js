/* A044 navigation only: backend core10 can_manage is source of authority. */
(function(){"use strict";
const app=document.getElementById("app");if(!app)return;
let frame=false;
const OWNER_LINKS=[
 {id:"core10-owner-dashboard-entry",text:"মালিকের ড্যাশবোর্ড · Owner dashboard",href:"./core10-owner-dashboard.html",biz:false,icon:"",
  label:"Open the Owner dashboard: businesses, sites, stock balances and open purchase work"},
 {id:"core10-stock-ops-entry",text:"স্টক কাজ · Stock operations",href:"./core10-stock-ops.html",biz:"core10-stock-ops-biz-entry",icon:"📥",
  label:"Open Stock operations: receive, issue, transfer and adjust stock"},
 {id:"core10-purchase-entry",text:"ক্রয় · Purchases",href:"./core10-purchase.html",biz:"core10-purchase-biz-entry",icon:"🧾",
  label:"Open Purchases: purchase orders and goods receipts"}
];
function drop(ids){for(const i of ids){const e=document.getElementById(i);if(e)e.remove()}}
function sync(){
 frame=false;
 const A=window.BOS_APP,B=window.BOS,ctx=A&&A.S&&A.S.ctx;
 const master=document.body&&document.body.dataset.core10Owner==="1";
 const key="core10-studio-entry";
 const existing=document.getElementById(key);
 const centreKey="core10-owner-control-centre-entry",centre=document.getElementById(centreKey);
 const mdKey="core10-master-data-entry",md=document.getElementById(mdKey);
 const mdBizKey="core10-master-data-biz-entry",mdBiz=document.getElementById(mdBizKey);
 // Owner-only navigation (Owner dashboard, Stock operations, Purchases). Navigation only, never a permission:
 // each page re-derives authority from the signed CORE10 context; ?biz only pre-selects a business CORE10 returns.
 const ownerHead=OWNER_LINKS.map(x=>x.id),ownerBiz=OWNER_LINKS.filter(x=>x.biz).map(x=>x.biz);
 if(!ctx||!ctx.profile||!ctx.profile.id){if(existing)existing.remove();if(centre)centre.remove();if(md)md.remove();if(mdBiz)mdBiz.remove();drop(ownerHead);drop(ownerBiz);return}
 if(master){
  if(ctx.is_owner!==true){if(existing)existing.remove();if(centre)centre.remove();if(md)md.remove();drop(ownerHead);return}
  const header=app.querySelector("header.top");if(!header)return;
  // B-021: canonical DEC-08 Owner Control Centre (core10.control_* RPCs on CORE10 staging only).
  if(!centre){
   const c=document.createElement("a");c.id=centreKey;c.textContent="মালিক নিয়ন্ত্রণ · Owner Control";
   c.href="./core10-owner-control-centre.html";c.setAttribute("aria-label","Open the Owner Control Centre: switch features, approvals, limits, schedules, history and exceptions");
   c.style.cssText="display:inline-flex;align-items:center;min-height:40px;margin:8px 4px;padding:8px 12px;border-radius:10px;border:1px solid #ddb47f;background:#2b3c4f;color:#f3e2c6;text-decoration:none;font:700 13px system-ui,sans-serif";
   header.appendChild(c)
  }
  // B-011: canonical NP02 Master Data (core10.master_* RPCs on CORE10 staging only).
  if(!md){
   const m=document.createElement("a");m.id=mdKey;m.textContent="মাস্টার ডেটা · Master Data";
   m.href="./core10-master-data.html";m.setAttribute("aria-label","Open Master Data: items, customers and suppliers, price lists and units");
   m.style.cssText=(document.getElementById(centreKey)||{style:{cssText:""}}).style.cssText;
   header.appendChild(m)
  }
  for(const x of OWNER_LINKS)if(!document.getElementById(x.id)){
   const o=document.createElement("a");o.id=x.id;o.textContent=x.text;o.href=x.href;o.setAttribute("aria-label",x.label);
   o.style.cssText=(document.getElementById(centreKey)||{style:{cssText:""}}).style.cssText;
   header.appendChild(o)
  }
  if(!existing){
   const a=document.createElement("a");a.id=key;a.textContent="Control Studio";
   a.href="./core10-control-studio.html";a.setAttribute("aria-label","Open Universal Owner Control Studio");
   a.style.cssText="display:inline-flex;align-items:center;min-height:40px;margin:8px 4px;padding:8px 12px;border-radius:10px;border:1px solid #a68b64;background:#253446;color:#f3e2c6;text-decoration:none;font:700 13px system-ui";
   header.appendChild(a)
  }
  return
 }
 const match=(location.search||"").match(/(?:^|[?&])workspace=(?:business|islamia)(?:&|$)/);
 const idMatch=(location.search||"").match(/(?:^|[?&])biz=([1-9][0-9]*)(?:&|$)/);
 const id=idMatch?Number(idMatch[1]):null;
 const valid=match&&Number.isSafeInteger(id)&&B&&B.biz&&
  String(B.biz.cur())===String(id)&&(B.biz.list()||[]).some(x=>Number(x.id)===id);
 if(centre)centre.remove();if(md)md.remove();drop(ownerHead);
 const section=app.querySelector(".bo-section .bo-actions");
 if(!valid||!section){if(existing)existing.remove();if(mdBiz)mdBiz.remove();drop(ownerBiz);return}
 // B-011: Master Data for the selected business. Navigation only: the page re-derives every permission from the
 // signed CORE10 context (build01_context_v1 + can_manage); ?biz only pre-selects among businesses CORE10 returns.
 if(!mdBiz||mdBiz.getAttribute("href")!=="./core10-master-data.html?biz="+id){
  if(mdBiz)mdBiz.remove();
  const m=document.createElement("a");m.id=mdBizKey;m.textContent="📦 মাস্টার ডেটা · Master Data";
  m.href="./core10-master-data.html?biz="+id;m.setAttribute("aria-label","Master Data for this business: items, customers and suppliers, price lists and units");
  m.style.cssText="display:flex;align-items:center;min-height:55px;padding:12px;border:1px solid #9a7f58;border-radius:11px;background:#233446;color:#f6dfb5;text-decoration:none;font:700 14px system-ui,sans-serif";
  section.appendChild(m)
 }
 // Owner-only business links: shown only when the signed context says is_owner === true.
 if(ctx.is_owner!==true)drop(ownerBiz);
 else for(const x of OWNER_LINKS){
  if(!x.biz)continue;
  const bid=x.biz,href=x.href+"?biz="+id,cur=document.getElementById(bid);
  if(cur&&cur.getAttribute("href")===href)continue;
  if(cur)cur.remove();
  const o=document.createElement("a");o.id=bid;o.textContent=x.icon+" "+x.text;o.href=href;o.setAttribute("aria-label",x.label+" for this business");
  o.style.cssText="display:flex;align-items:center;min-height:55px;padding:12px;border:1px solid #9a7f58;border-radius:11px;background:#233446;color:#f6dfb5;text-decoration:none;font:700 14px system-ui,sans-serif";
  section.appendChild(o)
 }
 if(!existing){
  const a=document.createElement("a");a.id=key;a.textContent="⚙ Business Controls";
  a.href="./core10-business-controls.html?biz="+id;
  a.setAttribute("aria-label","Business App Settings, shared Business Controls");
  a.style.cssText="display:flex;align-items:center;min-height:55px;padding:12px;border:1px solid #9a7f58;border-radius:11px;background:#233446;color:#f6dfb5;text-decoration:none;font:700 14px system-ui";
  section.appendChild(a)
 }
}
function schedule(){if(frame)return;frame=true;requestAnimationFrame(sync)}
if(typeof MutationObserver==="function")new MutationObserver(schedule).observe(app,{childList:true,subtree:true});
window.addEventListener("hashchange",schedule);window.addEventListener("bos:biz",schedule);
schedule();
})();
