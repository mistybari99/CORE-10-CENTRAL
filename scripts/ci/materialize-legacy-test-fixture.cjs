"use strict";
// CI-only bridge while old browser/regression suites are migrated to explicit legacy paths.
// Never shipped, committed as restored assets, or run against live/Supabase.
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const crypto=require("node:crypto");
const {execFileSync}=require("node:child_process");
// These retired pages contain historical URLs. Block DNS to BOTH protected projects
// inside the disposable CI runner BEFORE serving the historical browser fixture.
const protectedHosts=["kbuhnpqooycqbzrfejcs.supabase.co","luoeyyngayxpqecuuijb.supabase.co"];
function quarantineHosts(){
  const hosts=protectedHosts.map(h=>"127.0.0.1 "+h).join("\n")+"\n";
  execFileSync("sudo",["tee","-a","/etc/hosts"],{input:hosts,stdio:["pipe","ignore","inherit"]});
  const current=fs.readFileSync("/etc/hosts","utf8");
  for(const host of protectedHosts)assert.ok(current.includes("127.0.0.1 "+host),"LEGACY_DNS_BLOCK_NOT_INSTALLED");
}
const root=path.resolve(__dirname,"../..");
assert.equal(process.env.GITHUB_ACTIONS,"true","CI_FIXTURE_ONLY");
assert.equal(path.resolve(process.env.GITHUB_WORKSPACE||""),root,"CI_WORKSPACE_MISMATCH");
const manifest=require("../../docs/coordination/LEGACY_MOVE_MANIFEST_20261122.json");
assert.equal(manifest.files.length,463,"LEGACY_FIXTURE_INVENTORY_DRIFT");
quarantineHosts();
for(const file of manifest.files){
  const src=path.join(root,file.to),dest=path.join(root,file.from);
  assert.ok(file.to==="legacy/islamia-erp/"+file.from && !file.from.includes(".."),"LEGACY_FIXTURE_INVALID_PATH");
  assert.equal(fs.existsSync(dest),false,"LEGACY_FIXTURE_ROOT_ALREADY_EXISTS:"+file.from);
  const bytes=fs.readFileSync(src);
  const blob=crypto.createHash("sha1").update(Buffer.from("blob "+bytes.length+"\0")).update(bytes).digest("hex");
  assert.equal(blob,file.git_blob,"LEGACY_FIXTURE_SOURCE_MISMATCH:"+file.from);
  fs.mkdirSync(path.dirname(dest),{recursive:true});
  fs.writeFileSync(dest,bytes,{flag:"wx"});
}
console.log("PASS CI-ONLY preserved legacy test fixture: 463 original Git blobs restored ephemerally; not part of branch or live bundle.");
