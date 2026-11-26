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
const locationDetails=$("c10-location-details"),locationStatus=$("c10-location-status"),locationList=$("c10-location-list");
let locationRevision=0,locationMessage=[];
function clearLocations(){
  ++locationRevision;
  locationDetails.open=false;locationDetails.hidden=true;
  locationMessage=[];locationStatus.textContent="";locationList.replaceChildren();
}
function locationText(bn,en){
  locationMessage=[bn,en];locationStatus.textContent=t(bn,en);
}
locationDetails.addEventListener("toggle",async()=>{
  const revision=++locationRevision,contextEpoch=epoch;
  locationList.replaceChildren();locationMessage=[];locationStatus.textContent="";
  if(!locationDetails.open||blocked||!actor||!chosen.site)return;
  const businessId=chosen.business,siteId=chosen.site,expectedActor=actor;
  const current=()=>epoch===contextEpoch&&revision===locationRevision&&locationDetails.open;
  locationText("লোকেশন পড়া হচ্ছে…","Loading stock locations…");
  try{
    if(await currentUser()!==expectedActor||!current())throw Error("SESSION_CHANGED");
    const response=await client.schema("core10").rpc("inventory_list_locations_v1",{p_business:businessId,p_site:siteId});
    if(!current())return;
    if(await currentUser()!==expectedActor||response.error)throw Error("LOCATION_SCOPE");
    if(!current())return;
    const data=response.data;
    if(data?.business_id!==businessId||data.site_id!==siteId||!Array.isArray(data.items)||
       typeof data.truncated!=="boolean"||data.items.some(x=>x?.site_id!==siteId||!positive(x.location_id)||typeof x.code!=="string"))
      throw Error("LOCATION_SCOPE");
    for(const row of data.items){
      const item=doc.createElement("li");item.textContent=row.code+" · #"+row.location_id;locationList.append(item);
    }
    locationText(data.truncated?"প্রথম ২০০০টি অনুমোদিত লোকেশন।":"অনুমোদিত লোকেশন "+data.items.length,
      data.truncated?"First 2000 authorized locations.":"Authorized locations: "+data.items.length);
  }catch(_){
    if(current())locationText("এই সাইটের লোকেশন যাচাই করা যায়নি।","Could not verify locations for this site.");
  }
});
// Read-only T01.01 evidence for the selected business; never a certification or permission grant.
const pilotDetails=$("c10-pilot-details"),pilotStatus=$("c10-pilot-status"),pilotList=$("c10-pilot-list");
let pilotRevision=0,pilotRows=[],pilotMessage=[];
const recipePlanner=$("c10-recipe-planner"),recipeSelect=$("c10-recipe"),recipeMultiplier=$("c10-recipe-multiplier"),recipeButton=$("c10-recipe-validate"),recipeStatus=$("c10-recipe-status"),recipeResults=$("c10-recipe-results");
let recipeChoices=new Map(),recipeRevision=0,recipeMessage=[],recipeRows=[];
function drawRecipe(){
  recipeStatus.textContent=recipeMessage.length?t(...recipeMessage):"";
  recipeResults.replaceChildren();
  for(const row of recipeRows){const li=doc.createElement("li");li.textContent=t(...row);recipeResults.append(li);}
}
function clearRecipeResult(){
  ++recipeRevision;recipeMessage=[];recipeRows=[];recipeButton.disabled=false;drawRecipe();
}
function clearRecipe(){
  clearRecipeResult();recipeChoices.clear();recipeSelect.replaceChildren();
  recipeMultiplier.value="1";recipePlanner.hidden=true;
}
function offerRecipes(approved){
  clearRecipe();
  for(const x of approved){
    if(recipeChoices.has(Number(x.id)))continue;
    recipeChoices.set(Number(x.id),{id:Number(x.id),version:Number(x.version)});
    const option=doc.createElement("option");option.value=String(x.id);
    option.textContent=String(x.recipe_code||"Recipe").slice(0,80)+" · #"+x.id+" · v"+x.version;recipeSelect.append(option);
  }
  recipePlanner.hidden=recipeChoices.size===0;
}
recipeSelect.addEventListener("change",clearRecipeResult);
recipeMultiplier.addEventListener("input",clearRecipeResult);
recipeButton.addEventListener("click",async()=>{
  clearRecipeResult();
  const rev=recipeRevision,e=epoch,p=pilotRevision,b=chosen.business,s=chosen.site,who=actor;
  const selected=recipeChoices.get(Number(recipeSelect.value)),multiplier=Number(recipeMultiplier.value);
  if(blocked||!who||!b||!s||!pilotDetails.open||recipePlanner.hidden||!selected)return;
  if(!/^[0-9]+(?:\.[0-9]{1,6})?$/.test(recipeMultiplier.value)||!Number.isFinite(multiplier)||multiplier<=0||multiplier>100000){
    recipeMessage=["সঠিক গুণক দিন (সর্বোচ্চ ৬ দশমিক)।","Enter a valid multiplier (up to six decimals)."];drawRecipe();return;
  }
  const current=()=>epoch===e&&pilotRevision===p&&recipeRevision===rev&&actor===who&&!blocked&&chosen.business===b&&chosen.site===s&&pilotDetails.open&&!recipePlanner.hidden;
  recipeButton.disabled=true;recipeMessage=["Master উপকরণ যাচাই হচ্ছে…","Validating canonical Master materials…"];drawRecipe();
  try{
    if(await currentUser()!==who||!current())throw Error("RECIPE_SESSION");
    const result=await client.schema("core10").rpc("mfg_master_validation_v1",{p_business:b,p_site:s,p_recipe:selected.id,p_multiplier:multiplier});
    if(!current()||await currentUser()!==who||!current())throw Error("RECIPE_SESSION");
    if(result.error)throw Error("RECIPE_DENIED");
    const d=result.data;
    const quantity=x=>typeof x==="number"&&Number.isFinite(x)&&x>=0;
    const valid=x=>x&&x.master==="VERIFIED_CANONICAL"&&positive(x.item_id)&&positive(x.item_version)&&positive(x.uom_id)&&positive(x.uom_version)&&positive(x.base_uom_id)&&positive(x.base_uom_version)&&typeof x.uom_code==="string"&&typeof x.base_uom_code==="string"&&quantity(x.quantity)&&quantity(x.base_uom_quantity);
    if(!d||d.recipe_id!==selected.id||d.recipe_version!==selected.version||d.master!=="VERIFIED_CANONICAL"||d.planning_only!==true||d.stock_issued!==false||d.financial_posted!==false||d.substitution_selected!==false||!valid(d.output)||!Array.isArray(d.lines)||!Array.isArray(d.alternatives)||d.lines.length>2000||d.alternatives.length>2000||!d.lines.every(x=>valid(x)&&positive(x.line_no))||!d.alternatives.every(x=>valid(x)&&positive(x.rule_id)&&positive(x.line_no)))throw Error("RECIPE_RESPONSE");
    const material=x=>" #"+x.item_id+" v"+x.item_version+" · "+x.quantity+" "+x.uom_code+" → "+x.base_uom_quantity+" "+x.base_uom_code;
    recipeRows=[["ফিনিশড আইটেম"+material(d.output),"Finished item"+material(d.output)],...d.lines.map(x=>["উপকরণ "+x.line_no+material(x),"Ingredient "+x.line_no+material(x)]),...d.alternatives.map(x=>["বিকল্প (নির্বাচিত নয়)"+material(x),"Alternative (not selected)"+material(x)])];
    recipeMessage=["রেসিপি v"+d.recipe_version+" · Master যাচাইকৃত; stock/finance posting নয়।","Recipe v"+d.recipe_version+" · Master verified; no stock or finance posting."];
    drawRecipe();
  }catch(_){if(current()){recipeRows=[];recipeMessage=["যাচাই হয়নি: অনুমতি, Control, Master বা recipe revision পরীক্ষা করুন।","Not verified: check permission, Control, Master or recipe revision."];drawRecipe();}}
  finally{if(current())recipeButton.disabled=false;}
});
function clearPilot(){
  clearRecipe();++pilotRevision;pilotDetails.open=false;pilotDetails.hidden=true;
  pilotRows=[];pilotMessage=[];pilotList.replaceChildren();pilotStatus.textContent="";
}
function renderPilot(){
  pilotStatus.textContent=pilotMessage.length?t(...pilotMessage):"";
  pilotList.replaceChildren();
  for(const row of pilotRows){const el=doc.createElement("li");el.textContent=t(...row);pilotList.append(el);}
}
pilotDetails.addEventListener("toggle",async()=>{
  const rev=++pilotRevision,e=epoch,b=chosen.business,s=chosen.site,tenant=chosen.tenant,who=actor;
  clearRecipe();pilotRows=[];pilotMessage=[];renderPilot();
  if(!pilotDetails.open||blocked||!who||!b||!scope)return;
  const current=()=>epoch===e&&pilotRevision===rev&&pilotDetails.open&&!blocked&&actor===who&&chosen.business===b&&chosen.site===s;
  const sites=scope.sites.filter(x=>x.business===b&&x.tenant===tenant);
  const count=k=>sites.filter(x=>k.includes(x.kind)).length;
  const rows=[
    ["অনুমোদিত কারখানা: "+count(["factory"]),"Authorized factories: "+count(["factory"])],
    ["অনুমোদিত গুদাম: "+count(["godown","warehouse"]),"Authorized storage sites: "+count(["godown","warehouse"])],
    ["অনুমোদিত শোরুম: "+count(["showroom"]),"Authorized showrooms: "+count(["showroom"])]
  ];
  pilotMessage=["সার্ভার প্রমাণ যাচাই হচ্ছে…","Checking server evidence…"];renderPilot();
  async function read(name,args){
    if(!current()||await currentUser()!==who||!current())throw Error("PILOT_SESSION_CHANGED");
    const r=await client.schema("core10").rpc(name,args);
    if(!current()||await currentUser()!==who||!current())throw Error("PILOT_SESSION_CHANGED");
    if(r.error||!r.data||typeof r.data!=="object")return null;
    return r.data;
  }
  try{
    const u=await read("master_list_uoms_v1",{p_business:b});
    if(!current())return;
    const units=Array.isArray(u?.uoms)?u.uoms:[],conv=Array.isArray(u?.conversions)?u.conversions:[];
    const kg=units.find(x=>x.active===true&&x.code?.toLowerCase()==="kg"&&positive(x.id));
    const g=units.find(x=>x.active===true&&x.code?.toLowerCase()==="g"&&positive(x.id));
    const metric=!!(kg&&g&&kg.dimension===g.dimension&&conv.some(c=>c.active===true&&Number(c.from_uom_id)===Number(kg.id)&&Number(c.to_uom_id)===Number(g.id)&&Number(c.factor)===1000));
    rows.push(metric?["kg → g: সক্রিয় ১০০০ conversion পাওয়া গেছে","kg → g: active factor 1000 found"]:["kg → g: সক্রিয় সরাসরি conversion যাচাই হয়নি","kg → g: active direct conversion not verified"]);
    if(sites.some(x=>x.id===s&&x.kind==="factory")){
      const m=await read("mfg_inspect_v1",{p_business:b,p_site:s});
      if(!current())return;
      const valid=Array.isArray(m?.recipes)&&m.recipes.every(x=>x&&typeof x.recipe_code==="string"&&x.recipe_code.trim().length>0&&x.business_id===b&&x.site_id===s&&x.tenant_id===tenant&&positive(x.id)&&positive(x.version));
      if(valid){
        const latestByCode = new Map();
        const asOf = Date.now();
        for (const recipe of m.recipes) {
          const effectiveFrom = Date.parse(recipe.effective_from);
          if (recipe.status !== "approved" || !Number.isFinite(effectiveFrom) || effectiveFrom > asOf) continue;
          const previous = latestByCode.get(recipe.recipe_code);
          if (!previous || Number(recipe.version) > Number(previous.version)) {
            latestByCode.set(recipe.recipe_code, recipe);
          }
        }
        const approved = [...latestByCode.values()];
        offerRecipes(approved);
        rows.push(["কারখানার recipe revision: "+m.recipes.length+" · কার্যকর approved: "+approved.length,"Factory recipe revisions: "+m.recipes.length+" · effective approved: "+approved.length]);
      }else rows.push(["Recipe revision যাচাই হয়নি","Recipe revisions not verified"]);
    }else rows.push(["Recipe যাচাই করতে অনুমোদিত কারখানা নির্বাচন করুন","Select an authorized factory to inspect recipe revisions"]);
    rows.push(["Lot, pack, shelf life, label profile: এখনো যাচাই হয়নি","Lot, pack, shelf life and label profile: not yet verified"]);
    if(!current())return;
    pilotRows=rows;pilotMessage=["শুধু নির্বাচিত scope-এর read-only প্রমাণ; operational approval নয়।","Read-only evidence for selected scope; not operational approval."];renderPilot();
  }catch(_){if(current()){pilotRows=[];pilotMessage=["যাচাই অসম্পূর্ণ; আবার রিফ্রেশ করুন।","Verification incomplete; refresh and retry."];renderPilot();}}
});
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
  clearLocations();clearPilot();
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
  fill(site,ss,x=>[x.name,x.kind,"#"+x.id].filter(Boolean).join(" · "),t("অনুমোদিত স্থান নেই","No authorized sites"));
  if(tId!==null)group.value=String(tId);
  if(bId!==null)business.value=String(bId);
  if(sId!==null)site.value=String(sId);
  locationDetails.hidden=sId===null;
  pilotDetails.hidden=bId===null;
  anon.hidden=true;signed.hidden=false;panel.hidden=true;open.setAttribute("aria-expanded","false");
  if(bId===null){
    message("অনুমোদিত ব্যবসা নেই।","No authorized business.");
  }else{
    const kinds=[["factory","কারখানা","factories"],["godown","গোদাম","godowns"],
      ["warehouse","ওয়্যারহাউস","warehouses"],["showroom","শোরুম","showrooms"],["project","প্রকল্প","projects"]];
    const counts=new Map();
    for(const site of ss)counts.set(site.kind,(counts.get(site.kind)||0)+1);
    const detail=(column)=>kinds.filter(([kind])=>counts.has(kind))
      .map(row=>row[column]+" "+counts.get(row[0])).join(", ");
    message("এই ব্যবসায় আপনার অনুমোদিত সাইট "+ss.length+(ss.length?" · "+detail(1):""),
      "Your authorized sites in this business: "+ss.length+(ss.length?" · "+detail(2):""));
  }
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
  clearLocations();clearPilot();
  const n=++epoch;
  blocked=true;signed.hidden=true;for(const el of [group,business,site,refresh,logout])el.disabled=true;
  message("অনুমোদিত সাইট যাচাই হচ্ছে…","Checking authorized sites…");
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
  if(locationMessage.length)locationStatus.textContent=t(...locationMessage);
  renderPilot();drawRecipe();
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
