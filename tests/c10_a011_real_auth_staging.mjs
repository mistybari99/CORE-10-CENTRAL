// C10-A011 real Supabase Auth/PostgREST staging gate — MANUAL ONLY.
// Requires independently signed-in Owner and Staff JWTs on a SEPARATE staging project.
// Hard-blocks the live IMG-ERP-SG project; no secrets or service-role keys are committed.
// Leaves one clearly named QA Location in staging; do not run against operational data.
import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
const required=[
 "C10_STAGING_SUPABASE_URL",
 "C10_STAGING_PUBLISHABLE_KEY",
 "C10_STAGING_OWNER_JWT",
 "C10_STAGING_STAFF_JWT",
 "C10_STAGING_BUSINESS_ID"
];
for(const name of required)if(!process.env[name])throw Error("Missing staging input: "+name);
if(process.env.C10_CONFIRM_STAGING_WRITES!=="YES_STAGING_ONLY"){
 throw Error("Not authorized for staging write test: set C10_CONFIRM_STAGING_WRITES=YES_STAGING_ONLY");
}
const url=new URL(process.env.C10_STAGING_SUPABASE_URL);
const prod="kbuhnpqooycqbzrfejcs";
if(url.protocol!=="https:"||!url.hostname.endsWith(".supabase.co")||
 url.hostname.startsWith(prod+".")||url.hostname.includes(prod)){
 throw Error("Refusing non-staging or production Supabase endpoint");
}
const business=Number(process.env.C10_STAGING_BUSINESS_ID);
assert.ok(Number.isSafeInteger(business)&&business>0);
const api=url.origin+"/rest/v1/";
const key=process.env.C10_STAGING_PUBLISHABLE_KEY;
const owner=process.env.C10_STAGING_OWNER_JWT;
const staff=process.env.C10_STAGING_STAFF_JWT;
function jwtSub(t){
 const parts=t.split(".");
 if(parts.length!==3)throw Error("Signed JWT shape required");
 const payload=JSON.parse(Buffer.from(parts[1],"base64url").toString("utf8"));
 if(!payload.sub||!payload.exp||(payload.exp*1000)<=Date.now())throw Error("JWT missing sub or expired");
 return payload.sub;
}
assert.notEqual(jwtSub(owner),jwtSub(staff),"Owner and Staff must be different verified user accounts");
let tested=0;
async function request(method,route,token,body){
 const controller=new AbortController();
 const timer=setTimeout(()=>controller.abort(),12000);
 try{
  const res=await fetch(api+route,{
   method,signal:controller.signal,
   headers:{"apikey":key,"Authorization":"Bearer "+token,
    "Content-Type":"application/json","Prefer":"return=representation"},
   body:body?JSON.stringify(body):undefined
  });
  const t=await res.text();let data;
  try{data=JSON.parse(t)}catch(_){data={message:t}}
  return{ok:res.ok,status:res.status,data};
 }finally{clearTimeout(timer)}
}
const keyId=randomUUID();
const suffix=keyId.slice(0,8).replaceAll("-","");
const code="qa_c10_"+suffix;
const payload={
 p_business:business,p_kind:"showroom",p_code:code,
 p_name_bn:"QA - পরীক্ষামূলক শোরুম",
 p_name_en:"QA ONLY DO NOT USE "+suffix,
 p_org_branch:null,p_client:keyId
};
const badStaff=await request("POST","rpc/business_place_create135",staff,{
 ...payload,p_client:randomUUID()
});
assert.equal(badStaff.ok,false,"Staff must be denied creation on this business");
console.log("PASS real signed Staff JWT denied; HTTP "+badStaff.status);
tested++;
const first=await request("POST","rpc/business_place_create135",owner,payload);
assert.equal(first.ok,true,"Authorized owner staging creation failed: "+first.status);
assert.equal(first.data.dup,false);assert.equal(first.data.business_id,business);
assert.equal(first.data.kind,"showroom");assert.equal(first.data.status,"setting_up");
assert.ok(Number.isSafeInteger(Number(first.data.id)));
console.log("PASS real signed Owner JWT created staging Location ID "+first.data.id);
tested++;
const replay=await request("POST","rpc/business_place_create135",owner,payload);
assert.equal(replay.ok,true,"Identical retry must return a verified receipt");
assert.equal(replay.data.dup,true);assert.equal(replay.data.request_matched,true);
assert.equal(replay.data.id,first.data.id);assert.equal(replay.data.business_id,business);
console.log("PASS signed owner exact retry, no extra Location ID");
tested++;
const altered=await request("POST","rpc/business_place_create135",owner,{...payload,p_code:"qa_changed"});
assert.equal(altered.ok,false,"Mismatched retry must be denied");
assert.ok(JSON.stringify(altered.data).includes("client_id_payload_mismatch"));
console.log("PASS signed owner changed-payload replay denied");
tested++;
const foreign=process.env.C10_STAGING_OTHER_BUSINESS_ID;
if(foreign){
 const other=Number(foreign);
 if(Number.isSafeInteger(other)&&other>0&&other!==business){
  const denied=await request("POST","rpc/business_place_create135",staff,{
   ...payload,p_business:other,p_client:randomUUID()
  });
  assert.equal(denied.ok,false,"Staff cross-business creation must be denied");
  console.log("PASS real staff cross-business creation denied");tested++;
 }
}
const verify=await request("GET","locations?id=eq."+encodeURIComponent(String(first.data.id))+"&select=id,code,kind,status",owner);
assert.equal(verify.ok,true,"Owner must be able to read own created Location");
assert.ok(Array.isArray(verify.data)&&verify.data.length===1);
assert.equal(Number(verify.data[0].id),Number(first.data.id));
assert.equal(verify.data[0].status,"setting_up");
console.log("PASS Owner read-after-write from staging Location record");
tested++;
console.log("RESULT "+tested+" staging signed-JWT/PostgREST tests PASS. STAGING QA LOCATION REMAINS: "+code+" / ID "+first.data.id);
