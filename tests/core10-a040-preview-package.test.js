"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),os=require("node:os");
const {build,verify,FILES,ARTIFACT}=require("../internal/core10-a040-preview-package.js");
const root=path.resolve(__dirname,".."),tmp=fs.mkdtempSync(path.join(os.tmpdir(),"core10-a040-"));
try{
 const out=path.join(tmp,"dist"),v=build(root,out);
 assert.deepEqual(v.files,ARTIFACT);
 assert.equal(v.mode,"synthetic-read-only");
 assert.equal(v.files.length,8);
 for(const p of ["owner.html","business.html","config.js","vendor","sw.js","internal","tests","scripts"])
  assert.equal(fs.existsSync(path.join(out,p)),false,"legacy/private path leaked:"+p);
 assert.match(fs.readFileSync(path.join(out,"index.html"),"utf8"),/SIMULATED DATA ONLY/);
 assert.match(fs.readFileSync(path.join(out,"core10-stocktake-preview.html"),"utf8"),/href="index\.html"/);
 assert.deepEqual(verify(out).files,v.files);
 assert.throws(()=>build(root,out),/ARTIFACT_DEST_ALREADY_EXISTS/);
 assert.throws(()=>build(root,path.join(root,"dist")) ,/DEST_MUST_BE_OUTSIDE_SOURCE/);
 fs.appendFileSync(path.join(out,"core10-stocktake-preview.js"),"\n//tampered");
 assert.throws(()=>verify(out),/ARTIFACT_CHECKSUM_MISMATCH/);
 const fake=path.join(tmp,"fake");fs.mkdirSync(fake);
 for(const p of FILES)fs.copyFileSync(path.join(root,p),path.join(fake,p));
 fs.unlinkSync(path.join(fake,"core10-enterprise-client.js"));
 fs.symlinkSync(path.join(root,"core10-enterprise-client.js"),path.join(fake,"core10-enterprise-client.js"));
 assert.throws(()=>build(fake,path.join(tmp,"symlink")),/UNSAFE_PREVIEW_SOURCE/);
 fs.unlinkSync(path.join(fake,"core10-enterprise-client.js"));
 fs.writeFileSync(path.join(fake,"core10-enterprise-client.js"),"NO WRITE GUARD");
 assert.throws(()=>build(fake,path.join(tmp,"unlocked")),/LIVE_WRITE_LOCK_NOT_PROVEN/);
 console.log("PASS A040 isolated 8-file artifact allowlist, hash integrity, symlink and missing lock negative tests");
}finally{fs.rmSync(tmp,{recursive:true,force:true})}
