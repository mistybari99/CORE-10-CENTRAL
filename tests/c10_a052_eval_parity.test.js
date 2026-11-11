"use strict";
// JS mirror vs SQL evaluator on shared vectors. Needs PGDATABASE with A052 loaded (skipped with a notice otherwise).
const {execFileSync}=require("node:child_process");
const assert=require("node:assert/strict");
const E=require("../core10-owner-intent-engine.js");
if(!process.env.PGDATABASE){console.log("SKIP A052 parity (no PGDATABASE)");process.exit(0)}
const V=[
 ["wastage_threshold",{threshold_pct:5,outcome:"warn",unit:"kg"},{produced_qty:50,wasted_qty:3}],
 ["wastage_threshold",{threshold_pct:6,outcome:"approval_required",unit:"pcs"},{produced_qty:50,wasted_qty:3}],
 ["wastage_threshold",{threshold_pct:1.5,outcome:"warn",unit:"l"},{produced_qty:7,wasted_qty:0.25}],
 ["pack_discount_margin",{pack_litres:4,min_margin_pct:15,outcome:"warn",currency:"BDT"},{price_per_pack:3200,cost_per_litre:600,discount_pct:8}],
 ["pack_discount_margin",{pack_litres:0.5,min_margin_pct:20,outcome:"block",currency:"BDT"},{price_per_pack:450,cost_per_litre:700,discount_pct:12.5}],
 ["pack_discount_margin",{pack_litres:20,min_margin_pct:10,outcome:"approval_required",currency:"USD"},{price_per_pack:900,cost_per_litre:30,discount_pct:0}],
 ["low_stock_alert",{threshold:10,outcome:"warn"},{on_hand:8}],["low_stock_alert",{threshold:10,outcome:"warn"},{on_hand:10}],
 ["margin_floor_approval",{threshold:12.5,outcome:"approval_required"},{margin_pct:12.4}],
 ["order_total_approval",{threshold:600000,outcome:"approval_required",currency:"BDT"},{order_total:600000}],
 ["order_total_approval",{threshold:600000,outcome:"approval_required",currency:"BDT"},{order_total:599999.99}]];
const q=(o)=>"'"+JSON.stringify(o).replace(/'/g,"''")+"'::jsonb";
for(const [c,p,i] of V){
 const out=execFileSync("psql",["-X","-At","-v","ON_ERROR_STOP=1","-c",`SELECT c10_demo.intent_eval_v1('${c}',${q(p)},${q(i)})`],{encoding:"utf8"});
 const s=JSON.parse(out),j=E.evaluate(c,p,i);
 assert.equal(j.matched,s.matched,c+" matched");assert.equal(j.outcome,s.outcome,c+" outcome");
 for(const [k,v] of Object.entries(j.computed))assert.ok(Math.abs(v-s.computed[k])<1e-9,c+" "+k+" js="+v+" sql="+s.computed[k]);
}
console.log("PASS A052 JS/SQL evaluator parity on "+V.length+" vectors");
