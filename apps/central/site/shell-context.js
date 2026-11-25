/* CORE10 §7b.4 signed shell Group > Business > Site context.
 * Uses the SAME CORE10 staging Supabase auth key as existing module clients.
 * Context is a server-scoped navigation hint, never a local authorization decision.
 * No token/RPC result is persisted by this shell; no direct table access or writes.
 */
(function (win) {
"use strict";
const doc=win.document, root=doc.getElementById("c10-context");
if(!root)return;
const $=(id)=>doc.getElementById(id);
const anon=$("c10-context-anon"),signed=$("c10-context-signed"),open=$("c10-shell-open-login"),panel=$("c10-shell-login-panel");
const note=$("c10-context-note"),form=$("c10-shell-login-panel"),email=$("c10-shell-email"),password=$("c10-shell-password");
const submit=$("c10-shell-submit"),group=$("c10-group"),business=$("c10-business"),site=$("c10-site");
const refresh=$("c10-context-refresh"),logout=$("c10-shell-signout");
const cfg=win.CORE10_CONTROL_CENTRE_CONFIG;
const TARGET="https://rhrqhbyzrhaafynfhdaf.supabase.co";
let client=null,epoch=0,actor="",scope=null,chosen={tenant:null,business:null,site:null},blocked=false;
let lastMessage=[];
const t=(bn,en)=>doc.documentElement.dataset.lang==="en"?en:bn;
const businessRoles=new Set(["tenant_owner","business_owner","manager","investor","site_staff"]);
const positive=(value)=>Number.isSafeInteger(Number(value))&&Number(value)>0&&/^[1-9]\d*$/.test(String(value));
const fail=(s)=>{throw new Error(s);};
function message(bn,en){lastMessage=[bn,en];note.textContent=t(bn,en);}
function publishContext(state,detail={}){
  win.dispatchEvent(new CustomEvent("core10:context-change",{detail:{state,...detail}}));
}
// Embedded modules supply their own verified user. The only shared value is
// an in-memory display preference, which the module can accept or ignore.
win.CORE10_CENTRAL_CONTEXT=Object.freeze({
  preferredBusiness(userId){
    return !blocked&&scope&&actor&&actor===userId?chosen.business:null;
  }
});
function scrubEmbedded(){
  win.dispatchEvent(new Event("core10:signed-out"));
}
function clearPrivate(purge,state="signed-out"){
  const had=!!actor||!!scope;
  ++epoch;actor="";scope=null;chosen={tenant:null,business:null,site:null};blocked=false;
  signed.hidden=true;anon.hidden=false;panel.hidden=true;open.setAttribute("aria-expanded","false");
  group.replaceChildren();business.replaceChildren();site.replaceChildren();password.value="";
  publishContext(state);
  if(purge==="force"||(purge&&had))scrubEmbedded();
}
function configReady(){
  return !!cfg&&cfg.url===TARGET&&typeof cfg.key==="string"&&/^sb_publishable_[A-Za-z0-9_-]+$/.test(cfg.key)
    &&!!win.supabase&&typeof win.supabase.createClient==="function";
}
function verified(raw,userId){
  if(!raw||raw.actor_uid!==userId||!Array.isArray(raw.tenants)||!Array.isArray(raw.businesses)||!Array.isArray(raw.sites))fail("CONTEXT_SCOPE_INVALID");
  if(raw.tenants.length>100||raw.businesses.length>200||raw.sites.length>15000)fail("CONTEXT_SCOPE_OVERSIZE");
  const ts=new Map(),bs=new Map(),ss=new Set();
  for(const x of raw.tenants){
    if(!x||!positive(x.id)||typeof x.slug!=="string"||ts.has(Number(x.id)))fail("CONTEXT_TENANT_INVALID");
    ts.set(Number(x.id),{id:Number(x.id),slug:x.slug.slice(0,120),canBootstrap:x.can_manage_bootstrap===true});
  }
  for(const x of raw.businesses){
    if(!x||!positive(x.id)||!positive(x.tenant_id)||!ts.has(Number(x.tenant_id))||bs.has(Number(x.id)))fail("CONTEXT_BUSINESS_INVALID");
    bs.set(Number(x.id),{id:Number(x.id),tenant:Number(x.tenant_id),name:String(x.label||x.slug||x.id).slice(0,120),
      canManage:x.can_manage===true,role:businessRoles.has(x.role)?x.role:null});
  }
  const sites=[];
  for(const x of raw.sites){
    if(!x||!positive(x.id)||!positive(x.business_id)||!positive(x.tenant_id)||ss.has(Number(x.id)))fail("CONTEXT_SITE_INVALID");
    const b=bs.get(Number(x.business_id));
    if(!b||b.tenant!==Number(x.tenant_id))fail("CONTEXT_CROSS_TENANT");
    ss.add(Number(x.id));sites.push({id:Number(x.id),business:Number(x.business_id),tenant:Number(x.tenant_id),
      name:String(x.label||x.id).slice(0,120),kind:String(x.kind||"").slice(0,30)});
  }
  return {tenants:[...ts.values()],businesses:[...bs.values()],sites};
}
function fill(el,rows,label,emptyText){
  el.replaceChildren();
  if(!rows.length){const o=doc.createElement("option");o.value="";o.textContent=emptyText;el.append(o);el.disabled=true;return;}
  el.disabled=false;
  for(const x of rows){const o=doc.createElement("option");o.value=String(x.id);o.textContent=label(x);el.append(o);}
}
function present(ctx,wanted){
  const oldTenant=chosen.tenant,oldBusiness=chosen.business,oldSite=chosen.site;
  const validT=ctx.tenants.map(x=>x.id);
  const tId=validT.includes(wanted?.tenant)?wanted.tenant:validT.includes(oldTenant)?oldTenant:validT[0]||null;
  const bs=ctx.businesses.filter(x=>x.tenant===tId);
  const bIds=bs.map(x=>x.id);
  const bId=bIds.includes(wanted?.business)?wanted.business:bIds.includes(oldBusiness)?oldBusiness:bIds[0]||null;
  const ss=ctx.sites.filter(x=>x.business===bId);
  const sIds=ss.map(x=>x.id);
  const sId=sIds.includes(wanted?.site)?wanted.site:sIds.includes(oldSite)?oldSite:sIds[0]||null;
  chosen={tenant:tId,business:bId,site:sId};
  fill(group,ctx.tenants,x=>x.slug,t("কোনো গ্রুপ নেই","No groups"));
  fill(business,bs,x=>x.name,t("কোনো ব্যবসা নেই","No businesses"));
  fill(site,ss,x=>x.kind?x.name+" · "+x.kind:x.name,t("অনুমোদিত স্থান নেই","No authorized sites"));
  if(tId!==null)group.value=String(tId);
  if(bId!==null)business.value=String(bId);
  if(sId!==null)site.value=String(sId);
  anon.hidden=true;signed.hidden=false;panel.hidden=true;open.setAttribute("aria-expanded","false");
  message("স্বাক্ষরিত স্টেজিং · সার্ভার-অনুমোদিত প্রসঙ্গ","Signed staging · server-authorized context");
  const selected=bs.find(b=>b.id===bId);
  publishContext("ready",{
    business:selected?{name:selected.name,canManage:selected.canManage,role:selected.role}:null,
    canBootstrap:ctx.tenants.some(g=>g.id===tId&&g.canBootstrap)
  });
}
async function currentUser(){
  const r=await client.auth.getUser();
  return r&&!r.error&&typeof r.data?.user?.id==="string"&&r.data.user.id||null;
}
async function load(wanted){
  if(!client)return;
  const n=++epoch;
  blocked=true;signed.hidden=true;for(const el of [group,business,site,refresh,logout])el.disabled=true;
  publishContext("loading");
  try{
    const before=await currentUser();
    if(n!==epoch)return;
    if(!before){clearPrivate(true);message("সাইন-ইন করে আপনার অনুমোদিত গ্রুপ ও ব্যবসা দেখুন।","Sign in to view your authorized group and businesses.");return;}
    const r=await client.schema("core10").rpc("build01_context_v1",{});
    const after=await currentUser();
    if(n!==epoch)return;
    if(before!==after||!after||r.error){clearPrivate("force","error");message("সেশন বা অনুমতি বদলেছে। আবার সাইন ইন বা রিফ্রেশ করুন।","Session or permissions changed. Sign in or refresh again.");return;}
    const clean=verified(r.data,after);
    if(actor&&actor!==after){clearPrivate(true,"error");message("অ্যাকাউন্ট বদলেছে; আবার প্রসঙ্গ যাচাই করুন।","Account changed; revalidate the context.");return;}
    actor=after;scope=clean;present(clean,wanted);
  }catch(_){
    if(n===epoch){clearPrivate("force","error");message("সার্ভার থেকে অনুমোদিত প্রসঙ্গ যাচাই করা যায়নি।","Could not verify authorized context with the server.");}
  }finally{
    if(n===epoch){blocked=false;refresh.disabled=false;logout.disabled=false;}
  }
}
function request(wanted){if(blocked||!client)return;void load(wanted);}
function candidate(value){return positive(value)?Number(value):null;}
group.addEventListener("change",()=>request({tenant:candidate(group.value),business:null,site:null}));
business.addEventListener("change",()=>request({tenant:chosen.tenant,business:candidate(business.value),site:null}));
site.addEventListener("change",()=>request({tenant:chosen.tenant,business:chosen.business,site:candidate(site.value)}));
refresh.addEventListener("click",()=>request({tenant:chosen.tenant,business:chosen.business,site:chosen.site}));
open.addEventListener("click",()=>{
  panel.hidden=!panel.hidden;open.setAttribute("aria-expanded",String(!panel.hidden));
  if(!panel.hidden)email.focus();else password.value="";
});
form.addEventListener("submit",async(e)=>{
  e.preventDefault();if(!client||blocked||!email.value.trim()||!password.value)return;
  submit.disabled=true;const pass=password.value;password.value="";
  try{
    const r=await client.auth.signInWithPassword({email:email.value.trim(),password:pass});
    if(r.error||!r.data?.user?.id){clearPrivate(true);message("সাইন ইন ব্যর্থ হয়েছে।","Sign-in failed.");return;}
    await load();
  }catch(_){clearPrivate(true);message("সাইন ইন ব্যর্থ হয়েছে।","Sign-in failed.");}
  finally{submit.disabled=false;}
});
logout.addEventListener("click",async()=>{
  if(!client||blocked)return;
  // Purge cached labels and the embedded private view BEFORE waiting for a network sign-out.
  clearPrivate("force");message("সাইন আউট হচ্ছে…","Signing out…");
  try{await client.auth.signOut();}catch(_){/* Never restore old private view on failure. */}
  message("সাইন আউট হয়েছে।","Signed out.");
});
win.addEventListener("core10:language-change",()=>{
  note.textContent=t(...lastMessage);
});
if(!configReady()){
  open.disabled=true;message("CORE10 স্টেজিং সাইন-ইন উপলব্ধ নয়।","CORE10 staging sign-in unavailable.");
  publishContext("error");
  return;
}
client=win.supabase.createClient(cfg.url,cfg.key,{auth:{detectSessionInUrl:false}});
client.auth.onAuthStateChange((event)=>{
  if(event==="SIGNED_OUT"){clearPrivate("force");message("সাইন আউট হয়েছে।","Signed out.");}
  else if(event==="SIGNED_IN"||event==="INITIAL_SESSION"||event==="TOKEN_REFRESHED")
    Promise.resolve().then(()=>request());
});
message("সাইন-ইন করে আপনার অনুমোদিত গ্রুপ ও ব্যবসা দেখুন।","Sign in to view your authorized group and businesses.");
Promise.resolve().then(()=>request());
})(window);
