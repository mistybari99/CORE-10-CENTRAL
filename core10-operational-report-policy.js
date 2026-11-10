/* CORE 10 CENTRAL — modular report-family recommendation engine.
 * No legacy business report registry, brand, routes or database reads.
 * Advisory only; authenticated backend authorization is required for real reports.
 */
(function(root,factory){"use strict";const api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.CORE10_REPORT_FAMILIES=api;})(typeof window!=="undefined"?window:globalThis,function(){
"use strict";
const FAMILIES=Object.freeze({
 pos:["sales_summary","returns"],
 dealer_pos_screens:["sales_summary"],restaurant_pos:["sales_summary"],wholesale_pricing:["sales_summary"],
 online_orders:["sales_summary"],stock:["stock_balance","stock_movement"],
 channel_inventory:["stock_balance","stock_movement"],purchase:["supplier_orders","purchase_reconciliation"],
 production:["production_orders","production_variance"],menu_recipe:["material_requirements"],
 bill_of_materials:["material_requirements"],work_orders:["production_orders"],production_routing:["production_orders"],
 costing:["cost_coverage","margin_review"],landed_cost:["cost_coverage","shipment_cost"],
 accounting:["general_ledger","financial_period"],reports:["operational_exceptions"],
 quality_control:["quality_exceptions"],tinting:["batch_consumption"],principal_schemes:["supplier_rebates"],
 cheque_pdc:["receivables_due"],project_boq:["project_estimate"],project_budget:["project_budget"],
 progress_billing:["project_billing"],distribution_orders:["fulfillment"],
 shipments:["shipment_status"],currencies:["currency_exposure"],fx_rates:["currency_exposure"],
 returns_portal:["returns"],software_subscription:["subscription_revenue"],digital_delivery:["fulfillment"],
 service_tickets:["service_resolution"],service_orders:["service_fulfillment"],time_tracking:["billable_time"],
 contract_billing:["contract_revenue"],food_delivery:["fulfillment"],kitchen_order:["kitchen_queue"],
 customer_credit:["receivables_due"],bank_payments:["payment_reconciliation"],
 stock_link:["stock_movement"],accounting_posting:["general_ledger"],
 customs_automation:["customs_clearance"],letter_of_credit:["trade_finance"]
});
function create(catalog){
 if(!catalog||!Array.isArray(catalog.templates))throw Error("INDUSTRY_CATALOG_REQUIRED");
 function propose(input,context){
  if(!context||!context.businessId||!context.industryId)throw Error("BUSINESS_CONTEXT_REQUIRED");
  const template=catalog.templates.find(x=>x.id===context.industryId);
  if(!template)throw Error("UNKNOWN_INDUSTRY");
  if(!input||!Array.isArray(input.modules))throw Error("MODULE_SELECTION_REQUIRED");
  const declared=new Map(template.modules.map(x=>[x.id,x]));
  const seen=new Set(),groups=new Map();
  for(const id of input.modules){
   if(typeof id!=="string"||!declared.has(id))throw Error("UNREGISTERED_INDUSTRY_MODULE");
   if(seen.has(id))throw Error("DUPLICATE_MODULE_SELECTION");
   seen.add(id);
   const def=declared.get(id);
   for(const reportFamily of FAMILIES[id]||[]){
    if(!groups.has(reportFamily))groups.set(reportFamily,{familyId:reportFamily,requiredModules:[],states:[]});
    const group=groups.get(reportFamily);
    group.requiredModules.push(id);group.states.push(def.status);
   }
  }
  return Object.freeze({status:"proposal_only",businessId:context.businessId,industryId:context.industryId,
   writesPerformed:false,legacyRoutesImported:false,
   categories:Object.freeze([...groups.values()].map(group=>Object.freeze({
    familyId:group.familyId,sourceModules:Object.freeze(group.requiredModules),
    implementationState:group.states.every(s=>s==="supported_and_tested")?"requires_real_report_verification":"not_verified",
    requiresBusinessScopedBackend:true,realReportReady:false
   })))});
 }
 return Object.freeze({propose});
}
function install(router,catalog){
 if(!router||typeof router.register!=="function")throw Error("OPERATIONAL_ROUTER_REQUIRED");
 const engine=create(catalog);
 return router.register({id:"report.family.propose",access:"read_only",execute:engine.propose});
}
return Object.freeze({create,install});
});