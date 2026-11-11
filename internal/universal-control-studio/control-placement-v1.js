"use strict";
/**
 * CORE 10 CENTRAL C10-A043 — Shared Control Placement & Business Projection.
 * SAME canonical control ID in Central Studio and any authorized Business App.
 * Pure advisory contract: NO remote reads/writes, policy grants or role claims.
 */
const studio=require("./control-studio-v1.js");
const PLACEMENTS=Object.freeze(["central_only","business_only","both","hidden_from_menus"]);
const DELEGATION=Object.freeze(["central_only","business_owner","request_approval"]);
const GROUPS=Object.freeze(["settings","access","operations","inventory","finance","reports","automation","integrations","approvals","other"]);
const KEY=/^[a-z][a-z0-9]*(?:[._][a-z0-9]+)+$/;
function fail(code){const e=new Error(code);e.code=code;throw e}
function obj(x){return x!==null&&typeof x==="object"&&!Array.isArray(x)}
function copy(x){return JSON.parse(JSON.stringify(x))}
function freeze(x){
 if(Array.isArray(x))x.forEach(freeze);else if(obj(x))Object.values(x).forEach(freeze);
 if(x&&typeof x==="object")Object.freeze(x);return x;
}
function str(x){return typeof x==="string"&&x.trim().length>0&&x.length<=128}
function context(ctx){
 if(!obj(ctx)||!str(ctx.tenantId)||!str(ctx.businessId))fail("BUSINESS_CONTEXT_REQUIRED");
 if(ctx.siteId!=null&&!str(ctx.siteId))fail("INVALID_SITE_CONTEXT");
 return ctx
}
function normRecord(r){
 if(!obj(r)||!str(r.controlId)||!str(r.tenantId)||!str(r.businessId)&&r.businessId!==null||
    !PLACEMENTS.includes(r.placement)||!DELEGATION.includes(r.localEditMode)||
    !GROUPS.includes(r.menuGroup)||
    !Number.isSafeInteger(r.sortOrder)||r.sortOrder<0||r.sortOrder>9999)
  fail("INVALID_PLACEMENT_RULE");
 if(r.businessId===undefined)fail("MISSING_BUSINESS_SCOPE"); // null means tenant default
 if(r.placement==="central_only"&&r.localEditMode!=="central_only")
  fail("LOCAL_EDIT_REQUIRES_BUSINESS_SURFACE");
 if(r.placement==="hidden_from_menus"&&r.localEditMode!=="central_only")
  fail("HIDDEN_CONTROL_CANNOT_BE_LOCALLY_EDITABLE");
 return r
}
function validatePlacementRules(registry,records){
 const canonical=studio.verifyRegistry(registry),known=new Set(canonical.controls.map(x=>x.id));
 if(!Array.isArray(records))fail("PLACEMENTS_ARRAY_REQUIRED");
 const keys=new Set();
 for(const row of records){
  const r=normRecord(row);
  if(!known.has(r.controlId))fail("UNKNOWN_PLACEMENT_CONTROL");
  const key=[r.tenantId,r.businessId===null?"<tenant>":r.businessId,r.controlId].join("|");
  if(keys.has(key))fail("DUPLICATE_PLACEMENT_SCOPE");
  keys.add(key);
 }
 return true
}
function getPlacement(registry,controlId,ctx,records){
 const catalog=studio.verifyRegistry(registry);
 context(ctx);validatePlacementRules(catalog,records||[]);
 const def=catalog.controls.find(c=>c.id===controlId);
 if(!def)fail("UNKNOWN_PLACEMENT_CONTROL");
 const tenantRows=(records||[]).filter(r=>r.tenantId===ctx.tenantId&&r.controlId===controlId);
 // Tenant-specific baseline never leaks into an unrelated tenant.
 const baseline=tenantRows.find(r=>r.businessId===null);
 const specific=tenantRows.find(r=>r.businessId===ctx.businessId);
 const selected=specific||baseline||null;
 const rules=selected?{
  placement:selected.placement,localEditMode:selected.localEditMode,
  menuGroup:selected.menuGroup,sortOrder:selected.sortOrder
 }:{
  placement:"central_only",localEditMode:"central_only",menuGroup:GROUPS.includes(def.group)?def.group:"settings",
  sortOrder:100
 };
 const centralMenu=rules.placement==="central_only"||rules.placement==="both";
 const businessMenu=rules.placement==="business_only"||rules.placement==="both";
 return freeze({
  controlId:controlId,tenantId:ctx.tenantId,businessId:ctx.businessId,
  placement:rules.placement,localEditMode:rules.localEditMode,menuGroup:rules.menuGroup,
  sortOrder:rules.sortOrder,source:specific?"business":baseline?"tenant":"registry_default",
  centralMenu,businessMenu,universalRegistryDiscoverable:true,
  canonicalControlId:controlId,noDuplicateState:true,canExecute:false,
  serverAuthorizationRequired:true
 })
}
function projectSurface(registry,ctx,records,surface,options){
 const c=studio.verifyRegistry(registry);context(ctx);
 if(!["central","business"].includes(surface))fail("UNKNOWN_CONTROL_SURFACE");
 const opts=options||{};
 if(!obj(opts)||opts.settings!==undefined&&!Array.isArray(opts.settings))fail("INVALID_SURFACE_OPTIONS");
 const list=[];
 for(const control of c.controls){
  const p=getPlacement(c,control.id,ctx,records||[]);
  if(surface==="central"&&!p.centralMenu||surface==="business"&&!p.businessMenu)continue;
  const feat=studio.previewFeature(c,control.id,{
   tenantId:ctx.tenantId,businessId:ctx.businessId,siteId:ctx.siteId,platformId:ctx.platformId
  },opts.settings||[]);
  list.push({
   controlId:p.controlId,scope:{tenantId:ctx.tenantId,businessId:ctx.businessId},
   group:p.menuGroup,sortOrder:p.sortOrder,placement:p.placement,
   inheritedFrom:p.source,localEditMode:p.localEditMode,configuredValue:feat.requested,
   switchPreviewOn:feat.switchOn,operationallyCertified:false,
   canRequestLocalChange:surface==="business"&&p.localEditMode==="request_approval",
   localEditCandidate:surface==="business"&&p.localEditMode==="business_owner",
   canExecute:false,realPermissionGranted:false
  });
 }
 list.sort((a,b)=>a.sortOrder-b.sortOrder||a.group.localeCompare(b.group)||a.controlId.localeCompare(b.controlId));
 return freeze(list)
}
function proposePlacement(registry,ctx,records,req){
 studio.verifyRegistry(registry);context(ctx);
 if(!obj(req)||!str(req.controlId)||!PLACEMENTS.includes(req.placement)||
  !DELEGATION.includes(req.localEditMode)||!GROUPS.includes(req.menuGroup)||
  !Number.isSafeInteger(req.sortOrder)||req.sortOrder<0||req.sortOrder>9999||
  typeof req.reason!=="string"||req.reason.trim().length<5||
  typeof req.requestKey!=="string"||!KEY.test(req.requestKey))
  fail("INVALID_PLACEMENT_PROPOSAL");
 const targetBusiness=req.targetBusinessId===null?null:req.targetBusinessId;
 if(targetBusiness!==null&&(!str(targetBusiness)||targetBusiness!==ctx.businessId))
  fail("PLACEMENT_CROSS_BUSINESS_TARGET_DENIED");
 const next=normRecord({
  controlId:req.controlId,tenantId:ctx.tenantId,businessId:targetBusiness,
  placement:req.placement,localEditMode:req.localEditMode,
  menuGroup:req.menuGroup,sortOrder:req.sortOrder
 });
 const before=getPlacement(registry,req.controlId,ctx,records||[]);
 const diff={
  from:before.placement,to:next.placement,
  businessId:targetBusiness,localEditModeFrom:before.localEditMode,
  localEditModeTo:next.localEditMode,menuGroupTo:next.menuGroup,
  preservesCanonicalId:true,movesUIProjectionOnly:true,
  doesNotChangeModuleSwitch:true,doesNotChangeRoleGrant:true
 };
 return freeze({
  status:"proposed",tenantId:ctx.tenantId,businessId:targetBusiness,
  controlId:req.controlId,reason:req.reason.trim(),requestKey:req.requestKey,
  diff,proposedRule:copy(next),requires:[
   "SIGNED_OWNER_AUTHORITY","SERVER_TENANT_AND_BUSINESS_SCOPE",
   "CANONICAL_CONFIG_STORAGE","APPROVAL_POLICY","VERSIONED_AUDIT","CACHE_INVALIDATION"
  ],
  applied:false,persisted:false,canExecute:false
 })
}
function proposeBusinessSetting(registry,ctx,placements,req){
 context(ctx);
 if(!obj(req)||!str(req.controlId))fail("INVALID_BUSINESS_CHANGE");
 const policy=getPlacement(registry,req.controlId,ctx,placements||[]);
 if(!policy.businessMenu)fail("CONTROL_NOT_IN_BUSINESS_SURFACE");
 if(policy.localEditMode==="central_only")fail("CENTRAL_CONTROL_NOT_DELEGATED");
 const proposal=studio.prepareChange(registry,{
  controlId:req.controlId,scope:"business",scopeId:ctx.businessId,
  value:req.value,reason:req.reason,requestKey:req.requestKey
 });
 return freeze({
  controlId:req.controlId,businessId:ctx.businessId,
  approvalRequired:policy.localEditMode==="request_approval",
  requestOnly:true,canExecute:false,persisted:false,
  commonPolicyRecord:true,change:proposal,
  requiredServerOwnerAuthorization:true
 })
}
module.exports={PLACEMENTS,DELEGATION,GROUPS,validatePlacementRules,
 getPlacement,projectSurface,proposePlacement,proposeBusinessSetting};
