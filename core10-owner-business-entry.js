/* CORE 10 CENTRAL | Owner workspace access to the single 10-industry builder.
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
 const existing=document.getElementById("core10-owner-create-business");
 if(!authorized){if(existing)existing.remove();return}
 const header=app.querySelector("header.top");
 if(!header||existing)return;
 const a=document.createElement("a");a.id="core10-owner-create-business";
 a.href="./core10-business-builder.html";a.textContent="+ Create Business";
 a.setAttribute("aria-label","Create a business using a CORE 10 industry template");
 a.style.cssText="display:inline-flex;align-items:center;justify-content:center;min-height:40px;margin:8px 12px;padding:8px 14px;border-radius:10px;background:#7f293b;color:#fff;text-decoration:none;font:600 14px/1.4 system-ui,sans-serif";
 header.appendChild(a);
}
function schedule(){if(scheduled)return;scheduled=true;requestAnimationFrame(sync)}
new MutationObserver(schedule).observe(app,{childList:true,subtree:true});
window.addEventListener("hashchange",schedule);
schedule();
})();
