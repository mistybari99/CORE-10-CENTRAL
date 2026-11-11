"use strict";
const assert=require("node:assert/strict");
const catalog=require("../internal/universal-control-studio/control-catalog-v1.json");
const engine=require("../internal/universal-control-studio/control-placement-v1.js");
const studio=require("../internal/universal-control-studio/control-studio-v1.js");
const fails=(fn,code)=>assert.throws(fn,e=>e&&e.code===code,code);
const a={platformId:"platform",tenantId:"tenant-one",businessId:"business-alpha",siteId:"site-a"};
const b={...a,businessId:"business-beta",siteId:"site-b"};
const another={...a,tenantId:"tenant-other",businessId:"business-z",siteId:"site-z"};
const ctl="inventory.count",second="finance.reports";
const rules=[
 {tenantId:"tenant-one",businessId:null,controlId:ctl,placement:"central_only",
  localEditMode:"central_only",menuGroup:"inventory",sortOrder:2},
 {tenantId:"tenant-one",businessId:"business-alpha",controlId:ctl,placement:"both",
  localEditMode:"business_owner",menuGroup:"operations",sortOrder:4},
 {tenantId:"tenant-one",businessId:"business-beta",controlId:ctl,placement:"business_only",
  localEditMode:"request_approval",menuGroup:"inventory",sortOrder:3},
 {tenantId:"tenant-one",businessId:"business-alpha",controlId:second,placement:"hidden_from_menus",
  localEditMode:"central_only",menuGroup:"finance",sortOrder:5}
];
assert.equal(engine.validatePlacementRules(catalog,rules),true);
const ca=engine.getPlacement(catalog,ctl,a,rules);
const cb=engine.getPlacement(catalog,ctl,b,rules);
const cz=engine.getPlacement(catalog,ctl,another,rules);
assert.equal(ca.placement,"both");assert.equal(ca.businessMenu,true);assert.equal(ca.centralMenu,true);
assert.equal(cb.placement,"business_only");assert.equal(cb.businessMenu,true);assert.equal(cb.centralMenu,false);
assert.equal(cz.placement,"central_only","other tenant must not inherit tenant-one placement");
assert.equal(cz.source,"registry_default");
const hidden=engine.getPlacement(catalog,second,a,rules);
assert.equal(hidden.centralMenu,false);assert.equal(hidden.businessMenu,false);
assert.equal(hidden.universalRegistryDiscoverable,true,"hidden menu is never an inaccessible ghost rule");
const values=[
 {controlId:ctl,scope:"business",scopeId:"business-alpha",value:"on"},
 {controlId:ctl,scope:"business",scopeId:"business-beta",value:"off"}
];
const centralA=engine.projectSurface(catalog,a,rules,"central",{settings:values});
const businessA=engine.projectSurface(catalog,a,rules,"business",{settings:values});
const centralB=engine.projectSurface(catalog,b,rules,"central",{settings:values});
const businessB=engine.projectSurface(catalog,b,rules,"business",{settings:values});
const find=(items,id)=>items.find(r=>r.controlId===id);
assert.equal(find(centralA,ctl).controlId,find(businessA,ctl).controlId,
 "central and local UI must reference exact same canonical control id");
assert.equal(find(centralA,ctl).switchPreviewOn,true);
assert.equal(find(businessA,ctl).switchPreviewOn,true);
assert.equal(find(businessB,ctl).switchPreviewOn,false,
 "each business may configure its own effective values");
