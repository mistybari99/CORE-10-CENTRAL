// PACK-01: two real HMAC-signed synthetic JWTs over disposable PostgREST.
// This is NOT GoTrue, hosted staging, Production, or an RLS/Storage certification.
"use strict";
const assert=require("node:assert/strict");
const crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
const base=(process.env.CORE10_CI_REST_URL||"").replace(/\/$/,"");
if(!secret || secret.length<32 || !/^http:\/\/127\.0\.0\.1:\d+$/.test(base))
 throw Error("PACK01_DISPOSABLE_SIGNER_AND_LOOPBACK_POSTGREST_REQUIRED");
const U={
 tenantA:"11111111-1111-4111-8111-111111111111",
 businessA:"22222222-2222-4222-8222-222222222222",
 tenantB:"77777777-7777-4777-8777-777777777777",
 stockOnly:"44444444-4444-4444-8444-444444444444",
 revoked:"66666666-6666-4666-8666-666666666666"
};
const now=()=>Math.floor(Date.now()/1000);
function jwt(sub,claims={},key=secret){
 const b64=v=>Buffer.from(JSON.stringify(v)).toString("base64url");
 const data=b64({alg:"HS256",typ:"JWT"})+"."+b64({
  role:"authenticated",sub,aud:"authenticated",iat:now(),exp:now()+300,...claims
 });
 return data+"."+crypto.createHmac("sha256",key).update(data).digest("base64url");
}
async function req(path,token,method="GET",payload){
 const headers={accept:"application/json"};
 if(token)headers.authorization="Bearer "+token;
 if(payload!==undefined)headers["content-type"]="application/json";
 let response,raw;
 for(let i=0;i<30;i++){
  response=await fetch(base+path,{method,headers,
   body:payload===undefined?undefined:JSON.stringify(payload),
   signal:AbortSignal.timeout(16000),redirect:"error"});
  raw=await response.text();
  if(response.status!==503)break;
  await new Promise(r=>setTimeout(r,400));
 }
 let data;try{data=JSON.parse(raw)}catch{data=raw}
 return{status:response.status,data};
}
const rpc=(name,token,args)=>req("/rpc/"+name,token,"POST",args);
function pass(result,what){
 assert.ok(result.status>=200&&result.status<300,
  what+" expected 2xx got "+result.status+" "+JSON.stringify(result.data));
 return result.data;
}
function denied(result,what,expected){
 assert.ok(result.status>=400,what+" unexpectedly returned "+result.status+" "+JSON.stringify(result.data));
 if(expected)assert.equal(result.data&&result.data.message,expected,
  what+" wrong denial: "+JSON.stringify(result.data));
}
(async()=>{
 const a=jwt(U.tenantA),b=jwt(U.tenantB),ownerA=jwt(U.businessA);
 const mgr=jwt("33333333-3333-4333-8333-333333333333");
 assert.equal(pass(await rpc("can_tenant",a,{p_tenant:1}),"tenant A membership"),true);
 assert.equal(pass(await rpc("can_tenant",b,{p_tenant:2}),"tenant B membership"),true);
 assert.equal(pass(await rpc("can_tenant",b,{p_tenant:1}),"tenant B not A"),false);
 assert.equal(pass(await rpc("can_tenant",a,{p_tenant:2}),"tenant A not B"),false);
 // These same public RPCs must work for their own business before probing negatives.
 pass(await rpc("wf_read_overview_v1",a,{p_business:101}),"A workforce");
 pass(await rpc("wf_read_overview_v1",b,{p_business:201}),"B workforce");
 pass(await rpc("read_operation_overview_v1",ownerA,{p_business:101}),"business A operations");
 pass(await rpc("read_inventory_commands_v1",ownerA,{p_business:101}),"business A inventory");
 pass(await rpc("am_whoami_v1",ownerA,{p_business:101}),"business A asset role");
 pass(await rpc("a054_my_access_v1",ownerA,{p_business:101}),"business A HR role");
 // Same-tenant business owner 101 cannot read business 102 or tenant B business 201.
 denied(await rpc("wf_read_overview_v1",ownerA,{p_business:102}),"same-tenant business isolation","wf_denied");
 denied(await rpc("wf_read_overview_v1",ownerA,{p_business:201}),"cross tenant from business A","wf_denied");
 denied(await rpc("wf_read_overview_v1",b,{p_business:101}),"cross tenant workforce","wf_denied");
 denied(await rpc("read_operation_overview_v1",b,{p_business:101}),"foreign operation report","A049_READ_DENIED");
 denied(await rpc("read_inventory_commands_v1",b,{p_business:101}),"foreign inventory report","A048_READ_DENIED");
 denied(await rpc("am_whoami_v1",b,{p_business:101}),"foreign asset role","am_denied");
 denied(await rpc("a054_my_access_v1",b,{p_business:101}),"foreign workforce delegation","wf_denied");
 denied(await rpc("am_export_csv_v1",b,{p_business:101,
   p_request:"pack01-b-export-denied",p_kind:"work_orders",p_params:null}),
   "foreign maintenance export","am_denied");
 denied(await rpc("create_inventory_command_v1",b,{p_business:101,p_kind:"receive",
   p_source:null,p_destination:5001,p_item:8001,p_quantity:1,p_request:"pack01-b-stock-denied"}),
   "foreign inventory create","A048_PERMISSION_DENIED");
 denied(await rpc("create_operation_order_v1",b,{p_business:101,p_location:5001,
   p_item:8001,p_kind:"purchase_receive",p_quantity:1,p_unit_value:1,
   p_external:"foreign",p_request:"pack01-b-order-denied"}),
   "foreign order create","A049_ORDER_DENIED");
 // GOV002 prerequisite: canonical Build02A approval roles are server-resolved,
 // not inferred from inventory/site grants or unsigned app_metadata.
 const approval=(tok,tenant,business,action)=>rpc("can_approval_action_v1",tok,{
  p_tenant:tenant,p_business:business,p_action:action
 });
 assert.equal(pass(await approval(a,1,101,"approval.decide"),"tenant owner approval"),true);
 assert.equal(pass(await approval(ownerA,1,101,"approval.decide"),"business owner approval"),true);
 assert.equal(pass(await approval(mgr,1,101,"approval.submit"),"manager submit role"),true);
 assert.equal(pass(await approval(mgr,1,101,"approval.decide"),"manager not decision maker"),false);
 assert.equal(pass(await approval(jwt(U.stockOnly),1,101,"approval.decide"),"stock role cannot decide"),false);
 assert.equal(pass(await approval(b,1,101,"approval.decide"),"other tenant approval denied"),false);
 assert.equal(pass(await approval(ownerA,2,101,"approval.decide"),"wrong tenant ID denied"),false);
 assert.equal(pass(await approval(ownerA,1,201,"approval.decide"),"wrong business denied"),false);
 assert.equal(pass(await approval(ownerA,1,101,"stock.post"),"stock action not approval"),false);
 const writeApproval={
  p_business:101,p_subject:"33333333-3333-4333-8333-333333333333",
  p_actions:["approval.decide"],p_denied_actions:["approval.withdraw"],
  p_valid_until:new Date(Date.now()+3600000).toISOString(),
  p_request:"pack01-gov002-signed-grant",p_expected_version:null
 };
 denied(await rpc("build02a_set_approval_policy_v1",mgr,writeApproval),
  "manager cannot write policy","BUILD02A_POLICY_DENIED");
 denied(await rpc("build02a_set_approval_policy_v1",b,writeApproval),
  "foreign tenant cannot write policy","BUILD02A_POLICY_DENIED");
 pass(await rpc("build02a_set_approval_policy_v1",a,writeApproval),
  "tenant owner can grant manager decision for synthetic test");
 assert.equal(pass(await approval(mgr,1,101,"approval.decide"),"explicit manager decision now effective"),true);
 assert.equal(pass(await approval(mgr,1,101,"approval.withdraw"),"explicit denial wins over baseline"),false);
 const clearApproval={...writeApproval,p_actions:[],p_denied_actions:[],
  p_valid_until:null,p_request:"pack01-gov002-signed-clear"};
 pass(await rpc("build02a_set_approval_policy_v1",a,clearApproval),
  "tenant owner removes explicit policy on synthetic fixture");
 assert.equal(pass(await approval(mgr,1,101,"approval.decide"),"grant removal denies decision"),false);
 assert.equal(pass(await approval(mgr,1,101,"approval.withdraw"),"baseline after policy removal"),true);

 // Role stuffing cannot override server memberships.
 const stuffed=jwt(U.stockOnly,{app_metadata:{role:"tenant_owner"},business_role:"business_owner",tenant_id:1,is_owner:true});
 denied(await rpc("am_whoami_v1",stuffed,{p_business:101}),"role stuffing asset","am_denied");
 denied(await rpc("wf_read_overview_v1",jwt(U.revoked,{app_metadata:{role:"owner"}}),{p_business:101}),
  "revoked manager","wf_denied");
 // HTTP auth/signature verification and expiry, never synthetic SQL sub claims.
 denied(await rpc("am_whoami_v1",null,{p_business:101}),"anonymous");
 denied(await rpc("am_whoami_v1",jwt(U.businessA,{},"wrong_disposable_signing_key_at_least_32_chars"),{p_business:101}),
  "invalid HMAC signature");
 denied(await rpc("am_whoami_v1",jwt(U.businessA,{iat:now()-900,exp:now()-900}) /* > 5 min PostgREST clock skew */,{p_business:101}),"expired signed JWT");
 // A018 deliberately GRANTs SELECT on stock_balances_v1 with server-side
 // can_site RLS: 200+[] for unauthorized B is the intended safe response,
 // unlike private tables that must return 4xx. Create a real disposable row
 // through signed owner RPCs so [] cannot be explained by an empty dataset.
 const draft=pass(await rpc("create_inventory_command_v1",ownerA,{
  p_business:101,p_kind:"receive",p_source:null,p_destination:5001,
  p_item:8001,p_quantity:3,p_request:"pack01-signed-rls-stock-receive"
 }),"signed synthetic stock draft");
 assert.ok(draft.command_id,"stock draft ID required");
 pass(await rpc("advance_inventory_command_v1",ownerA,{
  p_command:draft.command_id,p_action:"confirm",p_version:1,
  p_request:"pack01-signed-rls-stock-confirm"
 }),"signed synthetic stock confirm");
 pass(await rpc("advance_inventory_command_v1",ownerA,{
  p_command:draft.command_id,p_action:"post",p_version:2,
  p_request:"pack01-signed-rls-stock-post"
 }),"signed synthetic stock post");
 const stockPath="/stock_balances_v1?select=tenant_id,business_id,site_id,location_id,item_id,on_hand&location_id=eq.5001&item_id=eq.8001";
 const ownRows=pass(await req(stockPath,ownerA),"own RLS-protected stock rows");
 assert.ok(Array.isArray(ownRows)&&ownRows.some(row=>row.business_id===101&&Number(row.on_hand)>=3),
  "owner must see a seeded stock row so tenant isolation proves something");
 const foreignRows=pass(await req(stockPath,b),"other-tenant RLS-filtered stock");
 assert.deepEqual(foreignRows,[],"foreign signed tenant must see no stock row");
 const stockOnlyRows=pass(await req(stockPath,jwt(U.stockOnly)),"site staff scoped stock");
 assert.ok(Array.isArray(stockOnlyRows),"site staff RLS response expected");
 // A018 site_grants SELECT is explicitly SELF-only RLS, not table-level 403.
 const grantPath="/site_grants?select=site_id,user_id,business_id&site_id=eq.1001";
 const ownGrant=pass(await req(grantPath,jwt(U.stockOnly)),"own site grant RLS");
 assert.ok(ownGrant.some(g=>g.user_id===U.stockOnly&&g.business_id===101),
  "stock staff must see its OWN seeded grant under self-only policy");
 const otherGrant=pass(await req(grantPath,b),"other-tenant site grant RLS");
 assert.deepEqual(otherGrant,[],"other-tenant token must not read stock staff grant");
 // All remaining PRIVATE tables must deny the direct HTTP SELECT surface.
 for(const table of ["am_grants","am_assets","wf_employees","a054_delegations",
   "operation_orders_v1","inventory_commands_v1"]){
  denied(await req("/"+table+"?select=*",a),"direct table read "+table);
  denied(await req("/"+table+"?select=*",b),"direct table read tenant B "+table);
 }
 denied(await rpc("ami_ctx",ownerA,{p_business:101}),"private asset helper");
 denied(await rpc("inventory_action_authorized_v1",ownerA,{
  p_tenant:1,p_business:101,p_location:5001,p_action:"stock.read"}),"private inventory helper");
 console.log("PACK01_SIGNED_TWO_TENANT_HTTP_PASS (HMAC JWT, disposable PG17/PostgREST ONLY)");
})().catch(e=>{console.error(e);process.exit(1)});
