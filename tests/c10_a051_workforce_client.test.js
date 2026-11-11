"use strict";
/* C10-A051 client/UI contract tests (no network, no database). */
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const API=require("../core10-workforce-client.js");
const root=path.join(__dirname,"..");
const sqlDir=path.join(root,"internal","enterprise-sql");
const sql=fs.readdirSync(sqlDir).filter(f=>/^c10_a051_workforce_.*\.sql$/.test(f)).map(f=>fs.readFileSync(path.join(sqlDir,f),"utf8")).join("\n");

// 1) allow-list == real SQL signatures (names AND argument names, in order)
const sigs={};
for(const m of sql.matchAll(/CREATE FUNCTION c10_demo\.(wf_[a-z_]+_v1)\(([^)]*)\)/g))
 sigs[m[1]]=m[2].split(",").map(x=>x.trim().split(/\s+/)[0]).filter(Boolean);
for(const name of API.NAMES){
 const fn="wf_"+name+"_v1";
 assert.ok(sigs[fn],"client allow-list entry has no SQL function: "+fn);
 assert.deepEqual(Object.keys(API.SPEC[name].a),sigs[fn],"argument names differ from SQL for "+fn);
}
const exposed=Object.keys(sigs);
for(const fn of exposed){
 const short=fn.replace(/^wf_/,"").replace(/_v1$/,"");
 assert.ok(API.NAMES.includes(short),"SQL RPC missing from client allow-list (dead or unreachable): "+fn);
}
// every SQL RPC is also granted to authenticated and nothing internal is
assert.match(sql,/proname ~ '\^wf_\.\*_v1\$'|f\.proname ~ '\^wf_\.\*_v1\$'/);
assert.ok(!/GRANT[^;]*wfi_/.test(sql),"internal wfi_ helpers must never be granted");
assert.ok(!/GRANT[^;]*TO anon/i.test(sql),"no anon grants");

