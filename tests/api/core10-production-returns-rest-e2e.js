// CORE10 A027/A028 disposable signed HTTP / PostgREST checks, no live Supabase Auth.
"use strict";
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
if(!secret||secret.length<32)throw Error("CI-only HMAC secret required");
const base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
const identities={
 owner:"11111111-1111-4111-8111-111111111111",
 manager:"33333333-3333-4333-8333-333333333333",
 staff:"44444444-4444-4444-8444-444444444444",
 investor:"55555555-5555-4555-8555-555555555555",
 customer:"77777777-7777-4777-8777-777777777777",
 revoked:"66666666-6666-4666-8666-666666666666"
};
function jwt(sub,claims={}){
 const now=Math.floor(Date.now()/1000);
 const head=Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url");
 const pay=Buffer.from(JSON.stringify({sub,role:"authenticated",aud:"authenticated",
  iat:now,exp:now+300,...claims})).toString("base64url");
 const raw=head+"."+pay;
 return raw+"."+crypto.createHmac("sha256",secret).update(raw).digest("base64url");
}
const tok=Object.fromEntries(Object.entries(identities).map(([k,v])=>[k,jwt(v)]));
async function http(path,token,method="GET",body){
 const headers={"content-type":"application/json"};
 if(token)headers.authorization="Bearer "+token;
 const response=await fetch(base+path,{method,headers,
  body:body===undefined?undefined:JSON.stringify(body)});
 let data;const raw=await response.text();
 try{data=JSON.parse(raw)}catch{data=raw}
 return {status:response.status,data};
}
async function rows(path,who,n,label){
 const res=await http(path,who);
 assert.equal(res.status,200,label+": "+JSON.stringify(res));
 assert.ok(Array.isArray(res.data),label+": not an array");
 assert.equal(res.data.length,n,label+": wrong count "+JSON.stringify(res.data));
 console.log("PASS "+label+" "+n+" row(s)");
 return res.data;
}
function accepted(r,label){
 assert.equal(r.status,200,label+": "+JSON.stringify(r));
 console.log("PASS "+label);
 return r.data;
}
function refused(r,label,message=null){
 if(message){assert.equal(r.status,400,label+": "+JSON.stringify(r));
 assert.equal(r.data?.message,message,label+": incorrect policy refusal");}
 else assert.ok([401,403,404].includes(r.status),label+": "+JSON.stringify(r));
 console.log("PASS DENIED "+label+" [HTTP "+r.status+"]");
}
const rpc=(name,token,payload)=>http("/rpc/"+name,token,"POST",payload);
(async()=>{
 const boms=await rows("/bom_recipes_v1?select=id,business_id,recipe_code,status&order=id.asc",
  tok.owner,2,"owner BOM catalog");
 assert.equal(boms[0].status,"approved");
 const b1=await rows("/production_cost_estimate_v1?select=batch_id,expected_output,estimated_total_cost,estimated_cost_per_unit,actual_cogs_certified&order=batch_id.asc",
  tok.owner,2,"owner batch estimated cost");
 assert.equal(Number(b1[0].expected_output),10);
 assert.equal(Number(b1[0].estimated_total_cost),220);
 assert.equal(Number(b1[0].estimated_cost_per_unit),22);
 assert.equal(b1[0].actual_cogs_certified,false);
 const net=await rows("/operational_net_returns_v1?business_id=eq.101&select=net_sale_value_unreconciled,net_purchase_value_unreconciled,actual_refunds_reconciled",
  tok.owner,1,"discounted returns net reporting");
 assert.equal(Number(net[0].net_sale_value_unreconciled),0);
 assert.equal(Number(net[0].net_purchase_value_unreconciled),30);
 assert.equal(net[0].actual_refunds_reconciled,false);
 await rows("/bom_recipes_v1?select=id",tok.customer,0,"independent customer cannot see owner's BOM");
 await rows("/return_documents_v1?select=id",tok.customer,0,"independent customer cannot see owner's returns");
 await rows("/production_batches_v1?select=id",tok.staff,0,"site staff cannot read secret production batches");
 await rows("/operational_net_returns_v1?select=business_id",tok.manager,0,"manager cannot read owner return finance KPI");
 await rows("/bom_recipes_v1?select=id",tok.investor,0,"investor cannot inspect manufacturing recipe");
 await rows("/return_documents_v1?select=id",tok.revoked,0,"revoked user cannot inspect customer returns");
 refused(await rpc("approve_bom_v1",tok.manager,{p_recipe:boms[0].id}),
  "manager cannot approve recipe","bom_approval_denied");
 refused(await rpc("create_bom_v1",tok.customer,{
  p_business:101,p_finished_item:8004,p_code:"OTHER-RECIPE",p_yield:2,
  p_ingredients:[{item:8001,qty:1,estimated_unit_cost:30}],
  p_overhead:0,p_request:"cross-company-bom"
 }),"independent customer cannot create owner's BOM","bom_owner_permission_denied");
 refused(await rpc("create_return_v1",tok.investor,{
  p_original:1,p_lines:[{line:1,quantity:1}],
  p_reason:"Unauthorized return",p_request:"investor-return"
 }),"investor cannot create customer return","return_scope_denied");
 refused(await http("/bom_recipes_v1",null),"anon BOM schema blocked");
 refused(await http("/production_batches_v1",jwt(identities.owner,{aud:"other-service"})),
  "invalid JWT audience rejected");
 const signed=tok.owner.split(".");
 signed[2]=(signed[2][0]==="A"?"B":"A")+signed[2].slice(1);
 refused(await http("/return_documents_v1",signed.join(".")),"tampered signed token rejected");

 // Manager's prepared draft production batch: owner reviews then 12 simultaneous
 // signed HTTP posts must create exactly one set of ingredient/output stock events.
 const mgr=await rows("/production_batches_v1?request_key=eq.manager-draft-batch&select=id,status",
  tok.owner,1,"manager prepared batch for review");
 const id=mgr[0].id;assert.equal(mgr[0].status,"draft");
 assert.equal(accepted(await rpc("confirm_production_batch_v1",tok.owner,{p_batch:id}),
  "owner confirmed manager production"),"confirmed");
 const postings=await Promise.all(Array.from({length:12},()=>rpc(
  "post_production_batch_v1",tok.owner,{p_batch:id})));
 assert.ok(postings.every(r=>r.status===200&&r.data==="posted"),
  "12 signed HTTP posts not idempotent: "+JSON.stringify(postings));
 const movements=await rows("/stock_movements?request_key=like.c10-production:"+id+":*&select=delta,request_key",
  tok.owner,3,"12 concurrent production posts: exactly two material and one output");
 assert.deepEqual(movements.map(m=>Number(m.delta)).sort((a,b)=>a-b),[-2,-1,5]);
 const reports=await rows("/inventory_reconciliation_v1?business_id=eq.101&select=on_hand,reconciled",
  tok.owner,3,"inventory reconciles after 12 production HTTP posts");
 assert.ok(reports.every(x=>x.reconciled));
 const cake=await rows("/stock_balances_v1?location_id=eq.5001&item_id=eq.8004&select=on_hand",
  tok.owner,1,"finished cake after parallel production");
 assert.equal(Number(cake[0].on_hand),15);

 // Original six-unit sale is fully returned. New partial-return draft can be
 // confirmed but cannot post beyond original quantity, even via parallel RPC.
 const original=await rows("/operational_documents_v1?request_key=eq.sale-cake-001&select=id",
  tok.owner,1,"source sale for negative return");
 const returnReq={
  p_original:original[0].id,p_lines:[{line:1,quantity:1}],
  p_reason:"Exceeds all originally sold units",p_request:"http-over-return"
 };
 const retid=accepted(await rpc("create_return_v1",tok.owner,returnReq),
  "draft additional return");
 assert.equal(accepted(await rpc("confirm_return_v1",tok.owner,{p_return:retid}),
  "owner confirmed return"),"confirmed");
 const over=await Promise.all(Array.from({length:3},()=>rpc(
  "post_return_v1",tok.owner,{p_return:retid})));
 for(const r of over)refused(r,"over-return never credited stock","return_exceeds_remaining_quantity");
 const state=await rows("/return_documents_v1?id=eq."+retid+"&select=status",
  tok.owner,1,"refused return stays unposted");
 assert.equal(state[0].status,"confirmed");
 const cakeAfter=await rows("/stock_balances_v1?location_id=eq.5001&item_id=eq.8004&select=on_hand",
  tok.owner,1,"refused return did not alter cake stock");
 assert.equal(Number(cakeAfter[0].on_hand),15);
 console.log("SUCCESS: actual signed-JWT HTTP BOM/production and original-line returns, atomic and concurrent idempotency, company isolation (CI only)");
})().catch(e=>{console.error(e);process.exitCode=1});
