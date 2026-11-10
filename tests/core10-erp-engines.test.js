"use strict";
const t=require("node:test"),a=require("node:assert/strict"),E=require("../core10-erp-engines.js");
t("inventory rejects cross-location records",()=>a.equal(E.inventory({business_id:1,location_id:2,item_id:3,movements:[{business_id:1,location_id:9,item_id:3,direction:"in",quantity:1}]}).reason,"cross_scope_movement"));
t("inventory rejects negative stock",()=>a.equal(E.inventory({business_id:1,location_id:2,item_id:3,movements:[{business_id:1,location_id:2,item_id:3,direction:"out",quantity:1}]}).reason,"negative_stock"));
t("production material availability",()=>a.equal(E.production({business_id:1,location_id:2,finished_item_id:3,output_units:10,components:[{item_id:4,quantity_per_unit:2,unit_cost:3,available:10}]}).reason,"insufficient_material"));
t("production costing",()=>a.equal(E.production({business_id:1,location_id:2,finished_item_id:3,output_units:10,components:[{item_id:4,quantity_per_unit:2,unit_cost:3,available:30}]}).estimated_cost,60));
t("purchase supplier draft",()=>a.equal(E.purchase({business_id:1,supplier_id:2,lines:[{item_id:3,quantity:4,unit_cost:5}]}).total,20));
t("POS stock reservation",()=>a.equal(E.sale({business_id:1,location_id:2,lines:[{item_id:3,quantity:5,unit_price:10,unit_cost:6,available:7,reserved:3}]}).reason,"insufficient_stock"));
t("POS tax and discount",()=>a.equal(E.sale({business_id:1,location_id:2,lines:[{item_id:3,quantity:2,unit_price:10,unit_cost:6,available:5,reserved:0}],tax:2,discount:3}).total,19));
t("approval requires privileged role",()=>a.equal(E.approval({business_id:1,request_id:2,action:"approve",actor_role:"counter",current_status:"pending"}).reason,"server_rpc_required"));
t("report refuses cross-business totals",()=>a.equal(E.report({business_id:1,sales:[{business_id:2,total:10}],purchases:[]}).reason,"invalid_sales_scope"));
t("report labels cash difference not profit",()=>a.match(E.report({business_id:1,sales:[{business_id:1,total:20}],purchases:[{business_id:1,total:5}]}).note,/not accounting profit/));

t("P0: forged owner role never authorizes client approval",()=>a.equal(E.approval({business_id:1,request_id:2,action:"approve",actor_role:"owner",current_status:"pending"}).reason,"server_rpc_required"));
t("P0: forged approver role never authorizes client approval",()=>a.equal(E.approval({business_id:1,request_id:2,action:"approve",actor_role:"approver",current_status:"pending"}).reason,"server_rpc_required"));
