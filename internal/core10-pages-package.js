"use strict";
// C10-A018 / REV-009: build a separate Pages artifact; NEVER publish the repo tree.
// This is packaging only. Pages SOURCE must be switched to GitHub Actions and verified
// before enabling the release workflow; green artifact CI is not proof of that switch.
const fs = require("node:fs");
const path = require("node:path");
const ROOT_EXT = new Set([".html",".js",".css",".json",".webmanifest",".svg",".png",".jpg",".jpeg",".webp",".ico",".gif",".woff",".woff2",".txt"]);
const DIR_EXT = new Map([
  ["data",new Set([".json",".svg",".png",".webp"])],
  ["vendor",new Set([".js",".css",".svg",".png",".jpg",".jpeg",".webp",".ico",".woff",".woff2"])],
  ["legacy/islamia-erp",ROOT_EXT],
  ["experimental/owner-console",ROOT_EXT]
]);
const REQUIRED = ["legacy/islamia-erp/index.html","legacy/islamia-erp/owner.html","legacy/islamia-erp/business.html","legacy/islamia-erp/sw.js","legacy/islamia-erp/v2/index.html","legacy/islamia-erp/v2/sw.js"];
const DENY = /(^|\/)(?:scripts|tests|internal|security|docs|design|\.github|node_modules)(?:\/|$)|(^|\/)(?:setup-|audit-)[^/]*\.html$|\.(?:sql|md|map|env|pem|key|bak|log)$/i;
function safeRelative(rel) {
  if (!rel || rel.startsWith("/") || rel.includes("\\") || rel.split("/").some(s=>!s||s==="."||s===".."||s.startsWith("."))) return false;
  return !DENY.test(rel);
}
function isAllowed(rel) {
  if (rel === "legacy/islamia-erp/.build-id" || rel === "legacy/islamia-erp/v2/.build-id") return true;
  if (!safeRelative(rel)) return false;
  const parts=rel.split("/");
  if(parts.length===1) return ROOT_EXT.has(path.extname(rel).toLowerCase()) || ["robots.txt"].includes(rel);
  for(const [dir,extensions] of DIR_EXT) {
    if(rel.startsWith(dir+"/")) return extensions.has(path.extname(rel).toLowerCase());
  }
  return false;
}
function listFiles(dir, rel="", out=[]) {
  if (!fs.existsSync(path.join(dir,rel))) return out;
  for (const ent of fs.readdirSync(path.join(dir,rel), {withFileTypes:true})) {
    const next=rel?rel+"/"+ent.name:ent.name;
    if(ent.isSymbolicLink()) throw new Error("SYMLINK_IN_PUBLISH_SCOPE:"+next);
    if(ent.isDirectory()) listFiles(dir,next,out);
    else if(ent.isFile()) out.push(next);
    else throw new Error("UNSUPPORTED_PUBLISH_ENTRY:"+next);
  }
  return out;
}
function collect(root) {
  const out=[];
  for(const name of fs.readdirSync(root)) {
    const abs=path.join(root,name), st=fs.lstatSync(abs);
    if(st.isSymbolicLink()) {
      if(isAllowed(name)) throw new Error("SYMLINK_IN_PUBLISH_SCOPE:"+name);
      continue;
    }
    if(st.isFile() && isAllowed(name)) out.push(name);
  }
  for(const dir of DIR_EXT.keys()) {
    const abs=path.join(root,dir);
    if(fs.existsSync(abs)) {
      if(!fs.lstatSync(abs).isDirectory()) throw new Error("INVALID_ASSET_DIRECTORY:"+dir);
      out.push(...listFiles(root,dir).filter(isAllowed));
    }
  }
  out.sort();
  for(const name of REQUIRED) if(!out.includes(name)) throw new Error("MISSING_REQUIRED_PAGES_ASSET:"+name);
  return out;
}
// §7c: legacy pages keep their frozen bytes but still load shared root assets by relative path
// (e.g. core10-shell.js, vendor/supabase.js). Mirror exactly those referenced, allowed root files next
// to the legacy pages inside the ARTIFACT only (repo tree unchanged).
const LEGACY_DIRS=["legacy/islamia-erp","legacy/islamia-erp/v2"];
function legacyMirror(root,files) {
  const have=new Set(files), out=[];
  for(const dir of LEGACY_DIRS) {
    const abs=path.join(root,dir);
    if(!fs.existsSync(abs)) continue;
    const refs=[];
    for(const page of fs.readdirSync(abs).filter(n=>n.endsWith(".html"))) {
      const html=fs.readFileSync(path.join(abs,page),"utf8");
      for(const m of html.matchAll(/<(?:script|link)\b[^>]*?\b(?:src|href)=["']([^"'#?]+)/gi)) refs.push(m[1]);
    }
    if(fs.existsSync(path.join(abs,"sw.js"))) {
      const pre=/PRECACHE=\[([^\]]*)\]/.exec(fs.readFileSync(path.join(abs,"sw.js"),"utf8"));
      if(pre) for(const m of pre[1].matchAll(/"([^"#?]+)/g)) refs.push(m[1]);
    }
    {
      for(const ref of refs) {
        if(/^(?:[a-z]+:|\/)/i.test(ref)||!safeRelative(ref)) continue;
        const dest=dir+"/"+ref;
        if(have.has(dest)||!isAllowed(ref)||!isAllowed(dest)) continue;
        if(!fs.existsSync(path.join(root,ref))||!fs.lstatSync(path.join(root,ref)).isFile()) continue;
        have.add(dest); out.push([dest,ref]);
      }
    }
  }
  return out.sort((x,y)=>x[0]<y[0]?-1:1);
}
function verify(destination) {
  const allFiles=listFiles(destination);
  if (!allFiles.includes(".nojekyll")) throw new Error("PAGES_NOJEKYLL_MISSING");
  const files=allFiles.filter(name=>name!==".nojekyll");
  for(const name of files) if(!isAllowed(name)) throw new Error("FORBIDDEN_PUBLISHED_ASSET:"+name);
  for(const name of REQUIRED) if(!files.includes(name)) throw new Error("PUBLISHED_ASSET_MISSING:"+name);
  return files.sort();
}
function build(repoRoot,destination) {
  const root=path.resolve(repoRoot), out=path.resolve(destination);
  if(out===root||out.startsWith(root+path.sep)) throw new Error("DIST_MUST_BE_OUTSIDE_REPO");
  if(fs.existsSync(out)) throw new Error("DIST_ALREADY_EXISTS");
  const files=collect(root);
  fs.mkdirSync(out,{recursive:true});
  const mirror=legacyMirror(root,files);
  for(const [name,src] of [...files.map(f=>[f,f]),...mirror]) {
    const dest=path.join(out,name);
    fs.mkdirSync(path.dirname(dest),{recursive:true});
    fs.copyFileSync(path.join(root,src),dest,fs.constants.COPYFILE_EXCL);
  }
  fs.writeFileSync(path.join(out,".nojekyll"),"");
  const verified=verify(out);
  if(verified.length!==files.length+mirror.length) throw new Error("PUBLISH_MANIFEST_COUNT_MISMATCH");
  return {count:verified.length,files:verified,mirrored:mirror.map(([d])=>d)};
}
if(require.main===module) {
  const destination=process.argv[2];
  if(!destination) { console.error("Usage: node internal/core10-pages-package.js <absolute-output-outside-repo>"); process.exit(2); }
  try {
    const result=build(path.resolve(__dirname,".."),destination);
    console.log("PASS Pages artifact allowlist:",result.count,"safe files; excluded scripts/tests/internal/docs");
    console.log("NOTE: artifact readiness only. Release blocked until Pages source is verified as GitHub Actions.");
  } catch(err) { console.error("FAIL Pages artifact:",err.message); process.exitCode=1; }
}
module.exports={build,verify,collect,isAllowed,legacyMirror,REQUIRED};
