// CORE-10-CENTRAL Step 05: isolated PostgREST/JWT REST RPC integration tests.
// Uses only synthetic CI data and a disposable test signing key.
// Run: CORE10_CI_JWT_SECRET=... node tests/api/core10-owner-inbox-rest-smoke.js
"use strict";
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const frontendSource = fs.readFileSync(path.join(__dirname,"..","..","core10-owner-inbox.js"),"utf8");
function checkedFrontendRows(payload,kind,businessId) {
  const location = {search:"",hash:"#/contract-test"};
  const app = {S:{ctx:{is_owner:false,profile:{id:"test"}},lang:"en"},H:{},sb:{}};
  const win = {BOS_APP:app,BOS:{biz:{
    list:()=>[{id:10,name_en:"Test A"},{id:20,name_en:"Test B"}],
    cur:()=>10
  }},location,addEventListener(){}};
  const doc = {body:{dataset:{}},head:{appendChild(){}},
    addEventListener(){},querySelector(){return null},
    createElement(){return {style:{},textContent:"",id:""}}
  };
  vm.runInNewContext(frontendSource,{window:win,document:doc,location,
    MutationObserver:undefined,Promise,Number,Set,Map,Array,console});
  const rows = win.CORE10_OWNER_INBOX.validate(payload,{kind,id:businessId});
  return rows===null?null:rows.length;
}

