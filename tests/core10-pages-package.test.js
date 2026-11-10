"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path"),os=require("node:os");
const {build,verify,isAllowed,REQUIRED}=require("../internal/core10-pages-package");
const home=fs.mkdtempSync(path.join(os.tmpdir(),"c10-pages-test-"));
const src=path.join(home,"repo"),out=path.join(home,"site");
function put(rel,body="safe") {
 const f=path.join(src,rel);fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,body);
}
try {
 for(const p of REQUIRED) put(p);
 for(const p of ["app.js","config.js","vendor/supabase.js","data/report_registry.json","experimental/owner-console/index.html","v2/js/safe.js","v2/styles/site.css"]) put(p);
 for(const p of ["scripts/tenant_migration.sql","scripts/c10_a018_demo_backend.sql","tests/secret.js","internal/secret.js","internal/enterprise-sql/private.sql","docs/handover.md",".github/workflows/ci.yml","experimental/owner-console/private.md","v2/scripts/danger.sql","v2/audit-unsafe.html","setup-admin.html","audit-private.html","data/secret.env","vendor/file.map"]) put(p,"DO_NOT_PUBLISH");
 assert.equal(isAllowed("scripts/c10_a018_demo_backend.sql"),false);
 assert.equal(isAllowed("v2/scripts/danger.sql"),false);
 assert.equal(isAllowed("setup-admin.html"),false);
 assert.equal(isAllowed("vendor/supabase.js"),true);
 const result=build(src,out);
 assert.equal(result.count,REQUIRED.length+7);
 assert.deepEqual(verify(out),result.files);
 for(const p of ["scripts/tenant_migration.sql","scripts/c10_a018_demo_backend.sql","tests/secret.js","internal/secret.js","internal/enterprise-sql/private.sql","docs/handover.md","v2/scripts/danger.sql","v2/audit-unsafe.html","setup-admin.html","data/secret.env","vendor/file.map"]) assert.equal(fs.existsSync(path.join(out,p)),false,p+" leaked");
 assert.equal(fs.readFileSync(path.join(out,"vendor/supabase.js"),"utf8"),"safe");
 assert.throws(()=>build(src,out),/DIST_ALREADY_EXISTS/);
 assert.throws(()=>build(src,path.join(src,"dist")) ,/DIST_MUST_BE_OUTSIDE_REPO/);
 put("vendor/follow.js");fs.symlinkSync(path.join(src,"scripts","tenant_migration.sql"),path.join(src,"vendor","leak.js"));
 assert.throws(()=>build(src,path.join(home,"other")) ,/SYMLINK_IN_PUBLISH_SCOPE/);
 fs.unlinkSync(path.join(src,"vendor","leak.js"));
 fs.unlinkSync(path.join(out,"owner.html"));
 assert.throws(()=>verify(out),/PUBLISHED_ASSET_MISSING/);
 put("vendor/hijack.js");
 fs.writeFileSync(path.join(out,"vendor","exploit.sql"),"unsafe");
 assert.throws(()=>verify(out),/FORBIDDEN_PUBLISHED_ASSET/);
 // Release pipeline contract: only the disabled template may refer to deploy-pages.
 const repoRoot=path.resolve(__dirname,"..");
 const disabled=path.join(repoRoot,".github/workflows/pages-dist.yml.disabled");
 assert.ok(fs.existsSync(disabled),"Disabled release template missing");
 assert.equal(fs.existsSync(path.join(repoRoot,".github/workflows/pages-dist.yml")),false,
   "Never activate Pages release without verifying GitHub Actions publishing source");
 const template=fs.readFileSync(disabled,"utf8");
 assert.match(template,/node internal\/core10-pages-package\.js/);
 assert.match(template,/node tests\/core10-pages-artifact-http\.test\.js/);
 assert.doesNotMatch(template,/cp -r|mkdir dist|path:\\s*\\./);
 console.log("PASS C10-A018 Pages allowlist: required parity, safe assets, SQL exclusion, symlink, modified artifact and idempotent output guards");
} finally {fs.rmSync(home,{recursive:true,force:true});}
