"use strict";
/* C10-A019: REAL Supabase Auth staging-only READ / RLS negative probe.
 * Manual GitHub Actions workflow only. No service_role, admin API, SQL or data writes.
 * Real E2E verdict is impossible until a separate disposable staging Supabase
 * project and four explicitly staged Auth users + grants are configured.
 */
const PRODUCTION_REF="kbuhnpqooycqbzrfejcs";
const CONFIRM="I_CONFIRM_DISPOSABLE_STAGING";
const REF=/^[a-z0-9]{20}$/;
const POS=/^[1-9][0-9]*$/;
function fail(code){throw new Error(code)}
function config(env){
  const ref=env.C10_STAGE_REF,confirm=env.C10_STAGE_CONFIRM;
  if(confirm!==CONFIRM||!REF.test(ref||"")||ref===PRODUCTION_REF)
    fail("DISPOSABLE_STAGING_REF_AND_APPROVAL_REQUIRED");
  const url="https://"+ref+".supabase.co";
  if(env.C10_STAGE_URL && env.C10_STAGE_URL!==url)fail("STAGING_HOST_MISMATCH");
  const key=env.C10_STAGE_ANON_KEY||"";
  if(!key||key.startsWith("sb_secret_")||key.startsWith("sb_service_")||
     /service[_-]?role/i.test(key))
    fail("PUBLISHABLE_OR_ANON_KEY_REQUIRED");
  // Do not silently accept arbitrary strings as an anon API key.
  // Supabase publishes sb_publishable_* keys or legacy signed anon JWTs.
  if(key.startsWith("sb_publishable_")){
    if(!/^sb_publishable_[A-Za-z0-9_-]{8,}$/.test(key))
      fail("UNRECOGNIZED_ANON_KEY");
  } else {
    const parts=key.split(".");
    if(parts.length!==3||parts.some(x=>!x)||!parts.every(x=>/^[A-Za-z0-9_-]+$/.test(x)))
      fail("UNRECOGNIZED_ANON_KEY");
    let claims;
    try{claims=JSON.parse(Buffer.from(parts[1],"base64url").toString("utf8"));}
    catch{fail("UNRECOGNIZED_ANON_KEY")}
    if(!claims||claims.role!=="anon")fail("NON_ANON_API_KEY_FORBIDDEN");
  }
  const accounts={};
  for(const label of ["OWNER_A","OWNER_B","STAFF_A","REVOKED_A"]){
    const email=env["C10_STAGE_"+label+"_EMAIL"],password=env["C10_STAGE_"+label+"_PASSWORD"];
    if(typeof email!=="string"||!email.includes("@")||typeof password!=="string"||password.length<8)
      fail("MISSING_STAGING_AUTH_ACCOUNT:"+label);
    accounts[label]={email,password};
  }
  if(new Set(Object.values(accounts).map(x=>x.email.toLowerCase())).size!==4)
    fail("FOUR_DISTINCT_STAGING_ACCOUNTS_REQUIRED");
  const ids={};
  for(const name of ["BUSINESS_A_ID","BUSINESS_B_ID","LOCATION_A_ID","LOCATION_B_ID"]){
    const value=env["C10_STAGE_"+name];
    if(!POS.test(value||""))fail("INVALID_EXPECTED_STAGING_ID:"+name);
    ids[name]=String(value);
  }
  if(ids.BUSINESS_A_ID===ids.BUSINESS_B_ID||ids.LOCATION_A_ID===ids.LOCATION_B_ID)
    fail("INDEPENDENT_STAGING_BUSINESSES_REQUIRED");
  return {url,key,accounts,ids};
}
function claimsOf(token){
  try{
    const payload=JSON.parse(Buffer.from(String(token).split(".")[1],"base64url").toString("utf8"));
    if(payload.role!=="authenticated"||!payload.sub||!Array.isArray(payload.aud)&&payload.aud!=="authenticated"||
       (Array.isArray(payload.aud)&&!payload.aud.includes("authenticated"))||
       !Number.isFinite(payload.exp)||payload.exp<=Date.now()/1000)fail("INVALID_AUTH_TOKEN");
    return {sub:payload.sub};
  }catch{fail("INVALID_AUTH_TOKEN")}
}
async function jsonRequest(doFetch,url,options){
  let response;
  try{response=await doFetch(url,{...options,signal:AbortSignal.timeout(12000),redirect:"error"});}
  catch{fail("STAGING_REQUEST_FAILED")}
  let result;
  try{result=await response.json();}catch{result=null}
  return {status:response.status,body:result};
}
async function authenticate(cfg,login,doFetch){
  const token=await jsonRequest(doFetch,cfg.url+"/auth/v1/token?grant_type=password",{
    method:"POST",headers:{apikey:cfg.key,"content-type":"application/json"},
    body:JSON.stringify(login)});
  if(token.status!==200||typeof token.body?.access_token!=="string")fail("STAGING_AUTH_SIGNIN_REJECTED");
  const accessToken=token.body.access_token;
  const claimed=claimsOf(accessToken);
  const user=await jsonRequest(doFetch,cfg.url+"/auth/v1/user",{
    method:"GET",headers:{apikey:cfg.key,Authorization:"Bearer "+accessToken}});
  if(user.status!==200||user.body?.id!==claimed.sub)
    fail("STAGING_AUTH_USER_VERIFICATION_FAILED");
  return {accessToken,userId:user.body.id};
}
async function readRows(cfg,doFetch,resource,token){
  if(!["locations","org_units"].includes(resource))fail("UNAPPROVED_STAGING_RESOURCE");
  const qs=resource==="locations"?"select=id&order=id.asc&limit=1000":
    "select=id&kind=eq.business&order=id.asc&limit=1000";
  const headers={apikey:cfg.key,Accept:"application/json"};
  if(token)headers.Authorization="Bearer "+token;
  const response=await jsonRequest(doFetch,cfg.url+"/rest/v1/"+resource+"?"+qs,{method:"GET",headers});
  if([401,403,404].includes(response.status))return {denied:true,ids:[]};
  if(response.status!==200||!Array.isArray(response.body))
    fail("STAGING_REST_ACCESS_OR_SCHEMA_ERROR:"+resource);
  if(response.body.length>=1000)fail("STAGING_SCOPE_RESULT_TRUNCATED:"+resource);
  const ids=[];
  for(const row of response.body){
    if(!row||!POS.test(String(row.id)))fail("INVALID_STAGING_ROW:"+resource);
    ids.push(String(row.id));
  }
  if(new Set(ids).size!==ids.length)fail("DUPLICATE_STAGING_ROWS:"+resource);
  return {denied:false,ids};
}
function holds(scope,id){return scope.ids.includes(id)}
async function run(env,doFetch=fetch){
  const cfg=config(env);
  const auth={};
  for(const [name,credentials] of Object.entries(cfg.accounts))
    auth[name]=await authenticate(cfg,credentials,doFetch);
  if(new Set(Object.values(auth).map(x=>x.userId)).size!==4)
    fail("DUPLICATE_AUTH_IDENTITIES");
  const obs={};
  for(const [role,value] of Object.entries(auth)){
    obs[role]={
      locations:await readRows(cfg,doFetch,"locations",value.accessToken),
      businesses:await readRows(cfg,doFetch,"org_units",value.accessToken)
    };
  }
  obs.ANON={
    locations:await readRows(cfg,doFetch,"locations",null),
    businesses:await readRows(cfg,doFetch,"org_units",null)
  };
  const {BUSINESS_A_ID:a,BUSINESS_B_ID:b,LOCATION_A_ID:la,LOCATION_B_ID:lb}=cfg.ids;
  function requires(role,resource,id){
    if(!holds(obs[role][resource],id))fail("STAGING_EXPECTED_OWN_ACCESS_MISSING:"+role+":"+resource);
  }
  function excludes(role,resource,id){
    if(holds(obs[role][resource],id))fail("STAGING_CROSS_SCOPE_LEAK:"+role+":"+resource);
  }
  // Positive proofs rule out a trivially over-restrictive policy falsely passing.
  requires("OWNER_A","locations",la);requires("OWNER_B","locations",lb);
  requires("OWNER_A","businesses",a);requires("OWNER_B","businesses",b);
  requires("STAFF_A","locations",la);
  excludes("OWNER_A","locations",lb);excludes("OWNER_B","locations",la);
  excludes("OWNER_A","businesses",b);excludes("OWNER_B","businesses",a);
  excludes("STAFF_A","locations",lb);excludes("STAFF_A","businesses",b);
  if(obs.STAFF_A.locations.ids.some(id=>id!==la))fail("STAFF_LOCATION_OVERGRANT");
  for(const role of ["REVOKED_A","ANON"]){
    for(const resource of ["locations","businesses"])
      if(obs[role][resource].ids.length)fail("REVOKED_OR_ANON_READS_DATA:"+role+":"+resource);
  }
  // Never output tokens, email, user_id or actual customer rows.
  return {pass:true,mode:"REAL_AUTH_STAGING_ONLY",roles_checked:5,
    assertions:"2 owners positive and cross-business negative, staff exact site, revoked and anon zero access",
    production_touched:false,write_requests:0};
}
if(require.main===module){
  run(process.env).then(result=>console.log("PASS C10-A019 "+JSON.stringify(result)))
    .catch(err=>{console.error("FAIL C10-A019 staging signed Auth gate: "+err.message);process.exitCode=1;});
}
module.exports={config,claimsOf,authenticate,readRows,run};
