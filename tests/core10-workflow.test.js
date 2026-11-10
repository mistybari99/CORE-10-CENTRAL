"use strict";
const t=require("node:test"),a=require("node:assert/strict"),W=require("../core10-workflow.js");
const purchase={business_id:1,supplier_id:2,lines:[{item_id:3,quantity:2,unit_cost:5}]};
const receive={business_id:1,location_id:2,item_id:3,movements:[{business_id:1,location_id:2,item_id:3,direction:"in",quantity:2}]};
t("purchase to receive workflow",()=>a.equal(W.plan({business_id:1,steps:[{ref:"po1",type:"purchase",payload:purchase},{ref:"grn1",type:"receive",payload:receive}]}).ok,true));
t("reject cross-business step",()=>a.equal(W.plan({business_id:1,steps:[{ref:"po1",type:"purchase",payload:{...purchase,business_id:2}}]}).reason,"cross_business_step"));
t("reject receiving without purchase",()=>a.equal(W.plan({business_id:1,steps:[{ref:"grn1",type:"receive",payload:receive}]}).reason,"receive_requires_purchase"));
t("reject duplicate reference",()=>a.equal(W.plan({business_id:1,steps:[{ref:"same",type:"purchase",payload:purchase},{ref:"same",type:"purchase",payload:purchase}]}).reason,"invalid_step"));