assert.equal(find(centralB,ctl),undefined,"business_only is hidden from standard central menu");
assert.equal(find(businessB,ctl).canRequestLocalChange,true);
assert.equal(find(businessB,ctl).localEditCandidate,false);
assert.equal(find(businessA,ctl).localEditCandidate,true);
assert.equal(find(centralA,second),undefined);
assert.equal(find(businessA,second),undefined);
for(const row of [...centralA,...businessA,...businessB]){
 assert.equal(row.canExecute,false);
 assert.equal(row.realPermissionGranted,false);
 assert.equal(row.operationallyCertified,false);
}
const move=engine.proposePlacement(catalog,a,rules,{
 controlId:ctl,targetBusinessId:"business-alpha",placement:"business_only",
 localEditMode:"request_approval",menuGroup:"inventory",sortOrder:7,
 reason:"Move this module to the local business control panel",
 requestKey:"placement.control.move.0001"
});
assert.equal(move.status,"proposed");
assert.equal(move.diff.from,"both");
assert.equal(move.diff.to,"business_only");
assert.equal(move.diff.preservesCanonicalId,true);
assert.equal(move.diff.doesNotChangeModuleSwitch,true);
assert.equal(move.diff.doesNotChangeRoleGrant,true);
assert.equal(move.persisted,false);
assert.equal(move.applied,false);
assert.equal(move.canExecute,false);
assert.equal(engine.getPlacement(catalog,ctl,a,rules).placement,"both",
 "proposal must never mutate the actual placement records");
const businessChange=engine.proposeBusinessSetting(catalog,a,rules,{
 controlId:ctl,value:"on",reason:"Enable business-level count workflow",
 requestKey:"business.count.change.0001"
});
assert.equal(businessChange.approvalRequired,false);
assert.equal(businessChange.change.scope,"business");
assert.equal(businessChange.change.scopeId,"business-alpha");
assert.equal(businessChange.change.canExecute,false);
const requested=engine.proposeBusinessSetting(catalog,b,rules,{
 controlId:ctl,value:"on",reason:"Need local approval to enable count",
 requestKey:"business.count.change.0002"
});
assert.equal(requested.approvalRequired,true);
assert.equal(requested.requestOnly,true);
assert.equal(requested.canExecute,false);
fails(()=>engine.proposeBusinessSetting(catalog,a,rules,{
 controlId:second,value:"on",reason:"hidden does not appear in local panel",
 requestKey:"business.finance.change.0001"}),"CONTROL_NOT_IN_BUSINESS_SURFACE");
fails(()=>engine.proposeBusinessSetting(catalog,another,rules,{
 controlId:ctl,value:"on",reason:"no central delegation for other tenant",
 requestKey:"business.count.change.0003"}),"CONTROL_NOT_IN_BUSINESS_SURFACE");
fails(()=>engine.proposePlacement(catalog,a,rules,{
 controlId:ctl,targetBusinessId:"business-beta",placement:"both",
 localEditMode:"central_only",menuGroup:"inventory",sortOrder:4,
 reason:"Try shifting into another business",requestKey:"placement.bad.cross.0001"
}),"PLACEMENT_CROSS_BUSINESS_TARGET_DENIED");
fails(()=>engine.proposePlacement(catalog,a,rules,{
 controlId:"isolation.tenant",targetBusinessId:"business-alpha",placement:"both",
 localEditMode:"central_only",menuGroup:"settings",sortOrder:4,
 reason:"Try moving mandatory security",requestKey:"placement.bad.secure.0001"
}),"UNKNOWN_PLACEMENT_CONTROL");
fails(()=>engine.validatePlacementRules(catalog,[rules[0],rules[0]]),"DUPLICATE_PLACEMENT_SCOPE");
fails(()=>engine.validatePlacementRules(catalog,[{...rules[1],localEditMode:"business_owner",placement:"central_only"}]),
 "LOCAL_EDIT_REQUIRES_BUSINESS_SURFACE");
fails(()=>engine.validatePlacementRules(catalog,[{...rules[1],localEditMode:"business_owner",placement:"hidden_from_menus"}]),
 "HIDDEN_CONTROL_CANNOT_BE_LOCALLY_EDITABLE");
fails(()=>engine.projectSurface(catalog,a,rules,"universal_everyone"),"UNKNOWN_CONTROL_SURFACE");
fails(()=>engine.projectSurface(catalog,{businessId:"business-alpha"},rules,"business"),
 "BUSINESS_CONTEXT_REQUIRED");
assert.equal(studio.previewFeature(catalog,ctl,a,values).switchOn,true);
assert.equal(studio.previewFeature(catalog,ctl,b,values).switchOn,false);
console.log("PASS C10-A043: central/business/both/hidden presentation, per-business values, central searchable, tenant isolation, delegated settings request, immutable ID, zero real permission");
