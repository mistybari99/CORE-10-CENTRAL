"use strict";
/* C10-A042 | Universal Control Studio contract only; no production authorization.
 * Not a Supabase adapter. These pure previews NEVER authorize real API actions.
 */
const SCOPES=["platform","tenant","business","site"];
const REGEX=/^[a-z][a-z0-9]*(?:[._][a-z0-9]+)+$/;
const TYPES=["workflow","rule","calculator","report","validator","approval","notification","automation","integration"];
function fail(code){let e=new Error(code);e.code=code;throw e}
function isObject(x){return x!==null&&typeof x==="object"&&!Array.isArray(x)}
function clone(x){return JSON.parse(JSON.stringify(x))}
function freeze(x){
 if(Array.isArray(x))x.forEach(freeze);
 else if(isObject(x))Object.values(x).forEach(freeze);
 if(x&&typeof x==="object")Object.freeze(x);
 return x;
}
function assertCode(x,code){if(typeof x!=="string"||!REGEX.test(x)||x.length>120)fail(code)}
function verifyRegistry(raw){
 if(!isObject(raw)||raw.schema_version!==1||raw.scope!=="cross_industry"||
    raw.operational_status!=="contract_only"||!Array.isArray(raw.controls)||
    !Array.isArray(raw.protected_invariants)||!Array.isArray(raw.scope_levels)||
    JSON.stringify(raw.scope_levels)!=='["platform","tenant","business","site","role","user"]')
  fail("INVALID_CONTROL_REGISTRY");
 if(raw.protected_invariants.length<8||raw.controls.length<10)fail("INCOMPLETE_CONTROL_REGISTRY");
 const protectedKeys=new Set();
 for(const key of raw.protected_invariants){assertCode(key,"INVALID_PROTECTED_CONTROL");if(protectedKeys.has(key))fail("DUPLICATE_PROTECTED_CONTROL");protectedKeys.add(key)}
 const defs=new Map();
 for(const d of raw.controls){
  if(!isObject(d))fail("INVALID_CONTROL");
  assertCode(d.id,"INVALID_CONTROL_ID");
  if(defs.has(d.id)||protectedKeys.has(d.id))fail("DUPLICATE_CONTROL_ID");
  if(d.type!=="switch"||JSON.stringify(d.options)!=='["on","off"]'||
     !["on","off"].includes(d.default)||d.readiness!=="contract_only"||
     !Array.isArray(d.scopes)||d.scopes.length===0||
     d.scopes.some(s=>!SCOPES.includes(s))||
     new Set(d.scopes).size!==d.scopes.length||
     !Array.isArray(d.dependencies)||!Array.isArray(d.actions)||!d.actions.length||
     d.actions.some(a=>typeof a!=="string"||!REGEX.test(a)))
    fail("INVALID_CONTROL_CONTRACT:"+d.id);
  defs.set(d.id,d)
 }
 function visit(id,ancestors){
  if(ancestors.has(id))fail("CONTROL_DEPENDENCY_CYCLE:"+id);
  const d=defs.get(id);if(!d)fail("UNKNOWN_CONTROL_DEPENDENCY:"+id);
  const seen=new Set(ancestors);seen.add(id);
  for(const dep of d.dependencies){if(!defs.has(dep))fail("UNKNOWN_CONTROL_DEPENDENCY:"+dep);visit(dep,seen)}
 }
 for(const id of defs.keys())visit(id,new Set());
 return freeze(clone(raw))
}
function matchScope(entry,ctx){
 if(!isObject(entry)||!isObject(ctx))return false;
 const col={platform:"platformId",tenant:"tenantId",business:"businessId",site:"siteId"}[entry.scope];
 const expected=col&&ctx[col];
 return typeof expected==="string"&&expected.length>0&&entry.scopeId===expected
}
function verifyContext(ctx){
 if(!isObject(ctx)||typeof ctx.tenantId!=="string"||!ctx.tenantId.trim()||
 typeof ctx.businessId!=="string"||!ctx.businessId.trim())fail("UNVERIFIED_SCOPE_CONTEXT");
 if(ctx.platformId!=null&&(typeof ctx.platformId!=="string"||!ctx.platformId.trim()))fail("INVALID_PLATFORM_CONTEXT");
 if(ctx.siteId!=null&&(typeof ctx.siteId!=="string"||!ctx.siteId.trim()))fail("INVALID_SITE_CONTEXT");
}
function verifyChanges(registry,changes){
 if(!Array.isArray(changes))fail("INVALID_CONTROL_OVERRIDES");
 const defs=new Map(registry.controls.map(x=>[x.id,x])),seen=new Set();
 for(const c of changes){
  if(!isObject(c)||typeof c.controlId!=="string"||!defs.has(c.controlId))fail("UNKNOWN_CONTROL_OVERRIDE");
  const d=defs.get(c.controlId);
  if(!d.scopes.includes(c.scope)||typeof c.scopeId!=="string"||!c.scopeId.trim()||
    c.scopeId.length>128||!d.options.includes(c.value)||
    (c.scope==="platform"&&c.scopeId!=="platform"))
    fail("INVALID_CONTROL_OVERRIDE");
  const key=[c.controlId,c.scope,c.scopeId].join("|");
  if(seen.has(key))fail("DUPLICATE_CONTROL_OVERRIDE");
  seen.add(key)
 }
 return true
}
function previewFeature(raw,id,ctx,changes){
 const registry=verifyRegistry(raw),defs=new Map(registry.controls.map(x=>[x.id,x]));
 if(!defs.has(id))fail("UNKNOWN_CONTROL");
 verifyContext(ctx);
 const items=changes||[];verifyChanges(registry,items);
 const done=new Map();
 function calc(key){
  if(done.has(key))return done.get(key);
  const d=defs.get(key),selected=items.filter(x=>x.controlId===key&&matchScope(x,ctx));
  const isOff=selected.some(x=>x.value==="off");  // Any ancestor OFF is a hard barrier.
  selected.sort((a,b)=>SCOPES.indexOf(a.scope)-SCOPES.indexOf(b.scope));
  const latest=selected[selected.length-1],requested=latest?latest.value:d.default;
  const deps=d.dependencies.map(calc),dependencyOff=deps.some(x=>!x.switchOn);
  const result={
   controlId:key,requested,origin:latest?latest.scope+":"+latest.scopeId:"default",
   switchOn:requested==="on"&&!isOff&&!dependencyOff,
   canExecute:false,advisoryOnly:true,operationallyCertified:false,
   reasons:[...(isOff?["INHERITED_OFF_BARRIER"]:[]),
    ...(dependencyOff?["DEPENDENCY_OFF"]:[]),
    ...(requested!=="on"?["SWITCH_OFF"]:[]),
    "SERVER_PERMISSION_AND_RUNTIME_CERTIFICATION_REQUIRED"]
  };
  done.set(key,result);return result
 }
 return freeze(clone(calc(id)))
}
function previewAccess(raw,input){
 if(!isObject(input)||!isObject(input.actor)||!isObject(input.context))fail("INVALID_ACCESS_REQUEST");
 const registry=verifyRegistry(raw),def=registry.controls.find(x=>x.id===input.controlId);
 if(!def||!def.actions.includes(input.action))fail("UNKNOWN_CONTROL_ACTION");
 const actor=input.actor,ctx=input.context;
 if(typeof actor.userId!=="string"||!actor.userId.trim()||
    !Array.isArray(actor.roles)||actor.roles.some(x=>typeof x!=="string"||!x.trim()))
   fail("INVALID_PREVIEW_ACTOR");
 if(!Array.isArray(input.grants))fail("INVALID_PREVIEW_GRANTS");
 if(input.preferences!=null&&!Array.isArray(input.preferences))fail("INVALID_VISIBILITY_PREFERENCES");
 const t=input.now?Date.parse(input.now):Date.now();
 if(!Number.isFinite(t))fail("INVALID_PREVIEW_TIMESTAMP");
 const feature=previewFeature(registry,input.controlId,ctx,input.overrides||[]);
 const matched=input.grants.filter(g=>{
  if(!isObject(g)||g.controlId!==input.controlId||g.action!==input.action||
     !["allow","deny"].includes(g.effect)||!["user","role"].includes(g.subjectType)||
     !matchScope(g,ctx))return false;
  if(g.subjectType==="user"&&g.subjectId!==actor.userId)return false;
  if(g.subjectType==="role"&&!actor.roles.includes(g.subjectId))return false;
  if(g.expiresAt!=null){
   if(typeof g.expiresAt!=="string"||!Number.isFinite(Date.parse(g.expiresAt))||Date.parse(g.expiresAt)<=t)return false;
  }
  return true;
 });
 const grant=matched.some(g=>g.effect==="deny")?"deny":matched.some(g=>g.effect==="allow")?"allow":"none";
 const prefs=(input.preferences||[]).filter(p=>isObject(p)&&p.controlId===input.controlId&&
  ["show","locked","hidden"].includes(p.value)&&matchScope(p,ctx)&&
  ((p.subjectType==="user"&&p.subjectId===actor.userId)||
   (p.subjectType==="role"&&actor.roles.includes(p.subjectId))));
 const userPrefs=prefs.filter(p=>p.subjectType==="user"),selected=userPrefs.length?userPrefs:prefs;
 const preferred=selected.some(p=>p.value==="hidden")?"hidden":selected.some(p=>p.value==="locked")?"locked":"show";
 const visibility=preferred==="hidden"?"hidden":grant!=="allow"||!feature.switchOn||preferred==="locked"?"locked":"show";
 return freeze({
  controlId:input.controlId,action:input.action,grantPreview:grant,
  visibility,preferredVisibility:preferred,featureSwitchOn:feature.switchOn,
  candidateAllowed:feature.switchOn&&grant==="allow",
  canExecute:false,securityAuthority:"server_only",
  reasons:Array.from(new Set([...feature.reasons,
   ...(grant==="none"?["NO_EXPLICIT_GRANT"]:[]),
   ...(grant==="deny"?["EXPLICIT_DENY_WINS"]:[])]))
 })
}
function prepareChange(raw,req){
 const registry=verifyRegistry(raw);
 if(!isObject(req)||typeof req.controlId!=="string")fail("INVALID_CHANGE_REQUEST");
 if(registry.protected_invariants.includes(req.controlId))fail("PROTECTED_INVARIANT_NOT_SWITCHABLE");
 const d=registry.controls.find(x=>x.id===req.controlId);
 if(!d)fail("UNKNOWN_CONTROL");
 verifyChanges(registry,[{controlId:d.id,scope:req.scope,scopeId:req.scopeId,value:req.value}]);
 if(typeof req.reason!=="string"||req.reason.trim().length<5||
   typeof req.requestKey!=="string"||!REGEX.test(req.requestKey))
  fail("CHANGE_REASON_AND_REQUEST_KEY_REQUIRED");
 return freeze({
  lifecycle:"proposed",controlId:d.id,scope:req.scope,scopeId:req.scopeId,
  targetValue:req.value,requestKey:req.requestKey,reason:req.reason.trim(),
  proposedOnly:true,persisted:false,applied:false,canExecute:false,
  gates:["OWNER_SERVER_AUTHORITY","REAL_SESSION_AND_SCOPE","EFFECTIVE_PERMISSION_PREVIEW",
   "DEPENDENCY_AND_CONFLICT_CHECK","APPROVAL","ATOMIC_WRITE","IMMUTABLE_AUDIT",
   "RESTORE_AND_RELEASE_READINESS"]
 })
}
function draftMicroEngine(raw,input){
 const registry=verifyRegistry(raw);
 if(!isObject(input))fail("INVALID_MICRO_ENGINE");
 assertCode(input.id,"INVALID_MICRO_ENGINE_ID");
 if(!registry.micro_engine_types.includes(input.kind)||
   typeof input.description!=="string"||input.description.trim().length<8||
   !Array.isArray(input.requiredControls)||!input.requiredControls.length||
   !Array.isArray(input.actions)||!input.actions.length||
   input.actions.some(a=>typeof a!=="string"||!REGEX.test(a)))
   fail("INVALID_MICRO_ENGINE_SPEC");
 const controls=new Set(registry.controls.map(x=>x.id));
 if(input.requiredControls.some(x=>!controls.has(x)))fail("UNKNOWN_MICRO_ENGINE_DEPENDENCY");
 return freeze({
  id:input.id,kind:input.kind,description:input.description.trim(),
  requiredControls:Array.from(new Set(input.requiredControls)),
  actions:Array.from(new Set(input.actions)),state:"draft",
  operationalStatus:"not_implemented",handlerRegistered:false,
  persisted:false,canExecute:false,
  releaseGates:["SERVER_IMPLEMENTATION","TENANT_AND_BUSINESS_SCOPE","AUTHZ_RLS_RPC",
   "APPROVAL_AND_AUDIT","NEGATIVE_E2E_TESTS","OWNER_REVIEW"]
 })
}
module.exports={verifyRegistry,verifyChanges,previewFeature,previewAccess,prepareChange,draftMicroEngine};
