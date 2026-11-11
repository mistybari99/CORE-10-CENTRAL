/* A044 navigation only: backend c10_demo can_manage is source of authority. */
(function(){"use strict";
const app=document.getElementById("app");if(!app)return;
let frame=false;
function sync(){
 frame=false;
 const A=window.BOS_APP,B=window.BOS,ctx=A&&A.S&&A.S.ctx;
 const master=document.body&&document.body.dataset.core10Owner==="1";
 const key="core10-studio-entry";
 const existing=document.getElementById(key);
 if(!ctx||!ctx.profile||!ctx.profile.id){if(existing)existing.remove();return}
 if(master){
  if(ctx.is_owner!==true){if(existing)existing.remove();return}
  const header=app.querySelector("header.top");if(!header)return;
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
 const section=app.querySelector(".bo-section .bo-actions");
 if(!valid||!section){if(existing)existing.remove();return}
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
