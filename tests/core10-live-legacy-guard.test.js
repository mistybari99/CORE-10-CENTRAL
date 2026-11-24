"use strict";
// Security gate: no live CORE10 source/module can access IMG-ERP config or old backend.
const assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path");
const root=path.resolve(__dirname,"..");
const live=[
"core10-owner-control-centre.css","core10-owner-control-centre-ui.js","core10-owner-control-client.js",
"core10-master-data.css","core10-master-data-client.js","core10-master-data-ui.js",
"core10-owner-dashboard.html","core10-owner-dashboard.js","core10-owner-dashboard-client.js","core10-owner-dashboard-ui.js","core10-owner-dashboard.css",
"core10-build01.html","core10-build01.css","core10-build01.js","core10-build01-client.js","core10-build01-pack02.js",
"core10-enterprise-client.js","core10-control-studio.css","vendor/supabase.js",
"core10-owner-control-centre.html","core10-owner-control-centre.js",
"core10-pack02-workspace.js","core10-pack02-workspace.css","core10-pack02-controls.js",
"docs/preview/c10-np01-canonical-reviewer-preview.html",
"internal/enterprise-client/c10_np01_reviewer_workspace_v1.mjs",
"internal/enterprise-client/c10_np01_reviewer_workspace_v1.css",
"internal/enterprise-client/c10_np01_canonical_review_client_v1.mjs"
];
const forbidden=[/(?:^|["'\s(])(?:\.\/)?config\.js(?:[?"'\s)]|$)/i,/(?:^|[\/"'`\s(])(?:\.{1,2}\/)*v2\//i,/\bBOS_CONFIG\b/,/kbuhnpqooycqbzrfejcs/i];
const reject=(content)=>forbidden.some(pattern=>pattern.test(content));
function walk(directory) {
  if(!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory,{withFileTypes:true}).flatMap(ent=>{
    const p=path.join(directory,ent.name);
    if(ent.isSymbolicLink())throw new Error("UNSAFE_MODULE_SYMLINK:"+p);
    return ent.isDirectory()?walk(p):(/\.(?:js|mjs|css|html|json)$/.test(p)?[p]:[]);
  });
}
const sources=new Set(live.map(p=>path.join(root,p)));
// The Central shell runtime is site/ plus the Worker module. Build and verify
// scripts are *not* shipped; verify.cjs itself contains intentional negative
// assertions referring to retired paths, and must never be mistaken for app code.
for(const directory of ["modules","apps/central/site"])
  for(const p of walk(path.join(root,directory)))sources.add(p);
if(fs.existsSync(path.join(root,"apps/central/worker-runtime.mjs")))
  sources.add(path.join(root,"apps/central/worker-runtime.mjs"));
// Unshipped historical CORE10 pages are NOT live: prohibit legacy loader imports,
// without misclassifying the deliberately unshipped and bundle-denied offline stocktake.
for(const name of fs.readdirSync(root).filter(p=>/^core10-.*\.html$/.test(p))) {
  const page=fs.readFileSync(path.join(root,name),"utf8");
  assert.doesNotMatch(page,/<script\b[^>]*\bsrc\s*=\s*["'](?:\.\/)?config\.js["'][^>]*>/i,
    "ROOT_CORE10_LEGACY_LOADER:"+name);
}
for(const p of sources){
  const rel=path.relative(root,p).replaceAll(path.sep,"/");
  assert.ok(fs.existsSync(p),"LIVE_SOURCE_MISSING:"+rel);
  let content=fs.readFileSync(p,"utf8");
  // §7b.3 is a Git-blob-identical shell import. Its stock module contains ONE
  // historical prose comment ("Never use legacy ..."). Retain the original bytes
  // for Worker-SHA equality, but do not treat this documented *prohibition* as an
  // executable config reference. The exception requires exact location + wording;
  // injected BOS_CONFIG in JavaScript still fails (proved by the negative below).
  if(rel==="apps/central/site/view/stock-signed.js"){
    const explanatory=" * Never use legacy BOS_CONFIG, direct table writes, shadow quantities or service role.";
    assert.equal(content.split(explanatory).length-1,1,"STOCK_SIGNED_COMMENT_DRIFT");
    content=content.replace(explanatory," * Do not use retired configuration or direct writes.");
    assert.equal(reject(content+"\nwindow.BOS_CONFIG = {}"),true,"COMMENT_EXCEPTION_RUNTIME_BYPASS");
  }
  assert.equal(reject(content),false,"LEGACY_CONFIG_LEAK:"+rel);
}
assert.equal(reject('https://storage.example/object/list-v2/bucket'),false,'Valid vendor API path must not resemble legacy v2/');
for(const forbiddenText of ['<script src="./config.js"></script>','import "../v2/foo.js"','window.BOS_CONFIG','https://kbuhnpqooycqbzrfejcs.supabase.co'])
  assert.equal(reject(forbiddenText),true,"LEGACY_GUARD_FALSE_NEGATIVE");
console.log("PASS live/module legacy config boundary: "+sources.size+" files + malicious-reference negatives");
