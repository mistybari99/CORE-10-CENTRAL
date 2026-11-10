"use strict";
/*
 * CORE-10-CENTRAL | C10-A019 | Supabase GoTrue staging READ-ONLY auth E2E.
 *
 * THIS IS NOT A PRODUCTION OR AUTOMATICALLY ENABLED TEST.
 * It must NEVER use service_role or production credentials. Stage deployment,
 * sample membership grants and test identities are explicitly preconditions.
 * Real GoTrue password grants (not a CI-generated HMAC) plus PostgREST RLS.
 * HTTP writes limited to GoTrue session sign-in, never database DML/RPC.
 */
const assert = require("node:assert/strict");
const PRODUCTION_REF = "kbuhnpqooycqbzrfejcs"; // Public project reference only, NOT a secret
const AGREEMENT = "CORE10_STAGING_AUTH_READ_ONLY_APPROVED";
const SEED = "DISPOSABLE_C10_DEMO_STAGING_SEED_VERIFIED";
const ROLES = ["tenantOwnerA","tenantOwnerB","siteStaffA","investorA","revokedA","platformOperator"];
function rejected(code) { const error=new Error(code); error.code=code; throw error; }
function integerArray(v) {
  return Array.isArray(v)&&v.every(x=>Number.isSafeInteger(x)&&x>0)&&
    new Set(v).size===v.length;
}
function parseConfig(env) {
  if(env.C10_STAGING_READONLY_APPROVAL!==AGREEMENT)rejected("OWNER_STAGING_AUTH_APPROVAL_REQUIRED");
  if(env.C10_STAGING_SEED_PROOF!==SEED)rejected("DISPOSABLE_STAGE_SEED_PROOF_REQUIRED");
  let url;
  try {url=new URL(env.C10_STAGING_URL||"");} catch {rejected("INVALID_STAGING_URL");}
  if(url.protocol!=="https:"||url.username||url.password||url.port||
    (url.pathname!=="/"&&url.pathname!=="")||url.search||url.hash||
    !/^[a-z0-9]{15,35}\.supabase\.co$/.test(url.hostname))rejected("INVALID_STAGING_URL");
  const ref=url.hostname.split(".")[0];
  if(ref===PRODUCTION_REF||env.C10_STAGING_PROJECT_REF!==ref)rejected("PRODUCTION_OR_REF_MISMATCH_BLOCKED");
  const key=env.C10_STAGING_ANON_KEY||"";
  if(!key||key.startsWith("sb_secret_")||key.startsWith("sb_service_"))rejected("ANON_API_KEY_REQUIRED");
  if(key.split(".").length===3) {
    try {
      const jwt=JSON.parse(Buffer.from(key.split(".")[1],"base64url").toString("utf8"));
      if(jwt.role!=="anon")rejected("SERVICE_ROLE_OR_NON_ANON_KEY_BLOCKED");
    } catch(e) {if(e.code)throw e; rejected("INVALID_ANON_JWT_KEY");}
  } else if(!key.startsWith("sb_publishable_"))rejected("ANON_API_KEY_REQUIRED");
  let users;
  try {users=JSON.parse(env.C10_STAGING_TEST_USERS_JSON||"");} catch {rejected("INVALID_STAGING_USERS");}
  if(!users||typeof users!=="object"||Array.isArray(users)||Object.keys(users).sort().join(",")!==[...ROLES].sort().join(","))rejected("INVALID_STAGING_USERS");
  const emails=new Set();
  for(const role of ROLES) {
    const u=users[role];
    if(!u||typeof u!=="object"||Array.isArray(u)||!Object.keys(u).sort().every(x=>["email","password","businessIds","siteIds"].includes(x)))rejected("INVALID_STAGING_USER:"+role);
    if(typeof u.email!=="string"||!u.email.includes("@")||typeof u.password!=="string"||u.password.length<8||!integerArray(u.businessIds)||!integerArray(u.siteIds))rejected("INVALID_STAGING_USER:"+role);
    if(emails.has(u.email.toLowerCase()))rejected("DUPLICATE_STAGING_USER");
    emails.add(u.email.toLowerCase());
  }
  const A=users.tenantOwnerA.businessIds,B=users.tenantOwnerB.businessIds;
  if(!A.length||!B.length||A.some(x=>B.includes(x)))rejected("TWO_TENANT_ISOLATION_FIXTURE_REQUIRED");
  if(!users.siteStaffA.businessIds.length||users.siteStaffA.businessIds.some(x=>!A.includes(x))||
    !users.siteStaffA.siteIds.length)rejected("STAFF_SCOPE_FIXTURE_REQUIRED");
  for(const role of ["investorA","revokedA","platformOperator"])
    if(users[role].businessIds.length||users[role].siteIds.length)rejected("NON_OPERATIONAL_ROLE_VISIBILITY_MUST_BE_ZERO:"+role);
  return Object.freeze({url:url.origin,projectRef:ref,key,users});
}
async function send(url,options,http=fetch) {
  const response=await http(url,{...options,signal:AbortSignal.timeout(15000)});
  let body;try{body=await response.json()}catch{body=null}
  return{status:response.status,body};
}
function expectRows(result,expected,label) {
  if(result.status!==200||!Array.isArray(result.body))rejected("STAGING_AUTH_DATA_API_NOT_READY:"+label);
  const ids=result.body.map(x=>x.id);
  if(ids.some(x=>!Number.isSafeInteger(x))||ids.length!==new Set(ids).size||
     ids.slice().sort((a,b)=>a-b).join(",")!==expected.slice().sort((a,b)=>a-b).join(","))
    rejected("SIGNED_RLS_VISIBILITY_MISMATCH:"+label);
}
async function auth(config,user,http) {
  const h={"apikey":config.key,"content-type":"application/json"};
  const grant=await send(config.url+"/auth/v1/token?grant_type=password",{
    method:"POST",headers:h,body:JSON.stringify({email:user.email,password:user.password})
  },http);
  if(grant.status!==200||typeof grant.body?.access_token!=="string"||
     !grant.body.access_token)rejected("GOTRUE_LOGIN_FAILED");
  const token=grant.body.access_token;
  const identity=await send(config.url+"/auth/v1/user",{
    method:"GET",headers:{"apikey":config.key,authorization:"Bearer "+token}
  },http);
  if(identity.status!==200||typeof identity.body?.id!=="string"||
     !identity.body.id)rejected("GOTRUE_SIGNED_USER_VERIFICATION_FAILED");
  return{token,id:identity.body.id};
}
async function read(config,token,path,http) {
  return send(config.url+"/rest/v1/"+path,{
    method:"GET",headers:{"apikey":config.key,"authorization":"Bearer "+token,
      "Accept-Profile":"c10_demo","Accept":"application/json"}
  },http);
}
function corruptSignature(token) {
  // Changing the last base64url character may change only unused padding bits
  // and leave the decoded HMAC untouched. Flip a FIRST signature character.
  const pieces=String(token).split(".");
  if(pieces.length===3&&pieces[2].length>0) {
    pieces[2]=(pieces[2][0]==="A"?"B":"A")+pieces[2].slice(1);
    return pieces.join(".");
  }
  return "invalid-non-jwt:"+String(token);
}
async function run(config,http=fetch) {
  if(!config||!config.users||!config.key||!config.url)rejected("VALIDATED_STAGING_CONFIG_REQUIRED");
  const ids=new Set(),sessions={};
  for(const role of ROLES) {
    const identity=await auth(config,config.users[role],http);
    if(ids.has(identity.id))rejected("SAME_AUTH_ID_FOR_DISTINCT_TEST_ROLES");
    ids.add(identity.id);sessions[role]=identity.token;
  }
  for(const role of ROLES){
    const u=config.users[role];
    expectRows(await read(config,sessions[role],"businesses?select=id&order=id.asc",http),
      u.businessIds,"businesses:"+role);
    expectRows(await read(config,sessions[role],"sites?select=id&order=id.asc",http),
      u.siteIds,"sites:"+role);
  }
  // Explicit cross-tenant access, rather than trusting only default select.
  const b=config.users.tenantOwnerB.businessIds[0];
  expectRows(await read(config,sessions.tenantOwnerA,
    "businesses?select=id&id=eq."+b,http),[],"A_forbidden_B");
  const a=config.users.tenantOwnerA.businessIds[0];
  expectRows(await read(config,sessions.tenantOwnerB,
    "businesses?select=id&id=eq."+a,http),[],"B_forbidden_A");
  // Bad bearer must be rejected by GoTrue/PostgREST, never accepted as anon.
  const invalid=await read(config,corruptSignature(sessions.tenantOwnerA),
    "businesses?select=id",http);
  if(invalid.status!==401&&invalid.status!==403)rejected("UNVERIFIED_TOKEN_ACCEPTED");
  const anon=await read(config,"","businesses?select=id",http);
  if(!([200,401,403].includes(anon.status) &&
    (anon.status!==200||Array.isArray(anon.body)&&anon.body.length===0)))
    rejected("ANONYMOUS_OPERATIONAL_DATA_EXPOSED");
  return Object.freeze({kind:"REAL_SUPABASE_GOTRUE_AND_RLS_STAGING_READ_ONLY",
    checked:ROLES.length,scopes:ROLES.length*2,crossTenantDenials:2,
    revokedAndInvestorDenied:true,forgedDenied:true,anonDenied:true,
    releaseCertified:false});
}
if(require.main===module) {
  try {const config=parseConfig(process.env);
    run(config).then(x=>console.log("PASS "+JSON.stringify(x)))
      .catch(e=>{console.error("FAIL C10-A019 "+(e.code||"STAGING_TEST_FAILED"));process.exitCode=1});
  }catch(e){console.error("BLOCKED C10-A019 "+(e.code||"STAGING_CONFIG_INVALID"));process.exitCode=1}
}
module.exports={parseConfig,run,expectRows,corruptSignature,PRODUCTION_REF,AGREEMENT,SEED,ROLES};
