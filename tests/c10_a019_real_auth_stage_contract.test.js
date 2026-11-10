"use strict";
/* Contract-only test: mocks GoTrue and PostgREST responses. It is NOT live
 * signed Supabase Auth E2E; the real harness is deliberately stage-gated. */
const assert=require("node:assert/strict");
const {parseConfig,run,expectRows,PRODUCTION_REF,AGREEMENT,SEED,ROLES}=
  require("../internal/core10-a019-real-auth-stage.js");
function user(role,businessIds,siteIds){
  return{email:role+"@example.invalid",password:"offline-only-strong-password",
    businessIds,siteIds};
}
const users={
 tenantOwnerA:user("a",[101,102],[1001,1002]),
 tenantOwnerB:user("b",[201],[2001]),
 siteStaffA:user("c",[101],[1001]),
 investorA:user("d",[],[]),
 revokedA:user("e",[],[]),
 platformOperator:user("f",[],[])
};
const ref="stagingabc1234567890";
const original={
 C10_STAGING_READONLY_APPROVAL:AGREEMENT,
 C10_STAGING_SEED_PROOF:SEED,
 C10_STAGING_URL:"https://"+ref+".supabase.co",
 C10_STAGING_PROJECT_REF:ref,
 C10_STAGING_ANON_KEY:"sb_publishable_fixture_offline_only",
 C10_STAGING_TEST_USERS_JSON:JSON.stringify(users)
};
function clone(x){return JSON.parse(JSON.stringify(x))}
function shouldBlock(label,alter,pattern) {
 const x=clone(original);alter(x);
 assert.throws(()=>parseConfig(x),pattern,label);
}
shouldBlock("no approval",e=>delete e.C10_STAGING_READONLY_APPROVAL,/OWNER_STAGING_AUTH_APPROVAL_REQUIRED/);
shouldBlock("no seed proof",e=>e.C10_STAGING_SEED_PROOF="not-yet",/DISPOSABLE_STAGE_SEED_PROOF_REQUIRED/);
shouldBlock("live production ref",e=>{e.C10_STAGING_URL="https://"+PRODUCTION_REF+".supabase.co";e.C10_STAGING_PROJECT_REF=PRODUCTION_REF},/PRODUCTION_OR_REF_MISMATCH_BLOCKED/);
shouldBlock("wrong stage ref",e=>e.C10_STAGING_PROJECT_REF="unrelatedref1234567890",/PRODUCTION_OR_REF_MISMATCH_BLOCKED/);
shouldBlock("http blocked",e=>e.C10_STAGING_URL="http://"+ref+".supabase.co",/INVALID_STAGING_URL/);
shouldBlock("URL path blocked",e=>e.C10_STAGING_URL+="\/rest/v1",/INVALID_STAGING_URL/);
shouldBlock("non Supabase domain",e=>e.C10_STAGING_URL="https://"+ref+".example.org",/INVALID_STAGING_URL/);
shouldBlock("service key forbidden",e=>e.C10_STAGING_ANON_KEY="sb_secret_test",/ANON_API_KEY_REQUIRED/);
shouldBlock("service role JWT forbidden",e=>{
  const h=Buffer.from("{}").toString("base64url");
  const p=Buffer.from(JSON.stringify({role:"service_role"})).toString("base64url");
  e.C10_STAGING_ANON_KEY=h+"."+p+".fixture";
},/SERVICE_ROLE_OR_NON_ANON_KEY_BLOCKED/);
shouldBlock("missing principal",e=>{const u=JSON.parse(e.C10_STAGING_TEST_USERS_JSON);delete u.revokedA;e.C10_STAGING_TEST_USERS_JSON=JSON.stringify(u)},/INVALID_STAGING_USERS/);
shouldBlock("duplicate login",e=>{const u=JSON.parse(e.C10_STAGING_TEST_USERS_JSON);u.revokedA.email=u.investorA.email;e.C10_STAGING_TEST_USERS_JSON=JSON.stringify(u)},/DUPLICATE_STAGING_USER/);
shouldBlock("cross-tenant fixture overlap",e=>{const u=JSON.parse(e.C10_STAGING_TEST_USERS_JSON);u.tenantOwnerB.businessIds=[101];e.C10_STAGING_TEST_USERS_JSON=JSON.stringify(u)},/TWO_TENANT_ISOLATION_FIXTURE_REQUIRED/);
shouldBlock("staff foreign tenant",e=>{const u=JSON.parse(e.C10_STAGING_TEST_USERS_JSON);u.siteStaffA.businessIds=[201];e.C10_STAGING_TEST_USERS_JSON=JSON.stringify(u)},/STAFF_SCOPE_FIXTURE_REQUIRED/);
shouldBlock("revoked cannot have scope",e=>{const u=JSON.parse(e.C10_STAGING_TEST_USERS_JSON);u.revokedA.businessIds=[101];e.C10_STAGING_TEST_USERS_JSON=JSON.stringify(u)},/NON_OPERATIONAL_ROLE_VISIBILITY_MUST_BE_ZERO/);
const config=parseConfig(original);
assert.equal(config.projectRef,ref);
assert.equal(ROLES.length,6);
const ids=Object.fromEntries(ROLES.map((role,i)=>[
  role,"00000000-0000-4000-8000-"+String(i+1).padStart(12,"0")]));
