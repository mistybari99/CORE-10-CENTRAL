// CORE 10 CENTRAL A018 | deterministic read-only capability contract tests.
// Run from repository root: node tests/core10-foundation-catalog-smoke.js
// These tests DO NOT certify live ERP workflows, database RLS, or 300+ site capacity.
"use strict";
const assert=require("node:assert/strict");
const manifest=require("../data/core10_capability_catalog_v1.json");
const registry=require("../core10-capability-registry.js");
const clone=v=>JSON.parse(JSON.stringify(v));
const evidence=()=>Object.fromEntries(["end_to_end","authenticated_permissions","report_reconciliation","security_negative_tests","rollback_recovery"].map(k=>[k,"fixture-only:"+k]));

function testCatalogStructure(){
 const verdict=registry.validateCatalog(manifest);
 assert.equal(verdict.ok,true,verdict.errors.join(", "));
 assert.equal(manifest.templates.length,10);
 assert.equal(new Set(manifest.templates.map(t=>t.id)).size,10);
 assert.deepEqual(manifest.canonical_hierarchy.map(x=>x.kind),registry.CANONICAL_HIERARCHY);
 assert.equal(manifest.enterprise_capacity_target.hard_limit,false);
 assert.equal(manifest.enterprise_capacity_target.measured,false);
 assert.ok(manifest.enterprise_capacity_target.branches_per_business>=100);
 assert.ok(manifest.enterprise_capacity_target.factories_per_business>=100);
 assert.ok(manifest.enterprise_capacity_target.warehouses_per_business>=100);
 assert.equal(manifest.invariants.require_backend_tenant_business_isolation,true);
 assert.equal(manifest.invariants.never_toggle_org_scope_on_automatically,true);
 assert.equal(manifest.invariants.preserve_existing_location_ids,true);
 console.log("PASS A018: ten templates, canonical enterprise hierarchy and no artificial 300-site ceiling");
}
function testFalseReadinessIsBlocked(){
 assert.equal(manifest.templates.filter(t=>t.source_status==="available").length,1);
 assert.equal(registry.findTemplate(manifest,"sweets_bakery").source_code,"food_manufacturing");
 assert.equal(registry.findTemplateByLiveCode(manifest,"hardware_paint").id,"paint_hardware");
 assert.equal(registry.findTemplateByLiveCode(manifest,"import_export").readiness,"partial");
 assert.equal(registry.findTemplate(manifest,"restaurant").source_status,"unregistered");
 assert.ok(manifest.optional_packs.some(p=>p.id==="dealership"));
 const summary=registry.listTemplateSummaries(manifest);
 assert.equal(summary.length,10);
 assert.ok(summary.every(row=>row.eligible===false));
 assert.equal(registry.assessReadiness(manifest,"sweets_bakery").eligible,false);
 assert.ok(registry.assessReadiness(manifest,"sweets_bakery").reasons.includes("TEMPLATE_NOT_CERTIFIED"));
 assert.ok(registry.assessReadiness(manifest,"restaurant").reasons.includes("BACKEND_NOT_AVAILABLE"));
 assert.deepEqual(registry.assessReadiness(manifest,"UNKNOWN").reasons,["UNKNOWN_TEMPLATE"]);
 console.log("PASS A018: an available DB template does not imply end-to-end certified readiness");
}
function testRejectFabricatedReadiness(){
 const invalid=clone(manifest);
 invalid.templates[0].readiness="supported_and_tested";
 assert.ok(registry.validateCatalog(invalid).errors.includes("templates[0]:uncertified_template"));
 assert.equal(registry.assessReadiness(invalid,"sweets_bakery").eligible,false);
 const partiallyVerified=clone(manifest);
 partiallyVerified.templates[0].readiness="supported_and_tested";
 partiallyVerified.templates[0].verification=evidence();
 const partial=registry.validateCatalog(partiallyVerified);
 assert.equal(partial.ok,false);
 assert.ok(partial.errors.includes("templates[0]:module_not_certified"));
 const synthetic=clone(manifest);
 synthetic.templates[0].readiness="supported_and_tested";
 synthetic.templates[0].verification=evidence();
 synthetic.templates[0].modules.forEach(m=>{m.status="supported_and_tested";m.verification=evidence()});
 assert.equal(registry.validateCatalog(synthetic).ok,true);
 assert.equal(registry.assessReadiness(synthetic,"sweets_bakery").eligible,true);
 assert.equal(registry.assessReadiness(synthetic,"restaurant").eligible,false);
 console.log("PASS A018: every module and template needs explicit E2E evidence before readiness");
}
function testDataModelFailuresFailClosed(){
 assert.equal(registry.validateCatalog(null).ok,false);
 assert.equal(registry.assessReadiness(null,"sweets_bakery").eligible,false);
 const dupe=clone(manifest);
 dupe.templates.push(clone(dupe.templates[0]));
 assert.equal(registry.validateCatalog(dupe).ok,false);
 const unsafe=clone(manifest);
 unsafe.invariants.require_backend_tenant_business_isolation=false;
 assert.equal(registry.validateCatalog(unsafe).ok,false);
 const badSiteCount=clone(manifest);
 badSiteCount.enterprise_capacity_target.branches_per_business=8;
 assert.equal(registry.validateCatalog(badSiteCount).ok,false);
 const missing=clone(manifest);
 missing.templates=missing.templates.filter(t=>t.id!=="construction");
 assert.equal(registry.validateCatalog(missing).ok,false);
 const falseBackend=clone(manifest);
 falseBackend.templates[1].source_code="restaurant";
 assert.equal(registry.validateCatalog(falseBackend).ok,false);
 const badModules=clone(manifest);
 badModules.templates[0].modules[1].id=badModules.templates[0].modules[0].id;
 assert.equal(registry.validateCatalog(badModules).ok,false);
 console.log("PASS A018: malformed, duplicate, unauthorized and artificially capped catalogs fail closed");
}
function main(){
 testCatalogStructure();
 testFalseReadinessIsBlocked();
 testRejectFabricatedReadiness();
 testDataModelFailuresFailClosed();
 console.log("PASS: CORE 10 A018 foundation catalog CONTRACT checks only; NOT a live tenancy or load certification");
}
main();
