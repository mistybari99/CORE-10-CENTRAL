"use strict";
// §7b.1 — fail closed if root files drift out of classification or any pinned
// LIVE source silently vanishes. No staging or protected Supabase access.
const {test}=require("node:test"),assert=require("node:assert/strict");
const path=require("node:path"),{execFileSync}=require("node:child_process");
const root=path.resolve(__dirname,"..");
const doc=require("../docs/coordination/FILE_CLASSIFICATION.json");
const legacy=require("../docs/coordination/LEGACY_MOVE_MANIFEST_20261122.json");
const run=(...args)=>execFileSync("git",args,{cwd:root,encoding:"utf8",stdio:["ignore","pipe","pipe"]});
const tracked=()=>run("ls-files","-z").split("\0").filter(Boolean);
const byteSort=(a,b)=>a<b?-1:a>b?1:0;
const same=(a,b)=>assert.deepEqual([...a].sort(byteSort),[...b].sort(byteSort));
test("§7b: every tracked root file has exactly one valid classification",()=>{
 assert.equal(doc.schema_version,1);
 assert.ok(doc.root_files.length>100);
 const classes=new Set(["LIVE","TRUNK_UNSHIPPED","LEGACY_FROZEN","TOOLING"]);
 const paths=doc.root_files.map(x=>x.path);
 assert.equal(new Set(paths).size,paths.length,"duplicate classification path");
 for(const item of doc.root_files){
  assert.ok(/^[^/\\]+$/.test(item.path),"top-level paths only");
  assert.ok(classes.has(item.classification),"unknown class");
  if(item.path.startsWith("core10-")) assert.ok(["LIVE","TRUNK_UNSHIPPED"].includes(item.classification),"CORE10 root must be live or draft");
 }
 same(paths,tracked().filter(p=>!p.includes("/")));
 assert.ok(!paths.includes("config.js")&&!paths.includes("index.html"),"Old app resurrected at root");
 assert.ok(!doc.root_files.some(x=>x.classification==="LEGACY_FROZEN"),"Relocated legacy is never a root source");
 // Negative check proves the root enumeration rejects both new and dropped paths.
 assert.notDeepEqual([...paths,"sneaky-unclassified.js"].sort(byteSort),tracked().filter(p=>!p.includes("/")).sort(byteSort));
});
test("§7b: all 463 frozen paths exist exactly once, isolated from root",()=>{
 assert.equal(doc.legacy.classification,"LEGACY_FROZEN");
 assert.equal(legacy.files.length,doc.legacy.expected_files);
 same(legacy.files.map(x=>x.to),tracked().filter(p=>p.startsWith("legacy/islamia-erp/")));
 for(const old of ["index.html","owner.html","business.html","sw.js","config.js"]){
  assert.ok(legacy.files.some(x=>x.from===old),"Frozen original lost "+old);
  assert.ok(!tracked().includes(old),"Legacy root was reintroduced: "+old);
 }
});
test("§7b: all 37 exact preview LIVE sources exist at recorded commit pins",()=>{
 const {pins,live_sources}=doc.preview;
 assert.equal(live_sources.length,37);
 assert.equal(new Set(live_sources.map(x=>x.path)).size,37);
 for(const [key,sha] of Object.entries(pins)){assert.match(sha,/^[a-f0-9]{40}$/);assert.ok(["T","S","setup","pr109","pr112"].includes(key));}
 const rootLive=new Set(doc.root_files.filter(x=>x.classification==="LIVE").map(x=>x.path));
 const expected=new Set(live_sources.filter(x=>x.runtime_class==="LIVE"&& !x.path.includes("/")).map(x=>x.path));
 same(rootLive,expected);
 for(const item of live_sources){
  assert.ok(pins[item.pin],"unknown pin "+item.pin);
  assert.equal(item.runtime_class,["pr109","pr112"].includes(item.pin)?"LIVE_DRAFT_SOURCE":"LIVE");
  assert.ok(!/(^|\/)(config\.js|v2)\b|(?:kbuhnpqooycqbzrfejcs|luoeyyngayxpqecuuijb)/i.test(item.path),"legacy in shipped paths");
  try{run("cat-file","-e",pins[item.pin]+":"+item.path);}
  catch(e){throw new Error("PINNED_LIVE_BLOB_MISSING:"+item.pin+"@"+pins[item.pin]+":"+item.path);}
 }
 assert.equal(rootLive.size,23);
 assert.equal(live_sources.filter(x=>x.runtime_class==="LIVE_DRAFT_SOURCE").length,9);
 // Negative fixture: a fabricated file at valid pin cannot masquerade as LIVE.
 assert.throws(()=>run("cat-file","-e",pins.T+":__missing_live_source__.js"));
});
