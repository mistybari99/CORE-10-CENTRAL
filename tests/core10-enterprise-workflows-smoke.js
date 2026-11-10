"use strict";
const assert=require("node:assert/strict");
const {create}=require("../core10-enterprise-workflows.js");
const trace=[];
function makeClient(){
 const db={
  from:function(name){trace.push(["from",name]);return{
   select:function(s){trace.push(["select",name,s]);return this},
   eq:function(k,v){trace.push(["eq",name,k,v]);return this},
   limit:function(n){trace.push(["limit",n]);return Promise.resolve({data:[{business_id:101}],error:null})}
  }},
  rpc:function(name,params){trace.push(["rpc",name,params]);
   return Promise.resolve({data:42,error:null})}
 };
 return {auth:{getUser:async function(){trace.push(["user"]);return{
   data:{user:{id:"11111111-1111-4111-8111-111111111111"}},error:null
  }}},schema:function(s){trace.push(["schema",s]);return db}};
}
async function rejectCode(fn,code){return assert.rejects(Promise.resolve().then(fn),e=>e&&e.code===code)}
const op={
 businessId:101,locationId:5001,kind:"sale",counterparty:"Customer",
 lines:[{item:8001,quantity:1.5,unit_price:100}],
 discount:5,requestKey:"draft-op-1"
};
const b={businessId:101,finishedItemId:8004,code:"Cake Recipe",
 yieldQuantity:5,overheadEstimate:10,
 ingredients:[{item:8001,qty:2,estimated_unit_cost:40}],
 requestKey:"bom-1"};
