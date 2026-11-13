/* Build 01 — one adapter over A018/A020/A034 and canonical scope predicates.
 * Explicit isolated config only; no production fallback, role claims or grants.
 */
(function(root,factory){
 "use strict";
 const existing=typeof module==="object"&&module.exports?require("./core10-enterprise-client.js"):root.CORE10_ENTERPRISE_CLIENT;
 const api=factory(existing);
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_BUILD01_CLIENT=api;
})(typeof window!=="undefined"?window:globalThis,function(existing){
 "use strict";
 function fail(code){const e=new Error(code);e.code=code;throw e;}
 const obj=x=>x&&typeof x==="object"&&!Array.isArray(x);
 function shape(x,keys){if(!obj(x)||Object.keys(x).some(k=>!keys.includes(k)))fail("BUILD01_INVALID_INPUT");}
 function id(x){if(!["string","number"].includes(typeof x)||!/^[1-9]\d*$/.test(String(x))||!Number.isSafeInteger(Number(x)))fail("BUILD01_INVALID_ID");return Number(x);}
 function text(x,max=120){if(typeof x!=="string"||!x.trim()||x.trim().length>max)fail("BUILD01_INVALID_TEXT");return x.trim();}
 function key(x){return text(x);}
 function uid(x){if(typeof x!=="string"||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x))fail("BUILD01_INVALID_SUBJECT");return x.toLowerCase();}
 function actions(x){if(!Array.isArray(x)||x.length>2||new Set(x).size!==x.length||x.some(a=>!["stock.read","stock.post"].includes(a)))fail("BUILD01_INVALID_ACTIONS");return [...x].sort();}
 function config(c){
  if(!obj(c)||c.enabled!==true||c.mode!=="isolated-development")fail("BUILD01_NOT_CONFIGURED");
  let u;try{u=new URL(c.url);}catch{fail("BUILD01_INVALID_TARGET");}
  if(u.protocol!=="http:"||!["127.0.0.1","localhost","[::1]"].includes(u.hostname)||u.username||u.password||u.pathname!=="/"||u.search||u.hash)fail("BUILD01_NONPRODUCTION_TARGET_REQUIRED");
  if(typeof c.publishableKey!=="string"||!c.publishableKey.trim())fail("BUILD01_PUBLISHABLE_KEY_REQUIRED");
  // Legacy anon JWTs are allowed for the isolated runtime; service-role JWTs are not.
  const part=c.publishableKey.split(".")[1];
  if(part){try{const raw=typeof atob==="function"?atob(part.replace(/-/g,"+").replace(/_/g,"/")):Buffer.from(part,"base64url").toString();if(JSON.parse(raw).role==="service_role")fail("BUILD01_SECRET_KEY_FORBIDDEN");}catch(e){if(e.code)throw e;}}
  if(c.publishableKey.startsWith("sb_secret_"))fail("BUILD01_SECRET_KEY_FORBIDDEN");
  return {url:u.origin,key:c.publishableKey};
 }
 function create(options){
  options=options||{};
  const target=config(options.config);
  const lib=options.library||(typeof window!=="undefined"?window.supabase:null);
  const client=options.client||(lib&&lib.createClient?lib.createClient(target.url,target.key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}}):null);
  if(!client||!client.auth||typeof client.auth.getUser!=="function"||typeof client.schema!=="function")fail("BUILD01_SIGNED_CLIENT_REQUIRED");
  function unwrap(r){
   if(!r||r.error){
    const raw=r&&r.error&&(r.error.message||r.error.code);
    fail(typeof raw==="string"&&/^[a-zA-Z0-9_.:-]{1,120}$/.test(raw)?raw:"BUILD01_RPC_DENIED_OR_UNAVAILABLE");
   }
   if(!obj(r.data))fail("BUILD01_INVALID_RESPONSE");
   return r.data;
  }
  async function actor(){
   let r;try{r=await client.auth.getUser();}catch{fail("BUILD01_SESSION_UNAVAILABLE");}
   if(!r||r.error||!r.data||!r.data.user)fail("BUILD01_SIGN_IN_REQUIRED");
   return uid(r.data.user.id);
  }
  async function rpc(name,args,business){
   const who=await actor(),db=client.schema("c10_demo");
   if(!db||typeof db.rpc!=="function")fail("BUILD01_API_UNAVAILABLE");
   const result=unwrap(await db.rpc(name,args||{}));
   if(name==="build01_context_v1"&&result.actor_uid!==who)fail("BUILD01_ACTOR_MISMATCH");
   if(business!==undefined){
    const returned=result.business_id??result.business?.id;
    if(returned===undefined||Number(returned)!==business)fail("BUILD01_SCOPE_MISMATCH");
   }
   return result;
  }
  async function context(){const d=await rpc("build01_context_v1");if(!Array.isArray(d.businesses)||!Array.isArray(d.legal_entities)||!Array.isArray(d.templates))fail("BUILD01_INVALID_CONTEXT");return d;}
  async function workspace(business){const n=id(business),d=await rpc("build01_workspace_v1",{p_business:n},n);if(!Array.isArray(d.sites)||!obj(d.access)||!Array.isArray(d.audit))fail("BUILD01_INVALID_WORKSPACE");return d;}
  async function signIn(email,password){
   if(typeof email!=="string"||!email.includes("@")||typeof password!=="string"||!password)fail("BUILD01_CREDENTIALS_REQUIRED");
   const r=await client.auth.signInWithPassword({email:email.trim(),password});
   if(!r||r.error||!r.data||!r.data.user)fail("BUILD01_LOGIN_FAILED");
   return context();
  }
  async function signOut(){const r=await client.auth.signOut({scope:"local"});if(r&&r.error)fail("BUILD01_SIGNOUT_FAILED");return {signed_out:true};}
  async function setup(input){
   shape(input,["legalId","slug","template","displayName","mode","sites","requestKey","brandHex"]);
   if(!existing||typeof existing.validateSetup!=="function")fail("BUILD01_SETUP_VALIDATOR_UNAVAILABLE");
   const args=existing.validateSetup(input),d=await rpc("build01_setup_v1",args);
   id(d.business_id);return d;
  }
  async function createSite(input){
   shape(input,["businessId","kind","label","requestKey"]);
   const business=id(input.businessId);
   if(!["showroom","factory","godown","warehouse","project"].includes(input.kind))fail("BUILD01_INVALID_SITE_KIND");
   const d=await rpc("build01_site_v1",{p_business:business,p_kind:input.kind,p_label:text(input.label),p_request:key(input.requestKey)},business);
   id(d.site_id);return d;
  }
  async function changeAccess(input){
   shape(input,["businessId","subjectUid","command","role","siteId","actions","deniedActions","expiresAt","requestKey","expectedVersion"]);
   const business=id(input.businessId),subject=uid(input.subjectUid),command=input.command;
   if(!["business_member.grant","business_member.revoke","site_grant.grant","site_grant.revoke"].includes(command))fail("BUILD01_INVALID_COMMAND");
   const member=command.startsWith("business_member."),grant=command.endsWith(".grant");
   const role=input.role==null||input.role===""?null:input.role;
   const site=input.siteId==null||input.siteId===""?null:id(input.siteId);
   const allowed=actions(input.actions||[]),denied=actions(input.deniedActions||[]);
   if(member&&(site!==null||allowed.length||denied.length)||!member&&site===null)fail("BUILD01_INVALID_ACCESS_SCOPE");
   if(member&&grant&&!["business_owner","manager","investor"].includes(role)||(!member||!grant)&&role!==null)fail("BUILD01_INVALID_ROLE");
   if(!grant&&(allowed.length||denied.length||input.expiresAt))fail("BUILD01_REVOKE_HAS_POLICY");
   let expiry=null;if(input.expiresAt){const date=new Date(input.expiresAt);if(!Number.isFinite(date.valueOf()))fail("BUILD01_INVALID_EXPIRY");expiry=date.toISOString();}
   const version=input.expectedVersion??null;
   if(version!==null&&(!Number.isSafeInteger(version)||version<0))fail("BUILD01_INVALID_VERSION");
   return rpc("build01_set_access_v1",{p_business:business,p_subject:subject,p_command:command,p_role:role,p_site:site,p_actions:allowed,p_denied_actions:denied,p_valid_until:expiry,p_request:key(input.requestKey),p_expected_version:version},business);
  }
  async function effectivePermission(input){
   shape(input,["businessId","siteId","action"]);
   if(!["stock.read","stock.post"].includes(input.action))fail("BUILD01_INVALID_ACTIONS");
   const d=await workspace(input.businessId),site=d.sites.find(s=>Number(s.id)===id(input.siteId));
   return {business_id:id(input.businessId),site_id:id(input.siteId),action:input.action,allowed:!!site&&Array.isArray(site.allowed_actions)&&site.allowed_actions.includes(input.action),source:"fresh_server_workspace"};
  }
  async function audit(business){return (await workspace(business)).audit;}
  return Object.freeze({signIn,signOut,context,workspace,setup,createSite,changeAccess,effectivePermission,audit});
 }
 return Object.freeze({create});
});
