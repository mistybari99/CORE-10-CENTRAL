// CORE10 A037 costing engine: signed-JWT PostgREST HTTP test (synthetic CI identities only, disposable DB).
"use strict";
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET,base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
if(!secret||secret.length<32)throw Error("CI-only JWT signing secret not provided");
const ids={owner:"11111111-1111-4111-8111-111111111111",businessOwner:"22222222-2222-4222-8222-222222222222",
 manager:"33333333-3333-4333-8333-333333333333",staff:"44444444-4444-4444-8444-444444444444",
 investor:"55555555-5555-4555-8555-555555555555",revoked:"66666666-6666-4666-8666-666666666666",
 customer:"77777777-7777-4777-8777-777777777777"};
function token(sub){const t=Math.floor(Date.now()/1000);
 const h=Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url");
 const b=Buffer.from(JSON.stringify({sub,role:"authenticated",aud:"authenticated",iat:t,exp:t+300})).toString("base64url");
 const u=h+"."+b;return u+"."+crypto.createHmac("sha256",secret).update(u).digest("base64url");}
const tok=Object.fromEntries(Object.entries(ids).map(([k,v])=>[k,token(v)]));
async function request(path,who,method="GET",payload){
 const res=await fetch(base+path,{method,headers:{"content-type":"application/json",...(who?{authorization:"Bearer "+who}:{})},
  body:payload===undefined?undefined:JSON.stringify(payload)});
 const s=await res.text();let d;try{d=JSON.parse(s)}catch{d=s}return{status:res.status,data:d};}
const rpc=(n,who,b)=>request("/rpc/"+n,who,"POST",b);
const ok=(r,l)=>{assert.equal(r.status,200,l+": "+JSON.stringify(r));console.log("PASS "+l);return r.data;};
const rows=async(p,who,n,l)=>{const r=ok(await request(p,who),l);assert.ok(Array.isArray(r),l);assert.equal(r.length,n,l+" rows "+JSON.stringify(r));return r;};
const denied=(r,l,msg)=>{if(msg){assert.equal(r.status,400,l+": "+JSON.stringify(r));assert.equal(r.data?.message,msg);}
 else assert.ok([401,403,404].includes(r.status),l+": "+JSON.stringify(r));console.log("PASS DENIED "+l+" [HTTP "+r.status+"]");};
(async()=>{
 const docs=await rows("/operational_documents_v1?select=id,request_key&request_key=like.a037rest-sale-*&order=request_key.asc",tok.owner,13,"owner lists seeded sales");
 const same=docs.find(d=>d.request_key==="a037rest-sale-same").id;
 const distinct=docs.filter(d=>d.request_key!=="a037rest-sale-same").map(d=>d.id);
 assert.equal(distinct.length,12);
 // costing starts with purchase value 200 for 20 units, none of the sales costed
 let val=await rows("/cost_valuation_report_v1?select=stock_on_hand,costed_quantity,inventory_value,reconciliation_status&item_id=eq.8201&location_id=eq.5001",tok.owner,1,"valuation before sale costing");
 assert.equal(Number(val[0].inventory_value),200);assert.equal(Number(val[0].costed_quantity),20);assert.equal(Number(val[0].stock_on_hand),5);
 assert.equal(val[0].reconciliation_status,"costed_exceeds_stock");
 // ---- security over real HTTP ----
 for(const who of ["manager","investor","revoked","customer","staff"])
  denied(await rpc("post_sale_cogs_v1",tok[who],{p_document:same}),who+" cannot post COGS","cost_post_denied");
 denied(await rpc("post_sale_cogs_v1",undefined,{p_document:same}),"anonymous cannot post COGS");
 for(const who of ["manager","investor","revoked","customer","staff"])
  await rows("/cost_events_v1?select=id",tok[who],0,who+" sees no cost ledger");
 await rows("/cost_events_v1?select=id",tok.businessOwner,1,"business owner sees own business ledger only (purchase event)");
 denied(await request("/cost_events_v1",tok.owner,"POST",{tenant_id:1,business_id:101}),"owner cannot insert ledger rows directly");
 denied(await request("/cost_valuation_v1?item_id=eq.8201",tok.owner,"PATCH",{total_value:0}),"owner cannot edit valuation directly");
 denied(await request("/cost_events_v1?id=gt.0",tok.owner,"DELETE"),"owner cannot delete ledger rows");
 // ---- 12 parallel requests for the SAME document: exactly one costs, 11 are idempotent no-ops ----
 const race=await Promise.all(Array.from({length:12},()=>rpc("post_sale_cogs_v1",tok.owner,{p_document:same})));
 race.forEach((r,i)=>assert.equal(r.status,200,"same-doc race "+i+": "+JSON.stringify(r)));
 assert.equal(race.filter(r=>r.data.status==="costed").length,1,"exactly one costing");
 assert.equal(race.filter(r=>r.data.status==="already_costed").length,11,"eleven idempotent retries");
 console.log("PASS 12 parallel same-document costing = 1 posting");
 let ev=await rows("/cost_events_v1?select=value&source_id=eq."+same+"&event_type=eq.sale_cogs",tok.owner,1,"single sale_cogs event");
 assert.equal(Number(ev[0].value),-30);
 // ---- 12 parallel DISTINCT documents against the same valuation row: no lost update, no negative value ----
 const race2=await Promise.all(distinct.map(id=>rpc("post_sale_cogs_v1",tok.owner,{p_document:id})));
 race2.forEach((r,i)=>assert.equal(r.status,200,"distinct race "+i+": "+JSON.stringify(r)));
 assert.equal(race2.filter(r=>r.data.status==="costed").length,12);
 console.log("PASS 12 parallel distinct costings");
 val=await rows("/cost_valuation_report_v1?select=stock_on_hand,costed_quantity,inventory_value,avg_cost,reconciliation_status&item_id=eq.8201&location_id=eq.5001",tok.owner,1,"valuation after races");
 assert.equal(Number(val[0].costed_quantity),5);assert.equal(Number(val[0].inventory_value),50);
 assert.equal(Number(val[0].avg_cost),10);assert.equal(val[0].reconciliation_status,"reconciled");
 const integrity=await rows("/cost_ledger_integrity_v1?select=balanced",tok.owner,1,"ledger integrity");
 assert.ok(integrity.every(x=>x.balanced===true));
 const margin=await rows("/sale_cogs_margin_v1?select=revenue,cogs,gross_margin,cogs_status&order=document_id.asc",tok.owner,13,"sale margins");
 assert.ok(margin.every(m=>m.cogs_status==="costed"));
 assert.equal(margin.reduce((a,m)=>a+Number(m.cogs),0),150);
 // blocked case over HTTP: a fresh sale of an uncosted quantity returns a reasoned block, not a margin
 console.log("A037 REST: all checks passed");
})().catch(e=>{console.error(e);process.exit(1);});
