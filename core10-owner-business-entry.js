/* CORE 10 CENTRAL | Owner-only safe navigation to industry builder + Stocktake demo.
 * Presentation link only; backend tenant-owner RLS remains authoritative.
 */
(function(){"use strict";
if(!document.body||document.body.dataset.core10Owner!=="1")return;
const app=document.getElementById("app");
if(!app)return;
let scheduled=false;
function sync(){
 scheduled=false;
 const state=window.BOS_APP&&window.BOS_APP.S&&window.BOS_APP.S.ctx;
 const authorized=!!(state&&state.is_owner===true);
 const createLink=document.getElementById("core10-owner-create-business");
 const previewLink=document.getElementById("core10-owner-stocktake-preview");
 if(!authorized){
  if(createLink)createLink.remove();
  if(previewLink)previewLink.remove();
  return
 }
 const header=app.querySelector("header.top");
 if(!header)return;
 if(!createLink){
  const a=document.createElement("a");a.id="core10-owner-create-business";
  a.href="./core10-business-builder.html";a.textContent="+ Create Business";
  a.setAttribute("aria-label","Create a business using a CORE 10 industry template");
  a.style.cssText="display:inline-flex;align-items:center;justify-content:center;min-height:40px;margin:8px 12px;padding:8px 14px;border-radius:10px;background:#7f293b;color:#fff;text-decoration:none;font:600 14px/1.4 system-ui,sans-serif";
  header.appendChild(a);
 }
 // C10-A040: visible to signed-in CORE10 Owner only. The destination is a
 // synthetic stocktake preview, NOT a live ERP endpoint or authority grant.
 if(!previewLink){
  const a=document.createElement("a");a.id="core10-owner-stocktake-preview";
  a.href="./core10-stocktake-preview.html";
  a.textContent="Stocktake · Demo";
  a.setAttribute("aria-label","Open the synthetic Stocktake Owner and Staff preview; no real stock changes");
  a.setAttribute("data-preview-only","true");
  a.style.cssText="display:inline-flex;align-items:center;justify-content:center;min-height:40px;margin:8px 4px;padding:8px 14px;border-radius:10px;border:1px solid #087f8c;background:#e1f5f1;color:#0d4e59;text-decoration:none;font:700 14px/1.4 system-ui,sans-serif";
  header.appendChild(a);
 }
}
function schedule(){if(scheduled)return;scheduled=true;requestAnimationFrame(sync)}
new MutationObserver(schedule).observe(app,{childList:true,subtree:true});
window.addEventListener("hashchange",schedule);
schedule();
})();
