/* CORE 10 | Generic report-family proposals by installed module capabilities.
 * Suggestions do not import an individual business's report routes or report IDs.
 */
(function(root,factory){"use strict";const api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.CORE10_REPORT_FAMILIES=api;})(typeof window!=="undefined"?window:globalThis,function(){
"use strict";
const groups=Object.freeze({
 pos:["sales_summary","sales_returns"],
 restaurant_pos:["sales_summary"],dealer_pos_screens:["sales_summary"],wholesale_pricing:["sales_summary"],
 stock:["stock_balance","stock_movements"],channel_inventory:["stock_balance","stock_movements"],
 purchase:["procurement_summary","supplier_balances"],distribution_orders:["order_fulfillment"],
 production:["production_batches","yield_variance"],bill_of_materials:["material_consumption"],menu_recipe:["material_consumption"],
 work_orders:["production_batches"],production_routing:["production_batches"],quality_control:["quality_exceptions"],
 costing:["cost_coverage","margin_analysis"],landed_cost:["cost_coverage"],accounting:["ledger_summary","financial_position"],
 reports:["operational_exceptions"],project_boq:["project_budget_vs_actual"],project_budget:["project_budget_vs_actual"],
 progress_billing:["project_billing"],shipments:["shipment_progress"],returns_portal:["sales_returns"],
 online_orders:["sales_summary"],service_orders:["service_fulfillment"],time_tracking:["service_utilization"],
 contract_billing:["contract_billing"],software_subscription:["subscription_metrics"],service_tickets:["service_fulfillment"],
 tinting:["production_batches"],cheque_pdc:["receivable_due"],principal_schemes:["supplier_balances"]
});
function propose(template,selectedModules){
 if(!template||!Array.isArray(template.modules))throw Error("INDUSTRY_TEMPLATE_REQUIRED");
 if(!Array.isArray(selectedModules))throw Error("SELECTED_MODULES_REQUIRED");
 const allowed=new Set(template.modules.map(m=>m.id)),result=new Map();
 for(const id of selectedModules){
  if(!allowed.has(id))throw Error("UNREGISTERED_MODULE:"+id);
  for(const family of groups[id]||[]){
   if(!result.has(family))result.set(family,{familyId:family,modules:[]});
   result.get(family).modules.push(id);
  }
 }
 return Object.freeze([...result.values()].map(x=>Object.freeze({id:x.familyId,
  sourceModules:Object.freeze(x.modules),state:"proposal_only",reportImplemented:false,
  requiresBusinessScope:true,requiredDataAndAccessProof:true})));
}
return Object.freeze({propose});
});