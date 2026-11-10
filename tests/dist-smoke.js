// Smoke test for dist/. Run: node tools/build_dist.js && NODE_PATH=$(npm root -g) node tests/dist-smoke.js
// Serves dist/ on localhost (applying the /* block of dist/_headers, so the real CSP is enforced).
"use strict";
const https = require("https"), cp = require("child_process"), os = require("os"), fs = require("fs"), path = require("path"), assert = require("node:assert/strict");
const { chromium } = require("playwright");
const DIST = path.resolve(__dirname, "..", "dist");
assert.ok(fs.existsSync(path.join(DIST, "index.html")), "run node tools/build_dist.js first");
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".svg": "image/svg+xml", ".webp": "image/webp", ".webmanifest": "application/manifest+json", ".wasm": "application/wasm", ".txt": "text/plain" };
// Global headers from the "/*" block of _headers.
const globalHdr = {};
{
  let on = false;
  for (const l of fs.readFileSync(path.join(DIST, "_headers"), "utf8").split("\n")) {
    if (/^\S/.test(l) && !l.startsWith("#")) on = l.trim() === "/*";
    else if (on && /^\s+[A-Za-z-]+:/.test(l)) { const i = l.indexOf(":"); globalHdr[l.slice(0, i).trim()] = l.slice(i + 1).trim(); }
  }
}
// swreg.js only registers the service worker over https, so serve https with a throwaway self-signed cert.
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "dist-smoke-"));
cp.execFileSync("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", path.join(tmp, "k.pem"), "-out", path.join(tmp, "c.pem"), "-days", "1", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1"], { stdio: "ignore" });
const server = https.createServer({ key: fs.readFileSync(path.join(tmp, "k.pem")), cert: fs.readFileSync(path.join(tmp, "c.pem")) }, (req, res) => {
  let p = decodeURIComponent(new URL(req.url, "http://x").pathname);
  if (p.endsWith("/")) p += "index.html";
  const f = path.join(DIST, p);
  if (!f.startsWith(DIST + path.sep) || !fs.existsSync(f) || !fs.statSync(f).isFile()) { res.writeHead(404); return res.end("nf"); }
  res.writeHead(200, { ...globalHdr, "Content-Type": TYPES[path.extname(f)] || "application/octet-stream" });
  fs.createReadStream(f).pipe(res);
});

(async () => {
  await new Promise(r => server.listen(0, "127.0.0.1", r));
  const base = "https://localhost:" + server.address().port + "/";
  const browser = await chromium.launch({ args: ["--ignore-certificate-errors"] });
  let failures = 0;
  const ok = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); if (!c) failures++; };
  try {
    const ctx = await browser.newContext({ ignoreHTTPSErrors: true });
    const page = await ctx.newPage();
    const errors = [];
    page.on("pageerror", e => errors.push("pageerror: " + e.message));
    page.on("console", m => { if (m.type() === "error" && !/Failed to load resource.*(supabase|googleapis|gstatic)/.test(m.text()) && !/ERR_(NAME_NOT_RESOLVED|INTERNET_DISCONNECTED|TUNNEL|CONNECTION|FAILED)/.test(m.text()) && !/Failed to load resource/.test(m.text())) errors.push("console: " + m.text()); });
    await page.goto(base + "index.html", { waitUntil: "load" });
    await page.waitForTimeout(2500);
    const login = await page.evaluate(() => !!document.querySelector("input[type=password], input[type=email], #login, [id*=login i], form") && document.body.innerText.trim().length > 0);
    ok(login, "login page renders (form/input + text present)");
    ok(errors.length === 0, "0 page errors / CSP violations" + (errors.length ? ": " + errors.join(" | ") : ""));

    // Every local <script src>/<link href> in index.html returns 200 from dist.
    const html = fs.readFileSync(path.join(DIST, "index.html"), "utf8");
    const urls = [...html.matchAll(/<(?:script|link)\b[^>]*?\s(?:src|href)="([^"#]+)"/g)].map(m => m[1]).filter(u => !/^(https?:)?\/\//.test(u));
    let bad = [];
    for (const u of urls) { const r = await ctx.request.get(base + u); if (r.status() !== 200) bad.push(u + " " + r.status()); }
    ok(urls.length > 5 && !bad.length, `all ${urls.length} local script/link refs return 200` + (bad.length ? ": " + bad.join(", ") : ""));
    for (const p of ["owner.html", "business.html", "sw.js", "_headers", "data/kb.json", "robots.txt"]) {
      const r = await ctx.request.get(base + p);
      if (p === "_headers") ok(r.status() !== 0, "_headers present in dist (served here as file; Cloudflare consumes it)");
      else ok(r.status() === 200, p + " returns 200");
    }

    // Service worker registers; app opens offline after first load.
    const swReady = await page.evaluate(async () => { try { const r = await Promise.race([navigator.serviceWorker.ready, new Promise((_, j) => setTimeout(() => j(new Error("timeout")), 15000))]); return !!r.active; } catch (e) { return String(e); } });
    ok(swReady === true, "service worker registers and activates (" + swReady + ")");
    await page.waitForTimeout(3000); // let precache settle
    await page.reload({ waitUntil: "load" }); // now controlled by the SW
    await page.waitForTimeout(1500);
    await ctx.setOffline(true);
    const off = await ctx.newPage();
    const offErrors = [];
    off.on("pageerror", e => offErrors.push(e.message));
    let offOk = false;
    try {
      await off.goto(base + "index.html", { waitUntil: "load", timeout: 20000 });
      await off.waitForTimeout(1500);
      offOk = await off.evaluate(() => document.body && document.body.innerText.trim().length > 0 && !!document.querySelector("form, input, button"));
    } catch (e) { console.log("offline error: " + e.message); }
    ok(offOk && !offErrors.length, "app opens offline after first load" + (offErrors.length ? ": " + offErrors.join(" | ") : ""));
    await ctx.setOffline(false);

    // Negative: forbidden file types are not reachable.
    const neg = ["internal/DEPLOY_CHECKLIST.md", "internal/setup-all.html", "internal/CORE10_SECURITY_PREFLIGHT.sql", "internal/", "tests/dist-smoke.js", "docs/development/CURRENT_HANDOFF.md", ".github/workflows/core10-double-audit.yml", "design/", "security/", "v2/app.js", "CLAUDE.md", "README.md", "tools/build_dist.js", ".gitignore"];
    const reach = [];
    for (const n of neg) { const r = await ctx.request.get(base + n); if (r.status() === 200) reach.push(n); }
    ok(!reach.length, "forbidden paths not reachable" + (reach.length ? ": " + reach.join(", ") : ""));
    const stray = [];
    (function w(d) { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) w(p); else if (/\.(sql|md)$|(^|\/)(setup|audit)-[^/]*\.html$/.test(path.relative(DIST, p))) stray.push(path.relative(DIST, p)); } })(DIST);
    ok(!stray.length, "no *.sql/*.md/setup-*/audit-* files in dist/");
  } catch (e) { console.error(e); failures++; }
  await browser.close(); server.close(); fs.rmSync(tmp, { recursive: true, force: true });
  console.log(failures ? `\n${failures} FAILED` : "\nALL PASSED");
  process.exit(failures ? 1 : 0);
})();
