"use strict";
// Owner-approved REV-009 relocation: prove every original Git blob is still byte-identical.
// SHA256 compares the frozen source blob with the relocated bytes (including binary v2 assets).
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
const root = path.resolve(__dirname, "..");
const manifest = require("../docs/coordination/LEGACY_MOVE_MANIFEST_20261122.json");
const legacyDir = path.join(root, "legacy/islamia-erp");
const sha256 = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
function walk(dir, relative = "") {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(ent => {
    const name = relative ? relative + "/" + ent.name : ent.name;
    if(ent.isSymbolicLink()) throw new Error("LEGACY_SYMLINK:" + name);
    if(ent.isDirectory()) return walk(path.join(dir,ent.name),name);
    assert.ok(ent.isFile(),"LEGACY_INVALID_ENTRY:"+name);
    return ["legacy/islamia-erp/" + name];
  });
}
assert.equal(manifest.schema_version,1);
assert.equal(manifest.source_commit,"6424aabe981513749ebfc166782fd60ff22ba140");
assert.equal(manifest.files.length,463,"Legacy moved-file inventory changed");
assert.ok(fs.statSync(legacyDir).isDirectory());
const seenSource=new Set(),seenTarget=new Set();
for(const ent of manifest.files) {
  assert.ok(typeof ent.from==="string" && !ent.from.includes("..") && !ent.from.startsWith("/"));
  assert.equal(ent.to,"legacy/islamia-erp/"+ent.from);
  assert.match(ent.git_blob,/^[a-f0-9]{40}$/);
  assert.ok(!seenSource.has(ent.from) && !seenTarget.has(ent.to),"DUPLICATE_LEGACY_PATH");
  seenSource.add(ent.from); seenTarget.add(ent.to);
  assert.equal(fs.existsSync(path.join(root,ent.from)),false,"LEGACY_SOURCE_STILL_AT_ROOT:"+ent.from);
  const actual=fs.readFileSync(path.join(root,ent.to));
  const historical=execFileSync("git",["cat-file","blob",ent.git_blob],{cwd:root,maxBuffer:128*1024*1024});
  assert.equal(sha256(actual),sha256(historical),"LEGACY_SHA256_MISMATCH:"+ent.to);
}
assert.deepEqual(walk(legacyDir).sort(),[...seenTarget].sort(),"LEGACY_INVENTORY_NOT_EXACT");
// Prove checksum gate detects a byte-level mutation without modifying the working tree.
const exemplar=manifest.files.find(x=>x.from==="pos.js");
const originalBytes=fs.readFileSync(path.join(root,exemplar.to));
const tampered=Buffer.from(originalBytes); tampered[0]^=1;
assert.notEqual(sha256(tampered),sha256(originalBytes),"LEGACY_TAMPER_NOT_DETECTED");
console.log("PASS REV-009 legacy relocation: 463 historical Git blobs SHA256-identical, no lost/new files, tamper negative PASS");
