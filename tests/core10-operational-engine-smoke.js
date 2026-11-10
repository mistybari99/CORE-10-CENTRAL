"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const policy=require("../core10-operational-item-policy.js");
const routerLib=require("../core10-operational-router.js");
const dictionary=require("../data/item_dictionary.json");
const source=fs.readFileSync(path.resolve(__dirname,"../core10-operational-item-policy.js"),"utf8")+
 fs.readFileSync(path.resolve(__dirname,"../core10-operational-router.js"),"utf8");
assert.doesNotMatch(source,/islamia|islamiya|ইসলামিয়া|report_registry|legacy-parity|BOS_APP/i);
const controlClasses=new Set(dictionary.map(x=>x.control_class));
assert.equal(dictionary.length,1312);
assert.equal(new Set(dictionary.map(x=>x.code)).size,1312);
for(const c of controlClasses)assert.ok(policy.CLASS_TO_KIND[c],"Unknown dictionary control class: "+c);
let observed=0;
for(const row of dictionary){
 const before=JSON.stringify(row),out=policy.recommend(row,{industryId:"retail_wholesale"});
 assert.equal(out.writesPerformed,false);
 assert.equal(JSON.stringify(row),before,"Advisor must not alter dictionary record");
 assert.equal(out.kind,policy.CLASS_TO_KIND[row.control_class]);
 assert.equal(out.recommendation.readiness,"proposal_only_requires_validation");
 observed++;
}
assert.equal(observed,1312);
const restaurant=policy.recommend({code:"RAW1",control_class:"Raw Material",sellable:false,tracked:true},{industryId:"restaurant"});
assert.equal(restaurant.recommendation.optionalIndustryHint,"recipe_and_kitchen_consumption");
assert.equal(restaurant.existingFlags.sellable,false);
const construction=policy.recommend({code:"MAT1",control_class:"Raw Material"},{industryId:"construction"});
assert.equal(construction.recommendation.optionalIndustryHint,"project_issue_and_boq");
const asset=policy.recommend({code:"X",control_class:"Asset",sellable:true,locked:true},{industryId:"services"});
assert.equal(asset.recommendation.tracking,"asset_register");
assert.equal(asset.existingFlags.sellable,true,"Never overwrite explicit sell flag");
assert.ok(asset.warnings.includes("SELLABLE_FLAG_NEEDS_POLICY_REVIEW"));
assert.ok(asset.warnings.includes("ITEM_LOCKED_NO_AUTOMATIC_CHANGE"));
const explicit=policy.recommend({code:"A",item_type:"resale_good",control_class:"Packaging"},{industryId:"ecommerce"});
assert.equal(explicit.kind,"resale_good");
assert.ok(explicit.warnings.includes("EXPLICIT_TYPE_DIFFERS_FROM_DICTIONARY_CLASS"));
assert.throws(()=>policy.recommend({}, {industryId:"unknown_sector"}),/UNKNOWN_INDUSTRY/);
const r=routerLib.create();routerLib.installItemPolicy(r,policy);
assert.deepEqual(r.list(),["item.policy.recommend"]);
const output=r.invoke("item.policy.recommend",{businessId:"biz-01",industryId:"paint_hardware"},
 {code:"ABC",control_class:"Stock/Direct Sale",business_id:"biz-01"});
assert.equal(output.kind,"resale_good");
assert.equal(output.industryId,"paint_hardware");
assert.throws(()=>r.invoke("item.policy.recommend",{},{}),/BUSINESS_CONTEXT_REQUIRED/);
assert.throws(()=>r.invoke("item.policy.recommend",{businessId:"biz-01",industryId:"restaurant"},
 {code:"FOREIGN",business_id:"biz-02"}),/INPUT_SCOPE_MISMATCH/);
assert.throws(()=>r.register({id:"money.post",access:"write",execute:()=>{}}),/UNVERIFIED_ENGINE_WRITE_ACCESS/);
for(const industryId of policy.INDUSTRIES) assert.equal(
 r.invoke("item.policy.recommend",{businessId:"biz-01",industryId},
 {code:"1",control_class:"Packaging"}).industryId,industryId);
console.log("PASS: 1,312 dictionary classifications, 10 industries, read-only scoped engine calls, no legacy brand/report dependency");
