"use strict";
const t=require("node:test"),a=require("node:assert/strict"),E=require("../core10-operations-engine.js");
t("BOM cost and yield",()=>{const r=E.recipeCost([{item_id:"flour",quantity:2,unit_cost:50}],10);a.equal(r.unit_cost,10)});
t("duplicate ingredient refused",()=>a.equal(E.recipeCost([{item_id:"a",quantity:1,unit_cost:2},{item_id:"a",quantity:1,unit_cost:2}],2).ok,false));
t("scenario profit never posts to ledger",()=>{const r=E.priceScenario({selling_price:300,unit_cost:150,units:10,overhead:500});a.equal(r.profit,1000);a.equal(r.simulation_only,true)});
t("break-even null if price below unit cost",()=>a.equal(E.priceScenario({selling_price:100,unit_cost:120,units:10,overhead:100}).break_even_units,null));
t("reorder trigger and suggested quantity",()=>{const r=E.reorder({available:10,daily_usage:5,lead_days:3,safety_stock:5});a.equal(r.reorder_now,true);a.equal(r.suggested_quantity,25)});
t("transfer cannot consume reserved stock",()=>{const r=E.transferFeasibility({available:20,reserved:15,requested:8});a.equal(r.can_fulfill,false);a.equal(r.shortfall,3)});
