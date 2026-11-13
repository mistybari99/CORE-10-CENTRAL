import test from "node:test";
import assert from "node:assert/strict";
const base="https://core10-central-preview-v1.mistybari99.workers.dev";
async function check(path,init){const r=await fetch(base+path,{...init,signal:AbortSignal.timeout(20000)});return r}
test("public preview root renders and blocks off-origin network",async()=>{
 const r=await check("/");
 assert.equal(r.status,200);
 assert.match(r.headers.get("content-type"),/text\/html/i);
 assert.match(r.headers.get("content-security-policy")||"",/connect-src 'none'/);
 const body=await r.text();assert.match(body,/CORE 10 CENTRAL/);assert.match(body,/No real data/);
});
test("public health reports pinned synthetic build",async()=>{
 const r=await check("/health");assert.equal(r.status,200);const x=await r.json();
 assert.equal(x.status,"ok");assert.equal(x.mode,"synthetic-preview");assert.equal(x.production_writes,false);
 assert.equal(x.source_sha,"ca0831bc07eb3ac6e65d5c81b4e65d9cba80ec91");
});
test("public original A045 workshop HTML and in-memory mock are served",async()=>{
 const [h,b]=await Promise.all([check("/core10-engine-workshop-demo.html"),check("/core10-engine-workshop-demo-backend.js")]);
 assert.equal(h.status,200);assert.equal(b.status,200);
 assert.match(await h.text(),/Micro-Engine Workshop \(DEMO\)/);
 assert.match(await b.text(),/in-memory, runs only in this browser tab/);
});
test("public preview denies production writes and internal files",async()=>{
 assert.equal((await check("/",{method:"POST"})).status,405);
 assert.equal((await check("/internal/enterprise-sql/c10_a051_workforce_core_v1.sql")).status,404);
 assert.equal((await check("/config.js")).status,404);
});