// 2) behaviour of the signed-session adapter
const calls=[];
const mk=(over={})=>({auth:{getUser:async()=>({data:{user:{id:"u"}},error:null})},schema:(s)=>({rpc:async(n,a)=>{calls.push([s,n,a]);return over.rpc?over.rpc(n,a):{data:{server_authorized:true},error:null}}})});
(async()=>{
 const api=API.create({client:mk()});
 await api.call("read_overview",{p_business:101});
 assert.deepEqual(calls[0],["c10_demo","wf_read_overview_v1",{p_business:101}]);
 for(const [label,fn,code] of [
  ["unknown rpc",()=>api.call("drop_everything",{}),"RPC_NOT_ALLOWED"],
  ["prototype name",()=>api.call("constructor",{}),"RPC_NOT_ALLOWED"],
  ["extra arg",()=>api.call("read_overview",{p_business:101,p_role:"owner"}),"UNKNOWN_ARGUMENT"],
  ["string business",()=>api.call("read_overview",{p_business:"101"}),"INVALID_ARGUMENT"],
  ["float business",()=>api.call("read_overview",{p_business:1.5}),"INVALID_ARGUMENT"],
  ["zero business",()=>api.call("read_overview",{p_business:0}),"INVALID_ARGUMENT"],
  ["bad request key",()=>api.call("cancel_leave",{p_business:1,p_request:"short",p_leave:1,p_note:"x"}),"INVALID_REQUEST_KEY"],
  ["bad date",()=>api.call("list_attendance",{p_business:1,p_from:"2026-1-1",p_to:"2026-01-02",p_employee:null,p_site:null}),"INVALID_ARGUMENT"],
  ["naive timestamp",()=>api.call("request_correction",{p_business:1,p_request:"corr-12345678",p_employee:1,p_work_date:"2026-10-01",p_new_in:"2026-10-01T09:00:00",p_new_out:null,p_new_status:null,p_reason:"abcde"}),"INVALID_ARGUMENT"],
  ["NaN money",()=>api.call("set_salary_structure",{p_business:1,p_request:"sal-12345678",p_employee:1,p_policy_code:"M",p_base:NaN,p_effective_from:"2026-01-01",p_reason:"abc"}),"INVALID_ARGUMENT"],
  ["missing arg",()=>api.call("list_employees",{p_business:1}),"INVALID_ARGUMENT"]]){
  await assert.rejects(fn,e=>e.code===code,label);
 }
 assert.equal(calls.length,1,"rejected calls must never reach the network");
 // unsigned / failed sessions
 await assert.rejects(()=>API.create({client:{auth:{getUser:async()=>({data:{user:null},error:{message:"bad jwt"}})},schema:()=>({rpc:async()=>({})})}}).call("read_overview",{p_business:1}),e=>e.code==="AUTHENTICATED_USER_REQUIRED");
 await assert.rejects(()=>API.create({client:{schema:()=>({rpc:async()=>({})})}}).call("read_overview",{p_business:1}),e=>e.code==="SIGNED_SUPABASE_CLIENT_REQUIRED");
 await assert.rejects(()=>API.create({client:null}).call("read_overview",{p_business:1}),e=>e.code==="SIGNED_SUPABASE_CLIENT_REQUIRED");
 // server errors surface verbatim, never become success; unauthorised read payloads are rejected
 await assert.rejects(()=>API.create({client:mk({rpc:()=>({data:null,error:{code:"P0001",message:"wf_denied"}})})}).call("read_overview",{p_business:1}),e=>e.code==="wf_denied");
 await assert.rejects(()=>API.create({client:mk({rpc:()=>({data:{ok:1},error:null})})}).call("read_overview",{p_business:1}),e=>e.code==="WORKFORCE_RESPONSE_UNAUTHORIZED");
 await assert.rejects(()=>API.create({client:mk({rpc:()=>({data:null,error:null})})}).call("read_overview",{p_business:1}),e=>e.code==="WORKFORCE_RESPONSE_REJECTED");
 // write receipts need no server_authorized flag but must be objects
 const w=await API.create({client:mk({rpc:()=>({data:{status:"applied"},error:null})})}).call("cancel_leave",{p_business:1,p_request:"cancel-12345678",p_leave:2,p_note:"abc"});
 assert.equal(w.status,"applied");
 // request keys are unique, well-formed, and sanitised
 const keys=new Set();for(let i=0;i<500;i++){const k=API.requestKey("pay!x");assert.match(k,/^[A-Za-z0-9_-]{8,100}$/);keys.add(k)}
 assert.equal(keys.size,500);
 // 3) UI source hygiene: no innerHTML sinks, no token storage, no client-side role authority, no direct table access
 for(const f of fs.readdirSync(root).filter(x=>/^core10-workforce-.*\.(js|html)$/.test(x))){
  const src=fs.readFileSync(path.join(root,f),"utf8");
  assert.ok(!/innerHTML|outerHTML|insertAdjacentHTML|document\.write|eval\(|new Function/.test(src),f+": unsafe DOM/eval sink");
  assert.ok(!/localStorage|sessionStorage|indexedDB/.test(src),f+": must not persist tokens/data locally");
  assert.ok(!/\.from\(["']/.test(src),f+": no direct table access");
  assert.ok(!/service_role|SUPABASE_SERVICE|BEGIN PRIVATE KEY/i.test(src),f+": secret-like material");
 }
 for(const f of fs.readdirSync(root).filter(x=>/^core10-workforce-.*\.html$/.test(x))){
  const src=fs.readFileSync(path.join(root,f),"utf8");
  assert.match(src,/Content-Security-Policy/);assert.ok(!/<script(?![^>]*\ssrc=)/.test(src),f+": inline script");
  assert.match(src,/data-screen="[a-z]+"/);
 }
 console.log("PASS A051 client contract ("+API.NAMES.length+" RPC allow-list entries match SQL signatures)");
})().catch(e=>{console.error(e);process.exitCode=1});
