/* CORE 10 CENTRAL | Preserve, reuse, upgrade: read-only legacy coverage.
 * Never clones an existing business or grants business access from a public page.
 */
(function(){"use strict";
const element=id=>document.getElementById(id);
const panel=element("legacyReuse");
const detail=element("legacyReuseDetails");
const returnLink=element("legacyReuseLink");
const select=element("template");
if(!panel||!detail||!returnLink||!select)return;
let state={ok:false,message:"Checking the existing Islamia ERP report registry…"};
function render(){
 const show=select.value==="sweets_bakery";
 panel.hidden=!show;panel.classList.toggle("hidden",!show);
 if(!show)return;
 detail.textContent=state.message;
 returnLink.hidden=!state.ok;
 returnLink.setAttribute("aria-disabled",state.ok?"false":"true");
}
select.addEventListener("change",render);
Promise.all(["./data/core10_legacy_preservation_v1.json",
 "./data/report_registry.json","./data/core10_capability_catalog_v1.json"].map(async url=>{
 const res=await fetch(url,{cache:"no-store"});
 if(!res.ok)throw new Error("REFERENCE_UNAVAILABLE");
 return res.json();
})).then(([baseline,reports,catalog])=>{
 const result=CORE10_LEGACY_PARITY.check(baseline,reports,catalog);
 if(!result.ok)throw new Error("REPORT_PARITY_MISMATCH");
 const counts=reports.status_counts||{};
 state={ok:true,message:
   "Existing Islamia ERP preserved as the source engine: "+
   result.checked.reports+" registered reports ("+Number(counts.implemented||0)+
   " marked implemented, "+Number(counts.incomplete||0)+" incomplete, "+
   Number(counts.unverified||0)+" unverified, "+Number(counts.unavailable||0)+
   " unavailable), "+result.checked.protectedModules+
   " declared core modules. These are registry labels, not certified live workflows. "+
   "Open the Owner portfolio to select the existing Islamia business—do not create a duplicate."};
 render();
}).catch(()=>{
 state={ok:false,message:"Could not verify existing reports and module contract. The legacy ERP has NOT been removed. Use the Owner portfolio directly; business duplication is not authorized."};
 render();
});
render();
})();