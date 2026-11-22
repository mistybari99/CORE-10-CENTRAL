"use strict";
// §7b.3: imported shell MUST reconstruct the exact already verified Worker.
const {test}=require("node:test"),assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto");
const {execFileSync}=require("node:child_process");
const root=path.resolve(__dirname,"..");
const info=require("../docs/coordination/CENTRAL_SHELL_IMPORT_20261122.json");
const cdir=path.join(root,"apps/central");
const run=(...a)=>execFileSync("git",a,{cwd:root,encoding:"utf8"}).trim();
const sha256=(b)=>crypto.createHash("sha256").update(b).digest("hex");
test("§7b.3 imported shell and data are the same source Git trees and blobs",()=>{
  assert.equal(info.schema_version,1);
  assert.equal(info.source_commit,"e9dd90d2c1616711378f657c4e5e0ce08e0d9db9");
  assert.equal(info.target_dir,"apps/central");
  for(const [name,obj] of Object.entries(info.unchanged_git_objects)){
    assert.match(obj,/^[a-f0-9]{40}$/);
    assert.equal(run("rev-parse","HEAD:apps/central/"+name),obj,"Imported Git object changed: "+name);
    assert.equal(run("rev-parse",info.source_commit+":preview/core10-central-owner-app/"+name),obj,
      "Source preview object mismatch: "+name);
    assert.ok(fs.existsSync(path.join(cdir,name)),"Imported input missing: "+name);
  }
  assert.equal(info.release_authorization,false);
  assert.equal(info.staging_changes,false);
});
test("§7b.3 only one reviewed verifier sentinel path changed; all 56 assertions retained",()=>{
  const source=execFileSync("git",["cat-file","blob",info.verify_original_blob],{cwd:root,encoding:"utf8"});
  const old='path.join(ROOT, "config.js")';
  const newer='path.join(ROOT, "legacy/islamia-erp/config.js")';
  assert.equal(source.split(old).length-1,1,"Historical safety check unexpectedly changed");
  const actual=fs.readFileSync(path.join(cdir,"verify.cjs"),"utf8");
  assert.equal(actual,source.replace(old,newer),"Verifier assertions weakened or modified");
  assert.equal(actual.split(newer).length-1,1);
  assert.equal(run("rev-parse",info.source_commit+":preview/core10-central-owner-app/verify.cjs"),info.verify_original_blob);
});
test("§7b.3 build input is pinned to original preview sources; no app-level deployment or secrets",()=>{
  const src=fs.readFileSync(path.join(cdir,"build.mjs"),"utf8");
  assert.match(src,/export const PINS\s*=/);
  assert.match(src,/export const LIVE\s*=/);
  assert.match(src,/export const STAGING\s*=/);
  assert.match(src,/const FORBIDDEN\s*=/);
  assert.match(src,/pinned\(T,\s*"core10-control-centre-config.js"\)/);
  assert.doesNotMatch(src,/\bsb_secret_|service_role|kbuhnpqooycqbzrfejcs/);
  assert.equal(info.expected_worker_sha256,"ba530d45179f9ea146bccb0a04899213a3e396adf7fe6030b28eebf938a5f4b2");
});
test("§7b.3 generated Worker is byte-for-byte equal to verified preview release",()=>{
  const file=path.join(cdir,"dist/worker.mjs");
  assert.ok(fs.existsSync(file),"RUN_APPS_CENTRAL_BUILD_FIRST");
  const compiled=fs.readFileSync(file);
  assert.equal(sha256(compiled),info.expected_worker_sha256,"WORKER_BYTES_CHANGED_FAIL_CLOSED");
  assert.ok(compiled.byteLength>900000,"WORKER_SUSPICIOUSLY_SMALL");
  assert.ok(!compiled.toString("latin1").includes("kbuhnpqooycqbzrfejcs"),"PROTECTED_HOST_IN_WORKER");
  assert.ok(!compiled.toString("latin1").includes("luoeyyngayxpqecuuijb"),"SECOND_PROTECTED_HOST_IN_WORKER");
});
