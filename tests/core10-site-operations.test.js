"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const O=require("../core10-site-operations.js");
test("ten business templates registered",()=>assert.equal(O.TEMPLATES.length,10));
test("business plan requires legal entity and known template",()=>{
 assert.equal(O.planBusiness({legal_entity_id:1,template_code:"sweets_bakery",name:"Islamia"}).ok,true);
 assert.equal(O.planBusiness({legal_entity_id:1,template_code:"unknown",name:"X"}).ok,false);
});
test("site drafts require valid business, type and name",()=>{
 assert.equal(O.createSiteDraft({business_id:1,kind:"factory",name_bn:"কারখানা"}).draft.status,"setting_up");
 assert.equal(O.createSiteDraft({business_id:1,kind:"warehouse",name_en:"Store"}).ok,false);
});
test("live activation is gated by readiness",()=>{
 const site={id:4,business_id:1,status:"setting_up"};
 assert.equal(O.transition(site,"live",{}).reason,"activation_prerequisites_missing");
 assert.equal(O.transition(site,"live",{business_verified:true,permissions_verified:true,stock_locations_verified:true}).ok,true);
 assert.equal(O.transition({...site,status:"closed"},"live",{}).ok,false);
});
test("transfer draft stays business-scoped and checks live endpoints",()=>{
 const x={business_id:1,from_business_id:1,to_business_id:1,from_location_id:10,to_location_id:11,item_id:3,quantity:2,from_site_status:"live",to_site_status:"live"};
 assert.equal(O.transfer(x).command.status,"draft");
 assert.equal(O.transfer({...x,to_business_id:2}).reason,"cross_business_transfer");
 assert.equal(O.transfer({...x,quantity:-2}).reason,"invalid_quantity");
 assert.equal(O.transfer({...x,to_site_status:"paused"}).reason,"site_not_live");
});
test("summary preserves unmapped locations",()=>{
 const s=[{id:3,business_id:1,kind:"factory"}],l=[{id:5,business_id:1,site_id:3},{id:6,business_id:1,site_id:null}];
 const x=O.summarize(s,l,1);assert.equal(x.sites,1);assert.equal(x.stock_locations,2);assert.equal(x.unmapped_locations,1);
});
