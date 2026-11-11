// C10-A021-A023: signed-JWT HTTP E2E on disposable PostgREST / PG17 only.
// Synthetic identities and test signing secret are NOT Supabase production accounts.
"use strict";
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
const base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
if(!secret||secret.length<32)throw Error("Missing disposable JWT secret");
const people={
 owner:"11111111-1111-4111-8111-111111111111",
 businessOwner:"22222222-2222-4222-8222-222222222222",
 manager:"33333333-3333-4333-8333-333333333333",
 staff:"44444444-4444-4444-8444-444444444444",
 investor:"55555555-5555-4555-8555-555555555555",
 investorTwo:"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
 revoked:"66666666-6666-4666-8666-666666666666",
 customer:"77777777-7777-4777-8777-777777777777",
 operator:"99999999-9999-4999-8999-999999999999"
};
function token(sub,extra={}){
 const now=Math.floor(Date.now()/1000);
 const h=Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url");
 const p=Buffer.from(JSON.stringify({role:"authenticated",sub,iat:now,exp:now+300,
  aud:"authenticated",...extra})).toString("base64url");
 const body=h+"."+p;
 return body+"."+crypto.createHmac("sha256",secret).update(body).digest("base64url");
}
async function http(route,t,method="GET",payload){
 const headers={"content-type":"application/json"};
 if(t)headers.authorization="Bearer "+t;
 const response=await fetch(base+route,{method,headers,
  body:payload===undefined?undefined:JSON.stringify(payload)});
 const raw=await response.text();let data;
 try{data=JSON.parse(raw)}catch{data=raw}
 return{status:response.status,data};
}
const jwt=Object.fromEntries(Object.entries(people).map(([k,id])=>[k,token(id)]));
async function list(path,t,n,label){
 const r=await http(path,t);
 assert.equal(r.status,200,label+": "+r.status+" "+JSON.stringify(r.data));
 assert.ok(Array.isArray(r.data),label+": response not a row list");
 assert.equal(r.data.length,n,label+": wrong count "+JSON.stringify(r.data));
 console.log("PASS "+label+" ("+n+" rows)");
 return r.data;
}
async function reject(path,t,method,payload,label,denial){
 const r=await http(path,t,method,payload);
 if(denial){
  assert.equal(r.status,400,label+": "+r.status+" "+JSON.stringify(r.data));
  assert.equal(r.data?.message,denial,label+": unexpected rejection");
 } else {
  assert.ok([401,403,404].includes(r.status),label+" unexpectedly permitted: "+r.status+" "+JSON.stringify(r.data));
 }
 console.log("PASS DENIED "+label+" [HTTP "+r.status+"]");
}
(async()=>{
 const mine=await list("/owner_business_kpi_v1?select=business_id,net_manual_profit,profit_entitlements,recorded_investor_payments,unpaid_investor_balance,total_units_on_hand,internal_transfers&order=business_id.asc",
  jwt.owner,2,"tenant master two independent business KPI rows");
 assert.deepEqual(mine.map(x=>x.business_id),[101,102]);
 const b=mine[0];
 assert.equal(Number(b.net_manual_profit),1100);
 assert.equal(Number(b.profit_entitlements),330);
 assert.equal(Number(b.recorded_investor_payments),110);
 assert.equal(Number(b.unpaid_investor_balance),220);
 assert.equal(Number(b.total_units_on_hand),18);
 assert.equal(Number(b.internal_transfers),1);
 assert.equal(Number(mine[1].total_units_on_hand),5);
 const master=await list("/tenant_consolidated_kpi_v1?select=tenant_id,visible_businesses,recorded_revenue,recorded_costs,net_manual_profit,profit_entitlements,recorded_investor_payments,unpaid_investor_balance,on_hand_units_all_skus,enterprise_ready",
  jwt.owner,1,"master consolidation");
 assert.equal(master[0].tenant_id,1);
 assert.equal(master[0].visible_businesses,2);
 assert.equal(Number(master[0].recorded_revenue),6000);
 assert.equal(Number(master[0].recorded_costs),4900);
 assert.equal(Number(master[0].net_manual_profit),1100);
 assert.equal(Number(master[0].on_hand_units_all_skus),23);
 assert.equal(Number(master[0].unpaid_investor_balance),220);
 assert.equal(master[0].enterprise_ready,false);

 const controls=await list("/owner_business_control_board_v1?select=business_id,pending_owner_decisions,production_certified&order=business_id.asc",
  jwt.owner,2,"master owner control board");
 assert.ok(controls.every(x=>x.pending_owner_decisions===0&&!x.production_certified));
 const modules=await list("/business_module_settings_v1?business_id=eq.101&module_code=eq.pos&select=visibility,operational_enabled",
  jwt.owner,1,"show/locked/hidden is not operational permission");
 assert.equal(modules[0].visibility,"hidden");
 assert.equal(modules[0].operational_enabled,false);
 const inv=await list("/business_inventory_report_v1?business_id=eq.101&select=received_units_excluding_transfers,issued_units_excluding_transfers,internal_transfers,internal_transferred_units,unreconciled_location_items",
  jwt.owner,1,"double-entry transfer excluded from external stock");
 assert.equal(Number(inv[0].received_units_excluding_transfers),20);
 assert.equal(Number(inv[0].issued_units_excluding_transfers),2);
 assert.equal(Number(inv[0].internal_transferred_units),8);
 assert.equal(Number(inv[0].unreconciled_location_items),0);

 const own=await list("/owner_business_kpi_v1?select=business_id",jwt.businessOwner,1,
  "business owner only assigned company");
 assert.equal(own[0].business_id,101);
 await list("/tenant_consolidated_kpi_v1?select=tenant_id",jwt.businessOwner,0,
  "business owner cannot inherit master access");

 const other=await list("/owner_business_kpi_v1?select=business_id,total_units_on_hand",jwt.customer,1,
  "independent customer tenant only own company");
 assert.equal(other[0].business_id,201);
 assert.equal(Number(other[0].total_units_on_hand),9);
 await list("/owner_business_kpi_v1?business_id=eq.101",jwt.customer,0,
  "filter-by-ID does not leak another tenant");

 const investor=await list("/investor_statement_v1?select=agreement_code,investor_id,window_start,allocated_profit,recorded_paid,unpaid_balance&order=window_start.asc",
  jwt.investor,2,"investor sees own quarterly statements only");
 assert.ok(investor.every(x=>x.agreement_code==="Q14-PROFIT"&&x.investor_id===people.investor));
 assert.deepEqual(investor.map(x=>Number(x.allocated_profit)),[70,84]);
 const investor2=await list("/investor_statement_v1?select=agreement_code,allocated_profit",
  jwt.investorTwo,1,"different investor own semiannual statement");
 assert.equal(investor2[0].agreement_code,"H16-PROFIT");
 assert.equal(Number(investor2[0].allocated_profit),176);
 await list("/finance_months_v1?select=net_profit",jwt.investor,0,
  "investor cannot inspect manual raw business revenue");
 await list("/owner_business_kpi_v1?select=business_id",jwt.investor,0,
  "investor cannot see owner management dashboard");
 await list("/owner_business_kpi_v1?select=business_id",jwt.manager,0,
  "manager cannot see owner finance dashboard");
 await list("/owner_business_kpi_v1?select=business_id",jwt.staff,0,
  "site staff cannot see owner finance dashboard");
 await list("/investor_statement_v1?select=agreement_id",jwt.revoked,0,
  "revoked identity sees no contracts");
 await list("/investor_statement_v1?select=agreement_id",jwt.operator,0,
  "platform operator cannot inspect customer finance");
 await list("/investor_statement_v1?select=agreement_id",jwt.customer,0,
  "other tenant cannot inspect investor contracts");

 await reject("/rpc/decide_module_visibility_v1",jwt.manager,"POST",
  {p_id:1,p_decision:"approve"},"manager cannot approve owner request","owner_decision_denied");
 await reject("/rpc/record_funding_payment_v1",jwt.investor,"POST",
  {p_entitlement:1,p_amount:1,p_evidence:"fake receipt",p_request:"investor-pay"},
  "investor cannot issue own payment","funding_payment_denied");
 await reject("/funding_payments_v1",jwt.owner,"POST",{
  tenant_id:1,business_id:101,entitlement_id:1,paid_amount:999,
  evidence_reference:"fake",request_key:"direct-override",recorded_by:people.owner},
  "direct cash ledger INSERT forbidden");
 await reject("/business_module_settings_v1?business_id=eq.101",jwt.owner,
  "PATCH",{operational_enabled:true},"direct module activation forbidden");
 await reject("/finance_months_v1",null,"GET",undefined,"anon finance denied");
 const parts=jwt.owner.split(".");
 parts[2]=(parts[2][0]==="A"?"B":"A")+parts[2].slice(1);
 await reject("/owner_business_kpi_v1",parts.join("."),"GET",undefined,"tampered HMAC rejected");
 await reject("/owner_business_kpi_v1",token(people.owner,{aud:"wrong-audience"}),"GET",undefined,
  "wrong-audience signed JWT rejected");
 await list("/owner_business_kpi_v1?select=business_id",
  token(people.manager,{user_metadata:{role:"owner",is_owner:true},
   app_metadata:{role:"tenant_owner",tenant_id:1}}),0,
  "forged owner claims never grant dashboard access");

 console.log("SUCCESS: independent tenant, 2 businesses, 2 investor contracts, internal-transfer invariant, owner approval and payment restrictions via real signed-JWT HTTP (CI only).");
})().catch(e=>{console.error(e);process.exitCode=1});
