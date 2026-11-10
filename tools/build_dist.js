#!/usr/bin/env node
// Builds dist/ from an ALLOWLIST of app files (no dependencies). Run from anywhere: node tools/build_dist.js
// Filenames are preserved exactly (sw.js PRECACHE uses relative names such as core.js?v=...).
//
// v2/ decision: NOT copied. index.html/owner.html/business.html, sw.js and every root *.js contain no
// reference to "v2/" (grep verified); it is a legacy copy of the app. Add it to DIRS only if that changes.
// data/: every file in data/ is fetched by the app (info.json, kb.json, item_dictionary.json,
// report_registry.json, seed_item_mapping.json); the build verifies each is referenced from a root *.js.
"use strict";
const fs = require("fs"), path = require("path");

const ROOT = path.resolve(__dirname, "..");
const DIST = path.join(ROOT, "dist");
const HEADERS_SRC = path.join(ROOT, "public-headers", "_headers");

const PAGES = ["index.html", "owner.html", "business.html"];
const ROOT_EXT = /\.(js|css|svg|webp|webmanifest)$/;
const ROOT_JSON = ["manifest.json", "bundle-manifest.json"];
const ROOT_EXTRA = ["robots.txt"];
const DIRS = ["vendor", "data"];
const FORBIDDEN_DIRS = ["internal", "design", "security", "tests", "docs", ".github", "v2", "tools", "public-headers"];
const FORBIDDEN_FILE = /\.(sql|md)$|(^|\/)setup-[^/]*\.html$|(^|\/)audit-[^/]*\.html$|(^|\/)\.env/i;

const fail = m => { console.error("BUILD FAILED: " + m); process.exit(1); };
const rel = p => path.relative(DIST, p).split(path.sep).join("/");

function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p)); else out.push(p);
  }
  return out;
}

// 1. Collect allowlisted files (path relative to repo root).
const files = new Set();
for (const p of PAGES) { if (!fs.existsSync(path.join(ROOT, p))) fail("missing page " + p); files.add(p); }
for (const f of fs.readdirSync(ROOT)) {
  if (fs.statSync(path.join(ROOT, f)).isFile() && ROOT_EXT.test(f) && !FORBIDDEN_FILE.test(f)) files.add(f);
}
for (const f of [...ROOT_JSON, ...ROOT_EXTRA, "sw.js"]) { if (!fs.existsSync(path.join(ROOT, f))) fail("missing " + f); files.add(f); }
for (const d of DIRS) {
  if (!fs.existsSync(path.join(ROOT, d))) fail("missing dir " + d);
  for (const f of walk(path.join(ROOT, d))) {
    const r = path.relative(ROOT, f).split(path.sep).join("/");
    if (!FORBIDDEN_FILE.test(r)) files.add(r);
  }
}

// 2. Every local reference in the HTML pages must be in the allowlist.
const missing = [];
for (const p of PAGES) {
  const html = fs.readFileSync(path.join(ROOT, p), "utf8");
  for (const m of html.matchAll(/<(?:script|link)\b[^>]*?\s(?:src|href)="([^"#]+)"/g)) {
    const u = m[1];
    if (/^(https?:)?\/\//.test(u) || u.startsWith("data:")) continue;
    const f = u.split("?")[0];
    if (!files.has(f)) missing.push(p + " -> " + u);
  }
}
// sw.js PRECACHE entries too.
const sw = fs.readFileSync(path.join(ROOT, "sw.js"), "utf8");
const pc = sw.match(/PRECACHE=\[([^\]]*)\]/);
if (pc) for (const m of pc[1].matchAll(/"([^"]+)"/g)) { if (!files.has(m[1].split("?")[0])) missing.push("sw.js PRECACHE -> " + m[1]); }
// data/ files must be referenced by app code (sanity: nothing unused slips in).
for (const f of files) {
  if (!f.startsWith("data/")) continue;
  const hit = fs.readdirSync(ROOT).filter(x => x.endsWith(".js")).some(x => fs.readFileSync(path.join(ROOT, x), "utf8").includes(f));
  if (!hit) missing.push("data file not referenced by any root js (remove or justify): " + f);
}
if (missing.length) fail("references not satisfied by allowlist:\n  " + missing.join("\n  "));

// 3. _headers CSP must equal index.html <meta> CSP + frame-ancestors 'none'.
if (!fs.existsSync(HEADERS_SRC)) fail("missing public-headers/_headers");
const hdr = fs.readFileSync(HEADERS_SRC, "utf8");
const metaCsp = (fs.readFileSync(path.join(ROOT, "index.html"), "utf8").match(/http-equiv="Content-Security-Policy"\s+content="([^"]+)"/) || [])[1];
const hdrCsp = (hdr.match(/^\s*Content-Security-Policy:\s*(.+)$/m) || [])[1];
if (!metaCsp) fail("no CSP <meta> in index.html");
if (!hdrCsp) fail("no CSP in _headers");
if (hdrCsp.trim() !== metaCsp.trim() + "; frame-ancestors 'none'") fail("_headers CSP differs from index.html <meta> CSP (+ frame-ancestors 'none'); update public-headers/_headers");

// 4. Copy.
fs.rmSync(DIST, { recursive: true, force: true });
fs.mkdirSync(DIST, { recursive: true });
for (const f of [...files].sort()) {
  const to = path.join(DIST, f);
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.copyFileSync(path.join(ROOT, f), to);
}
fs.copyFileSync(HEADERS_SRC, path.join(DIST, "_headers"));

// 5. Safety net: forbidden content in dist/ fails the build.
const bad = [];
for (const f of walk(DIST)) {
  const r = rel(f);
  if (FORBIDDEN_FILE.test(r) || FORBIDDEN_DIRS.some(d => r === d || r.startsWith(d + "/"))) bad.push(r);
}
if (bad.length) { fs.rmSync(DIST, { recursive: true, force: true }); fail("forbidden files in dist:\n  " + bad.join("\n  ")); }

// 6. Manifest.
let total = 0;
const all = walk(DIST).map(f => { const s = fs.statSync(f).size; total += s; return [rel(f), s]; }).sort((a, b) => a[0] < b[0] ? -1 : 1);
for (const [n, s] of all) console.log(String(s).padStart(10) + "  " + n);
console.log(`\ndist/: ${all.length} files, ${(total / 1048576).toFixed(2)} MiB (${total} bytes)`);
if (all.length > 20000) fail("Cloudflare Pages free limit is 20,000 files");
if (all.some(([, s]) => s > 25 * 1048576)) fail("a file exceeds Cloudflare Pages 25 MiB per-file limit");
