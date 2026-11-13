// C10-A053/A054: signed HMAC JWT -> PostgREST -> c10_demo RPC E2E. Disposable PostgreSQL ONLY.
// NOT a Supabase-issued GoTrue token and NEVER a production release test. Run AFTER tests/c10_a054_policy_e2e.sql state (business 102).
"use strict";
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const secret=process.env.CORE10_CI_JWT_SECRET;
const base=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
if(!secret||secret.length<32)throw Error("DISPOSABLE_JWT_SECRET_REQUIRED");
const U={owner:"11111111-1111-4111-8111-111111111111",boB:"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",mgrB:"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
 branch:"dddddddd-dddd-4ddd-8ddd-dddddddddddd",investor:"55555555-5555-4555-8555-555555555555",revoked:"66666666-6666-4666-8666-666666666666",
 ownerB:"77777777-7777-4777-8777-777777777777",operator:"99999999-9999-4999-8999-999999999999"};
function sign(payload,key=secret){
 const h=Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url"),p=Buffer.from(JSON.stringify(payload)).toString("base64url");
 return h+"."+p+"."+crypto.createHmac("sha256",key).update(h+"."+p).digest("base64url");
}
const now=()=>Math.floor(Date.now()/1000);
const jwt=(sub,extra={})=>sign({role:"authenticated",sub,aud:"authenticated",iat:now(),exp:now()+300,...extra});
const T=Object.fromEntries(Object.entries(U).map(([k,v])=>[k,jwt(v)]));
const run=crypto.randomBytes(4).toString("hex");let n=0;const rk=(p)=>p+"-"+run+"-"+(++n);
async function rpc(name,token,args){
 const headers={accept:"application/json","content-type":"application/json"};if(token)headers.authorization="Bearer "+token;
 for(let attempt=0;;attempt++){
  const res=await fetch(base+"/rpc/"+name,{method:"POST",headers,body:JSON.stringify(args||{}),redirect:"error",signal:AbortSignal.timeout(20000)});
  const raw=await res.text();let data;try{data=JSON.parse(raw)}catch{data=raw}
  if(res.status===503&&attempt<40){await new Promise(r=>setTimeout(r,500));continue}
  return{status:res.status,data};
 }
}
const ok=(r,m)=>{assert.ok(r.status>=200&&r.status<300,m+": HTTP "+r.status+" "+JSON.stringify(r.data));return r.data};
const deny=(r,m,reason)=>{assert.equal(r.status,400,m+": expected policy denial, got "+r.status+" "+JSON.stringify(r.data));assert.equal(r.data&&r.data.message,reason,m+": reason mismatch "+JSON.stringify(r.data))};
const authFail=(r,m)=>assert.ok([401,403].includes(r.status),m+": expected auth failure, got "+r.status+" "+JSON.stringify(r.data));
(async()=>{
 // transport authentication
 authFail(await rpc("a054_liability_report_v1",null,{p_business:102,p_period:null}),"anonymous");
 authFail(await rpc("a054_liability_report_v1",sign({role:"authenticated",sub:U.boB,aud:"authenticated",exp:now()+300},"x".repeat(40)),{p_business:102,p_period:null}),"forged signature");
 authFail(await rpc("a054_liability_report_v1",jwt(U.boB,{exp:now()-60}),{p_business:102,p_period:null}),"expired token");
 assert.ok((await rpc("a054_liability_report_v1",jwt(U.boB,{role:"service_role"}),{p_business:102,p_period:null})).status>=400,"unknown role claim must not succeed");
 for(const t of["a054_delegations","a054_payment_records","a054_policy_versions","a054_legal_holds","a053_persona_registry"]){
  const res=await fetch(base+"/"+t,{headers:{authorization:"Bearer "+T.owner,"accept-profile":"c10_demo"}});
  assert.ok(res.status>=400,"direct table "+t+" must not be exposed: "+res.status);
 }
 // internal helpers are not callable
 assert.ok((await rpc("a054i_deleg",T.boB,{p_business:102,p_role:"hr",p_site:null,p_period:null,p_mode:"any"})).status>=400,"helper not exposed");
 assert.ok((await rpc("a054i_patch",T.owner,{p_sig:"x",p_marker:"x",p_from:"x",p_to:"y"})).status>=400,"patch helper not exposed");
 // claims never grant authority: a staff token stuffed with owner claims is still staff
 deny(await rpc("a054_liability_report_v1",jwt(U.branch,{app_metadata:{role:"tenant_owner"},user_role:"owner",business_role:"business_owner"}),{p_business:102,p_period:"2026-10-01"}),"claim stuffing","a054_liability_denied");
 // liability: owners yes, everybody else no
 const rep=ok(await rpc("a054_liability_report_v1",T.boB,{p_business:102,p_period:"2026-10-01"}),"owner liability");
 assert.equal(rep.payment_executed,false);assert.equal(rep.paid,false);assert.equal(rep.money_movement,false);assert.equal(rep.ledger_posted,false);
 assert.ok(rep.totals&&"approved_unpaid_amount" in rep.totals&&"paid_recorded_amount" in rep.totals&&"total_outstanding" in rep.totals,"approved-unpaid and paid reported separately");
 deny(await rpc("a054_liability_report_v1",T.branch,{p_business:102,p_period:null}),"staff","a054_liability_denied");
 for(const [who,why] of [["ownerB","tenant B"],["investor","investor"],["revoked","revoked"],["operator","operator"]])
  deny(await rpc("a054_liability_report_v1",T[who],{p_business:102,p_period:null}),why,"wf_denied");
 // portfolio adapter over HTTP
 const pf=ok(await rpc("a053_read_portfolio_workforce_v1",T.owner,{p_period:"2026-10-01"}),"portfolio owner");
 assert.equal(pf.state,"CONNECTED");assert.equal(pf.paid,false);assert.ok(pf.businesses.every(b=>b.tenant_id===1),"owner sees only own tenant");
 const mg=ok(await rpc("a053_read_portfolio_workforce_v1",T.mgrB,{p_period:"2026-10-01"}),"portfolio manager");
 assert.ok(mg.businesses.every(b=>b.state==="OWNER_ONLY"&&b.workforce===null&&b.liability===null),"manager gets no figures");
 assert.ok(!/60426|headcount_by_site/.test(JSON.stringify(mg)),"no salary leak to manager");
 const tb=ok(await rpc("a053_read_portfolio_workforce_v1",T.ownerB,{p_period:"2026-10-01"}),"portfolio tenant B");
 assert.deepEqual(tb.businesses.map(b=>b.business_id),[201],"tenant B sees only its business");
 deny(await rpc("a053_read_portfolio_workforce_v1",T.owner,{p_period:"2026-10-15"}),"mid-month period","a053_invalid_period");
 // policy validation over HTTP (multiplier, not percent)
 deny(await rpc("a054_save_policy_v1",T.boB,{p_business:102,p_request:rk("pol"),p_kind:"overtime",p_subject:"DEFAULT",p_effective_from:"2027-01-01",p_params:{mode:"on",weekday_multiplier:0.01,offday_multiplier:2},p_reason:"percent confusion",p_legal_ref:null}),"0.01x","a054_multiplier_below_base_rate");
 deny(await rpc("a054_save_policy_v1",T.boB,{p_business:102,p_request:rk("pol"),p_kind:"overtime",p_subject:"DEFAULT",p_effective_from:"2027-01-01",p_params:{mode:"off"},p_reason:"OT off",p_legal_ref:"LEGAL-REF-123"}),"OT off by business owner","a054_legal_gate_tenant_owner_required");
 deny(await rpc("a054_save_policy_v1",T.mgrB,{p_business:102,p_request:rk("pol"),p_kind:"overtime",p_subject:"DEFAULT",p_effective_from:"2027-01-01",p_params:{mode:"on",weekday_multiplier:1.5,offday_multiplier:2},p_reason:"manager",p_legal_ref:null}),"manager policy","a054_owner_required");
 const sv=ok(await rpc("a054_save_policy_v1",T.boB,{p_business:102,p_request:rk("pol"),p_kind:"overtime",p_subject:"DEFAULT",p_effective_from:"2027-02-01",p_params:{mode:"on",weekday_multiplier:1.5,offday_multiplier:2},p_reason:"future OT version",p_legal_ref:null}),"future OT version");
 assert.equal(sv.state,"scheduled");
 // delegation lifecycle over HTTP: grant -> delegate acts -> revoke -> immediately denied
 const gk=rk("dg"),g=ok(await rpc("a054_grant_delegation_v1",T.boB,{p_business:102,p_request:gk,p_delegate:U.mgrB,p_role:"payroll_preparer",p_effect:"allow",p_site:null,p_period_from:"2026-08-01",p_period_to:"2026-08-01",p_expires_at:null,p_reason:"August preparer"}),"grant");
 assert.deepEqual(ok(await rpc("a054_grant_delegation_v1",T.boB,{p_business:102,p_request:gk,p_delegate:U.mgrB,p_role:"payroll_preparer",p_effect:"allow",p_site:null,p_period_from:"2026-08-01",p_period_to:"2026-08-01",p_expires_at:null,p_reason:"August preparer"}),"replay"),g);
 deny(await rpc("a054_grant_delegation_v1",T.mgrB,{p_business:102,p_request:rk("dg"),p_delegate:U.boB,p_role:"hr",p_effect:"allow",p_site:null,p_period_from:null,p_period_to:null,p_expires_at:null,p_reason:"manager tries"}),"manager grants","a054_owner_required");
 assert.equal(ok(await rpc("wf_payroll_preview_v1",T.mgrB,{p_business:102,p_period:"2026-08-01"}),"delegate previews").paid,false);
 deny(await rpc("wf_payroll_preview_v1",T.mgrB,{p_business:102,p_period:"2026-07-01"}),"other month","a054_delegation_denied");
 ok(await rpc("a054_revoke_delegation_v1",T.boB,{p_business:102,p_request:rk("rv"),p_delegation:g.delegation_id,p_expected_version:1,p_note:"revoked over HTTP"}),"revoke");
 deny(await rpc("wf_payroll_preview_v1",T.mgrB,{p_business:102,p_period:"2026-08-01"}),"after revoke","a054_delegation_denied");
 // payments are RECORDS only; over-recording is refused; staff cannot record
 deny(await rpc("a054_record_external_payment_v1",T.branch,{p_business:102,p_request:rk("pay"),p_period:"2026-10-01",p_employee:1,p_amount:1,p_method:"cash",p_reference:"VCH-HTTP-1",p_paid_on:"2026-11-01",p_note:null}),"staff record","a054_delegation_denied");
 deny(await rpc("a054_record_external_payment_v1",T.boB,{p_business:102,p_request:rk("pay"),p_period:"2026-10-01",p_employee:1,p_amount:99999999,p_method:"cash",p_reference:"VCH-HTTP-2",p_paid_on:"2026-11-01",p_note:null}),"over-record","a054_payment_exceeds_outstanding");
 const csv=ok(await rpc("a054_export_liability_csv_v1",T.boB,{p_business:102,p_request:rk("csv"),p_period:"2026-10-01"}),"csv");
 assert.ok(!/Bela|Babul/.test(csv.csv),"csv has no names");assert.equal(csv.payment_executed,false);
 deny(await rpc("a054_export_liability_csv_v1",T.branch,{p_business:102,p_request:rk("csv"),p_period:"2026-10-01"}),"staff csv","a054_liability_denied");
 // staff privacy: own leave balance only
 ok(await rpc("a054_leave_balance_v1",T.branch,{p_business:102,p_employee:null,p_year:2026}),"own balance");
 console.log("A053_A054_REST_E2E_PASS (signed HMAC, NOT GoTrue)");
})().catch(e=>{console.error(e);process.exit(1)});
