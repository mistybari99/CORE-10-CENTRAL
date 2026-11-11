// C10-A051: signed HMAC JWT -> PostgREST -> c10_demo Workforce RPC E2E. Disposable PostgreSQL ONLY.
// NOT a Supabase-issued GoTrue token and NEVER a production release test. Run after the A051 SQL e2e fixture state.
"use strict";
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
const base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
if(!secret||secret.length<32)throw Error("DISPOSABLE_JWT_SECRET_REQUIRED");
const U={owner:"11111111-1111-4111-8111-111111111111",bo:"22222222-2222-4222-8222-222222222222",mgr:"33333333-3333-4333-8333-333333333333",
 investor:"55555555-5555-4555-8555-555555555555",revoked:"66666666-6666-4666-8666-666666666666",owner2:"77777777-7777-4777-8777-777777777777",
 staff2:"88888888-8888-4888-8888-888888888888",operator:"99999999-9999-4999-8999-999999999999",
 sup:"a1111111-1111-4111-8111-111111111111",e1:"a2222222-2222-4222-8222-222222222222",e3:"a3333333-3333-4333-8333-333333333333"};
function sign(payload,key=secret){
 const h=Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url"),p=Buffer.from(JSON.stringify(payload)).toString("base64url");
 return h+"."+p+"."+crypto.createHmac("sha256",key).update(h+"."+p).digest("base64url");
}
const now=()=>Math.floor(Date.now()/1000);
const jwt=(sub,extra={})=>sign({role:"authenticated",sub,aud:"authenticated",iat:now(),exp:now()+300,...extra});
const T=Object.fromEntries(Object.entries(U).map(([k,v])=>[k,jwt(v)]));
async function rpc(name,token,args){
 const headers={accept:"application/json","content-type":"application/json"};if(token)headers.authorization="Bearer "+token;
 const res=await fetch(base+"/rpc/"+name,{method:"POST",headers,body:JSON.stringify(args||{}),redirect:"error",signal:AbortSignal.timeout(20000)});
 const raw=await res.text();let data;try{data=JSON.parse(raw)}catch{data=raw}return{status:res.status,data};
}
const ok=(r,m)=>{assert.ok(r.status>=200&&r.status<300,m+": HTTP "+r.status+" "+JSON.stringify(r.data));return r.data};
const deny=(r,m,reason)=>{assert.equal(r.status,400,m+": expected policy denial, got "+r.status+" "+JSON.stringify(r.data));assert.equal(r.data&&r.data.message,reason,m+": reason mismatch "+JSON.stringify(r.data))};
const authFail=(r,m)=>assert.ok([401,403].includes(r.status),m+": expected auth failure, got "+r.status+" "+JSON.stringify(r.data));
(async()=>{
 // --- transport authentication
 authFail(await rpc("wf_read_overview_v1",null,{p_business:101}),"anonymous");
 authFail(await rpc("wf_read_overview_v1",sign({role:"authenticated",sub:U.owner,aud:"authenticated",exp:now()+300},"x".repeat(40)),{p_business:101}),"forged signature");
 authFail(await rpc("wf_read_overview_v1",jwt(U.owner,{exp:now()-60}),{p_business:101}),"expired token");
 const sr=await rpc("wf_read_overview_v1",jwt(U.owner,{role:"service_role"}),{p_business:101});
 assert.ok(sr.status>=400,"unknown/privileged role claim must not succeed: "+sr.status);
 // --- direct table access is not available through the API
 for(const t of["wf_employees","wf_payslips","wf_payroll_lines","wf_audit","wf_salary_structures"]){
  const res=await fetch(base+"/"+t,{headers:{authorization:"Bearer "+T.owner}});
  assert.ok([401,403,404].includes(res.status),t+" must not be readable directly: "+res.status);
 }
 // --- authority derived from DB, not token claims
 deny(await rpc("wf_read_overview_v1",T.investor,{p_business:101}),"investor","wf_denied");
 deny(await rpc("wf_read_overview_v1",T.revoked,{p_business:101}),"revoked manager","wf_denied");
 deny(await rpc("wf_read_overview_v1",T.owner2,{p_business:101}),"other tenant owner","wf_denied");
 deny(await rpc("wf_read_overview_v1",T.staff2,{p_business:101}),"other tenant staff","wf_denied");
 deny(await rpc("wf_read_overview_v1",T.operator,{p_business:101}),"platform operator without membership","wf_denied");
 const esc=await rpc("wf_read_overview_v1",jwt(U.e1,{user_role:"tenant_owner",app_metadata:{role:"tenant_owner",tenant_id:1},user_metadata:{role:"owner"}}),{p_business:101});
 assert.equal(ok(esc,"employee with forged role claims").level,"employee","claims must never elevate authority");
 assert.equal(ok(await rpc("wf_read_overview_v1",T.owner,{p_business:101}),"owner").level,"tenant_owner");
 assert.equal(ok(await rpc("wf_read_overview_v1",T.mgr,{p_business:101}),"manager").capabilities.payroll,false);
 // --- privacy: payroll and salary fail closed
 deny(await rpc("wf_payroll_preview_v1",T.mgr,{p_business:101,p_period:"2026-10-01"}),"manager payroll preview","wf_payroll_access_denied");
 deny(await rpc("wf_list_payroll_runs_v1",T.sup,{p_business:101}),"supervisor payroll runs","wf_payroll_access_denied");
 deny(await rpc("wf_payslip_register_v1",T.e1,{p_business:101,p_period:null}),"employee register","wf_payroll_access_denied");
 deny(await rpc("read_workforce_business_summary_v1",T.mgr,{p_business:101,p_period:null}),"manager integration summary","wf_summary_denied");
 const slips=ok(await rpc("wf_my_payslips_v1",T.e1,{p_business:101}),"own payslips");
 assert.ok(slips.items.length>=1);
 const reg=ok(await rpc("wf_payslip_register_v1",T.owner,{p_business:101,p_period:"2026-10-01"}),"owner register");
 const foreign=reg.items.find(x=>x.employee_no==="EMP-003").payslip_id;
 deny(await rpc("wf_get_my_payslip_v1",T.e1,{p_business:101,p_payslip:foreign}),"foreign payslip","wf_payslip_not_found");
 const own=ok(await rpc("wf_get_my_payslip_v1",T.e1,{p_business:101,p_payslip:slips.items[0].id}),"own payslip");
 assert.equal(own.payslip.payment_status,"not_tracked_in_this_module");
 const dir=ok(await rpc("wf_list_employees_v1",T.mgr,{p_business:101,p_search:null,p_status:null,p_site:null,p_limit:100,p_offset:0}),"manager directory");
 assert.ok(dir.items.every(x=>x.contact_phone==null&&x.national_id_last4==null),"manager directory carries no PII");
 const sdir=ok(await rpc("wf_list_employees_v1",T.sup,{p_business:101,p_search:null,p_status:null,p_site:null,p_limit:100,p_offset:0}),"supervisor directory");
 assert.ok(sdir.items.every(x=>x.site_id===1001),"supervisor sees only own site");
 assert.equal(ok(await rpc("wf_list_employees_v1",T.e3,{p_business:101,p_search:null,p_status:null,p_site:null,p_limit:100,p_offset:0}),"employee directory").total,1);
 const csv=ok(await rpc("wf_export_csv_v1",T.mgr,{p_business:101,p_request:"http-export-0001",p_kind:"employees",p_params:{}}),"manager export").csv;
 assert.ok(!/\+880171|1234/.test(csv),"export has no phone/NID");
 // --- idempotency and replay over HTTP, including parallel retries
 const body={p_business:101,p_request:"http-punch-batch-1",p_site:1001,p_source:"device",p_punches:[{employee_no:"EMP-002",at:"2026-11-04T09:00:00+06:00",direction:"in",ref:"http-ref-1"}]};
 const first=ok(await rpc("wf_import_punches_v1",T.mgr,body),"punch batch");
 assert.equal(first.accepted,1);
 const burst=await Promise.all(Array.from({length:10},()=>rpc("wf_import_punches_v1",T.mgr,body)));
 for(const [i,r] of burst.entries())assert.deepEqual(ok(r,"parallel replay "+i),first,"replay must return the original receipt");
 deny(await rpc("wf_import_punches_v1",T.mgr,{...body,p_punches:[{...body.p_punches[0],at:"2026-11-04T10:00:00+06:00"}]}),"changed payload same key","wf_idempotency_conflict");
 deny(await rpc("wf_import_punches_v1",T.sup,{...body,p_request:"http-punch-batch-2",p_site:1002}),"supervisor other site","wf_punch_import_denied");
 deny(await rpc("wf_import_punches_v1",T.owner2,{...body,p_request:"http-punch-batch-3"}),"cross-tenant import","wf_denied");
 // --- workflow guards visible over HTTP
 const runs=ok(await rpc("wf_list_payroll_runs_v1",T.owner,{p_business:101}),"owner runs");
 assert.equal(runs.paid,false);const frozen=runs.items.find(x=>x.status==="frozen");assert.ok(frozen,"frozen October run exists");
 deny(await rpc("wf_payroll_transition_v1",T.owner,{p_business:101,p_request:"http-void-0001",p_run:frozen.id,p_action:"void",p_note:"attempt to void frozen"}),"void frozen","wf_payroll_state_invalid");
 deny(await rpc("wf_create_payroll_draft_v1",T.bo,{p_business:101,p_request:"http-draft-0001",p_period:"2026-10-01",p_amends_run:null,p_reason:null}),"silent re-run of frozen period","wf_period_already_frozen_amend_required");
 deny(await rpc("wf_request_leave_v1",T.e1,{p_business:101,p_request:"http-leave-0001",p_employee:null,p_type_code:"SICK",p_from:"2026-10-27",p_to:"2026-10-28",p_reason:"retro leave"}),"leave into frozen month","wf_leave_affects_frozen_period");
 const liab=ok(await rpc("read_payroll_liability_preview_v1",T.owner,{p_business:101,p_period:"2026-10-01"}),"liability preview");
 assert.equal(liab.paid,false);assert.equal(liab.money_movement,false);assert.equal(liab.ledger_posted,false);
 assert.equal(ok(await rpc("wf_integrity_report_v1",T.owner,{p_business:101}),"integrity").ok,true);
 console.log("PASS A051 signed-HMAC PostgREST workforce API E2E (disposable, NOT real GoTrue)");
})().catch(e=>{console.error(e);process.exitCode=1});
