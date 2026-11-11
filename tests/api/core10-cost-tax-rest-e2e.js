// CORE10 A030 signed JWT / PostgREST HTTP integration, synthetic CI users only.
"use strict";
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET,base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
if(!secret||secret.length<32)throw Error("CI-only JWT signing secret not provided");
const ids={owner:"11111111-1111-4111-8111-111111111111",
 businessOwner:"22222222-2222-4222-8222-222222222222",
 manager:"33333333-3333-4333-8333-333333333333",
 investor:"55555555-5555-4555-8555-555555555555",
 customer:"77777777-7777-4777-8777-777777777777",
 revoked:"66666666-6666-4666-8666-666666666666"};
function token(sub,extra={}){
 const t=Math.floor(Date.now()/1000);
 const h=Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url");
 const b=Buffer.from(JSON.stringify({sub,role:"authenticated",aud:"authenticated",
  iat:t,exp:t+300,...extra})).toString("base64url");
 const u=h+"."+b;return u+"."+crypto.createHmac("sha256",secret).update(u).digest("base64url");
}
const tok=Object.fromEntries(Object.entries(ids).map(([k,v])=>[k,token(v)]));
async function request(path,who,method="GET",payload){
 const res=await fetch(base+path,{method,headers:{"content-type":"application/json",
  ...(who?{authorization:"Bearer "+who}:{})},
  body:payload===undefined?undefined:JSON.stringify(payload)});
 const s=await res.text();let d;try{d=JSON.parse(s)}catch{d=s}
 return {status:res.status,data:d};
}
const rpc=(name,who,body)=>request("/rpc/"+name,who,"POST",body);
function ok(r,label){assert.equal(r.status,200,label+": "+JSON.stringify(r));console.log("PASS "+label);return r.data;}
async function rows(path,who,num,label){const r=ok(await request(path,who),label);
 assert.ok(Array.isArray(r),label+": no row list");assert.equal(r.length,num,label+": wrong row count "+JSON.stringify(r));return r;}
function deny(r,label,reason){
 if(reason){assert.equal(r.status,400,label+": "+JSON.stringify(r));assert.equal(r.data?.message,reason);}
 else assert.ok([401,403,404].includes(r.status),label+": "+JSON.stringify(r));
 console.log("PASS DENIED "+label+" [HTTP "+r.status+"]");
}
(async()=>{
 const own=await rows("/owner_cost_tax_summary_v1?select=business_id,posted_sales,estimated_cogs_known_only,estimated_margin_when_fully_costed,estimated_tax_known_only,legally_or_financially_certified&order=business_id.asc",
  tok.owner,2,"owner only business cost/tax rows");
 const b=own[0];assert.equal(b.business_id,101);
 assert.equal(b.posted_sales,2);
 assert.equal(Number(b.estimated_cogs_known_only),100);
 assert.equal(Number(b.estimated_margin_when_fully_costed),180);
 assert.equal(Number(b.estimated_tax_known_only),36.52);
 assert.equal(b.legally_or_financially_certified,false);
 const tax=await rows("/posted_sale_tax_preview_v1?select=estimated_tax_amount,pricing_mode,rate_bps,tax_filing_certified&order=document_id.asc",
  tok.owner,2,"discount-aware inclusive tax estimate");
 assert.deepEqual(tax.map(x=>Number(x.estimated_tax_amount)),[23.48,13.04]);
 assert.ok(tax.every(x=>x.pricing_mode==="inclusive"&&x.rate_bps===1500&&!x.tax_filing_certified));
 const costs=await rows("/posted_sales_cost_preview_v1?select=estimated_cogs,estimated_gross_margin,actual_cogs_certified&order=document_id.asc",
  tok.owner,2,"manual cost coverage and no false actual COGS");
 assert.deepEqual(costs.map(x=>Number(x.estimated_cogs)),[80,20]);
 assert.deepEqual(costs.map(x=>Number(x.estimated_gross_margin)),[100,80]);
 assert.ok(costs.every(x=>x.actual_cogs_certified===false));
 const inv=await rows("/inventory_value_preview_v1?business_id=eq.101&select=estimated_stock_value,unpriced_stock_skus,actual_inventory_value_certified",
  tok.owner,1,"business stock estimated value");
 assert.equal(Number(inv[0].estimated_stock_value),400);
 assert.equal(inv[0].actual_inventory_value_certified,false);
 await rows("/owner_cost_tax_summary_v1?select=business_id",tok.businessOwner,1,
  "business owner cannot see sibling summary");
 await rows("/owner_cost_tax_summary_v1?select=business_id",tok.manager,0,
  "manager cannot see owner rate/tax dashboard");
 await rows("/owner_cost_tax_summary_v1?select=business_id",tok.investor,0,
  "investor cannot see cost and tax rates");
 await rows("/owner_cost_tax_summary_v1?select=business_id",tok.revoked,0,
  "revoked account cannot see costing");
 await rows("/item_cost_rates_v1?select=item_id",tok.customer,0,
  "independent customer cannot read owner rate cards");
 await rows("/tax_preview_profiles_v1?select=rate_bps",tok.customer,0,
  "independent tenant cannot read owner's manual tax rate");
 deny(await rpc("create_tax_preview_profile_v1",tok.manager,{
  p_business:101,p_label:"Unauthorized Tax",p_rate_bps:1500,p_mode:"exclusive",
  p_request:"manager-tax"
 }),"manager unable to overwrite tax preview","tax_profile_owner_denied");
 deny(await rpc("create_cost_rate_v1",tok.customer,{
  p_business:101,p_item:8001,p_cost:1,p_request:"foreign-tax"
 }),"customer cannot create portfolio cost","cost_rate_owner_denied");
 deny(await request("/item_cost_rates_v1?business_id=eq.101",tok.owner,"PATCH",{unit_cost:1}),
  "direct cost mutation forbidden");
 deny(await request("/tax_preview_profiles_v1",null),"anonymous tax model schema denied");
 deny(await request("/owner_cost_tax_summary_v1",token(ids.owner,{aud:"untrusted-service"})),
  "incorrect audience denied");
 const corrupt=tok.owner.split(".");corrupt[2]=(corrupt[2][0]==="A"?"B":"A")+corrupt[2].slice(1);
 deny(await request("/owner_cost_tax_summary_v1",corrupt.join(".")),"altered HMAC denied");
 // An independent cost draft for a sibling business cannot change existing company
 // rates, and 8 parallel repeated HTTP requests must result in one draft.
 const payload={p_business:102,p_item:8002,p_cost:25,p_request:"second-business-cost-draft"};
 const attempts=await Promise.all(Array.from({length:8},()=>rpc("create_cost_rate_v1",tok.owner,payload)));
 const returned=attempts.map((x,i)=>Number(ok(x,"parallel cost rate request "+(i+1))));
 assert.equal(new Set(returned).size,1,"concurrent cost draft not idempotent");
 const sibling=await rows("/item_cost_rates_v1?business_id=eq.102&select=id,status",
  tok.owner,1,"one isolated cost rate draft");
 assert.equal(sibling[0].status,"draft");
 const still=await rows("/owner_cost_tax_summary_v1?business_id=eq.101&select=estimated_margin_when_fully_costed",
  tok.owner,1,"sibling cost draft does not mutate existing gross-margin preview");
 assert.equal(Number(still[0].estimated_margin_when_fully_costed),180);
 console.log("SUCCESS: actual HTTP HMAC-verified JWT RLS cost/tax math, 8 concurrent idempotent writes and false-certified guards (synthetic only).");
})().catch(e=>{console.error(e);process.exitCode=1});
