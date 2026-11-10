"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const root=path.resolve(__dirname,".."),dictionary=require("../data/item_dictionary.json");
const templates=require("../data/core10_capability_catalog_v1.json").templates;
const item=require("../core10-engines/item-policy.js"),reports=require("../core10-engines/report-families.js");
const result=item.coverage(dictionary);
assert.equal(result.total,1312);assert.equal(result.classified,1312);assert.equal(result.unclassified,0);
assert.equal(result.roles.resale,303);assert.equal(result.roles.finished_good,208);
assert.equal(result.roles.asset,162);assert.equal(result.roles.raw_material,149);
for(const row of dictionary){
 const r=item.suggest(row,{industryId:"retail_wholesale"});
 assert.equal(r.state,"suggestion_only");assert.equal(r.mustApprove,true);
 assert.equal(r.changesOperationalData,false);assert.equal(r.actualCost,null);
 assert.equal(r.defaultSellable,["resale","finished_good"].includes(r.role));
}
assert.equal(item.suggest({code:"X",control_class:"New class"}).state,"review_required");
assert.equal(item.suggest(null).state,"review_required");
for(const t of templates){
 const modules=t.modules.map(m=>m.id);
 const suggested=reports.propose(t,modules);
 assert.equal(suggested.every(r=>r.state==="proposal_only"&&!r.reportImplemented&&r.requiresBusinessScope),true);
 assert.equal(new Set(suggested.map(x=>x.id)).size,suggested.length);
 assert.throws(()=>reports.propose(t,["not_registered_here"]),/UNREGISTERED_MODULE/);
}
const builder=require("../core10-business-builder.js");
const catalog=require("../data/core10_capability_catalog_v1.json");
const example={name:"Example Food Business",slug:"example-food",templateId:"sweets_bakery",
 brandHex:"#315B76",mode:"quick",sites:[],modules:[]};
assert.throws(()=>builder.toBackendInput(catalog,example,{legalId:1,requestKey:"K"}),/TEMPLATE_BACKEND_UNAVAILABLE/);
const legacyCode=require("../data/core10_legacy_preservation_v1.json").legacy_food_template_code;
assert.notEqual(catalog.templates[0].source_code,legacyCode,"Never map shared industry setup to an existing customized business backend");
for(const file of ["core10-engines/item-policy.js","core10-engines/report-families.js"]){
 const source=fs.readFileSync(path.join(root,file),"utf8");
 assert.doesNotMatch(source,/islamia|islamiya|ইসলামিয়া|report_registry\.json|stock\.rpc/i,"Operational tools must be business-neutral");
}
console.log("PASS: 1312 dictionary rules; brand-neutral item classification and module-scoped report families for 10 industries");
