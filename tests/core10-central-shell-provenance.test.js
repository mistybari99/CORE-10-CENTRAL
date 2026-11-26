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
    // Immutable ORIGINAL release is still checked at its exact import commit.
    assert.equal(run("rev-parse","4345b6e4aa7ee593a455ee29dceccf55d61ade7f:apps/central/"+name),obj,"Original imported Git object changed: "+name);
    // Non-UI build/runtime/data provenance must stay byte-identical on current HEAD.
    if(name!=="site" && name!=="build.mjs") assert.equal(run("rev-parse","HEAD:apps/central/"+name),obj,"Non-UI imported Git object changed: "+name);
    assert.equal(run("rev-parse",info.source_commit+":preview/core10-central-owner-app/"+name),obj,
      "Source preview object mismatch: "+name);
    assert.ok(fs.existsSync(path.join(cdir,name)),"Imported input missing: "+name);
  }
  // Every shipped UI path changed since §7b.3 must be declared.
  const changed=run("diff","--name-only","4345b6e4aa7ee593a455ee29dceccf55d61ade7f","HEAD","--","apps/central/site").split("\n").filter(Boolean).sort();
  assert.deepEqual(changed,[
    "apps/central/site/view/stock-signed.js",
    "apps/central/site/index.html","apps/central/site/app.css","apps/central/site/app.js","apps/central/site/shell-context.js",
    "apps/central/site/tokens.css","apps/central/site/view/view.css","apps/central/site/view/master-signed.js",
    "apps/central/site/view/sales.html",
    "apps/central/site/view/sales-signed.html",
    "apps/central/site/view/sales-signed.js",
  ].sort(),
    "Undeclared shipped-site change since import");
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
  const original=execFileSync("git",["cat-file","blob",run("rev-parse","4345b6e4aa7ee593a455ee29dceccf55d61ade7f:apps/central/build.mjs")],{cwd:root,encoding:"utf8"});
  const pin="  salesSigned: { sha: \"3e008e8ec7db896f46a94ab8ca3d91271905d71d\", ref: \"ccr-15ed11dd-n3hw5h\", status: \"TRUNK_INTEGRATED\" },\n", assets="  for (const p of [\"core10-sales-order.css\",\"core10-sales-master-catalog.js\",\"core10-sales-order-client.js\",\"core10-sales-order-ui.js\",\"core10-sales-invoice-ui.js\",\"core10-sales-order-entry.js\"]) add(\"/signed-sales/\" + p, pinned(\"salesSigned\", p), { kind: \"ACTUAL_SOURCE\", status: PINS.salesSigned.status, commit: full(\"salesSigned\"), source: p, git_blob: blob(\"salesSigned\", p) });\n";
  assert.equal(src,original.replace('  pr112: { sha:',pin+'  pr112: { sha:').replace('  const ws = {};',assets+'  const ws = {};'),"Only reviewed canonical Sales pin and asset mapping allowed");
  assert.match(src,/export const PINS\s*=/);
  assert.match(src,/export const LIVE\s*=/);
  assert.match(src,/export const STAGING\s*=/);
  assert.match(src,/const FORBIDDEN\s*=/);
  assert.match(src,/pinned\(T,\s*"core10-control-centre-config.js"\)/);
  assert.doesNotMatch(src,/\bsb_secret_|service_role|kbuhnpqooycqbzrfejcs/);
  assert.equal(info.expected_worker_sha256,"ba530d45179f9ea146bccb0a04899213a3e396adf7fe6030b28eebf938a5f4b2");
});
test("§7b.3 historical release SHA is pinned; evolved candidate embeds exact current UI bytes",()=>{
  const file=path.join(cdir,"dist/worker.mjs");
  assert.ok(fs.existsSync(file),"RUN_APPS_CENTRAL_BUILD_FIRST");
  const compiled=fs.readFileSync(file);
  assert.ok(compiled.byteLength>900000,"WORKER_SUSPICIOUSLY_SMALL");
  assert.ok(!compiled.toString("latin1").includes("kbuhnpqooycqbzrfejcs"),"PROTECTED_HOST_IN_WORKER");
  assert.ok(!compiled.toString("latin1").includes("luoeyyngayxpqecuuijb"),"SECOND_PROTECTED_HOST_IN_WORKER");
  if(run("rev-parse","HEAD:apps/central/site")===info.unchanged_git_objects.site) {
    assert.equal(sha256(compiled),info.expected_worker_sha256,"FROZEN_RELEASE_SHA_CHANGED");
  } else {
    assert.notEqual(sha256(compiled),info.expected_worker_sha256,
      "CHANGED_SHELL_MUST_NOT_MASQUERADE_AS_PREVIOUS_WORKER");
    const line=compiled.toString("utf8").split("\n").find(x=>x.startsWith("const FILES="));
    assert.ok(line,"MISSING_WORKER_FILE_TABLE");
    const files=JSON.parse(line.slice("const FILES=".length,-1));
    assert.ok(files["/view/stock-signed.js"],"MISSING_SIGNED_STOCK_ASSET");
    assert.deepEqual(Buffer.from(files["/view/stock-signed.js"][1],"base64"),fs.readFileSync(path.join(cdir,"site","view/stock-signed.js")),"Worker Stock asset differs");
    for(const name of ["index.html","app.css","app.js","shell-context.js","tokens.css","view/view.css","view/master-signed.js","view/sales.html","view/sales-signed.html","view/sales-signed.js"]) {
      assert.ok(files["/"+name],"MISSING_SHIPPED_SHELL_ASSET "+name);
      assert.deepEqual(Buffer.from(files["/"+name][1],"base64"),fs.readFileSync(path.join(cdir,"site",name)),
        "Worker asset differs from current shell: "+name);
    }
  }
});
