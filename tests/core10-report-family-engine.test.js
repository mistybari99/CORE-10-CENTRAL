"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const report=require("../core10-operational-report-policy.js");
const router=require("../core10-operational-router.js");
const catalog=require("../data/core10_capability_catalog_v1.json");
const item=require("../core10-operational-item-policy.js");
const source=fs.readFileSync(path.join(__dirname,"../core10-operational-report-policy.js"),"utf8");
assert.doesNotMatch(source,/islamia|islamiya|ইসলামিয়া|report_registry|legacy.parity|BOS_APP/i);
const registry=router.create();
router.installItemPolicy(registry,item);report.install(registry,catalog);
assert.deepEqual(registry.list(),["item.policy.recommend","report.family.propose"]);
for(const t of catalog.templates){
 const context={businessId:"business-test",industryId:t.id};
 const selection=t.modules.map(x=>x.id);
 const result=registry.invoke("report.family.propose",context,{business_id:"business-test",modules:selection});
 assert.equal(result.businessId,context.businessId);assert.equal(result.industryId,t.id);
 assert.equal(result.status,"proposal_only");assert.equal(result.writesPerformed,false);
 assert.equal(result.legacyRoutesImported,false);
 const ids=new Set();
 for(const c of result.categories){
  assert.equal(c.realReportReady,false);
  assert.equal(c.requiresBusinessScopedBackend,true);
  assert.ok(c.sourceModules.every(m=>selection.includes(m)));
  assert.equal(ids.has(c.familyId),false,"No duplicate report family");
  ids.add(c.familyId);
 }
 assert.throws(()=>registry.invoke("report.family.propose",context,{modules:["other_industry_only"]}),/UNREGISTERED_INDUSTRY_MODULE/);
 assert.throws(()=>registry.invoke("report.family.propose",context,{business_id:"foreign",modules:[]}),/INPUT_SCOPE_MISMATCH/);
}
const build=catalog.templates.find(x=>x.id==="construction");
const actual=registry.invoke("report.family.propose",{businessId:"xyz",industryId:"construction"},
 {modules:build.modules.filter(x=>["project_boq","progress_billing"].includes(x.id)).map(x=>x.id)});
assert.ok(actual.categories.some(x=>x.familyId==="project_estimate"));
assert.ok(actual.categories.some(x=>x.familyId==="project_billing"));
const pkg=catalog.templates.find(x=>x.id==="sweets_bakery");
const neutral=registry.invoke("report.family.propose",{businessId:"zz",industryId:pkg.id},
 {modules:pkg.modules.filter(x=>["stock","costing"].includes(x.id)).map(x=>x.id)});
assert.ok(neutral.categories.some(x=>x.familyId==="stock_balance"));
assert.ok(neutral.categories.some(x=>x.familyId==="cost_coverage"));
assert.equal(neutral.categories.every(x=>!x.realReportReady),true);
assert.throws(()=>registry.invoke("report.family.propose",{businessId:"",industryId:"services"},{modules:[]}),/BUSINESS_CONTEXT_REQUIRED/);
console.log("PASS: 10-industry scoped, neutral report family engine; no legacy reports or ready claims, read-only router invocation");
