"use strict";
const assert=require("node:assert/strict");
const E=require("../core10-owner-intent-engine.js");
const {GUIDANCE}=require("../core10-owner-intent-guidance.js");
const P=(t)=>E.parse(t);
function ok(t,cap,params,locale){
 const r=P(t);
 assert.equal(r.support_status,"SUPPORTED",t+" -> "+JSON.stringify(r));
 assert.equal(r.capability_key,cap,t);
 for(const [k,v] of Object.entries(params))assert.equal(r.params[k],v,t+" param "+k);
 if(locale)assert.equal(r.locale,locale,t);
 assert.ok(E.validateParams(cap,r.params).ok,t);
 return r;
}
// ---- supported, English + Bangla (P0 worked cases) ----
ok("Warn me if sweets wastage goes above 3% in a batch (kg)","wastage_threshold",{threshold_pct:3,outcome:"warn",unit:"kg",item_group:"sweets"},"en");
ok("মিষ্টির নষ্ট ৩ শতাংশের বেশি হলে আমাকে সতর্ক করো","wastage_threshold",{threshold_pct:3,outcome:"warn",item_group:"sweets"},"bn");
ok("wastage over 2.5 percent needs approval","wastage_threshold",{threshold_pct:2.5,outcome:"approval_required"},"en");
ok("If a 4 litre paint pack discount drops margin below 15% warn me","pack_discount_margin",{pack_litres:4,min_margin_pct:15,outcome:"warn",currency:"BDT"},"en");
ok("পেইন্ট ৪ লিটার প্যাকে ডিসকাউন্ট দিলে মার্জিন ১৫% এর নিচে গেলে অনুমোদন লাগবে","pack_discount_margin",{pack_litres:4,min_margin_pct:15,outcome:"approval_required"},"bn");
ok("500 ml paint pack discount margin below 20% block it","pack_discount_margin",{pack_litres:0.5,min_margin_pct:20,outcome:"block"},"en");
ok("Construction project materials order of 6 lakh taka or more needs my approval","order_total_approval",{threshold:600000,outcome:"approval_required",currency:"BDT"},"en");
ok("প্রকল্পের মালামালের অর্ডার ৬,০০,০০০ টাকা বা তার বেশি হলে আমার অনুমোদন লাগবে","order_total_approval",{threshold:600000,currency:"BDT"},"bn");
ok("purchase order above 2.5 lakh needs approval","order_total_approval",{threshold:250000},"en");
ok("alert me when stock is below 20 kg","low_stock_alert",{threshold:20,outcome:"warn"},"en");
ok("স্টক ১০ পিসের কম হলে সতর্ক করো","low_stock_alert",{threshold:10},"bn");
ok("margin below 10% needs approval","margin_floor_approval",{threshold:10,outcome:"approval_required"},"en");
const mixed=ok("sweets wastage ৫% এর বেশি হলে warn করো","wastage_threshold",{threshold_pct:5},"mixed");
assert.ok(mixed.assumptions.some(a=>a.key==="unit"&&a.editable===true),"assumptions are editable and listed");
// ---- needs clarification (missing / invalid) ----
let r=P("discount below margin 12% needs approval");
assert.equal(r.support_status,"NEEDS_CLARIFICATION");assert.deepEqual(r.missing,["pack_litres"]);assert.equal(r.questions[0].param,"pack_litres");assert.ok(r.questions[0].bn);
r=P("sweets wastage too high warn me");assert.equal(r.support_status,"NEEDS_CLARIFICATION");assert.ok(r.missing.includes("threshold_pct"));
r=P("wastage over 250% warn");assert.equal(r.support_status,"NEEDS_CLARIFICATION");assert.ok(!("threshold_pct" in r.params),"invalid value dropped, not guessed");
r=P("margin below 150% approval");assert.equal(r.support_status,"NEEDS_CLARIFICATION");
r=P("stock below 20%");assert.equal(r.support_status,"NEEDS_CLARIFICATION","a percentage is not a stock quantity");
// ---- invalid locale / empty ----
for(const t of["你好世界，请设置阈值","12345","  ","!!!","مرحبا بالعالم"]){r=P(t);assert.equal(r.locale,"unknown",t);assert.equal(r.support_status,"NEEDS_CLARIFICATION");assert.equal(r.capability_key,null)}
// ---- unsupported / engineering required: never executable ----
const eng=[["Send SMS when stock below 10","notification","notification_v1"],["এসএমএস পাঠাও স্টক কম হলে","notification","notification_v1"],
 ["Sync orders with Shopify api","integration","integration_v1"],["Automatically create purchase order when stock is low","automation","automation_v1"],
 ["two level approval workflow for big orders","workflow","workflow_v1"],["increase salary overtime to 1.5x","payroll_policy",undefined],
 ["ওভারটাইম বেতন বাড়াও","payroll_policy",undefined],["add VAT 15% on sales","tax_policy",undefined],["ভ্যাট হিসাব করো","tax_policy",undefined],
 ["show monthly project materials report","report_handler","report_v1"],["প্রকল্পের মালামালের রিপোর্ট দেখাও","report_handler","report_v1"],
 ["asdf qwer hello world","unclassified",undefined]];
