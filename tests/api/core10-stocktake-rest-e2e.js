// C10-A031: Signed HMAC JWT HTTP E2E, disposable PostgreSQL17/PostgREST ONLY.
// NOT a Supabase-issued GoTrue token, and NEVER a production release test.
"use strict";
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
const base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
if(!secret||secret.length<32)throw Error("DISPOSABLE_JWT_SECRET_REQUIRED");
const actors={
 owner:"11111111-1111-4111-8111-111111111111",
 businessOwner:"22222222-2222-4222-8222-222222222222",
 staff:"44444444-4444-4444-8444-444444444444",
 investor:"55555555-5555-4555-8555-555555555555",
 revoked:"66666666-6666-4666-8666-666666666666",
 customer:"77777777-7777-4777-8777-777777777777",
 operator:"99999999-9999-4999-8999-999999999999"
};
function jwt(sub,claims={}){
 const now=Math.floor(Date.now()/1000);
 const h=Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url");
 const p=Buffer.from(JSON.stringify({role:"authenticated",sub,aud:"authenticated",
  iat:now,exp:now+300,...claims})).toString("base64url");
 const body=h+"."+p;
 return body+"."+crypto.createHmac("sha256",secret).update(body).digest("base64url");
}
const tokens=Object.fromEntries(Object.entries(actors).map(([k,v])=>[k,jwt(v)]));
async function request(path,token,method="GET",payload){
 const headers={accept:"application/json"};
 if(token)headers.authorization="Bearer "+token;
 if(payload!==undefined)headers["content-type"]="application/json";
 const res=await fetch(base+path,{method,headers,
  body:payload===undefined?undefined:JSON.stringify(payload),
  redirect:"error",signal:AbortSignal.timeout(15000)});
 const raw=await res.text();
 let data;try{data=JSON.parse(raw)}catch{data=raw}
 return {status:res.status,data};
}
async function rpc(name,token,args){return request("/rpc/"+name,token,"POST",args)}
function ok(r,msg){assert.ok(r.status>=200&&r.status<300,msg+": HTTP "+r.status+" "+JSON.stringify(r.data));return r.data}
function rows(r,n,msg){const v=ok(r,msg);assert.ok(Array.isArray(v),msg+": not an array");assert.equal(v.length,n,msg+": count mismatch "+JSON.stringify(v));return v}
function denied(r,msg,reason){
 if(reason){assert.equal(r.status,400,msg+": "+JSON.stringify(r.data));assert.equal(r.data?.message,reason,msg+": policy mismatch");}
 else assert.ok([401,403,404].includes(r.status),msg+": unexpected access "+JSON.stringify(r));
}
(async()=>{
 ok(await rpc("post_stock_event",tokens.owner,{
  p_location:5001,p_item:8001,p_delta:10,p_request:"stocktake-http-seed-main"}),"seed main");
 ok(await rpc("post_stock_event",tokens.owner,{
  p_location:5002,p_item:8001,p_delta:4,p_request:"stocktake-http-seed-factory"}),"seed factory");

 const create={p_location:5001,p_counts:[{item_id:8001,counted:7}],p_request:"http-stocktake-one"};
 const ids=await Promise.all(Array.from({length:8},()=>rpc("create_stocktake_v1",tokens.staff,create)));
 const take=ok(ids[0],"staff count");
 for(const [i,r] of ids.entries())assert.equal(ok(r,"simultaneous count retry "+i),take);
 const list=rows(await request("/stocktakes_v1?select=id,status,location_id&order=id.asc",tokens.staff),1,"staff scoped header");
 assert.equal(list[0].status,"draft");assert.equal(list[0].location_id,5001);
 rows(await request("/stocktake_lines_v1?select=item_id,counted_quantity,expected_quantity",tokens.staff),1,"staff count details");
 denied(await rpc("create_stocktake_v1",tokens.staff,{...create,p_counts:[{item_id:8001,counted:6}]}),
 "changed request key","stocktake_idempotency_conflict");
 denied(await rpc("create_stocktake_v1",tokens.staff,{
  p_location:5001,p_counts:[{item_id:9001,counted:2}],p_request:"foreign-sku"}),
  "foreign business SKU count","stocktake_item_business_mismatch");
 ok(await rpc("submit_stocktake_v1",tokens.staff,{p_id:take}),"staff submits");
 const pre=rows(await request("/stocktake_discrepancy_v1?select=expected_quantity,counted_quantity,difference,status",tokens.staff),1,"physical discrepancy");
 assert.equal(Number(pre[0].expected_quantity),10);
 assert.equal(Number(pre[0].counted_quantity),7);
 assert.equal(Number(pre[0].difference),-3);
 assert.equal(pre[0].status,"submitted");
 const before=rows(await request("/stock_balances_v1?location_id=eq.5001&select=on_hand",tokens.owner),1,"balance before approval");
 assert.equal(Number(before[0].on_hand),10,"unapproved counted quantity must never change stock");
 denied(await rpc("approve_stocktake_v1",tokens.staff,{p_id:take}),
  "staff cannot approve own count","stocktake_approval_denied");
 denied(await rpc("approve_stocktake_v1",tokens.customer,{p_id:take}),
  "other tenant cannot approve","stocktake_approval_denied");
 denied(await rpc("approve_stocktake_v1",tokens.investor,{p_id:take}),
  "investor cannot approve","stocktake_approval_denied");
 ok(await rpc("approve_stocktake_v1",tokens.owner,{p_id:take}),"owner approves");
 const posts=await Promise.all(Array.from({length:8},()=>rpc("post_stocktake_v1",tokens.owner,{p_id:take})));
 for(const [i,r] of posts.entries())assert.equal(ok(r,"simultaneous post retry "+i),"posted");
 const b=rows(await request("/stock_balances_v1?location_id=eq.5001&select=on_hand",tokens.owner),1,"adjusted balance");
 assert.equal(Number(b[0].on_hand),7);
 const journal=rows(await request("/stocktake_lines_v1?stocktake_id=eq."+take+
  "&select=adjustment_movement_id",tokens.owner),1,"source-linked journal");
 assert.ok(journal[0].adjustment_movement_id>0);
 const delta=rows(await request("/stock_movements?id=eq."+journal[0].adjustment_movement_id+
  "&select=delta",tokens.owner),1,"exact adjustment journal");
 assert.equal(Number(delta[0].delta),-3);
 const reconciliation=rows(await request("/inventory_reconciliation_v1?select=reconciled",tokens.owner),2,"reconciliation after count");
 assert.ok(reconciliation.every(x=>x.reconciled===true));
 rows(await request("/stocktake_audit_v1?stocktake_id=eq."+take+"&select=id",tokens.owner),4,"exact once event history");
 denied(await rpc("void_stocktake_v1",tokens.owner,{p_id:take,p_reason:"cannot delete posted"}),
  "posted stocktake immutable","posted_stocktake_immutable");

 // Fresh count becomes STALE when an actual stock movement arrives before approval posting.
 const stale=ok(await rpc("create_stocktake_v1",tokens.staff,{
  p_location:5001,p_counts:[{item_id:8001,counted:5}],p_request:"http-stocktake-stale"}),"count for stale test");
 ok(await rpc("submit_stocktake_v1",tokens.staff,{p_id:stale}),"submit stale candidate");
 ok(await rpc("approve_stocktake_v1",tokens.owner,{p_id:stale}),"approve stale candidate");
 ok(await rpc("post_stock_event",tokens.owner,{
  p_location:5001,p_item:8001,p_delta:-1,p_request:"http-sale-between-count-and-post"}),"intervening sale");
 denied(await rpc("post_stocktake_v1",tokens.owner,{p_id:stale}),
  "stale snapshot must fail closed","stocktake_stale_recount_required");
 ok(await rpc("void_stocktake_v1",tokens.owner,{
  p_id:stale,p_reason:"Recount necessary after stock movement"}),"void stale count");
 denied(await rpc("post_stocktake_v1",tokens.owner,{p_id:stale}),
  "voided count not posted","stocktake_not_approved");

 // Owner counts own factory, cannot self-approve even as master tenant owner.
 const factory=ok(await rpc("create_stocktake_v1",tokens.owner,{
  p_location:5002,p_counts:[{item_id:8001,counted:4}],p_request:"http-stocktake-factory"}),"owner counts factory");
 ok(await rpc("submit_stocktake_v1",tokens.owner,{p_id:factory}),"owner submits own count");
 denied(await rpc("approve_stocktake_v1",tokens.owner,{p_id:factory}),
  "owner self-approval blocked","stocktake_self_approval_forbidden");
 ok(await rpc("approve_stocktake_v1",tokens.businessOwner,{p_id:factory}),"independent business owner reviews");
 ok(await rpc("post_stocktake_v1",tokens.businessOwner,{p_id:factory}),"zero difference posted");
 rows(await request("/stocktake_lines_v1?stocktake_id=eq."+factory+
  "&adjustment_movement_id=not.is.null&select=item_id",tokens.owner),0,"zero discrepancy produces no journal");

 // Authorization assertions must be signed and verified by PostgREST, not just SQL session fakes.
 rows(await request("/stocktakes_v1?select=id",tokens.customer),0,"foreign tenant denied");
 rows(await request("/stocktakes_v1?select=id",tokens.investor),0,"investor denied");
 rows(await request("/stocktakes_v1?select=id",tokens.revoked),0,"revoked denied");
 rows(await request("/stocktakes_v1?select=id",tokens.operator),0,"operator denied");
 rows(await request("/stocktakes_v1?location_id=eq.5002&select=id",tokens.staff),0,"staff cannot view factory count");
 rows(await request("/stocktake_audit_v1?select=id",tokens.staff),2*4,"staff can see own location audit only");
 denied(await request("/stocktake_lines_v1",tokens.owner,"PATCH",{counted_quantity:999}),
  "direct counter bypass denied");
 denied(await request("/stocktakes_v1",null),"anonymous read denied");
 denied(await rpc("create_stocktake_v1",null,create),"anonymous write denied");
 const fraud=jwt(actors.investor,{user_metadata:{role:"tenant_owner"},
  app_metadata:{is_owner:true,tenant_id:1}});
 rows(await request("/stocktakes_v1?select=id",fraud),0,"forged JWT metadata cannot elevate investor");
 const bad=tokens.owner.split(".");bad[2]=(bad[2][0]==="A"?"B":"A")+bad[2].slice(1);
 denied(await request("/stocktakes_v1",bad.join(".")),"tampered JWT signature blocked");
 const summary=rows(await request("/stocktakes_v1?select=id,status&order=id.asc",tokens.owner),3,"two posted + one voided");
 assert.equal(summary.filter(x=>x.status==="posted").length,2);
 assert.equal(summary.filter(x=>x.status==="voided").length,1);
 const final=rows(await request("/inventory_reconciliation_v1?select=reconciled",tokens.owner),2,"final ledger invariant");
 assert.ok(final.every(x=>x.reconciled));
 console.log("PASS C10-A031 signed HMAC HTTP: concurrent create+post, owner approval, count separation, stale/void, tenant/staff/investor/revoked/anon guards, exact journal. SIMULATED JWT, NOT Supabase GoTrue.");
})().catch(error=>{console.error("FAILED C10-A031 "+error.stack);process.exitCode=1});
