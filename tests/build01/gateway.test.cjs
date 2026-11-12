"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),http=require("node:http");
const {createGateway}=require("./gateway.cjs");
const anon=["e30",Buffer.from(JSON.stringify({role:"anon"})).toString("base64url"),"synthetic-test-signature"].join(".");
const listen=s=>new Promise(r=>s.listen(0,"127.0.0.1",r));
const close=s=>new Promise(r=>s.close(r));
test("gateway exposes only explicit loopback auth and RPC surfaces, never admin/internal/config fallback",async()=>{
 const seen=[];
 const upstream=http.createServer((req,res)=>{seen.push(req.url);res.writeHead(200,{"content-type":"application/json"});res.end('{"ok":true}');});
 await listen(upstream);
 const url="http://127.0.0.1:"+upstream.address().port;
 const gateway=createGateway({authUrl:url,restUrl:url,publishableKey:anon});await listen(gateway);
 const base="http://127.0.0.1:"+gateway.address().port;
 try{
  assert.equal((await fetch(base+"/")).status,200);
  const config=await(await fetch(base+"/core10-build01-config.js")).text();
  assert(config.includes(base));assert(!config.includes("BOS_CONFIG"));
  for(const route of ["/auth/v1/admin/users","/auth/v1/signup","/rest/v1/business_members","/rest/v1/rpc/change_access_v1","/config.js","/AGENTS.md","/internal/enterprise-sql/c10_build01_access_integration_v1.sql"])
   assert.equal((await fetch(base+route)).status,404,route);
  assert.equal((await fetch(base+"/auth/v1/user")).status,200);
  assert.equal((await fetch(base+"/rest/v1/rpc/build01_context_v1",{method:"POST",headers:{"content-type":"application/json"},body:"{}"})).status,200);
  assert.deepEqual(seen,["/user","/rpc/build01_context_v1"]);
  assert.equal((await fetch(base+"/auth/v1/user",{headers:{origin:"https://other.example"}})).status,403);
  assert.equal((await fetch(base+"/rest/v1/rpc/build01_context_v1",{method:"POST",body:"x".repeat(65537)})).status,413);
  assert.equal(seen.length,2);
 }finally{await close(gateway);await close(upstream);}
});
test("gateway constructor refuses remote services and secret/service keys",()=>{
 assert.throws(()=>createGateway({authUrl:"https://remote.supabase.co",restUrl:"http://127.0.0.1:3000",publishableKey:anon}),/LOOPBACK/);
 const secret=["e30",Buffer.from(JSON.stringify({role:"service_role"})).toString("base64url"),"x"].join(".");
 assert.throws(()=>createGateway({authUrl:"http://127.0.0.1:9999",restUrl:"http://127.0.0.1:3000",publishableKey:secret}),/ONLY_ANON/);
});
