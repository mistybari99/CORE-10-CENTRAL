import test from "node:test";
import assert from "node:assert/strict";
import worker from "../preview/worker.mjs";

const request=(path,method="GET")=>new Request("https://preview.example"+path,{method});

test("PREVIEW root is a responsive synthetic UI with source links",async()=>{
 const r=await worker.fetch(request("/"));
 assert.equal(r.status,200);
 assert.match(r.headers.get("content-type"),/text\/html/);
 assert.match(r.headers.get("content-security-policy"),/connect-src 'none'/);
 const h=await r.text();
 for(const x of ["CORE 10 CENTRAL","No real data","preview.js","preview.css","Business context"])assert.ok(h.includes(x),x);
});

test("PREVIEW client holds isolated package map and no real API calls",async()=>{
 const r=await worker.fetch(request("/preview.js"));
 const js=await r.text();
 for(const x of ["A045","A046","A047","A048","A049","A050","A051","A052","A053","A054","A055","In-memory only","No server write"])assert.ok(js.includes(x),x);
 assert.doesNotMatch(js,/\.from\(['"]|\.rpc\(['"]|fetch\(/);
});

test("PREVIEW has no writes, secret routes or arbitrary fetch proxy",async()=>{
 for(const method of ["POST","PUT","PATCH","DELETE"]){
  assert.equal((await worker.fetch(request("/",method))).status,405);
 }
 for(const path of ["/internal/enterprise-sql/c10_a051_workforce_core_v1.sql","/.github/workflows/core10-a051-workforce-ci.yml","/config.js","/env","/api/stock","/../../internal/enterprise-sql","/core10-workforce-client.js"]){
  assert.equal((await worker.fetch(request(path))).status,404,path);
 }
});

test("health endpoint proves nonproduction guard and pinned source",async()=>{
 const r=await worker.fetch(request("/health")),j=await r.json();
 assert.equal(j.status,"ok");assert.equal(j.mode,"synthetic-preview");
 assert.equal(j.production_writes,false);
 assert.match(j.source_sha,/^[0-9a-f]{40}$/);
});

test("Build 01 and Build 02A have an honest synthetic walkthrough",async()=>{
 const r=await worker.fetch(request("/build01-build02a.html"));
 assert.equal(r.status,200);
 const h=await r.text();
 for(const x of ["Build 01","Build 02A","78900331a1d1f8ea4712288f094eab82479db764","does not use real login"])assert.ok(h.includes(x),x);
 const js=await (await worker.fetch(request("/build01-build02a.js"))).text();
 assert.doesNotMatch(js,/fetch\(|\.rpc\(|localStorage|sessionStorage/);
});

test("original A045 demo asset fetch is allowlisted and pinned",async()=>{
 const old=globalThis.fetch,seen=[];
 globalThis.fetch=async url=>{seen.push(String(url));return new Response("/* original fixture */",{status:200})};
 try{
  const r=await worker.fetch(request("/core10-engine-workshop-demo-backend.js"));
  assert.equal(r.status,200);
  assert.equal(await r.text(),"/* original fixture */");
  assert.equal(seen.length,1);
  assert.match(seen[0],/^https:\/\/raw\.githubusercontent\.com\/mistybari99\/CORE-10-CENTRAL\/[a-f0-9]{40}\/core10-engine-workshop-demo-backend\.js$/);
  assert.equal((await worker.fetch(request("/core10-engine-workshop-secret.js"))).status,404);
 }finally{globalThis.fetch=old}
});
