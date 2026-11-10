/* CORE 10 CENTRAL | Browser wizard wiring. No live mutations. */
(function(){"use strict";
const $=id=>document.getElementById(id), esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
let catalog,builder,step=0,autoSlug=true;
const steps=[0,1,2,3];
function error(s){$("notice").textContent=s||""}
function current(){return builder.snapshot()}
function draw(){
 if(!builder)return;
 const m=current(),t=catalog.templates.find(t=>t.id===m.templateId);
 $("summaryTemplate").textContent=t?t.name_en:"—";$("summaryName").textContent=m.name||"—";
 $("summaryModules").textContent=m.modules.length;$("summarySites").textContent=m.mode==="quick"?"Default 1":m.sites.length;
 $("sourceStatus").textContent=t?"Backend: "+t.source_status+" · Readiness: "+t.readiness:"";
 $("moduleChoices").innerHTML=(t?t.modules:[]).map(mod=>'<div class="module"><input id="module-'+esc(mod.id)+'" type="checkbox" data-module="'+esc(mod.id)+'" '+(m.modules.includes(mod.id)?"checked":"")+'><label for="module-'+esc(mod.id)+'">'+esc(mod.id.replaceAll("_"," "))+'<small>'+esc(mod.status)+" · "+esc(mod.origin||"")+'</small></label></div>').join("")||'<p class="hint">No declared modules for this business type.</p>';
 document.querySelectorAll("[data-module]").forEach(input=>input.addEventListener("change",()=>{const selected=new Set(current().modules);if(input.checked)selected.add(input.dataset.module);else selected.delete(input.dataset.module);builder.update({modules:[...selected]});draw()}));
 $("siteControls").classList.toggle("hidden",m.mode==="quick");$("quickSite").classList.toggle("hidden",m.mode!=="quick");
 $("siteRows").innerHTML=m.sites.map((s,i)=>'<div class="summary-line"><span>'+esc(s.kind)+" · "+esc(s.label)+'</span><button class="button" data-remove="'+i+'">Remove</button></div>').join("");
 document.querySelectorAll("[data-remove]").forEach(b=>b.addEventListener("click",()=>{const sites=current().sites;sites.splice(Number(b.dataset.remove),1);builder.update({sites});draw()}));
 steps.forEach(i=>{$("step"+i).classList.toggle("hidden",i!==step)});
 document.querySelectorAll("[data-step]").forEach(btn=>{if(Number(btn.dataset.step)===step)btn.setAttribute("aria-current","step");else btn.removeAttribute("aria-current")});
 $("back").disabled=step===0;$("next").classList.toggle("hidden",step===3);$("export").classList.toggle("hidden",step!==3);
 if(step===3){const preview=builder.preview();$("review").textContent=preview.validation.ok?"Setup valid for preview. Backend remains locked.":"Validation: "+preview.validation.errors.join(", ");$("jsonPreview").textContent=JSON.stringify(preview,null,2)}
}
function setStep(i){if(!steps.includes(i))return;step=i;error("");draw()}
function updateForm(){
 builder.update({name:$("businessName").value,slug:$("slug").value,templateId:$("template").value,
 brandHex:$("brand").value,mode:$("mode").value,sites:$("mode").value==="quick"?[]:current().sites});
}
function bind(){
 $("template").addEventListener("change",()=>{const m=current();builder.update({templateId:$("template").value,modules:[]});updateForm();draw()});
 $("businessName").addEventListener("input",()=>{if(autoSlug){$("slug").value=$("businessName").value.toLowerCase().trim().replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,"").slice(0,80)}updateForm();draw()});
 $("slug").addEventListener("input",()=>{autoSlug=false;updateForm();draw()});
 ["brand","mode"].forEach(id=>$(id).addEventListener("change",()=>{updateForm();draw()}));
 $("addSite").addEventListener("click",()=>{const label=$("siteName").value.trim(),kind=$("siteKind").value;
 if(!label){error("Enter a site name.");return}
 const sites=current().sites;
 if(sites.some(s=>s.kind===kind&&s.label.toLowerCase()===label.toLowerCase())){error("Duplicate site in this business.");return}
 sites.push({kind,label});builder.update({sites});$("siteName").value="";error("");draw()});
 $("back").addEventListener("click",()=>setStep(step-1));
 $("next").addEventListener("click",()=>{if(step===0&&!current().name.trim()){error("Business name is required.");return}if(step===0&&!/^[a-z][a-z0-9-]{0,79}$/.test(current().slug)){error("Slug must start with a letter and contain only lowercase letters, numbers and hyphens.");return}if(step===2){const v=builder.validate();if(!v.ok){error(v.errors.join(", "));return}}setStep(step+1)});
 document.querySelectorAll("[data-step]").forEach(b=>b.addEventListener("click",()=>{const target=Number(b.dataset.step);if(target<=step)setStep(target)}));
 $("export").addEventListener("click",()=>{const preview=builder.preview();if(!preview.validation.ok){error(preview.validation.errors.join(", "));return}
 const blob=new Blob([JSON.stringify(preview,null,2)],{type:"application/json"}),url=URL.createObjectURL(blob),a=document.createElement("a");a.href=url;a.download="core10-business-setup-preview.json";a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);error("Validated preview downloaded. No ERP records created.")});
}
fetch("./data/core10_capability_catalog_v1.json",{cache:"no-store"}).then(r=>{if(!r.ok)throw Error("Catalog unavailable");return r.json()}).then(c=>{
 if(!c||c.schema_version!==1||!Array.isArray(c.templates)||c.templates.length!==10)throw Error("Invalid 10-template catalog");
 catalog=c;builder=CORE10_BUSINESS_BUILDER.create({catalog,releaseEnabled:false});
 $("template").innerHTML=c.templates.map(t=>'<option value="'+esc(t.id)+'">'+esc(t.name_en)+'</option>').join("");
 bind();draw();
}).catch(e=>error("Cannot initialize business creation: "+e.message));
})();