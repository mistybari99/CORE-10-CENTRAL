import test from "node:test";
import assert from "node:assert/strict";
import {createQualityDemo,applyQualityDemo,visibleLots,visibleBusinesses,demoFefo,totalUnits,isExpired} from "./quality-demo.mjs";
const cmd=(type,lotId,key,fields={})=>({type,lotId,key,businessId:101,...fields});
test("two independent demo tenants have isolated business and lot visibility",()=>{
 const s=createQualityDemo();
 assert.deepEqual(visibleBusinesses("foreign").map(x=>x.id),[201]);
 assert.deepEqual(visibleBusinesses("owner").map(x=>x.id),[101,102]);
 assert.deepEqual(visibleLots(s,"foreign",101),[]);
 assert.deepEqual(visibleLots(s,"investor",101),[]);
 assert.deepEqual(visibleLots(s,"revoked",101),[]);
 assert.deepEqual(visibleLots(s,"staff",101).map(x=>x.id),[1,2]);
 assert.equal(visibleLots(s,"owner",101).length,3);
});
test("inspection and owner release from quarantine then issue only after release",()=>{
 let s=createQualityDemo();
 assert.throws(()=>applyQualityDemo(s,"owner",cmd("issue",2,"before-release",{siteId:1001,quantity:1})),/not_sellable/);
 let out=applyQualityDemo(s,"reviewer",cmd("inspect",2,"review-001",{pass:true})); s=out.state;
 assert.throws(()=>applyQualityDemo(s,"reviewer",cmd("decision",2,"wrong-release",{decision:"release"})),/owner_required/);
 out=applyQualityDemo(s,"owner",cmd("decision",2,"release-001",{decision:"release"}));s=out.state;
 assert.equal(s.lots.find(x=>x.id===2).status,"released");
 out=applyQualityDemo(s,"staff",cmd("issue",2,"issue-001",{siteId:1001,quantity:3}));s=out.state;
 assert.equal(totalUnits(s.lots.find(x=>x.id===2)),5);
 const replay=applyQualityDemo(s,"staff",cmd("issue",2,"issue-001",{siteId:1001,quantity:3}));
 assert.equal(replay.replayed,true);
 assert.equal(totalUnits(replay.state.lots.find(x=>x.id===2)),5);
 assert.throws(()=>applyQualityDemo(s,"staff",cmd("issue",2,"issue-001",{siteId:1001,quantity:4})),/idempotency_conflict/);
 assert.throws(()=>applyQualityDemo(s,"staff",cmd("issue",2,"issue-002",{siteId:1001,quantity:10})),/insufficient_lot_stock/);
});
test("expiry, failing inspection and stock hold are enforced",()=>{
 let s=createQualityDemo();
 assert.equal(isExpired(s.lots.find(l=>l.id===3)) ,true);
 assert.throws(()=>applyQualityDemo(s,"owner",cmd("decision",3,"release-old-1",{decision:"release"})),/expired_lot/);
 assert.throws(()=>applyQualityDemo(s,"owner",cmd("dispose",1,"disposal-good",{siteId:1001,quantity:1})),/hold_required/);
 assert.throws(()=>applyQualityDemo(s,"reviewer",cmd("decision",1,"staff-hold",{decision:"hold"})),/owner_required/);
 const out=applyQualityDemo(s,"owner",cmd("decision",1,"hold-001",{decision:"hold"}));s=out.state;
 assert.throws(()=>applyQualityDemo(s,"staff",cmd("transfer",1,"staff-quarantine",{fromSiteId:1001,toSiteId:1002,quantity:2})),/site_scope_denied/);
 const p=applyQualityDemo(s,"owner",cmd("dispose",1,"disposal-held",{siteId:1001,quantity:2}));
 assert.equal(p.state.lots.find(l=>l.id===1).stock[1001],16);
});
test("genealogy recall cascades and requires disposition before closure",()=>{
 let s=createQualityDemo();
 const r=applyQualityDemo(s,"owner",cmd("recall",1,"recall-001",{reason:"Simulated contamination",severity:"critical"}));s=r.state;
 assert.deepEqual(r.result.affected,[1,2]);
 assert.equal(s.lots.find(l=>l.id===2).status,"recalled");
 assert.throws(()=>applyQualityDemo(s,"staff",cmd("issue",1,"recall-sell",{siteId:1001,quantity:1})),/not_sellable/);
 assert.throws(()=>applyQualityDemo(s,"owner",cmd("close_recall",null,"close-early",{recallId:1})),/recall_stock_remaining/);
 for(const l of [1,2]){const lot=s.lots.find(x=>x.id===l);for(const [siteId,qty] of Object.entries(lot.stock)){
 if(qty>0)s=applyQualityDemo(s,"owner",cmd("dispose",l,"dispose-"+l+"-"+siteId,{siteId:Number(siteId),quantity:qty})).state;
 }}
 s=applyQualityDemo(s,"owner",cmd("close_recall",null,"close-clean",{recallId:1})).state;
 assert.equal(s.recalls[0].status,"closed");
 assert.equal(s.lots.find(x=>x.id===1).status,"recalled");
});
test("cross tenant business, duplicates and ancestry cycles are impossible",()=>{
 const s=createQualityDemo();
 assert.throws(()=>applyQualityDemo(s,"foreign",cmd("inspect",1,"foreign-01",{pass:true})),/scope_denied/);
 assert.throws(()=>applyQualityDemo(s,"investor",cmd("inspect",1,"investor-01",{pass:true})),/scope_denied/);
 assert.throws(()=>applyQualityDemo(s,"revoked",cmd("issue",1,"revoked-01",{siteId:1001,quantity:1})),/scope_denied/);
 assert.throws(()=>applyQualityDemo(s,"owner",cmd("link",2,"cycle-001",{childLotId:1})),/genealogy_cycle/);
 assert.throws(()=>applyQualityDemo(s,"owner",cmd("link",1,"cross-biz",{childLotId:4})),/genealogy_scope_denied/);
 assert.throws(()=>applyQualityDemo(s,"owner",cmd("register",null,"invalid-reg",{siteId:1001,item:"Sweets",code:"RAS-261112-A",quantity:10})),/invalid_lot/);
});
test("FEFO ignores unapproved and expired lot; preserves total site stock on transfer",()=>{
 let s=createQualityDemo();
 const plan=demoFefo(s,101,"Rasgolla",1001,10);
 assert.equal(plan[0].suggested,10);
 assert.throws(()=>applyQualityDemo(s,"owner",cmd("transfer",1,"overdraw",{fromSiteId:1001,toSiteId:1002,quantity:99})),/insufficient_lot_stock/);
 const v=applyQualityDemo(s,"owner",cmd("transfer",1,"transfer-001",{fromSiteId:1001,toSiteId:1002,quantity:6}));
 s=v.state;const lot=s.lots.find(x=>x.id===1);
 assert.deepEqual([lot.stock[1001],lot.stock[1002]],[12,11]);
 assert.equal(totalUnits(lot),23);
});
