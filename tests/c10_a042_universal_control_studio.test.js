"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path");
const studio=require("../internal/universal-control-studio/control-studio-v1.js");
const catalog=require("../internal/universal-control-studio/control-catalog-v1.json");
const fails=(fn,code)=>assert.throws(fn,e=>e&&e.code===code,code);
const copy=x=>JSON.parse(JSON.stringify(x));
const source=studio.verifyRegistry(catalog);
assert.equal(source.operational_status,"contract_only");
assert.ok(source.controls.length>=18);
assert.ok(source.protected_invariants.length>=10);
assert.ok(Object.isFrozen(source.controls[0]));
const scope={platformId:"platform",tenantId:"t1",businessId:"b1",siteId:"s1"};
const ctl="inventory.count";
const enabled=[{controlId:ctl,scope:"business",scopeId:"b1",value:"on"}];
const owner=studio.previewFeature(catalog,ctl,scope,enabled);
assert.equal(owner.switchOn,true);
assert.equal(owner.canExecute,false);
assert.equal(owner.operationallyCertified,false);
assert.equal(studio.previewFeature(catalog,ctl,{...scope,businessId:"b2",siteId:"s2"},enabled).switchOn,false,
 "different business must not inherit a sibling ON");
assert.equal(studio.previewFeature(catalog,ctl,scope,[...enabled,
 {controlId:ctl,scope:"tenant",scopeId:"t1",value:"off"}]).switchOn,false,
 "ancestor OFF cannot be lifted by narrower business ON");
assert.equal(studio.previewFeature(catalog,ctl,scope,[...enabled,
 {controlId:ctl,scope:"site",scopeId:"s1",value:"off"}]).switchOn,false);
const dep=[
 {controlId:"approvals.delegation",scope:"business",scopeId:"b1",value:"on"},
 {controlId:"approvals.owner_queue",scope:"business",scopeId:"b1",value:"on"}
];
assert.equal(studio.previewFeature(catalog,"approvals.delegation",scope,dep).switchOn,true);
assert.equal(studio.previewFeature(catalog,"approvals.delegation",scope,dep.slice(0,1)).switchOn,false);
const action="inventory.count.read";
const actor={userId:"person1",roles:["staff","counter"]};
const grant={controlId:ctl,action,subjectType:"role",subjectId:"staff",
 scope:"business",scopeId:"b1",effect:"allow",expiresAt:"2031-01-01T00:00:00Z"};
const req={controlId:ctl,action,actor,context:scope,overrides:enabled,
 grants:[grant],now:"2029-01-01T00:00:00Z"};
const allowed=studio.previewAccess(catalog,req);
assert.equal(allowed.grantPreview,"allow");
assert.equal(allowed.visibility,"show");
assert.equal(allowed.candidateAllowed,true);
assert.equal(allowed.canExecute,false,"policy preview must not authorize server writes");
const deny={...grant,subjectType:"user",subjectId:"person1",effect:"deny"};
assert.equal(studio.previewAccess(catalog,{...req,grants:[grant,deny]}).grantPreview,"deny");
assert.equal(studio.previewAccess(catalog,{...req,grants:[grant,deny]}).visibility,"locked");
assert.equal(studio.previewAccess(catalog,{...req,now:"2032-01-01T00:00:00Z"}).grantPreview,"none");
assert.equal(studio.previewAccess(catalog,{...req,context:{...scope,businessId:"b2",siteId:"s2"}}).grantPreview,"none");
assert.equal(studio.previewAccess(catalog,{...req,grants:[]}).candidateAllowed,false);
const rolePref={controlId:ctl,scope:"business",scopeId:"b1",subjectType:"role",subjectId:"staff",value:"hidden"};
const userPref={...rolePref,subjectType:"user",subjectId:"person1",value:"show"};
assert.equal(studio.previewAccess(catalog,{...req,preferences:[rolePref]}).visibility,"hidden");
const u=studio.previewAccess(catalog,{...req,preferences:[rolePref,userPref]});
assert.equal(u.visibility,"show");assert.equal(u.canExecute,false);
const proposal=studio.prepareChange(catalog,{controlId:ctl,scope:"business",scopeId:"b1",
 value:"on",reason:"Enable approved module for this business",requestKey:"change.inventory.001"});
assert.equal(proposal.lifecycle,"proposed");
assert.equal(proposal.persisted,false);assert.equal(proposal.applied,false);
assert.ok(proposal.gates.includes("IMMUTABLE_AUDIT"));
fails(()=>studio.prepareChange(catalog,{controlId:"isolation.tenant",scope:"business",
 scopeId:"b1",value:"off",reason:"Disable isolation check",requestKey:"change.isolation.001"}),
 "PROTECTED_INVARIANT_NOT_SWITCHABLE");
fails(()=>studio.prepareChange(catalog,{controlId:ctl,scope:"role",scopeId:"staff",
 value:"on",reason:"Staff must not enable feature globally",requestKey:"change.role.001"}),"INVALID_CONTROL_OVERRIDE");
fails(()=>studio.previewAccess(catalog,{...req,action:"inventory.count.force_post"}),"UNKNOWN_CONTROL_ACTION");
fails(()=>studio.previewFeature(catalog,ctl,scope,[...enabled,...enabled]),"DUPLICATE_CONTROL_OVERRIDE");
fails(()=>studio.previewFeature(catalog,ctl,{businessId:"b1"},enabled),"UNVERIFIED_SCOPE_CONTEXT");
const micro=studio.draftMicroEngine(catalog,{id:"rules.owner.exception",
 kind:"rule",description:"Owner controlled exception rule with scope and audit",
 requiredControls:["approvals.owner_queue"],actions:["approvals.owner_queue.decide"]});
assert.equal(micro.canExecute,false);
assert.equal(micro.handlerRegistered,false);
assert.equal(micro.operationalStatus,"not_implemented");
fails(()=>studio.draftMicroEngine(catalog,{id:"rules.unknown",
 kind:"workflow",description:"Missing dependency for this module",
 requiredControls:["security.server_side"],actions:["approvals.owner_queue.decide"]}),"UNKNOWN_MICRO_ENGINE_DEPENDENCY");
const broken=copy(catalog);broken.controls.find(x=>x.id==="approvals.owner_queue").dependencies=["approvals.delegation"];
fails(()=>studio.verifyRegistry(broken),"CONTROL_DEPENDENCY_CYCLE:approvals.owner_queue");
const duplicate=copy(catalog);duplicate.controls.push(copy(duplicate.controls[0]));
fails(()=>studio.verifyRegistry(duplicate),"DUPLICATE_CONTROL_ID");
const doc=fs.readFileSync(path.resolve(__dirname,"../docs/architecture/CORE10_UNIVERSAL_CONTROL_STUDIO_V1.md"),"utf8");
assert.match(doc,/No explicit grant/i);
assert.match(doc,/Micro-Engine Workshop/);
assert.doesNotMatch(JSON.stringify(catalog)+doc,/islamia|misty|sweet|bakery|মিষ্টি/i);
console.log("PASS C10-A042 universal control contract: "+catalog.controls.length+" feature switches, 10 immutable rules, scoped OFF, deny precedence, expiry, UI visibility, change and micro-engine drafts, no real authorization");
