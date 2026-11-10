/* CORE 10 CENTRAL | Authenticated staging connection for ten-template wizard.
 * No production writes. Requires separately configured staging release flags
 * AND database RLS/RPC permissions. Client-side flags are never authorization.
 */
(function(){"use strict";
const $=id=>document.getElementById(id);
const status=(message)=>{$("stagingStatus").textContent=message};
const env=window.CORE10_ENTERPRISE_STAGING_RELEASE||{};
let api,builder,requestKey=null;
async function init(){
 builder=window.CORE10_BUILDER_INSTANCE;
 if(!builder)return;
 builder.onChange(()=>{requestKey=null;$("createStagingDraft").disabled=!api||!api.status().draftWritesEnabled});
 const cfg=window.BOS_CONFIG,lib=window.supabase;
 if(!cfg||!cfg.url||!cfg.key||!lib||typeof lib.createClient!=="function"){
  status("Supabase client configuration unavailable. Preview export still works.");return;
 }
 let client;
 try{client=lib.createClient(cfg.url,cfg.key)}catch(_){status("Supabase session could not initialize.");return}
 let user;
 try{const r=await client.auth.getUser();user=r&&r.data&&r.data.user}catch(_){}
 if(!user||!user.id){status("Sign in through CORE 10 Owner Workspace first, then return to this screen.");return}
 if(env.stagingEnabled!==true||env.draftWritesEnabled!==true){
  status("Signed in · Backend draft creation is locked until separate staging release certification.");return;
 }
 let catalog;
 try{
  const r=await fetch("./data/core10_capability_catalog_v1.json",{cache:"no-store"});
  if(!r.ok)throw Error("Catalog unavailable");
  catalog=await r.json();
  api=CORE10_INDUSTRY_CLIENT.create({client,catalog,stagingEnabled:true,draftWritesEnabled:true});
  const legal=await api.listLegalEntities();
  if(!Array.isArray(legal)||!legal.length){status("No authorized legal entities found for this signed-in account.");return}
  $("legalEntity").replaceChildren();
  for(const row of legal){
   const option=document.createElement("option");
   option.value=String(row.id);option.textContent=row.label||"Legal entity "+row.id;
   $("legalEntity").appendChild(option);
  }
  $("legalEntity").disabled=false;
  $("createStagingDraft").disabled=false;
  status("Staging authentication confirmed. Draft-only provisioning is available.");
 }catch(e){status("Staging schema or permissions not ready: "+String(e&&e.code||"access unavailable"))}
}
$("createStagingDraft").addEventListener("click",async function(){
 if(!api||!api.status().draftWritesEnabled){status("Draft provisioning release locked.");return}
 const check=builder.validate();
 if(!check.ok){status("Correct the setup fields: "+check.errors.join(", "));return}
 const id=Number($("legalEntity").value);
 if(!Number.isSafeInteger(id)||id<1){status("Select an authorized legal entity.");return}
 if(!requestKey){
  if(!window.crypto||typeof window.crypto.randomUUID!=="function"){status("Secure request identifier unavailable.");return}
  requestKey=window.crypto.randomUUID();
 }
 this.disabled=true;status("Creating a draft business under signed tenant permissions…");
 try{
  const result=await api.setupDraft(builder.snapshot(),{legalId:id,requestKey});
  status("Draft business #"+String(result.business_id)+" created. ERP modules remain locked until approval.");
 }catch(e){
  status("Draft setup denied or unavailable: "+String(e&&e.code||"backend rejected request"));
 }finally{this.disabled=false}
});
if(builder)init();
else document.addEventListener("core10-builder-ready",init,{once:true});
})();