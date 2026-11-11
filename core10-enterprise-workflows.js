/* CORE 10 CENTRAL - enterprise workflows bridge C10-A031, DRAFT/HOLD.
 * Connects to the single verified Supabase session. All feature flags default OFF;
 * actual rights are enforced exclusively by database RLS and guarded RPCs.
 * No service-role key, direct writes or live deployment. Do not use before signed
 * real Supabase Auth/SG migration, legacy mapping and release approval.
 */
(function(root,factory){
 "use strict";
 var api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_ENTERPRISE_WORKFLOWS=api;
})(typeof window!=="undefined"?window:(typeof globalThis!=="undefined"?globalThis:null),function(){
 "use strict";
 function fail(code){var e=new Error(code);e.code=code;throw e}
 function obj(x){return x!==null&&typeof x==="object"&&!Array.isArray(x)}
 function positive(x){return Number.isSafeInteger(x)&&x>0}
 function qty(x){return typeof x==="number"&&Number.isFinite(x)&&x>0&&x<=100000&&Math.abs(Math.round(x*1000)-x*1000)<1e-7}
 function money(x){return typeof x==="number"&&Number.isFinite(x)&&x>=0&&x<=100000000000&&Math.abs(Math.round(x*100)-x*100)<1e-7}
 function request(x){return typeof x==="string"&&x.trim()===x&&x.length>=1&&x.length<=120}
 function clean(x,max){return typeof x==="string"&&x.trim().length>0&&x.trim().length<=max}
 function ymd(x){if(typeof x!=="string"||!/^\d{4}-\d{2}-\d{2}$/.test(x))return false;
  var d=new Date(x+"T00:00:00Z");return Number.isFinite(d.getTime())&&d.toISOString().slice(0,10)===x}
 function month(x){return ymd(x)&&x.slice(-2)==="01"}
 function mapping(o,fields){if(!obj(o))fail("INVALID_WORKFLOW_INPUT");var r={};for(var p of fields){r[p]=o[p]}return r}
 function lines(xs,type){
  if(!Array.isArray(xs)||xs.length<1||xs.length>100)fail("INVALID_WORKFLOW_LINES");
  var used=new Set();
  return xs.map(function(x){
   if(!obj(x))fail("INVALID_WORKFLOW_LINES");
   var k=type==="return"?["line","quantity"]:type==="bom"?["item","qty","estimated_unit_cost"]:["item","quantity","unit_price"];
   if(Object.keys(x).sort().join(",")!==k.slice().sort().join(","))fail("INVALID_WORKFLOW_LINES");
   var id=type==="return"?x.line:x.item;
   if(!positive(id)||used.has(id))fail("INVALID_WORKFLOW_LINES");
   used.add(id);
   if(type==="return"){if(!qty(x.quantity))fail("INVALID_WORKFLOW_LINES");return{line:id,quantity:x.quantity}}
   if(type==="bom"){if(!qty(x.qty)||!money(x.estimated_unit_cost))fail("INVALID_WORKFLOW_LINES");
     return{item:id,qty:x.qty,estimated_unit_cost:x.estimated_unit_cost}}
   if(!qty(x.quantity)||!money(x.unit_price))fail("INVALID_WORKFLOW_LINES");
   return{item:id,quantity:x.quantity,unit_price:x.unit_price}
  });
 }
 function create(conf){
  conf=conf||{};
  var client=conf.client;
  var read=conf.experimentalRead===true,
   draft=read&&conf.experimentalDraftWrite===true,
   posting=draft&&conf.experimentalPosting===true,
   finance=draft&&conf.experimentalFinancialWrite===true;
  // Flags prevent accidental draft UI exposure; they cannot grant SQL permissions.
  async function db(kind){
   if(!read||(kind==="draft"&&!draft)||(kind==="post"&&!posting)||
      (kind==="finance"&&!finance))fail("ENTERPRISE_WORKFLOWS_NOT_RELEASED");
   if(!client||!client.auth||typeof client.auth.getUser!=="function"||
      typeof client.schema!=="function")fail("SIGNED_SUPABASE_CLIENT_REQUIRED");
   var auth=await client.auth.getUser();
   if(!auth||auth.error||!auth.data||!auth.data.user||!clean(auth.data.user.id,128))
    fail("AUTHENTICATED_USER_REQUIRED");
   var scoped=client.schema("c10_demo");
   if(!scoped||typeof scoped.from!=="function"||typeof scoped.rpc!=="function")
    fail("ENTERPRISE_API_SCHEMA_UNAVAILABLE");
   return scoped;
  }
  function data(result){
   if(!result||result.error){var e=new Error(result?.error?.message||"ENTERPRISE_BACKEND_ERROR");
    e.code=result?.error?.code||"ENTERPRISE_BACKEND_ERROR";throw e}
   return result.data;
  }
  async function rpc(name,params,kind){
   var scoped=await db(kind);
   return data(await scoped.rpc(name,params));
  }
  async function listing(table,fields,business){
   if(business!==null&&!positive(business))fail("INVALID_BUSINESS_ID");
   var scoped=await db("read");
   var q=scoped.from(table).select(fields);
   if(business!==null)q=q.eq("business_id",business);
   return data(await q.limit(200));
  }
  function byId(id){if(!positive(id))fail("INVALID_DOCUMENT_ID");return id}
  function key(x){if(!request(x))fail("INVALID_REQUEST_KEY");return x}
  function business(x){if(!positive(x))fail("INVALID_BUSINESS_ID");return x}
  // Owner read models are server-scoped by c10_demo.can_manage.
  function ownerBoard(){return listing("owner_business_kpi_v1",
   "business_id,slug,display_name,business_status,net_manual_profit,profit_entitlements,unpaid_investor_balance,sites,unreconciled_location_items,operationally_certified",null)}
  function businessOperations(b){return listing("operational_business_report_v1",
   "business_id,posted_purchase_docs,posted_sale_docs,received_purchase_value_unreconciled,posted_sale_value_unreconciled,unposted_documents,cash_or_invoice_certified",business(b))}
  function businessProduction(b){return listing("production_cost_estimate_v1",
   "business_id,batch_id,bom_id,location_id,status,expected_output,estimated_total_cost,estimated_cost_per_unit,actual_cogs_certified",business(b))}
  function businessReturns(b){return listing("operational_net_returns_v1",
   "business_id,gross_sale_value_unreconciled,sale_return_value_unsettled,net_sale_value_unreconciled,net_purchase_value_unreconciled,actual_refunds_reconciled",business(b))}
  function businessCostTax(b){return listing("owner_cost_tax_summary_v1",
   "business_id,posted_sales,estimated_cogs_known_only,missing_cost_lines,estimated_margin_when_fully_costed,estimated_tax_known_only,legally_or_financially_certified",business(b))}
  function investorStatements(b){return listing("investor_statement_v1",
   "business_id,agreement_id,investor_id,agreement_code,contract_status,allocated_profit,recorded_paid,unpaid_balance,bank_transfer_verified",business(b))}
  function tenantDashboard(){return listing("tenant_consolidated_kpi_v1",
   "tenant_id,visible_businesses,recorded_revenue,recorded_costs,net_manual_profit,unpaid_investor_balance,stock_integrity_failures,enterprise_ready",null)}

  function operationalDraft(p){
   if(!obj(p)||!positive(p.businessId)||!positive(p.locationId)||
      !["purchase","sale"].includes(p.kind)||!clean(p.counterparty,120)||
      !money(p.discount)||!request(p.requestKey))fail("INVALID_OPERATIONAL_DRAFT");
   return rpc("create_operational_document_v1",{
    p_business:p.businessId,p_location:p.locationId,p_kind:p.kind,
    p_counterparty:p.counterparty.trim(),p_lines:lines(p.lines,"operation"),
    p_discount:p.discount,p_request:p.requestKey},"draft");
  }
  function productionDraft(p){
   if(!obj(p)||!positive(p.bomId)||!positive(p.locationId)||
      !qty(p.multiplier)||!request(p.requestKey))fail("INVALID_PRODUCTION_DRAFT");
   return rpc("create_production_batch_v1",{
    p_bom:p.bomId,p_location:p.locationId,p_multiplier:p.multiplier,
    p_request:p.requestKey},"draft");
  }
  function returnDraft(p){
   if(!obj(p)||!positive(p.originalDocumentId)||!clean(p.reason,500)||
      p.reason.trim().length<5||!request(p.requestKey))fail("INVALID_RETURN_DRAFT");
   return rpc("create_return_v1",{
    p_original:p.originalDocumentId,p_lines:lines(p.lines,"return"),
    p_reason:p.reason.trim(),p_request:p.requestKey},"draft");
  }
  function bomDraft(p){
   if(!obj(p)||!positive(p.businessId)||!positive(p.finishedItemId)||
      !clean(p.code,80)||p.code.trim().length<2||
      !qty(p.yieldQuantity)||!money(p.overheadEstimate)||!request(p.requestKey))
      fail("INVALID_BOM_DRAFT");
   return rpc("create_bom_v1",{
    p_business:p.businessId,p_finished_item:p.finishedItemId,
    p_code:p.code.trim(),p_yield:p.yieldQuantity,
    p_ingredients:lines(p.ingredients,"bom"),
    p_overhead:p.overheadEstimate,p_request:p.requestKey},"draft");
  }
  function costRateDraft(p){
   if(!obj(p)||!positive(p.businessId)||!positive(p.itemId)||
      !money(p.unitCost)||!request(p.requestKey))fail("INVALID_COST_DRAFT");
   return rpc("create_cost_rate_v1",{
    p_business:p.businessId,p_item:p.itemId,p_cost:p.unitCost,p_request:p.requestKey},"draft");
  }
  function taxPreviewDraft(p){
   if(!obj(p)||!positive(p.businessId)||!clean(p.label,120)||
      p.label.trim().length<3||!Number.isSafeInteger(p.rateBps)||
      p.rateBps<0||p.rateBps>10000||!["inclusive","exclusive"].includes(p.mode)||
      !request(p.requestKey))fail("INVALID_TAX_PREVIEW_DRAFT");
   return rpc("create_tax_preview_profile_v1",{
    p_business:p.businessId,p_label:p.label.trim(),
    p_rate_bps:p.rateBps,p_mode:p.mode,p_request:p.requestKey},"draft");
  }
  function financeMonth(p){
   if(!obj(p)||!positive(p.businessId)||!month(p.month)||
    !money(p.revenue)||!money(p.costs)||!request(p.requestKey))
    fail("INVALID_FINANCE_MONTH_DRAFT");
   return rpc("record_finance_month_v1",{
    p_business:p.businessId,p_month:p.month,p_revenue:p.revenue,
    p_costs:p.costs,p_request:p.requestKey},"finance");
  }
  function contractDraft(p){
   if(!obj(p)||!positive(p.businessId)||!clean(p.investorId,128)||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(p.investorId)||!clean(p.code,80)||
    p.code.trim().length<2||!money(p.principal)||p.principal<=0||
    !Number.isSafeInteger(p.shareBps)||p.shareBps<1||p.shareBps>10000||
    ![1,3,6].includes(p.everyMonths)||!month(p.validFrom)||!month(p.validUntil)||
    p.validUntil<=p.validFrom||!request(p.requestKey))
    fail("INVALID_FINANCE_CONTRACT_DRAFT");
   return rpc("create_funding_agreement_v1",{
    p_business:p.businessId,p_investor:p.investorId,p_code:p.code.trim(),
    p_principal:p.principal,p_share_bps:p.shareBps,
    p_every_months:p.everyMonths,p_from:p.validFrom,p_until:p.validUntil,
    p_request:p.requestKey},"finance");
  }
  function recordPayment(p){
   if(!obj(p)||!positive(p.entitlementId)||!money(p.amount)||p.amount<=0||
    !clean(p.evidence,120)||p.evidence.trim().length<4||!request(p.requestKey))
    fail("INVALID_PAYMENT_RECORD");
   return rpc("record_funding_payment_v1",{
    p_entitlement:p.entitlementId,p_amount:p.amount,
    p_evidence:p.evidence.trim(),p_request:p.requestKey},"finance");
  }
  // Approval and posting are deliberately separate from draft flags.
  // An authenticated client flag is NOT owner authorization.
  function action(name,param,id){return rpc(name,{[param]:byId(id)},"post")}
  return Object.freeze({
   status:function(){return Object.freeze({
     enabled:read,draftsEnabled:draft,postingEnabled:posting,
     financeWritesEnabled:finance,schema:"c10_demo",productionCertified:false})},
   ownerBoard:ownerBoard,tenantDashboard:tenantDashboard,
   businessOperations:businessOperations,businessProduction:businessProduction,
   businessReturns:businessReturns,businessCostTax:businessCostTax,
   investorStatements:investorStatements,
   operationalDraft:operationalDraft,productionDraft:productionDraft,
   returnDraft:returnDraft,bomDraft:bomDraft,costRateDraft:costRateDraft,
   taxPreviewDraft:taxPreviewDraft,financeMonth:financeMonth,
   contractDraft:contractDraft,recordPayment:recordPayment,
   confirmOperation:function(id){return action("confirm_operational_document_v1","p_document",id)},
   postOperation:function(id){return action("post_operational_document_v1","p_document",id)},
   confirmProduction:function(id){return action("confirm_production_batch_v1","p_batch",id)},
   postProduction:function(id){return action("post_production_batch_v1","p_batch",id)},
   confirmReturn:function(id){return action("confirm_return_v1","p_return",id)},
   postReturn:function(id){return action("post_return_v1","p_return",id)},
   approveBom:function(id){return action("approve_bom_v1","p_recipe",id)},
   approveCostRate:function(id){return action("approve_cost_rate_v1","p_id",id)},
   approveTaxPreview:function(id){return action("approve_tax_preview_profile_v1","p_id",id)},
   approveFinanceMonth:function(id){return action("approve_finance_month_v1","p_month_id",id)},
   activateFunding:function(id){return action("activate_funding_agreement_v1","p_agreement",id)},
   createFundingEntitlement:function(id,window,requestKey){
    if(!month(window))fail("INVALID_PERIOD");return rpc("create_funding_entitlement_v1",{
     p_agreement:byId(id),p_window:window,p_request:key(requestKey)},"finance")}
  });
 }
 return Object.freeze({create:create});
});
