"use strict";
const assert=require("node:assert/strict");
const e=require("../engines/item-policy.js");
const original=require("../data/item_dictionary.json");
const standardTypes=["finished_good","resale","raw_material","packaging","consumable","asset","controlled","infrastructure"];
assert.equal(Object.keys(e.TYPES).length,8);
for(const type of standardTypes){
 const r=e.recommend({item_type:type});
 assert.equal(r.ok,true);
 assert.equal(r.status,"PROPOSAL_ONLY");
 assert.equal(typeof r.suggested.sellable,"boolean");
}
assert.equal(e.recommend({item_type:"resale"}).suggested.sellable,true);
assert.equal(e.recommend({item_type:"raw_material"}).suggested.sellable,false);
assert.equal(e.recommend({item_type:"packaging"}).suggested.count_in_operational_stock,true);
assert.equal(e.recommend({item_type:"asset"}).suggested.asset_register,true);
assert.equal(e.recommend({item_type:"asset"}).suggested.count_in_operational_stock,false);
assert.equal(e.recommend({item_type:"unknown"}).ok,false);
assert.equal(e.recommend({item_type:"asset",control_class:"Raw Material"}).ok,false);
const a=e.recommend({item_type:"resale",proposed_overrides:{sellable:false}});
const b=e.recommend({item_type:"resale"});
assert.equal(a.suggested.sellable,false);
assert.equal(b.suggested.sellable,true,"Per-business policy must not bleed to another request");
assert.equal(a.requires_approval,true);
assert.equal(b.requires_approval,false);
assert.equal(e.recommend({item_type:"resale",proposed_overrides:{admin:true}}).ok,false);
const dictCodes=new Set();
for(const entry of original){
 assert.ok(!dictCodes.has(entry.code),"Duplicate dictionary code");
 dictCodes.add(entry.code);
 const out=e.recommend({control_class:entry.control_class});
 assert.equal(out.ok,true,"Dictionary class unsupported for "+entry.code);
}
assert.equal(dictCodes.size,1312,"No legacy dictionary items may be silently excluded");
const catalog=require("../data/core10_capability_catalog_v1.json");
assert.equal(catalog.templates.length,10);
const food=catalog.templates.find(x=>x.id==="sweets_bakery");
assert.equal(food.source_code,null,"No customized backend can be shared by default");
assert.equal(food.source_status,"unregistered");
assert.equal(food.readiness,"not_implemented");
assert.ok(food.modules.every(x=>x.status==="not_implemented"));
for(const t of catalog.templates)assert.notEqual(t.source_code,"food_manufacturing","Legacy customized backend leaked into a shared template");
console.log("PASS 8 neutral item classifications, 1312 dictionary categories, per-business proposal isolation, catalog legacy separation");