(async()=>{
 const client=makeClient();
 const disabled=create({client});
 assert.deepEqual(disabled.status(),{
  enabled:false,draftsEnabled:false,postingEnabled:false,
  financeWritesEnabled:false,schema:"c10_demo",productionCertified:false});
 await rejectCode(()=>disabled.ownerBoard(),"ENTERPRISE_WORKFLOWS_NOT_RELEASED");
 await rejectCode(()=>disabled.operationalDraft(op),"ENTERPRISE_WORKFLOWS_NOT_RELEASED");
 await rejectCode(()=>disabled.postOperation(1),"ENTERPRISE_WORKFLOWS_NOT_RELEASED");
 assert.equal(trace.length,0,"disabled bridge touched session or database");

 const ro=create({client,experimentalRead:true});
 assert.deepEqual(await ro.ownerBoard(),[{business_id:101}]);
 assert.deepEqual(await ro.businessOperations(101),[{business_id:101}]);
 assert.deepEqual(await ro.tenantDashboard(),[{business_id:101}]);
 assert.ok(trace.some(e=>e[0]==="schema"&&e[1]==="c10_demo"));
 assert.ok(trace.some(e=>e[0]==="eq"&&e[1]==="operational_business_report_v1"&&e[3]===101));
 await rejectCode(()=>ro.operationalDraft(op),"ENTERPRISE_WORKFLOWS_NOT_RELEASED");
 await rejectCode(()=>ro.financeMonth({}),"INVALID_FINANCE_MONTH_DRAFT");
 await rejectCode(()=>ro.postOperation(12),"ENTERPRISE_WORKFLOWS_NOT_RELEASED");

 const draft=create({client,experimentalRead:true,experimentalDraftWrite:true});
 assert.equal(await draft.operationalDraft(op),42);
 assert.deepEqual(trace.filter(x=>x[0]==="rpc").at(-1),["rpc","create_operational_document_v1",{
  p_business:101,p_location:5001,p_kind:"sale",p_counterparty:"Customer",
  p_lines:[{item:8001,quantity:1.5,unit_price:100}],
  p_discount:5,p_request:"draft-op-1"
 }]);
 assert.equal(await draft.bomDraft(b),42);
 assert.equal(trace.filter(x=>x[0]==="rpc").at(-1)[1],"create_bom_v1");
 assert.equal(await draft.productionDraft({bomId:1,locationId:5001,multiplier:0.5,requestKey:"batch-1"}),42);
 assert.equal(trace.filter(x=>x[0]==="rpc").at(-1)[1],"create_production_batch_v1");
 assert.equal(await draft.returnDraft({originalDocumentId:21,
  lines:[{line:1,quantity:0.5}],reason:"Damaged packaging",requestKey:"return-1"}),42);
 assert.equal(trace.filter(x=>x[0]==="rpc").at(-1)[1],"create_return_v1");
 assert.equal(await draft.costRateDraft({businessId:101,itemId:8001,unitCost:40,requestKey:"cost-1"}),42);
 assert.equal(await draft.taxPreviewDraft({businessId:101,label:"Unverified Owner Rate",
  rateBps:1500,mode:"inclusive",requestKey:"tax-1"}),42);
 await rejectCode(()=>draft.postOperation(21),"ENTERPRISE_WORKFLOWS_NOT_RELEASED");
 await rejectCode(()=>draft.financeMonth({
  businessId:101,month:"2026-01-01",revenue:100,costs:70,requestKey:"fin-1"
 }),"ENTERPRISE_WORKFLOWS_NOT_RELEASED");
 assert.equal(draft.status().postingEnabled,false);
 assert.equal(draft.status().productionCertified,false);
 assert.ok(!trace.some(x=>["insert","update","delete"].includes(x[0])));

 const all=create({client,experimentalRead:true,experimentalDraftWrite:true,
  experimentalPosting:true,experimentalFinancialWrite:true});
 assert.equal(await all.confirmOperation(21),42);
 assert.equal(trace.filter(x=>x[0]==="rpc").at(-1)[1],"confirm_operational_document_v1");
 assert.equal(await all.postOperation(21),42);
 assert.equal(trace.filter(x=>x[0]==="rpc").at(-1)[1],"post_operational_document_v1");
 assert.equal(await all.confirmProduction(21),42);
 assert.equal(await all.postProduction(21),42);
 assert.equal(trace.filter(x=>x[0]==="rpc").at(-1)[1],"post_production_batch_v1");
 assert.equal(await all.approveBom(11),42);
 assert.equal(await all.postReturn(21),42);
 assert.equal(await all.approveCostRate(11),42);
 assert.equal(await all.approveTaxPreview(11),42);
 assert.equal(await all.financeMonth({businessId:101,month:"2026-01-01",
  revenue:100,costs:70,requestKey:"fin-1"}),42);
 assert.equal(trace.filter(x=>x[0]==="rpc").at(-1)[1],"record_finance_month_v1");
 assert.equal(await all.contractDraft({businessId:101,
  investorId:"55555555-5555-4555-8555-555555555555",
  code:"Q-Contract",principal:2000000,shareBps:1400,everyMonths:3,
  validFrom:"2026-01-01",validUntil:"2026-07-01",requestKey:"contract-1"}),42);
 assert.equal(trace.filter(x=>x[0]==="rpc").at(-1)[1],"create_funding_agreement_v1");
 assert.equal(await all.recordPayment({entitlementId:1,amount:20,
  evidence:"Test voucher 1",requestKey:"voucher-1"}),42);
 assert.equal(trace.filter(x=>x[0]==="rpc").at(-1)[1],"record_funding_payment_v1");
 assert.equal(await all.createFundingEntitlement(1,"2026-01-01","entitlement-1"),42);

 await rejectCode(()=>all.operationalDraft({...op,lines:[{item:8001,quantity:-2,unit_price:10}]}),
  "INVALID_WORKFLOW_LINES");
 await rejectCode(()=>all.operationalDraft({...op,lines:[
  {item:8001,quantity:1,unit_price:20},{item:8001,quantity:1,unit_price:20}
 ]}),"INVALID_WORKFLOW_LINES");
 await rejectCode(()=>all.bomDraft({...b,ingredients:[{item:8001,qty:1,estimated_unit_cost:2,tenant_id:2}]}),
 "INVALID_WORKFLOW_LINES");
 await rejectCode(()=>all.productionDraft({bomId:1,locationId:2,multiplier:0,
  requestKey:"batch-invalid"}),"INVALID_PRODUCTION_DRAFT");
 await rejectCode(()=>all.returnDraft({originalDocumentId:1,reason:"short",
  lines:[{line:1,quantity:1}],requestKey:"ret"}),"INVALID_RETURN_DRAFT");
 await rejectCode(()=>all.taxPreviewDraft({businessId:1,label:"Tax",
  rateBps:15000,mode:"inclusive",requestKey:"tax"}),"INVALID_TAX_PREVIEW_DRAFT");
 await rejectCode(()=>all.financeMonth({businessId:101,month:"2026-13-01",
  revenue:100,costs:90,requestKey:"bad-month"}),"INVALID_FINANCE_MONTH_DRAFT");
 await rejectCode(()=>all.contractDraft({businessId:101,investorId:"nonsense",
  code:"Bad",principal:10,shareBps:1000,everyMonths:3,validFrom:"2026-01-01",
  validUntil:"2026-07-01",requestKey:"x"}),"INVALID_FINANCE_CONTRACT_DRAFT");
 await rejectCode(()=>all.postOperation(-1),"INVALID_DOCUMENT_ID");
 const anonymous=create({client:{...client,auth:{getUser:async()=>({data:{user:null},error:null})}},
  experimentalRead:true,experimentalDraftWrite:true,experimentalPosting:true});
 await rejectCode(()=>anonymous.postOperation(1),"AUTHENTICATED_USER_REQUIRED");
 const errorClient={...client,schema:()=>({from:()=>({select:()=>({limit:()=>Promise.resolve({data:[],error:null})})}),
  rpc:()=>Promise.resolve({data:null,error:{code:"42501",message:"not permitted"}})})};
 const errorBridge=create({client:errorClient,experimentalRead:true,experimentalDraftWrite:true});
 await rejectCode(()=>errorBridge.operationalDraft(op),"42501");
 assert.equal(Object.isFrozen(all.status()),true);
 console.log("PASS: signed-session API bridge disables dangerous methods by default, typed multi-module payload validation, server RPC only, owner-finance gating, error propagation.");
})().catch(e=>{console.error(e);process.exitCode=1});
