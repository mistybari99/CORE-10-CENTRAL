"use strict";
// Disposable signed-JWT API + PostgREST integration, no live SG sessions.
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
if(!secret||secret.length<32)throw Error("CI JWT secret missing");
const base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
const ids={
 owner:"11111111-1111-4111-8111-111111111111",
 businessOwner:"22222222-2222-4222-8222-222222222222",
 manager:"33333333-3333-4333-8333-333333333333",
 staff:"44444444-4444-4444-8444-444444444444",
 investor:"55555555-5555-4555-8555-555555555555",
 customer:"77777777-7777-4777-8777-777777777777",
 revoked:"66666666-6666-4666-8666-666666666666"
};
function token(sub,overrides={}){
 const now=Math.floor(Date.now()/1000);
 const head=Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url");
 const pay=Buffer.from(JSON.stringify({role:"authenticated",sub,iat:now,exp:now+300,
  aud:"authenticated",...overrides})).toString("base64url");
 const msg=head+"."+pay;
 return msg+"."+crypto.createHmac("sha256",secret).update(msg).digest("base64url");
}
const jwt=Object.fromEntries(Object.entries(ids).map(([k,v])=>[k,token(v)]));
async function query(path,who,method="GET",body){
 const res=await fetch(base+path,{method,headers:{
  "content-type":"application/json",...(who?{authorization:"Bearer "+who}:{})
 },body:body===undefined?undefined:JSON.stringify(body)});
 const raw=await res.text();let data;
 try{data=JSON.parse(raw)}catch{data=raw}
 return{status:res.status,data};
}
async function rows(path,who,count,label){
 const r=await query(path,who);
 assert.equal(r.status,200,label+": "+JSON.stringify(r));
 assert.ok(Array.isArray(r.data),label+": expected row list");
 assert.equal(r.data.length,count,label+": "+JSON.stringify(r.data));
 console.log("PASS "+label+" ["+count+"]");
 return r.data;
}
async function rpc(name,who,p){return query("/rpc/"+name,who,"POST",p)}
function accepted(r,label){
 assert.equal(r.status,200,label+": "+r.status+" "+JSON.stringify(r.data));
 console.log("PASS "+label);return r.data;
}
function blocked(r,label,reason){
 if(reason){
  assert.equal(r.status,400,label+" HTTP "+r.status+" "+JSON.stringify(r.data));
  assert.equal(r.data?.message,reason,label+": wrong denial");
 }else{
  assert.ok([401,403,404].includes(r.status),label+" bypassed:"+JSON.stringify(r));
 }
 console.log("PASS DENIED "+label);
}
(async()=>{
 const own=await rows("/operational_business_report_v1?select=business_id,posted_sale_docs,posted_purchase_docs,posted_sale_value_unreconciled,received_purchase_value_unreconciled,unposted_documents&order=business_id.asc",
  jwt.owner,2,"owner views two scoped operations");
 assert.deepEqual(own.map(x=>x.business_id),[101,102]);
 assert.equal(Number(own[0].posted_sale_docs),1);
 assert.equal(Number(own[0].posted_purchase_docs),1);
 assert.equal(Number(own[0].posted_sale_value_unreconciled),1000);
 assert.equal(Number(own[0].received_purchase_value_unreconciled),800);
 assert.equal(Number(own[0].unposted_documents),1);
 await rows("/operational_business_report_v1?select=business_id",jwt.businessOwner,1,
  "business owner sees only own operation KPI");
 await rows("/operational_business_report_v1?select=business_id",jwt.manager,0,
  "manager cannot see full financial operations report");
 await rows("/operational_documents_v1?select=id",jwt.manager,3,
  "manager can see own business draft and posted documents");
 await rows("/operational_documents_v1?select=id",jwt.staff,0,
  "site stock permission does not leak sales or purchase docs");
 await rows("/operational_documents_v1?select=id",jwt.investor,0,
  "investor cannot browse supplier/customer documents");
 await rows("/operational_documents_v1?select=id",jwt.revoked,0,
  "revoked manager cannot browse documents");
 const other=await rows("/operational_business_report_v1?select=business_id,received_purchase_value_unreconciled",jwt.customer,1,
  "customer tenant independent purchase report");
 assert.equal(other[0].business_id,201);
 assert.equal(Number(other[0].received_purchase_value_unreconciled),45);
 await rows("/operational_documents_v1?business_id=eq.101&select=id",jwt.customer,0,
  "cross tenant direct ID filter reveals nothing");

 blocked(await rpc("confirm_operational_document_v1",jwt.manager,{p_document:1}),
  "manager cannot approve sale","operational_confirm_denied");
 blocked(await rpc("create_operational_document_v1",jwt.investor,{
  p_business:101,p_location:5001,p_kind:"sale",p_counterparty:"Fake",
  p_lines:[{item:8001,quantity:1,unit_price:1}],p_discount:0,p_request:"investor-sale"
 }),"investor cannot sell","operational_scope_denied");
 blocked(await query("/operational_documents_v1",jwt.owner,"POST",{
  tenant_id:1,business_id:101,site_id:1001,location_id:5001,
  kind:"sale",counterparty:"Forged sale",subtotal:10,discount:0,
  lines_payload:[],request_key:"bypass",created_by:ids.owner
 }),"owner cannot INSERT posted sales directly");
 blocked(await query("/operational_documents_v1",null),"anonymous has no access to operational ledger");

 // Actual concurrent signed HTTP clients must converge on one draft; confirmed
 // purchase must post exactly once to inventory regardless of replay load.
 const payload={
  p_business:101,p_location:5001,p_kind:"purchase",
  p_counterparty:"Concurrent Demo Supplier",
  p_lines:[{item:8001,quantity:2,unit_price:15}],
  p_discount:0,p_request:"rest-concurrent-purchase-001"
 };
 const starts=await Promise.all(Array.from({length:8},()=>rpc(
  "create_operational_document_v1",jwt.owner,payload)));
 const id=Number(accepted(starts[0],"HTTP purchase created draft once"));
 assert.ok(Number.isSafeInteger(id)&&id>0);
 for(const r of starts)assert.equal(Number(accepted(r,"parallel same-key purchase retry")),id);
 const draft=await rows("/operational_documents_v1?id=eq."+id+
  "&select=id,status,net_amount",jwt.owner,1,"concurrent draft identity");
 assert.equal(draft[0].status,"draft");
 assert.equal(Number(draft[0].net_amount),30);
 assert.equal(accepted(await rpc("confirm_operational_document_v1",jwt.owner,{p_document:id}),
  "owner confirmed concurrent purchase"),"confirmed");
 const posts=await Promise.all(Array.from({length:12},()=>rpc(
  "post_operational_document_v1",jwt.owner,{p_document:id})));
 assert.ok(posts.every(r=>r.status===200&&r.data==="posted"),
  "concurrent posting failed or duplicated: "+JSON.stringify(posts));
 const movements=await rows("/stock_movements?request_key=eq.c10-op:"+id+
  ":line:1&select=id,delta",jwt.owner,1,
  "12 concurrent signed HTTP posts created one journal event");
 assert.equal(Number(movements[0].delta),2);
 const state=await rows("/operational_business_report_v1?business_id=eq.101"+
  "&select=posted_purchase_docs,received_purchase_value_unreconciled,posted_sale_value_unreconciled",
  jwt.owner,1,"single purchase posted, legacy sale unchanged");
 assert.equal(Number(state[0].posted_purchase_docs),2);
 assert.equal(Number(state[0].received_purchase_value_unreconciled),830);
 assert.equal(Number(state[0].posted_sale_value_unreconciled),1000);
 const stock=await rows("/inventory_reconciliation_v1?business_id=eq.101"+
  "&select=location_id,on_hand,reconciled&order=location_id.asc",
  jwt.owner,2,"stock reconciliation after 12 parallel HTTP operations");
 assert.deepEqual(stock.map(x=>Number(x.on_hand)),[9,3]);
 assert.ok(stock.every(x=>x.reconciled));

 blocked(await rpc("create_operational_document_v1",jwt.owner,{
  ...payload,p_lines:[{item:8001,quantity:5,unit_price:15}]
 }),"same key payload changed","operational_request_idempotency_conflict");
 blocked(await rpc("create_operational_document_v1",jwt.customer,payload),
  "customer cannot book purchase against owner tenant","operational_scope_denied");
 blocked(await rpc("confirm_operational_document_v1",token(ids.manager,{
  user_metadata:{is_owner:true},app_metadata:{role:"tenant_owner"}
 }),{p_document:id}),"forged JWT metadata does not grant approval","operational_confirm_denied");
 const wrong=token(ids.owner,{aud:"wrong-service"});
 blocked(await query("/operational_documents_v1",wrong),"wrong JWT audience rejected");
 console.log("SUCCESS: signed JWT operational business/tenant privacy, purchase->stock->sale, 8 parallel idempotent creates, 12 parallel exact once posts, stable reports.");
})().catch(e=>{console.error(e);process.exitCode=1});
