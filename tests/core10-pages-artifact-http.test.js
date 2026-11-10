"use strict";
/* C10-A018 Package 0. HTTP verification of the exact Pages artifact to be
 * published AFTER a separately approved GitHub Actions Pages-source switch.
 * This is a local, no-credential test; not signed-in production E2E.
 */
const assert=require("node:assert/strict");
const fs=require("node:fs");
const http=require("node:http");
const path=require("node:path");
const {verify,isAllowed}=require("../internal/core10-pages-package.js");

async function main(){
  const arg=process.argv[2];
  if(!arg||!path.isAbsolute(arg))throw new Error("ABSOLUTE_ARTIFACT_PATH_REQUIRED");
  const dir=path.resolve(arg);
  const files=verify(dir);
  assert.ok(files.length>100,"Artifact unexpectedly small, legacy bundle may be missing");
  const positive=[
    "index.html","owner.html","business.html","sw.js",
    "v2/index.html","v2/sw.js","app.js","vendor/supabase.js",
    "data/report_registry.json","core10-business-builder.html"
  ];
  for(const p of positive)assert.ok(files.includes(p),"REQUIRED_PUBLISH_PATH_MISSING:"+p);
  const blocked=[
    "scripts/c10_a018_demo_backend.sql",
    "scripts/c10_a018_readonly_structure_snapshot.sql",
    "internal/enterprise-sql/c10_a018_demo_backend.sql",
    "internal/enterprise-sql/c10_a019_sg_scope_preflight_readonly.sql",
    "tests/e2e/forbidden_files.js",
    "internal/core10-pages-package.js",
    "docs/development/CURRENT_HANDOFF.md",
    ".github/workflows/pages-dist.yml.disabled",
    "v2/scripts/secret.sql","data/private.env","audit-private.html","setup-admin.html"
  ];
  for(const p of blocked)assert.equal(files.includes(p),false,"LEAKED_INTERNAL_FILE:"+p);
  assert.ok(files.every(isAllowed),"Artifact inventory has non-public paths");
  const server=http.createServer((req,res)=>{
    let rel;
    try { rel=decodeURIComponent(new URL(req.url,"http://127.0.0.1").pathname).slice(1); }
    catch { res.writeHead(400);res.end();return; }
    if(!rel||rel.endsWith("/"))rel+="index.html";
    const target=path.resolve(dir,rel);
    if(!target.startsWith(dir+path.sep)||!fs.existsSync(target)||!fs.statSync(target).isFile()){
      res.writeHead(404);res.end("not found");return;
    }
    res.writeHead(200,{"Cache-Control":"no-store"});fs.createReadStream(target).pipe(res);
  });
  await new Promise((resolve,reject)=>server.listen(0,"127.0.0.1",err=>err?reject(err):resolve()));
  try {
    const origin="http://127.0.0.1:"+server.address().port;
    for(const p of positive){
      const response=await fetch(origin+"/"+p);
      assert.equal(response.status,200,"HTTP ASSET MISSING:"+p);
      assert.ok((await response.arrayBuffer()).byteLength>0,"EMPTY ASSET:"+p);
    }
    for(const p of blocked){
      const response=await fetch(origin+"/"+p);
      assert.equal(response.status,404,"HTTP INTERNAL_FILE_EXPOSED:"+p);
    }
    for(const p of ["scripts%2Fc10_a018_demo_backend.sql","%2e%2e%2Fscripts%2Fc10_a018_demo_backend.sql"]){
      const response=await fetch(origin+"/"+p);
      assert.notEqual(response.status,200,"PATH_TRAVERSAL_EXPOSED:"+p);
    }
    console.log("PASS C10-A018 Pages HTTP artifact: "+positive.length+
      " real legacy/frontend routes 200; "+blocked.length+" internal routes 404;"+
      " traversal denied; "+files.length+" allowlisted files; NO DEPLOYMENT");
  } finally {await new Promise((resolve,reject)=>server.close(err=>err?reject(err):resolve()));}
}
main().catch(e=>{console.error("FAIL C10-A018 artifact HTTP: "+e.stack);process.exitCode=1;});