function testJwt(role,overrides={}) {
  // Synthetically parseable ONLY. Staging GoTrue must cryptographically verify
  // real issued tokens; these are never transmitted beyond the mocked test.
  const head={alg:"HS256",typ:"JWT"};
  const claims={sub:ids[role],role:"authenticated",aud:"authenticated",
    exp:Math.floor(Date.now()/1000)+600,...overrides};
  return [Buffer.from(JSON.stringify(head)).toString("base64url"),
    Buffer.from(JSON.stringify(claims)).toString("base64url"),"synthetic_CI_signature"].join(".");
}
const tokenByRole=Object.fromEntries(ROLES.map(role=>[role,testJwt(role)]));
const tokens=Object.fromEntries(ROLES.map(role=>[tokenByRole[role],role]));
function reply(code,body){return{status:code,json:async()=>body}}
let signIns=0,readCount=0,unapprovedWrites=0;
async function fakeFetch(url,options){
 const uri=new URL(url),method=options.method||"GET",headers=options.headers||{};
 assert.equal(uri.origin,config.url);
 assert.equal(options.redirect,"error","Bearer/anon credentials must never be forwarded through redirects");
 assert.ok(options.signal instanceof AbortSignal,"A hard request deadline is mandatory");
 if(uri.pathname==="/auth/v1/token"){
  assert.equal(method,"POST");signIns++;
  const body=JSON.parse(options.body);
  const role=ROLES.find(r=>users[r].email===body.email&&users[r].password===body.password);
  return role?reply(200,{access_token:tokenByRole[role]}):reply(401,{});
 }
 const role=tokens[headers.authorization?.replace(/^Bearer /,"")];
 if(uri.pathname==="/auth/v1/user"){
  assert.equal(method,"GET");
  return role?reply(200,{id:ids[role]}):reply(401,{});
 }
 if(uri.pathname.startsWith("/rest/v1/")){
  if(method!=="GET"){unapprovedWrites++;throw Error("Unexpected DB write");}
  if(headers["Accept-Profile"]!=="c10_demo")throw Error("Missing isolated schema contract");
  if(!role)return reply(401,{message:"not authenticated"});
  readCount++;
  const table=uri.pathname.split("/").pop();
  if(!["businesses","sites"].includes(table))throw Error("Unknown query");
  let values=table==="businesses"?users[role].businessIds:users[role].siteIds;
  const idFilter=uri.searchParams.get("id");
  if(idFilter&&idFilter.startsWith("eq."))values=values.filter(x=>x===Number(idFilter.slice(3)));
  return reply(200,values.map(id=>({id})));
 }
 throw Error("Unexpected network call");
}
(async()=>{
 const result=await run(config,fakeFetch);
 assert.equal(result.checked,6);
 assert.equal(result.scopes,12);
 assert.equal(result.crossTenantDenials,2);
 assert.equal(result.releaseCertified,false);
 assert.equal(signIns,6);
 assert.ok(readCount>=14);
 assert.equal(unapprovedWrites,0);
 assert.throws(()=>expectRows({status:200,body:[{id:101},{id:201}]},[101],"injected"),/SIGNED_RLS_VISIBILITY_MISMATCH/);
 // Effective role policy must fail closed even when URL was correctly stage-guarded.
 const leaky=async(url,options)=>{
   const r=await fakeFetch(url,options);
   if(url.includes("/rest/v1/businesses")&&options.headers?.authorization==="Bearer "+tokenByRole.tenantOwnerA)
     return reply(200,[{id:101},{id:102},{id:201}]);
   return r;
 };
 await assert.rejects(run(config,leaky),/SIGNED_RLS_VISIBILITY_MISMATCH/);
 shouldBlock("malformed publishable key",e=>e.C10_STAGING_ANON_KEY="sb_publishable_bad!",/MALFORMED_PUBLISHABLE_KEY_BLOCKED/);
 shouldBlock("truncated publishable key",e=>e.C10_STAGING_ANON_KEY="sb_publishable_x",/MALFORMED_PUBLISHABLE_KEY_BLOCKED/);
 shouldBlock("service role named key",e=>e.C10_STAGING_ANON_KEY="service_role_mock",/ANON_API_KEY_REQUIRED/);
 const {tokenClaims}=require("../internal/core10-a019-real-auth-stage.js");
 assert.deepEqual(tokenClaims(tokenByRole.tenantOwnerA),{sub:ids.tenantOwnerA});
 for(const claims of [
   {aud:"anonymous"},{role:"anon"},{exp:Math.floor(Date.now()/1000)-30},
   {sub:"not-a-uuid"}
 ])assert.throws(()=>tokenClaims(testJwt("tenantOwnerA",claims)),/GOTRUE_ACCESS_TOKEN_CLAIMS_INVALID/);
 assert.throws(()=>tokenClaims("not_a_jwt"),/GOTRUE_ACCESS_TOKEN_CLAIMS_INVALID/);
 const badAuthToken=async(url,options)=>{
   const response=await fakeFetch(url,options);
   if(url.includes("/auth/v1/token"))
     return reply(200,{access_token:testJwt("tenantOwnerA",{role:"anon"})});
   return response;
 };
 await assert.rejects(run(config,badAuthToken),/GOTRUE_ACCESS_TOKEN_CLAIMS_INVALID/);
 const wrongSubject=async(url,options)=>{
   const response=await fakeFetch(url,options);
   if(url.includes("/auth/v1/user"))
     return reply(200,{id:"ffffffff-ffff-4fff-8fff-ffffffffffff"});
   return response;
 };
 await assert.rejects(run(config,wrongSubject),/GOTRUE_SIGNED_USER_VERIFICATION_FAILED/);
 const redirected=async(url,options)=>{
   assert.equal(options.redirect,"error");
   if(url.includes("/auth/v1/token"))return reply(302,{location:"https://untrusted.invalid"});
   return fakeFetch(url,options);
 };
 await assert.rejects(run(config,redirected),/STAGING_NETWORK_OR_REDIRECT_DENIED/);
 const networkFailure=async()=>{throw new Error("should never leak staging credentials");};
 await assert.rejects(run(config,networkFailure),/STAGING_NETWORK_OR_REDIRECT_DENIED/);
 console.log("PASS C10-A019 stage GoTrue contract MOCK: approval/project/anon key guards; six principals; two-tenant cross reads; revoked+investor+operator; fake bearer denied; no DB writes. NOT real Supabase Auth E2E.");
})().catch(e=>{console.error("FAIL C10-A019 MOCK "+e.message);process.exitCode=1});
