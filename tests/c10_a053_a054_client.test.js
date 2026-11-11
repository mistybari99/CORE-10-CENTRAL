"use strict";
/* C10-A053/A054 client/UI contract tests (no network, no database). */
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const API=require("../core10-workforce-policy-client.js");
const root=path.join(__dirname,"..");
const sqlDir=path.join(root,"internal","enterprise-sql");
const read=(f)=>fs.readFileSync(path.join(root,f),"utf8");
const sqlFiles=fs.readdirSync(sqlDir).filter(f=>/^c10_a05[1-4]_.*\.sql$/.test(f));
const sql=sqlFiles.map(f=>fs.readFileSync(path.join(sqlDir,f),"utf8")).join("\n");

// 1) allow-list == real SQL signatures (rpc name AND argument names in order); every new public RPC is reachable
const sigs={};
for(const m of sql.matchAll(/CREATE FUNCTION c10_demo\.((?:wf|a053|a054)_[a-z_0-9]+_v1)\(([^)]*)\)/g))
 sigs[m[1]]=m[2].split(",").map(x=>x.trim().split(/\s+/)[0]).filter(Boolean);
for(const [name,spec] of Object.entries(API.SPEC)){
 assert.ok(sigs[spec.rpc],"allow-list entry has no SQL function: "+spec.rpc);
 assert.deepEqual(Object.keys(spec.a),sigs[spec.rpc],"argument names differ from SQL for "+spec.rpc);
 if(/^wf_/.test(spec.rpc))assert.ok(["my_businesses","payroll_preview","list_payroll_runs","create_payroll_draft","payroll_transition"].includes(name),"unreviewed A051 RPC exposed: "+spec.rpc);
}
const reachable=new Set(Object.values(API.SPEC).map(s=>s.rpc));
for(const fn of Object.keys(sigs).filter(f=>/^(a053|a054)_/.test(f)))assert.ok(reachable.has(fn),"new SQL RPC missing from client allow-list: "+fn);
// grants: only *_v1 public RPCs; helpers never; no anon
for(const f of ["c10_a054_workforce_policy_v1.sql","c10_a053_workforce_integration_v1.sql"]){
 const s=read("internal/enterprise-sql/"+f);
 assert.match(s,/~ '\^a05[34]_\.\*_v1\$'/,"public grant pattern in "+f);
 assert.ok(!/GRANT[^;]*a05[34]i_/.test(s),"helpers must never be granted");
 assert.ok(!/GRANT[^;]*TO anon/i.test(s),"no anon grants");
}
// 2) approval is not payment: nothing in SQL/client can execute a payment
const forbidden=/(execute_payment|pay_salary|disburse|payout|initiate_transfer|bank_file|send_money)/i;
for(const name of API.NAMES)assert.ok(!forbidden.test(name)&&!forbidden.test(API.SPEC[name].rpc),"payment-executing API forbidden: "+name);
for(const fn of Object.keys(sigs))assert.ok(!forbidden.test(fn),"payment-executing SQL function forbidden: "+fn);
const pay=read("internal/enterprise-sql/c10_a054_workforce_policy_v1.sql");
assert.match(pay,/'payment_executed',false/);assert.match(pay,/'money_movement',false/);
// 3) UI sources: no unsafe sinks, no inline handlers, strict CSP pages
const uiJs=["core10-workforce-policy-app.js","core10-workforce-policy-client.js"];
for(const f of uiJs){
 const s=read(f);
 for(const bad of [/innerHTML/,/outerHTML/,/insertAdjacentHTML/,/document\.write/,/\beval\s*\(/,/new Function/,/localStorage\.setItem\([^)]*(token|jwt|secret)/i,/service_role/i])assert.ok(!bad.test(s),f+" contains unsafe pattern "+bad);
}
for(const page of ["integration","delegation","policy","liability"]){
 const h=read("core10-workforce-"+page+".html");
 assert.match(h,/Content-Security-Policy/);assert.match(h,/script-src 'self'/);assert.ok(!/\son[a-z]+=/i.test(h),"inline handler in "+page);
 assert.match(h,new RegExp('data-screen="'+page+'"'));
}
// 4) behaviour of the adapter
const calls=[];
const mk=(over={})=>({auth:{getUser:async()=>({data:{user:{id:"u"}},error:null})},schema:(s)=>({rpc:async(n,a)=>{calls.push([s,n,a]);return over.rpc?over.rpc(n,a):{data:{server_authorized:true},error:null}}})});
(async()=>{
 const api=API.create({client:mk()});
 await api.call("liability_report",{p_business:102,p_period:"2026-10-01"});
 assert.deepEqual(calls[0],["c10_demo","a054_liability_report_v1",{p_business:102,p_period:"2026-10-01"}]);
 for(const [label,fn,code] of [
  ["unknown rpc",()=>api.call("pay_salary",{}),"RPC_NOT_ALLOWED"],
  ["prototype",()=>api.call("constructor",{}),"RPC_NOT_ALLOWED"],
  ["extra arg (role escalation)",()=>api.call("my_access",{p_business:1,p_role:"owner"}),"UNKNOWN_ARGUMENT"],
  ["string business",()=>api.call("liability_report",{p_business:"102",p_period:null}),"INVALID_ARGUMENT"],
  ["bad uuid",()=>api.call("grant_delegation",{p_business:1,p_request:"dg-12345678",p_delegate:"not-a-uuid",p_role:"hr",p_effect:"allow",p_site:null,p_period_from:null,p_period_to:null,p_expires_at:null,p_reason:"abc"}),"INVALID_ARGUMENT"],
  ["naive expiry timestamp",()=>api.call("grant_delegation",{p_business:1,p_request:"dg-12345678",p_delegate:"11111111-1111-4111-8111-111111111111",p_role:"hr",p_effect:"allow",p_site:null,p_period_from:null,p_period_to:null,p_expires_at:"2026-12-01T10:00:00",p_reason:"abc"}),"INVALID_ARGUMENT"],
  ["short request key",()=>api.call("record_external_payment",{p_business:1,p_request:"short",p_period:"2026-10-01",p_employee:1,p_amount:1,p_method:"cash",p_reference:"abc",p_paid_on:"2026-11-01",p_note:null}),"INVALID_REQUEST_KEY"],
  ["NaN amount",()=>api.call("record_external_payment",{p_business:1,p_request:"pay-12345678",p_period:"2026-10-01",p_employee:1,p_amount:NaN,p_method:"cash",p_reference:"abc",p_paid_on:"2026-11-01",p_note:null}),"INVALID_ARGUMENT"],
  ["missing arg",()=>api.call("save_policy",{p_business:1}),"INVALID_ARGUMENT"]]){
  await assert.rejects(fn,e=>e.code===code,label);
 }
 assert.equal(calls.length,1,"rejected calls must never reach the network");
 await assert.rejects(()=>API.create({client:{auth:{getUser:async()=>({data:{user:null},error:{message:"bad jwt"}})},schema:()=>({rpc:async()=>({})})}}).call("my_access",{p_business:1}),e=>e.code==="AUTHENTICATED_USER_REQUIRED");
 await assert.rejects(()=>API.create({client:null}).call("my_access",{p_business:1}),e=>e.code==="SIGNED_SUPABASE_CLIENT_REQUIRED");
 await assert.rejects(()=>API.create({client:mk({rpc:()=>({data:null,error:{code:"P0001",message:"a054_liability_denied"}})})}).call("liability_report",{p_business:1,p_period:null}),e=>e.code==="a054_liability_denied");
 await assert.rejects(()=>API.create({client:mk({rpc:()=>({data:{totals:{}},error:null})})}).call("liability_report",{p_business:1,p_period:null}),e=>e.code==="WORKFORCE_RESPONSE_UNAUTHORIZED");
 const w=await API.create({client:mk({rpc:()=>({data:{status:"recorded",payment_executed:false},error:null})})}).call("record_external_payment",{p_business:1,p_request:"pay-12345678",p_period:"2026-10-01",p_employee:1,p_amount:10.5,p_method:"cash",p_reference:"VCH-1",p_paid_on:"2026-11-01",p_note:null});
 assert.equal(w.payment_executed,false);
 const k1=api.requestKey("x"),k2=api.requestKey("x");assert.notEqual(k1,k2);assert.match(k1,/^[A-Za-z0-9_-]{8,100}$/);
 // 5) A046 registry parity: SQL persona registry == manifest (alias, uid, tenant, businesses, active)
 const man=JSON.parse(read("internal/demo-identity-program/demo-identity-manifest-v1.json"));
 const a053=read("internal/enterprise-sql/c10_a053_workforce_integration_v1.sql");
 for(const p of man.personas){
  const re=new RegExp("\\('"+p.key+"','"+p.uid+"','A046_REGISTRY','"+p.key+"',"+(p.tenant_id===null?"NULL":p.tenant_id)+",'\\{"+p.business_ids.join(",")+"\\}',"+p.active+",");
  assert.match(a053,re,"registry row differs from A046 manifest: "+p.key);
 }
 console.log("A053_A054_CLIENT_TEST_PASS");
})().catch(e=>{console.error(e);process.exit(1)});
