"use strict";
// Genuine local GoTrue v2.197.0 password/session JWTs over PostgREST 12.2.12.
// No signed-by-test user tokens, live account, hosted Supabase or production SQL.
const assert=require("node:assert/strict");
const AUTH=process.env.CORE10_BUILD01_AUTH_URL||"";
const REST=process.env.CORE10_BUILD01_REST_URL||"";
for(const raw of [AUTH,REST]){
 const u=new URL(raw||"http://invalid/");
 assert.equal(u.protocol,"http:");
 assert.ok(["localhost","127.0.0.1"].includes(u.hostname));
}
assert.equal(process.env.CORE10_BUILD01_DISPOSABLE_ACK,"I_CONFIRM_BUILD01_DISPOSABLE");
assert.match(process.env.PGDATABASE||"",/^core10_build01_auth_\d+$/);
const password="Synthetic-Only_Build01_2026!";
const U={
 owner:"11111111-1111-4111-8111-111111111111",
 biz:"22222222-2222-4222-8222-222222222222",
 manager:"33333333-3333-4333-8333-333333333333",
 staff:"44444444-4444-4444-8444-444444444444",
 investor:"55555555-5555-4555-8555-555555555555",
 foreign:"77777777-7777-4777-8777-777777777777"
};
const mail={owner:"owner",biz:"business-owner",manager:"manager",staff:"staff",investor:"investor",foreign:"other-owner"};
async function http(url,{token,body,method="GET"}={}){
 const r=await fetch(url,{method,headers:{accept:"application/json",
 ...(token?{authorization:"Bearer "+token}:{}),
 ...(body!==undefined?{"content-type":"application/json"}:{})},
 body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
 let data;const raw=await r.text();try{data=JSON.parse(raw)}catch{data=raw}
 return {status:r.status,data};
}
async function login(who){
 const result=await http(AUTH+"/token?grant_type=password",{method:"POST",body:{
  email:"build01-"+mail[who]+"@example.test",password}});
 assert.ok(result.status>=200&&result.status<300,who+" login failed "+result.status);
 assert.equal(result.data.user.id,U[who]);
 const payload=JSON.parse(Buffer.from(result.data.access_token.split(".")[1],"base64url").toString());
 assert.equal(payload.sub,U[who]);assert.ok(payload.session_id,"GoTrue session_id required");
 return result.data.access_token;
}
const rpc=(tok,name,args={})=>http(REST+"/rpc/"+name,{method:"POST",token:tok,body:args});
function pass(r,what){
 assert.ok(r.status>=200&&r.status<300,what+" returned "+r.status+" "+JSON.stringify(r.data));
 return r.data;
}
function deny(r,what){
 assert.ok(r.status>=400,what+" unexpectedly permitted "+r.status+" "+JSON.stringify(r.data));
}
async function check(tok,tenant,business,action){
 const ans=pass(await rpc(tok,"can_approval_action_v1",{
  p_tenant:tenant,p_business:business,p_action:action}),"approval gate "+action);
 assert.equal(typeof ans,"boolean");
 return ans;
}
const p=(subject,actions,deniedActions,until,request)=>({
 p_business:101,p_subject:subject,p_actions:actions,p_denied_actions:deniedActions,
 p_valid_until:until,p_request:request,p_expected_version:null
});
(async()=>{
 const o=await login("owner"),biz=await login("biz"),m=await login("manager"),
  s=await login("staff"),i=await login("investor"),t=await login("foreign");
 assert.equal(await check(o,1,101,"approval.decide"),true);
 assert.equal(await check(biz,1,101,"approval.decide"),true);
 assert.equal(await check(m,1,101,"approval.submit"),true);
 assert.equal(await check(m,1,101,"approval.withdraw"),true);
 assert.equal(await check(m,1,101,"approval.decide"),false);
 assert.equal(await check(m,1,101,"approval.exception"),false);
 assert.equal(await check(s,1,101,"approval.decide"),false);
 assert.equal(await check(i,1,101,"approval.decide"),false);
 assert.equal(await check(t,1,101,"approval.decide"),false);
 assert.equal(await check(o,2,101,"approval.decide"),false);
 assert.equal(await check(o,1,201,"approval.decide"),false);
 assert.equal(await check(t,2,201,"approval.decide"),true);
 assert.equal(await check(biz,1,101,"stock.post"),false);

 // Real GoTrue /user metadata cannot promote a manager to decision-maker.
 pass(await http(AUTH+"/user",{method:"PUT",token:m,body:{data:{
  role:"tenant_owner",is_owner:true,approval_actions:["approval.decide"]}}}),"metadata update");
 assert.equal(await check(m,1,101,"approval.decide"),false);

 const expiring=p(U.manager,["approval.decide"],["approval.withdraw"],
  new Date(Date.now()+2500).toISOString(),"pack01-local-gov-ttl");
 deny(await rpc(m,"build02a_set_approval_policy_v1",expiring),"manager policy mutation");
 deny(await rpc(t,"build02a_set_approval_policy_v1",expiring),"foreign policy mutation");
 const saved=pass(await rpc(o,"build02a_set_approval_policy_v1",expiring),"owner policy grant");
 assert.equal(saved.request_key,expiring.p_request);assert.ok(saved.event_id);
 assert.deepEqual(pass(await rpc(o,"build02a_set_approval_policy_v1",expiring),
  "owner idempotent replay"),saved);
 assert.equal(await check(m,1,101,"approval.decide"),true);
 assert.equal(await check(m,1,101,"approval.withdraw"),false);
 await new Promise(resolve=>setTimeout(resolve,3000));
 assert.equal(await check(m,1,101,"approval.decide"),false,
  "expired approval policy must drop decision without logout");
 assert.equal(await check(m,1,101,"approval.withdraw"),true,
  "expiry reverts to ordinary manager action baseline");
 const long=p(U.manager,["approval.decide"],["approval.withdraw"],
   new Date(Date.now()+300000).toISOString(),"pack01-local-gov-renewal");
 pass(await rpc(o,"build02a_set_approval_policy_v1",long),"owner renewed delegation");
 assert.equal(await check(m,1,101,"approval.decide"),true);
 // Business owner may update an ACTIVE manager's policy; never reactivate
 // membership by writing a new approval policy after revocation.
 const businessPolicy=p(U.manager,["approval.decide"],[],
  new Date(Date.now()+300000).toISOString(),"pack01-local-gov-biz-write");
 pass(await rpc(biz,"build02a_set_approval_policy_v1",businessPolicy),
  "business owner allowed policy write to active manager");
 const revoke={
  p_business:101,p_subject:U.manager,p_command:"business_member.revoke",
  p_role:null,p_site:null,p_actions:[],p_denied_actions:[],
  p_valid_until:null,p_request:"pack01-local-gov-revoke"
 };
 pass(await rpc(o,"build01_set_access_v1",revoke),"owner canonical membership revoke");
 assert.equal(await check(m,1,101,"approval.decide"),false,
  "revoke must override live GoTrue token's future-dated delegated approval");
 assert.equal(await check(m,1,101,"approval.submit"),false,
  "revoke must remove baseline manager submit");
 pass(await http(AUTH+"/user",{token:m}),"GoTrue signed user remains logged in after DB revoke");
 deny(await rpc(m,"build02a_set_approval_policy_v1",long),"revoked member policy mutation");
 const afterRevoke=p(U.manager,["approval.decide"],[],
  new Date(Date.now()+300000).toISOString(),"pack01-local-gov-biz-denied");
 const blocked=await rpc(biz,"build02a_set_approval_policy_v1",afterRevoke);
 deny(blocked,"revoked member must not receive a new delegated policy");
 assert.equal(blocked.data?.message,"BUILD02A_SUBJECT_NOT_ELIGIBLE");
 assert.equal(await check(m,1,101,"approval.decide"),false,
  "policy write cannot restore revoked membership");
 deny(await rpc(null,"can_approval_action_v1",{
  p_tenant:1,p_business:101,p_action:"approval.decide"}),"anonymous approval resolver");
 pass(await http(AUTH+"/logout?scope=local",{token:m,method:"POST"}),"GoTrue logout");
 // Read-only boolean permission resolver deliberately fails closed (200 false)
 // when actor_uid() resolves to NULL after local session logout.
 const afterLogout=await rpc(m,"can_approval_action_v1",{
  p_tenant:1,p_business:101,p_action:"approval.submit"});
 if(afterLogout.status>=200&&afterLogout.status<300){
  assert.equal(afterLogout.data,false,"logged-out JWT must never allow approval");
 }else deny(afterLogout,"logged-out approval resolver rejected");
 // The protected Build01 context must refuse the old signed token entirely.
 deny(await rpc(m,"build01_context_v1"),"logged-out JWT reused for protected context");
 console.log("PASS PACK01 ACTUAL LOCAL GOTRUE APPROVAL: signed roles, explicit DENY, TTL, immediate membership revoke, cross-tenant, logout; disposable only");
})().catch(e=>{console.error(e);process.exitCode=1});