for(const [t,cat,h] of eng){
 r=P(t);
 assert.equal(r.support_status,"ENGINEERING_REQUIRED",t+" "+JSON.stringify(r.support_status));
 assert.equal(r.capability_key,null);assert.equal(r.unsupported.category,cat,t);assert.equal(r.unsupported.a045_handler_id||undefined,h,t);
 assert.ok(r.unsupported.requirement.acceptance_criteria.length>0&&r.unsupported.requirement.blockers.length>0,"structured requirement");
 assert.ok(r.unsupported.reason_bn&&r.unsupported.reason_en);
 assert.deepEqual(r.params,{});
}
const refused=[["Give Rahim admin permission","permission_grant"],["রহিমকে অ্যাডমিন অনুমতি দাও","permission_grant"],["run this SQL to update prices","arbitrary_code"],
 ["এই স্ক্রিপ্ট চালাও","arbitrary_code"],["post to ledger journal entry now","direct_posting"],["delete all audit history","destructive_change"]];
for(const [t,cat] of refused){r=P(t);assert.equal(r.support_status,"UNSUPPORTED",t);assert.equal(r.unsupported.category,cat,t);assert.equal(r.capability_key,null)}
// approval wording must not be mistaken for a permission grant
assert.equal(P("order above 5 lakh needs approval").support_status,"SUPPORTED");
// ---- interpretation payload ----
const i=E.toInterpretation(P("Warn me if sweets wastage goes above 3% in a batch (kg)"));
assert.deepEqual(Object.keys(i).sort(),["assumptions","capability_key","confidence","locale","matched_terms","missing","params","parser_version","questions","support_status"]);
const iu=E.toInterpretation(P("Send SMS when stock below 10"));assert.equal(iu.unsupported.a045_handler_id,"notification_v1");
// ---- evaluators (mirror of SQL; SQL parity checked in c10_a052_eval_parity.test.js) ----
let ev=E.evaluate("wastage_threshold",{threshold_pct:5,outcome:"warn",unit:"kg"},{produced_qty:50,wasted_qty:3});
assert.equal(ev.computed.wastage_pct,6);assert.equal(ev.matched,true);assert.equal(ev.canAuthorizeOperation,false);assert.equal(ev.mutates,false);
ev=E.evaluate("pack_discount_margin",{pack_litres:4,min_margin_pct:15,outcome:"warn",currency:"BDT"},{price_per_pack:3200,cost_per_litre:600,discount_pct:8});
assert.deepEqual(ev.computed,{net_price:2944,pack_cost:2400,margin_pct:18.4783,max_discount_pct:11.7647});assert.equal(ev.matched,false);
assert.throws(()=>E.evaluate("wastage_threshold",{threshold_pct:5,outcome:"warn",unit:"kg"},{produced_qty:5,wasted_qty:9}),/invalid_input/);
assert.throws(()=>E.evaluate("wastage_threshold",{threshold_pct:5,outcome:"warn",unit:"mile"},{produced_qty:5,wasted_qty:1}),/invalid_params/);
assert.throws(()=>E.evaluate("pack_discount_margin",{pack_litres:4,min_margin_pct:15,outcome:"warn",currency:"BDT"},{price_per_pack:3200,cost_per_litre:600,discount_pct:100}),/invalid_input/);
assert.equal(E.validateParams("low_stock_alert",{threshold:1,outcome:"warn",formula:"1+1"}).ok,false);
assert.equal(E.validateParams("grant_permission",{}).ok,false);
// ---- guidance catalog completeness: every field bilingual, every capability has guidance ----
const need=["title","what","why","when","default","exception","consequence","data_formula_units","linked_report"];
for(const [k,g] of Object.entries(GUIDANCE))for(const f of need)for(const l of["en","bn"])assert.ok(g.content[f]&&g.content[f][l]&&g.content[f][l].length>3,k+"."+f+"."+l);
for(const [k,c] of Object.entries(E.CAPABILITIES)){assert.ok(GUIDANCE[c.guidance],k+" guidance");assert.equal(GUIDANCE[c.guidance].capability_key,k)}
// ---- no dynamic code in source ----
const src=require("fs").readFileSync(require.resolve("../core10-owner-intent-engine.js"),"utf8");
assert.ok(!/\beval\s*\(|new Function|fetch\(|XMLHttpRequest/.test(src),"engine must be pure");
console.log("PASS A052 rule engine: Bangla/English supported, clarification, unsupported, refused, locale, evaluators, guidance");
