"use strict";
// C10-A040: isolated offline-review Stocktake demo, never a Pages/production deploy.
// Only synthetic assets. No owner.html, config.js, SQL, Auth, real data, or tokens.
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto");
const FILES=Object.freeze(["core10-stocktake-preview.html","core10-stocktake-preview.css",
 "core10-stocktake-preview.js","core10-enterprise-client.js","core10-owner-icon.svg"]);
const ARTIFACT=Object.freeze([".nojekyll","index.html","manifest.json",...FILES].sort());
const INDEX=[
'<!doctype html><html lang="en"><head><meta charset="utf-8">',
'<meta name="viewport" content="width=device-width,initial-scale=1">',
'<meta name="robots" content="noindex,nofollow">',
'<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; base-uri \'none\'; form-action \'none\'; frame-ancestors \'none\'">',
'<title>CORE 10 CENTRAL — Stocktake Demo</title>',
'<style>body{font:16px/1.6 system-ui,sans-serif;background:#edf4f7;color:#143343;max-width:680px;margin:12vh auto;padding:30px}main{border-radius:18px;background:#fff;border:1px solid #d6e5e9;padding:30px}h1{line-height:1.2}.note{padding:14px;background:#fff6e6;color:#77500c;border-radius:10px}a{display:inline-block;background:#087f8c;color:#fff;padding:12px 20px;border-radius:10px;font-weight:700;text-decoration:none}a:focus-visible{outline:3px solid #d49425;outline-offset:3px}</style>',
'</head><body><main><h1>CORE 10 CENTRAL — Stocktake demo</h1>',
'<p class="note"><strong>SIMULATED DATA ONLY.</strong> No account, real stock, production database, or payment is connected. This build is a review artifact, not an ERP release.</p>',
'<p>Inspect the Staff count, Owner review, variance dashboard and local audit demonstration.</p>',
'<p><a href="core10-stocktake-preview.html">Open interactive Stocktake Demo</a></p>',
'</main></body></html>'
].join("\n");
function hash(buf){return crypto.createHash("sha256").update(buf).digest("hex")}
function names(dir){return fs.readdirSync(dir,{withFileTypes:true}).map(e=>{
 if(!e.isFile()||e.isSymbolicLink())throw Error("ARTIFACT_UNEXPECTED_ENTRY:"+e.name);
 return e.name;
}).sort()}
function verify(dest){
 const dir=path.resolve(dest),current=names(dir);
 if(JSON.stringify(current)!==JSON.stringify(ARTIFACT))throw Error("ARTIFACT_ALLOWLIST_MISMATCH");
 const manifest=JSON.parse(fs.readFileSync(path.join(dir,"manifest.json"),"utf8"));
 if(manifest.mode!=="synthetic-read-only"||
   JSON.stringify(Object.keys(manifest.sha256).sort())!==JSON.stringify(["index.html",...FILES].sort()))
  throw Error("ARTIFACT_MANIFEST_INVALID");
 for(const name of ["index.html",...FILES])
  if(hash(fs.readFileSync(path.join(dir,name)))!==manifest.sha256[name])
   throw Error("ARTIFACT_CHECKSUM_MISMATCH:"+name);
 if(fs.readFileSync(path.join(dir,".nojekyll"),"utf8")!=="")throw Error("ARTIFACT_NOJEKYLL_INVALID");
 const html=fs.readFileSync(path.join(dir,"core10-stocktake-preview.html"),"utf8");
 if(!html.includes("DEMO DATA — NO ERP CHANGES")||!html.includes('id="stage-read" disabled')||
   !html.includes('href="index.html"')||html.includes('href="owner.html"'))
  throw Error("ARTIFACT_STOCKTAKE_DEMO_ONLY_BOUNDARY_FAILED");
 if(!fs.readFileSync(path.join(dir,"core10-enterprise-client.js"),"utf8")
    .includes("C10_A038_REAL_AUTH_AND_OWNER_RELEASE_REQUIRED"))
  throw Error("ARTIFACT_WRITE_LOCK_NOT_PRESENT");
 return Object.freeze({mode:manifest.mode,files:current,checksums:manifest.sha256})
}
function build(root,dest){
 const source=path.resolve(root),out=path.resolve(dest);
 if(out===source||out.startsWith(source+path.sep))throw Error("DEST_MUST_BE_OUTSIDE_SOURCE");
 if(fs.existsSync(out))throw Error("ARTIFACT_DEST_ALREADY_EXISTS");
 const contents={};
 for(const name of FILES){
  const filename=path.join(source,name),st=fs.lstatSync(filename);
  if(!st.isFile()||st.isSymbolicLink())throw Error("UNSAFE_PREVIEW_SOURCE:"+name);
  contents[name]=fs.readFileSync(filename);
 }
 const html=contents["core10-stocktake-preview.html"].toString("utf8");
 const back='href="owner.html"';
 if(html.split(back).length!==2)throw Error("PREVIEW_BACKLINK_CHANGED");
 contents["core10-stocktake-preview.html"]=Buffer.from(html.replace(back,'href="index.html"'),"utf8");
 if(!html.includes("DEMO DATA — NO ERP CHANGES")||!html.includes('id="stage-read" disabled')||
   !contents["core10-enterprise-client.js"].toString("utf8").includes("C10_A038_REAL_AUTH_AND_OWNER_RELEASE_REQUIRED"))
  throw Error("LIVE_WRITE_LOCK_NOT_PROVEN");
 const output={"index.html":Buffer.from(INDEX,"utf8"),...contents};
 const manifest={mode:"synthetic-read-only",contract:"C10-A040",sha256:{}};
 for(const [name,buf] of Object.entries(output))manifest.sha256[name]=hash(buf);
 fs.mkdirSync(out,{recursive:true});
 for(const [name,buf] of Object.entries(output))fs.writeFileSync(path.join(out,name),buf,{flag:"wx"});
 fs.writeFileSync(path.join(out,".nojekyll"),"",{flag:"wx"});
 fs.writeFileSync(path.join(out,"manifest.json"),JSON.stringify(manifest,null,2)+"\n",{flag:"wx"});
 return verify(out)
}
if(require.main===module){
 try{
  if(!process.argv[2]||!path.isAbsolute(process.argv[2]))throw Error("ABSOLUTE_ARTIFACT_OUTPUT_REQUIRED");
  const result=build(path.resolve(__dirname,".."),process.argv[2]);
  console.log("PASS C10-A040: "+result.files.length+" isolated synthetic assets; NO PROD/STAGING/DEPLOYMENT");
 }catch(e){console.error("FAIL C10-A040:",e.message);process.exitCode=1}
}
module.exports={build,verify,FILES,ARTIFACT,INDEX};
