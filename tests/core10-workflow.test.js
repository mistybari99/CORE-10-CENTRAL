"use strict";
const t=require("node:test"),a=require("node:assert/strict"),W=require("../core10-workflow.js");
const purchase={business_id:1,supplier_id:2,lines:[{item_id:3,quantity:2,unit_cost:5}]};
const receive={business_id:1,location_id:2,item_id:3,movements:[{business_id:1,location_id:2,item_id:3,direction:"in",quantity:2}]};
t("purchase to receive workflow",()=>a.equal(W.plan({business_id:1,steps:[{ref:"po1",type:"purchase",payload:purchase},{ref:"grn1",type:"receive",payload:receive}]}).ok,true));
t("reject cross-business step",()=>a.equal(W.plan({business_id:1,steps:[{ref:"po1",type:"purchase",payload:{...purchase,business_id:2}}]}).reason,"cross_business_step"));
t("reject receiving without purchase",()=>a.equal(W.plan({business_id:1,steps:[{ref:"grn1",type:"receive",payload:receive}]}).reason,"receive_requires_purchase"));
t("reject duplicate reference",()=>a.equal(W.plan({business_id:1,steps:[{ref:"same",type:"purchase",payload:purchase},{ref:"same",type:"purchase",payload:purchase}]}).reason,"invalid_step"));

t("P0: client transfer planner cannot represent one-sided stock posting",()=>a.equal(W.plan({business_id:1,steps:[{ref:"x",type:"transfer",payload:receive}]}).reason,"server_rpc_required"));
t("P0: caller-supplied approver role cannot authorize client approval",()=>a.equal(W.plan({business_id:1,steps:[{ref:"a",type:"approve",payload:{business_id:1,request_id:2,action:"approve",actor_role:"owner",current_status:"pending"}}]}).reason,"server_rpc_required"));

t("P0: reject invalid business scope before planning",()=>{for(const business_id of ["0","abc",-1,0,1.5,null])a.equal(W.plan({business_id,steps:[{ref:"po1",type:"purchase",payload:purchase}]}).reason,"invalid_workflow")});
t("P0: reject oversized plans before allocating work",()=>a.equal(W.plan({business_id:1,steps:Array.from({length:101},(_,i)=>({ref:"po"+i,type:"purchase",payload:purchase}))}).reason,"invalid_workflow"));
t("P0: normalized numeric business IDs remain scoped",()=>a.equal(W.plan({business_id:"1",steps:[{ref:"po1",type:"purchase",payload:purchase}]}).ok,true));
t("P0: invalid payload scope is rejected",()=>a.equal(W.plan({business_id:1,steps:[{ref:"po1",type:"purchase",payload:{...purchase,business_id:"not-a-business"}}]}).reason,"cross_business_step"));

t("P0: refuse receipt of item absent from purchase",()=>a.equal(W.plan({business_id:1,steps:[{ref:"po",type:"purchase",payload:purchase},{ref:"grn",type:"receive",payload:{...receive,item_id:99,movements:[{...receive.movements[0],item_id:99}]}}]}).reason,"receipt_purchase_mismatch"));
t("P0: refuse goods receipt above purchased quantity",()=>a.equal(W.plan({business_id:1,steps:[{ref:"po",type:"purchase",payload:purchase},{ref:"grn",type:"receive",payload:{...receive,movements:[{...receive.movements[0],quantity:3}]}}]}).reason,"receipt_purchase_mismatch"));
t("P0: refuse outbound movement masquerading as receipt",()=>a.equal(W.plan({business_id:1,steps:[{ref:"po",type:"purchase",payload:purchase},{ref:"grn",type:"receive",payload:{...receive,movements:[{...receive.movements[0],direction:"out"}]}}]}).reason,"receipt_purchase_mismatch"));
t("P0: refuse multi-movement receipt in single-item preview",()=>a.equal(W.plan({business_id:1,steps:[{ref:"po",type:"purchase",payload:purchase},{ref:"grn",type:"receive",payload:{...receive,movements:[...receive.movements,...receive.movements]}}]}).reason,"receipt_contract_invalid"));

t("P0: client cannot treat caller-supplied posted flags as authenticated financial evidence",()=>a.equal(W.plan({business_id:1,steps:[{ref:"report1",type:"report",payload:{business_id:1,sales:[{business_id:1,total:100,status:"posted"}],purchases:[]}}]}).reason,"server_rpc_required"));
t("P0: empty financial report also requires authenticated server RPC",()=>a.equal(W.plan({business_id:1,steps:[{ref:"report2",type:"report",payload:{business_id:1,sales:[],purchases:[]}}]}).reason,"server_rpc_required"));
