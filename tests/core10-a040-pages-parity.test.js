"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const {verify}=require("../internal/core10-pages-package.js");
const input=process.argv[2];
if(!input||!path.isAbsolute(input))throw Error("ABSOLUTE_PAGES_ARTIFACT_REQUIRED");
const dir=path.resolve(input),files=verify(dir);
for(const p of ["owner.html","core10-owner-business-entry.js","core10-stocktake-preview.html",
 "core10-stocktake-preview.css","core10-stocktake-preview.js","core10-enterprise-client.js","core10-owner-icon.svg"])
 assert.ok(files.includes(p),"MISSING_PAGES_DEMO_ASSET:"+p);
for(const p of ["internal/core10-a040-preview-package.js",
 "internal/enterprise-sql/c10_a038_stocktake_v1.sql","tests/core10-a040-preview-package.test.js",
 ".github/workflows/core10-a040-stocktake-preview-delivery.yml"])
 assert.ok(!files.includes(p),"PRIVATE_FILE_EXPOSED:"+p);
const entry=fs.readFileSync(path.join(dir,"core10-owner-business-entry.js"),"utf8");
assert.match(entry,/core10-owner-stocktake-preview/);
assert.match(entry,/state\.is_owner===true/);
const html=fs.readFileSync(path.join(dir,"core10-stocktake-preview.html"),"utf8");
assert.match(html,/DEMO DATA — NO ERP CHANGES/);
assert.match(html,/id="stage-read" disabled/);
console.log("PASS A040 full Pages allowlist parity: owner nav + demo assets present, SQL/internal omitted; NO DEPLOYMENT");
