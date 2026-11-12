"use strict";
const assert=require("node:assert/strict");
const {config,claimsOf,run}=require("./core10-supabase-auth-staging-probe.js");
const clone=x=>JSON.parse(JSON.stringify(x));
const ref="bbbbbbbbbbbbbbbbbbbb";
const env={
 C10_STAGE_REF:ref,C10_STAGE_CONFIRM:"I_CONFIRM_DISPOSABLE_STAGING",
 C10_STAGE_ANON_KEY:"sb_publishable_ci_mock_not_a_real_key",
 C10_STAGE_BUSINESS_A_ID:"101",C10_STAGE_BUSINESS_B_ID:"202",
 C10_STAGE_LOCATION_A_ID:"11",C10_STAGE_LOCATION_B_ID:"22"
};
for(const role of ["OWNER_A","OWNER_B","STAFF_A","REVOKED_A"]){
 env["C10_STAGE_"+role+"_EMAIL"]=role.toLowerCase()+"@example.invalid";
 env["C10_STAGE_"+role+"_PASSWORD"]="mock-password-never-live";
}
const roles=["OWNER_A","OWNER_B","STAFF_A","REVOKED_A"];
const ids=Object.fromEntries(roles.map((r,i)=>[r,String(i+1).padStart(8,"0")+"-0000-4000-8000-00000000000"+(i+1)]));
const jwt=role=>{
 const body={role:"authenticated",sub:ids[role],aud:"authenticated",exp:Math.floor(Date.now()/1000)+600};
 return [Buffer.from(JSON.stringify({alg:"HS256"})).toString("base64url"),
   Buffer.from(JSON.stringify(body)).toString("base64url"),"synthetic_signature_ONLY_MOCK"].join(".");
};
const tokenByRole=Object.fromEntries(roles.map(role=>[role,jwt(role)]));
function httpJson(status,body){return{status,json:async()=>body}}
function mock(options={}){
 const calls=[];
 const f=async (url,opts={})=>{
  const u=new URL(url);
  assert.equal(u.origin,"https://"+ref+".supabase.co");
  assert.equal(opts.redirect,"error");
  const method=opts.method||"GET";
  assert.ok(["POST","GET"].includes(method));
  let role=null;
  if(u.pathname==="/auth/v1/token"){
   assert.equal(method,"POST","Only Auth grant POST permitted");
   const payload=JSON.parse(opts.body);
   assert.ok(Object.keys(payload).every(k=>["email","password"].includes(k)));
   role=roles.find(r=>env["C10_STAGE_"+r+"_EMAIL"]===payload.email);
   if(!role)return httpJson(400,{error:"invalid_credentials"});
   calls.push("signin:"+role);
   return httpJson(200,{access_token:tokenByRole[role]});
  }
  const auth=opts.headers?.Authorization;
  if(auth)role=roles.find(r=>auth==="Bearer "+tokenByRole[r]);
  if(u.pathname==="/auth/v1/user"){
   if(!role)return httpJson(401,{error:"invalid"});
   calls.push("user:"+role);
   return httpJson(200,{id:ids[role]});
  }
  if(u.pathname.startsWith("/rest/v1/")){
   assert.equal(method,"GET","RLS probe must never write data");
   assert.equal(opts.body,undefined);
   calls.push("rest:"+(role||"ANON")+":"+u.pathname);
   const table=u.pathname.split("/").pop();
   let locationIds=role==="OWNER_A"||role==="STAFF_A"?["11"]:role==="OWNER_B"?["22"]:[];
   let businessIds=role==="OWNER_A"||role==="STAFF_A"?["101"]:role==="OWNER_B"?["202"]:[];
   if(options.leakRole===role&&table==="locations")locationIds.push("22");
   if(options.overgrantStaff && role==="STAFF_A"&&table==="locations")locationIds.push("33");
   if(options.anonLeak && !role&&table==="locations")locationIds.push("11");
   if(options.revokedLeak && role==="REVOKED_A"&&table==="org_units")businessIds.push("101");
   if(options.missingOwner && role==="OWNER_A"&&table==="locations")locationIds=[];
   if(options.unavailable && role==="OWNER_B"&&table==="locations")return httpJson(500,{error:"internal"});
   if(options.overLimit && role==="OWNER_A"&&table==="locations")locationIds=Array.from({length:1000},(_,i)=>String(i+1));
   return httpJson(200,(table==="locations"?locationIds:businessIds).map(id=>({id:Number(id)})));
  }
  throw Error("UNEXPECTED_ENDPOINT:"+u.pathname);
 };
 return {f,calls};
}
(async()=>{
 const {f,calls}=mock();const v=await run(env,f);
 assert.equal(v.pass,true);
 assert.equal(v.roles_checked,5);
 assert.equal(v.write_requests,0);
 assert.equal(v.production_touched,false);
 assert.equal(calls.filter(x=>x.startsWith("signin:")).length,4);
 assert.equal(calls.filter(x=>x.startsWith("user:")).length,4);
 assert.equal(calls.filter(x=>x.startsWith("rest:")).length,10);
 const bad=(input,code)=>assert.throws(()=>config(input),new RegExp(code));
 bad({...env,C10_STAGE_REF:"kbuhnpqooycqbzrfejcs"},"DISPOSABLE_STAGING");
 bad({...env,C10_STAGE_CONFIRM:""},"DISPOSABLE_STAGING");
 bad({...env,C10_STAGE_URL:"https://example.com"},"STAGING_HOST");
 bad({...env,C10_STAGE_ANON_KEY:"sb_secret_very_secret"},"PUBLISHABLE_OR_ANON");
 bad({...env,C10_STAGE_ANON_KEY:"service_role"},"PUBLISHABLE_OR_ANON");
 bad({...env,C10_STAGE_OWNER_B_EMAIL:env.C10_STAGE_OWNER_A_EMAIL},"FOUR_DISTINCT");
 bad({...env,C10_STAGE_BUSINESS_B_ID:"101"},"INDEPENDENT");
 bad({...env,C10_STAGE_LOCATION_A_ID:"0"},"INVALID_EXPECTED");
 assert.throws(()=>claimsOf("garbage"),/INVALID_AUTH_TOKEN/);
 for(const [scenario,prefix] of [
  [{leakRole:"OWNER_A"},"STAGING_CROSS_SCOPE_LEAK"],
  [{overgrantStaff:true},"STAFF_LOCATION_OVERGRANT"],
  [{anonLeak:true},"REVOKED_OR_ANON_READS_DATA"],
  [{revokedLeak:true},"REVOKED_OR_ANON_READS_DATA"],
  [{missingOwner:true},"STAGING_EXPECTED_OWN_ACCESS_MISSING"],
  [{unavailable:true},"STAGING_REST_ACCESS_OR_SCHEMA_ERROR"],
  [{overLimit:true},"STAGING_SCOPE_RESULT_TRUNCATED"]
 ])await assert.rejects(()=>run(env,mock(scenario).f),new RegExp(prefix),"Should fail closed: "+prefix);
 const empty=clone(env);delete empty.C10_STAGE_REVOKED_A_PASSWORD;
 assert.throws(()=>config(empty),/MISSING_STAGING_AUTH_ACCOUNT/);
 console.log("PASS C10-A019 real staging Auth probe CONTRACT: mock positive, two owner cross-deny, staff overgrant, revoked/anon leak, missing access, broken REST, pagination, production ref and key guards. NO real Supabase users queried or writes performed.");
})().catch(e=>{console.error("FAIL C10-A019 mock contract: "+e.message);process.exitCode=1});
