// C10-A019/A020: real HTTP/PostgREST signed-JWT end-to-end on DISPOSABLE PG17 only.
// Secret and identities are CI fixtures, not Supabase-issued production accounts.
"use strict";
const assert=require("node:assert/strict");
const crypto=require("node:crypto");
const base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
const secret=process.env.CORE10_CI_JWT_SECRET;
if(!secret||secret.length<32)throw Error("Disposable JWT secret missing");
const ids={
 owner:"11111111-1111-4111-8111-111111111111",
 bizOwner:"22222222-2222-4222-8222-222222222222",
 manager:"33333333-3333-4333-8333-333333333333",
 siteStaff:"44444444-4444-4444-8444-444444444444",
 investor:"55555555-5555-4555-8555-555555555555",
 revoked:"66666666-6666-4666-8666-666666666666",
 customer:"77777777-7777-4777-8777-777777777777",
 customerStaff:"88888888-8888-4888-8888-888888888888",
 operator:"99999999-9999-4999-8999-999999999999"
};
function jwt(sub,claims={}){
 const t=Math.floor(Date.now()/1000);
 const head=Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url");
 const payload=Buffer.from(JSON.stringify({role:"authenticated",sub,aud:"authenticated",iat:t,exp:t+300,...claims})).toString("base64url");
 const signed=head+"."+payload;
 return signed+"."+crypto.createHmac("sha256",secret).update(signed).digest("base64url");
}
async function req(path,{token=null,method="GET",body,headers={}}={}){
 const h={accept:"application/json",...headers};
 if(token)h.authorization="Bearer "+token;
 if(body!==undefined)h["content-type"]="application/json";
 const res=await fetch(base+path,{method,headers:h,body:body===undefined?undefined:JSON.stringify(body)});
 const raw=await res.text();let data;try{data=JSON.parse(raw)}catch{data=raw}
 return {status:res.status,data};
}
const tok=Object.fromEntries(Object.entries(ids).map(([k,v])=>[k,jwt(v)]));
function ok(r,label){
 assert.ok(r.status>=200&&r.status<300,label+" HTTP "+r.status+" "+JSON.stringify(r.data));
 console.log("PASS "+label+" [HTTP "+r.status+"]");return r.data;
}
function denied(r,label){
 assert.ok(r.status===401||r.status===403||r.status===404,
  label+" unexpectedly allowed: HTTP "+r.status+" "+JSON.stringify(r.data));
 console.log("PASS DENIED "+label+" [HTTP "+r.status+"]");
}
function deniedByPolicy(r,label,message){
 assert.equal(r.status,400,label+": expected current SQL denial status; HTTP "+r.status);
 assert.equal(r.data?.code,"P0001",label+": must be deliberate explicit server refusal");
 assert.equal(r.data?.message,message,label+": unexpected error reason");
 console.log("PASS DENIED BY RPC "+label+" [HTTP "+r.status+" "+message+"]");
}
function rows(r,label,n){const d=ok(r,label);assert.ok(Array.isArray(d),label+": not an array");assert.equal(d.length,n,label+": wrong row count "+JSON.stringify(d));return d}
function rpc(name,token,body){return req("/rpc/"+name,{method:"POST",token,body})}
const setup=(slug,request,mode="quick",sites=null)=>({
 p_legal:11,p_slug:slug,p_template:"food_manufacturing",p_display_name:slug,
 p_mode:mode,p_sites:sites,p_request:request,p_brand_hex:"#6D1D2A"
});
function isClientDenied(r,label){
 denied(r,label);
 assert.ok(r.data===null||typeof r.data!=="object"||!r.data.on_hand,
  label+" returned private balance");
}
(async()=>{
 // Real signed tokens passed through PostgREST's HMAC verifier, impersonation and RLS.
 const owner=rows(await req("/businesses?select=id,tenant_id,status&order=id.asc",{token:tok.owner}),"owner businesses",2);
 assert.deepEqual(owner.map(x=>x.id),[101,102]);
 assert.ok(owner.every(x=>x.tenant_id===1));
 const ownStaff=rows(await req("/sites?select=id,business_id&order=id.asc",{token:tok.siteStaff}),"site staff visibility",1);
 assert.equal(ownStaff[0].id,1001);
 const cust=rows(await req("/businesses?select=id,tenant_id",{token:tok.customer}),"independent customer sees own business only",1);
 assert.equal(cust[0].id,201);
 rows(await req("/businesses?select=id",{token:tok.bizOwner}),"business owner only one business",1);
 rows(await req("/businesses?select=id",{token:tok.manager}),"manager only one business",1);
 rows(await req("/businesses?select=id",{token:tok.investor}),"investor cannot see operational businesses",0);
 rows(await req("/businesses?select=id",{token:tok.revoked}),"revoked cannot see businesses",0);
 rows(await req("/businesses?select=id",{token:tok.operator}),"platform operator cannot read client data",0);
 rows(await req("/businesses?select=id",{token:tok.customerStaff}),"customer staff sees only authorized business",1);
 rows(await req("/stock_locations?select=id",{token:tok.siteStaff}),"site-staff one stock location",1);
 rows(await req("/stock_locations?select=id",{token:tok.customerStaff}),"customer staff segregated stock location",1);

 denied(await rpc("setup_business_v1",null,setup("anon","anon-001")),"anonymous setup denied");
 deniedByPolicy(await rpc("setup_business_v1",tok.manager,setup("manager-forge","manager-001")),"manager cannot forge tenant ownership","setup_not_authorized");
 deniedByPolicy(await rpc("setup_business_v1",tok.investor,setup("investor-try","investor-001")),"investor cannot setup","setup_not_authorized");
 deniedByPolicy(await rpc("setup_business_v1",tok.revoked,setup("revoked-try","revoked-001")),"revoked cannot setup","setup_not_authorized");
 deniedByPolicy(await rpc("setup_business_v1",tok.customer,setup("foreign-owner","foreign-001")),"other tenant cannot setup in owner legal entity","setup_not_authorized");

 // RLS alone does not protect DRAFT status: direct table writes must be revoked.
 denied(await req("/businesses",{token:tok.owner,method:"POST",body:{
  tenant_id:1,legal_entity_id:11,slug:"bypass-active",
  template_code:"food_manufacturing",request_key:"bypass",status:"active"
 }}),"direct ACTIVE business insert forbidden");
 denied(await req("/sites",{token:tok.owner,method:"POST",body:{
  tenant_id:1,business_id:101,kind:"showroom",label:"Untracked",request_key:"untracked"
 }}),"direct site insert forbidden");
 denied(await req("/stock_movements",{token:tok.owner,method:"POST",body:{
  tenant_id:1,business_id:101,site_id:1001,location_id:5001,
  item_id:8001,delta:999,request_key:"bypass-ledger"
 }}),"direct journal insert forbidden");

 // Deterministic retry and draft-only setup; same signed JWT through both calls.
 const b1=ok(await rpc("setup_business_v1",tok.owner,setup("http-quick","http-quick-01")),"Quick signed-JWT setup");
 const b1retry=ok(await rpc("setup_business_v1",tok.owner,setup("http-quick","http-quick-01")),"Quick exact retry");
 assert.equal(b1,b1retry);
 const advanced=setup("http-advanced","http-adv-01","advanced",[
  {kind:"showroom",label:"Showroom A"},{kind:"factory",label:"Factory A"},
  {kind:"godown",label:"Godown A"}
 ]);
 const b2=ok(await rpc("setup_business_v1",tok.owner,advanced),"Advanced signed-JWT setup");
 const created=rows(await req("/business_setup_overview_v1?select=business_id,setup_status,visible_sites,visible_modules,brand_hex,setup_mode&order=business_id.asc",{token:tok.owner}),
 "owner sees exactly created setup drafts",2);
 assert.deepEqual(created.map(x=>x.business_id),[b1,b2]);
 assert.deepEqual(created.map(x=>x.visible_sites),[1,3]);
 assert.deepEqual(created.map(x=>x.visible_modules),[7,7]);
 assert.ok(created.every(x=>x.setup_status==="draft"&&x.brand_hex==="#6D1D2A"));
 rows(await req("/business_setup_overview_v1?select=business_id",{token:tok.customer}),"independent tenant sees zero owner setup profiles",0);
 rows(await req("/business_setup_overview_v1?select=business_id",{token:tok.siteStaff}),"site staff sees no unrelated setup profiles",0);
 // HTTP conflict comes as PostgREST 400, not necessarily forbidden; distinguish errors.
 let conflict=await rpc("setup_business_v1",tok.owner,{...setup("http-quick","http-quick-01"),p_display_name:"payload changed"});
 assert.ok(conflict.status>=400&&String(conflict.data?.message||"").includes("idempotency_key_payload_conflict"));
 console.log("PASS conflicting retries rejected");

 // Two-role inventory: stock entry, atomic transfer, reconciliation and isolation.
 const initial=ok(await rpc("post_stock_event",tok.owner,{
  p_location:5001,p_item:8001,p_delta:25,p_request:"http-stock-01"}),"signed owner stock receive");
 const retry=ok(await rpc("post_stock_event",tok.owner,{
  p_location:5001,p_item:8001,p_delta:25,p_request:"http-stock-01"}),"stock retry");
 assert.equal(retry,initial);
 const transfer=ok(await rpc("transfer_stock_v1",tok.owner,{
  p_source:5001,p_destination:5002,p_item:8001,p_quantity:8,p_request:"http-transfer-01"
 }),"signed owner atomic stock transfer");
 const transferRetry=ok(await rpc("transfer_stock_v1",tok.owner,{
  p_source:5001,p_destination:5002,p_item:8001,p_quantity:8,p_request:"http-transfer-01"
 }),"transfer retry");
 assert.equal(transfer,transferRetry);
 const balances=rows(await req("/stock_balances_v1?select=location_id,item_id,on_hand&order=location_id.asc",{token:tok.owner}),
 "owner scoped balance",2);
 assert.deepEqual(balances.map(x=>x.location_id),[5001,5002]);
 assert.deepEqual(balances.map(x=>Number(x.on_hand)),[17,8]);
 const reconciliation=rows(await req("/inventory_reconciliation_v1?select=location_id,reconciled&order=location_id.asc",{token:tok.owner}),
 "owner ledger reconciliation",2);
 assert.ok(reconciliation.every(x=>x.reconciled===true));
 rows(await req("/stock_balances_v1?select=location_id",{token:tok.customer}),"customer cannot read owner stock",0);
 rows(await req("/stock_balances_v1?select=location_id",{token:tok.investor}),"investor cannot read stock",0);
 rows(await req("/stock_transfers_v1?select=id",{token:tok.siteStaff}),"site staff cannot see both transfer sites",0);
 const overdraw=await rpc("post_stock_event",tok.owner,{
  p_location:5001,p_item:8001,p_delta:-100,p_request:"http-overdraw"
 });
 assert.ok(overdraw.status>=400&&String(overdraw.data?.message||"").includes("insufficient_stock"));
 const unauthorized=await rpc("transfer_stock_v1",tok.siteStaff,{
  p_source:5001,p_destination:5002,p_item:8001,p_quantity:1,p_request:"staff-foreign-site"
 });
 assert.ok(unauthorized.status>=400&&String(unauthorized.data?.message||"").includes("transfer_not_authorized"));
 console.log("PASS insufficient stock and staff foreign-site transfers blocked");

 // JWT signature/authentication failures: authentication must be verified by HTTP gateway.
 const t=jwt(ids.owner),bits=t.split(".");
 bits[2]=(bits[2][0]==="A"?"B":"A")+bits[2].slice(1);
 denied(await rpc("setup_business_v1",bits.join("."),setup("tampered","tampered-001")),"tampered HMAC");
 denied(await rpc("setup_business_v1",jwt(ids.owner,{exp:Math.floor(Date.now()/1000)-3600}),setup("expired","expired-001")),"expired JWT");
 denied(await rpc("setup_business_v1",jwt(ids.owner,{aud:"wrong-service"}),setup("bad-aud","bad-aud-001")),"wrong audience");
 denied(await rpc("setup_business_v1",jwt(ids.owner,{nbf:Math.floor(Date.now()/1000)+3600}),setup("not-yet-valid","nbf-001")),"future nbf JWT");
 deniedByPolicy(await rpc("setup_business_v1",jwt(ids.manager,{user_metadata:{is_owner:true,role:"tenant_owner"},app_metadata:{is_owner:true}}),setup("forged-metadata","forged-001")),"metadata does not escalate manager","setup_not_authorized");
 deniedByPolicy(await rpc("setup_business_v1",jwt(ids.customer,{tenant_id:1,role:"authenticated",user_metadata:{tenant_id:1}}),setup("forged-tenant","forged-tenant-001")),"forged tenant does not escalate","setup_not_authorized");
 rows(await req("/businesses?select=id",{token:tok.owner,headers:{"X-Requested-Role":"service_role","X-User-Id":ids.customer}}),"spoofed headers do not alter DB tenant identity",4);
 console.log("SUCCESS: signed JWT HTTP proves CRUD/RPC grant restrictions, real scope filtering, atomic setup/inventory, negative cases (CI synthetic tokens only).");
})().catch(e=>{console.error(e);process.exitCode=1});