const secret = process.env.CORE10_CI_JWT_SECRET;
const endpoint = process.env.CORE10_CI_REST_URL || "http://127.0.0.1:3000/rpc/core10_owner_inbox_v1";
if (!secret || secret.length < 32) {
  throw new Error("Missing or weak disposable CORE10_CI_JWT_SECRET");
}
const people = {
  owner:"00000000-0000-4000-8000-000000000001",
  staff:"00000000-0000-4000-8000-000000000002",
  revoked:"00000000-0000-4000-8000-000000000003"
};
function jwt(sub, overrides = {}) {
  const now = Math.floor(Date.now() / 1000);
  const payload = {sub,role:"authenticated",aud:"authenticated",iat:now,exp:now+120,...overrides};
  const header = Buffer.from(JSON.stringify({alg:"HS256",typ:"JWT"})).toString("base64url");
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const unsigned = header + "." + body;
  const signature = crypto.createHmac("sha256",secret).update(unsigned).digest("base64url");
  return unsigned + "." + signature;
}
async function rpc(token,args) {
  const headers = {"content-type":"application/json"};
  if (token) headers.authorization="Bearer "+token;
  const res=await fetch(endpoint,{method:"POST",headers,body:JSON.stringify(args)});
  const raw=await res.text();
  let data;try{data=JSON.parse(raw)}catch{data=raw}
  return {status:res.status,data};
}
function refused(r,label){
  assert.ok(r.status >= 400,label+": server permitted request HTTP "+r.status);
  assert.ok(!r.data || !r.data.certified,label+": unauthorized certified data returned");
  assert.ok(!r.data || !Array.isArray(r.data.items),label+": unauthorized items returned");
  console.log("PASS DENIED: "+label+" [HTTP "+r.status+"]");
}
function accepted(r,label,businessId,count) {
  assert.equal(r.status,200,label+": "+r.status+" "+JSON.stringify(r.data));
  assert.equal(r.data?.certified,true);
  assert.equal(r.data?.scope,"owner");
  assert.equal(r.data?.business_id,businessId);
  assert.ok(Array.isArray(r.data?.items));
  assert.equal(r.data.items.length,count,label+": unexpected item count");
  for (const item of r.data.items) {
    assert.equal(typeof item.business_id,"number");
    assert.equal(item.status,"pending");
    assert.match(item.id,/^[a-z_]+:[0-9a-f-]+$/);
    assert.match(item.created_at,/^\d{4}-\d{2}-\d{2}T/);
    assert.ok([10,20].includes(item.business_id));
    if (businessId!==null)assert.equal(item.business_id,businessId);
  }
  console.log("PASS ACCEPTED: "+label+" ["+count+" mapped items]");
  return new Set(r.data.items.map(x=>x.id));
}
(async()=>{
  const owner=jwt(people.owner);
  const masterResponse = await rpc(owner,{p_business_id:null,p_limit:40});
  const tenResponse = await rpc(owner,{p_business_id:10,p_limit:40});
  const twentyResponse = await rpc(owner,{p_business_id:20,p_limit:40});
  const all=accepted(masterResponse,"master owner",null,9);
  const ten=accepted(tenResponse,"business 10 owner",10,6);
  const twenty=accepted(twentyResponse,"business 20 owner",20,3);
  // End-to-end serialization contract: real signed-JWT PostgREST JSON must
  // pass the actual browser-side validator, not a hand-crafted mock alone.
  assert.equal(checkedFrontendRows(masterResponse.data,"master",null),9);
  assert.equal(checkedFrontendRows(tenResponse.data,"business",10),6);
  assert.equal(checkedFrontendRows(twentyResponse.data,"business",20),3);
  assert.equal(checkedFrontendRows({...tenResponse.data,business_id:"10"},"business",10),null);
  assert.equal(checkedFrontendRows({...tenResponse.data,items:[
    ...tenResponse.data.items,twentyResponse.data.items[0]
  ]},"business",10),null);
  console.log("PASS: real PostgREST response -> actual frontend validator (3 valid, 2 rejected)");
  assert.ok(ten.has("release:1"));
  assert.ok(all.has("release:1"));
  assert.ok(twenty.has("entry_change:1"));
  for (const excluded of ["release:2","release:3","exception:1","emergency:2",
    "pay:2","item_change:2","item_change:3",
    "entry:eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"]) {
    assert.ok(!all.has(excluded),"unexpected approval data leak: "+excluded);
  }
  console.log("PASS: canonical IDs, invalid/approved/inactive source filtering");

  refused(await rpc(jwt(people.staff),{p_business_id:10,p_limit:40}),
    "staff selected-business direct RPC");
  refused(await rpc(jwt(people.staff),{p_business_id:null,p_limit:40}),
    "staff master direct RPC");
  refused(await rpc(jwt(people.staff,{
    user_metadata:{is_owner:true,role:"owner"},app_metadata:{is_owner:true}
  }),{p_business_id:20,p_limit:40}),"forged metadata owner claim");
  refused(await rpc(jwt(people.revoked),{p_business_id:10,p_limit:40}),
    "inactive/revoked owner");
  refused(await rpc(jwt("00000000-0000-4000-8000-000000000099"),{p_business_id:null,p_limit:40}),
    "unregistered authenticated user");
  refused(await rpc(jwt(people.owner,{exp:Math.floor(Date.now()/1000)-3600}),
    {p_business_id:10,p_limit:40}),"expired signed JWT");
  // Mutate the FIRST base64url character of the signature. Mutating its
  // final character is unreliable: unused trailing base64 bits can produce
  // a different token string with the exact same decoded HMAC bytes.
  const signed=jwt(people.owner);
  const tokenParts=signed.split(".");
  assert.equal(tokenParts.length,3);
  const signature=tokenParts[2];
  assert.ok(signature.length>1);
  tokenParts[2]=(signature[0]==="A"?"B":"A")+signature.slice(1);
  refused(await rpc(tokenParts.join("."),
    {p_business_id:null,p_limit:40}),"invalid JWT HMAC");
  refused(await rpc(null,{p_business_id:null,p_limit:40}),"anonymous request");
  refused(await rpc(owner,{p_business_id:30,p_limit:40}),"inactive business");
  refused(await rpc(owner,{p_business_id:40,p_limit:40}),"planned business");
  refused(await rpc(owner,{p_business_id:999,p_limit:40}),"unknown business");
  refused(await rpc(owner,{p_business_id:10,p_limit:41}),"limit above 40");
  refused(await rpc(owner,{p_business_id:10,p_limit:0}),"zero limit");
  console.log("SUCCESS: all signed-JWT PostgREST owner/tenant/security cases passed (synthetic CI only).");
})().catch(e=>{console.error(e);process.exitCode=1});
