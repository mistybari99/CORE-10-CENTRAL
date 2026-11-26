"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const {pathToFileURL}=require("node:url"),{execFileSync}=require("node:child_process");
const root=path.resolve(__dirname,".."),file=path.join(root,"apps/central/dist-clean/worker.mjs");
const src=()=>fs.readFileSync(file,"utf8");
const files=()=>JSON.parse(src().split("\n").find(l=>l.startsWith("const FILES=")).slice(12,-1));
const decode=(f,k)=>Buffer.from(f[k][1],"base64").toString("utf8");
test("clean signed routes, no preview or draft assets, all HTML dependencies resolve",async()=>{
 const {ALLOW}=await import("../apps/central/clean/transform.mjs");
 const f=files();assert.deepEqual(Object.keys(f),ALLOW);
 for(const route of Object.keys(f))assert.doesNotMatch(route,/replay|workspace-data|sales-data|mfg-data|\/docs\/preview|\/live\/core10-sales-|\/live\/modules\/manufacturing/);
 for(const route of Object.keys(f).filter(x=>x.endsWith(".html"))){
  const html=decode(f,route);for(const match of html.matchAll(/(?:src|href)="([^"]+)"/g)){
   const ref=match[1];if(ref.startsWith("#")||ref==="about:blank")continue;
   const u=new URL(ref,"https://core10.invalid"+route);assert.equal(u.origin,"https://core10.invalid");assert.ok(f[u.pathname],"missing "+ref+" from "+route);
  }
 }
 const app=decode(f,"/app.js"),html=decode(f,"/index.html");assert.match(app,/sales: "\/view\/sales-signed\.html"/);assert.match(app,/home: "\/view\/owner-dashboard-signed\.html"/);
 for(const item of ["staff","manufacturing","features","approvals"])assert.ok(!html.includes('href="#/'+item+'"'));
 assert.doesNotMatch(app,/\/view\/(workspace|sales|mfg)\.html/);
 execFileSync(process.execPath,["--check",path.join(root,"apps/central/clean/app.js")]);
});
test("actual Worker HTTP contract: signed routes 200; every removed demo route 404; strict headers",async()=>{
 const worker=(await import(pathToFileURL(file))).default;
 const f=files(),call=(p,method="GET")=>worker.fetch(new Request("https://core10.invalid"+p,{method}));
 for(const route of ["/",...Object.keys(f)]){const res=await call(route);assert.equal(res.status,200,route);assert.equal(res.headers.get("cache-control"),"no-store");assert.match(res.headers.get("content-security-policy"),/connect-src 'self' https:\/\/rhrqhbyzrhaafynfhdaf\.supabase\.co/);assert.doesNotMatch(res.headers.get("x-core10-source"),/pr109=|pr112=/);assert.equal((await res.arrayBuffer()).byteLength,Buffer.from(f[route==="/"?"/index.html":route][1],"base64").length);}
 for(const route of ["/view/workspace.html","/view/sales.html","/view/mfg.html","/view/replay.js","/view/control-data.js","/view/master-data.js","/view/sales-data.js","/view/mfg-data.js","/live/docs/preview/c10-np01-canonical-reviewer-preview.html","/config.js","/v2/config.js"])assert.equal((await call(route)).status,404,route);
 assert.equal((await call("/","POST")).status,405);
 assert.equal((await (await call("/","HEAD")).arrayBuffer()).byteLength,0);
});
