"use strict";
// Verification of the read-only review Worker. Local (default) or remote: REVIEW_BASE=https://... node verify.cjs
// Checks 390/1440 layout, same-origin-only network, no backend/auth calls, negative write tests,
// forbidden files absent, no secrets or legacy config in the bundle, every hub link resolves.
const assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const HERE = __dirname, ROOT = path.resolve(HERE, "../..");
const SHOTS = process.env.REVIEW_SHOTS || "";
const results = [];
async function step(name, fn) {
  try { await fn(); results.push(["PASS", name]); console.log("PASS " + name); }
  catch (e) { results.push(["FAIL", name]); console.log("FAIL " + name + " :: " + String(e.message).split("\n")[0]); }
}
const PAGES = ["/", "/live/core10-build01.html", "/live/core10-owner-control-centre.html",
  "/live/docs/preview/c10-np01-canonical-reviewer-preview.html",
  ...["universal-owner", "business-owner", "business-owner-branded", "staff", "controls-central", "controls-business"].map((f) => "/pack02.html?fx=" + f)];

(async () => {
  let server = null, base = (process.env.REVIEW_BASE || "").replace(/\/$/, "");
  if (!base) { const { serve } = await import(path.join(HERE, "local-serve.mjs")); server = await serve(0); base = "http://127.0.0.1:" + server.address().port; }
  const origin = new URL(base).origin;
  console.log("target " + base);

  await step("bundle has no secrets, JWTs, service-role or legacy config backend", async () => {
    const w = fs.readFileSync(path.join(HERE, "dist/worker.mjs"), "utf8");
    const legacyHosts = (fs.readFileSync(path.join(ROOT, "config.js"), "utf8").match(/[a-z0-9]{20}\.supabase\.co/g) || []);
    for (const h of legacyHosts) assert.ok(!w.includes(h) && !w.includes(Buffer.from(h).toString("base64").slice(0, 24)), "legacy host " + h);
    const decoded = Object.values(JSON.parse(w.split("\n").find((l) => l.startsWith("const FILES=")).slice(12, -1))).map(([, b]) => Buffer.from(b, "base64").toString("latin1")).join("\n");
    for (const h of legacyHosts) assert.ok(!decoded.includes(h), "legacy host in served file " + h);
    // Real key material only (guard code that *rejects* sb_secret_/service_role keys is expected in the source).
    assert.ok(!/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.|sb_(secret|publishable)_[A-Za-z0-9_-]{12,}|BOS_CONFIG\s*=\s*\{/.test(decoded), "key-like token in a served file");
    assert.ok(!/key:\s*"[^"]+"/.test(fs.readFileSync(path.join(ROOT, "core10-control-centre-config.js"), "utf8")), "control centre key must stay empty");
  });

  await step("HTTP: every page and asset 200 with CSP connect-src 'none' and nosniff", async () => {
    for (const p of ["/", "/review.css", "/review.js", "/pack02.html", "/pack02.js", "/pack02-fixtures.js", "/manifest.json",
      "/live/vendor/supabase.js", "/live/core10-owner-control-centre.css", "/evidence/occ-owner-1440.png"]) {
      const r = await fetch(base + p); assert.equal(r.status, 200, p);
      assert.match(r.headers.get("content-security-policy") || "", /connect-src 'none'/, p);
      assert.equal(r.headers.get("x-content-type-options"), "nosniff", p);
    }
  });

  await step("negative: POST/PUT/PATCH/DELETE refused with 405 (no write path exists)", async () => {
    for (const m of ["POST", "PUT", "PATCH", "DELETE"]) for (const p of ["/", "/rest/v1/rpc/control_set_feature_v1", "/auth/v1/token", "/live/core10-build01.html"]) {
      const r = await fetch(base + p, { method: m, headers: { "content-type": "application/json" }, body: "{}" });
      assert.equal(r.status, 405, m + " " + p); assert.match(await r.text(), /READ_ONLY_REVIEW/);
    }
  });

  await step("negative: legacy config, SQL gateway, harness and backend paths are 404", async () => {
    for (const p of ["/config.js", "/live/config.js", "/owner.html", "/live/owner.html", "/live/core10-shell.js", "/tests/control-centre/sql-gateway.cjs",
      "/live/tests/control-centre/sql-gateway.cjs", "/live/tests/control-centre/harness.html", "/rest/v1/", "/auth/v1/user", "/live/tests/control-centre/seed.sql"]) {
      assert.equal((await fetch(base + p)).status, 404, p);
    }
  });

  await step("manifest: every ACTUAL_SOURCE row matches the pinned git blob and served bytes", async () => {
    const m = await (await fetch(base + "/manifest.json")).json();
    const crypto = require("node:crypto");
    const { execFileSync } = require("node:child_process");
    const rows = m.files.filter((f) => f.kind === "ACTUAL_SOURCE"); assert.ok(rows.length >= 20);
    for (const f of rows) {
      assert.equal(execFileSync("git", ["rev-parse", m.pin + ":" + f.source], { cwd: ROOT, encoding: "utf8" }).trim(), f.git_blob, f.source);
      const body = Buffer.from(await (await fetch(base + f.route)).arrayBuffer());
      assert.equal(crypto.createHash("sha256").update(body).digest("hex"), f.sha256, f.route);
    }
  });

  const browser = await chromium.launch();
  for (const width of [390, 1440]) {
    for (const p of PAGES) {
      await step(`${width}px ${p}: loads, same-origin only, no backend/auth request, no overflow, no page error`, async () => {
        const ctx = await browser.newContext({ viewport: { width, height: width < 500 ? 844 : 900 } });
        const page = await ctx.newPage(), errors = [], foreign = [], backend = [], bad = [];
        page.on("pageerror", (e) => errors.push(e.message));
        page.on("request", (r) => { const u = r.url(); if (!u.startsWith(origin + "/") && !u.startsWith("data:") && !u.startsWith("blob:")) foreign.push(u);
          if (/\/(rest|auth|storage|functions)\/v1\//.test(u) || /supabase\.co/.test(u)) backend.push(u); });
        page.on("response", (r) => { if (r.status() >= 400) bad.push(r.status() + " " + r.url()); });
        await page.goto(base + p, { waitUntil: "load" }); await page.waitForTimeout(700);
        assert.deepEqual(foreign, []); assert.deepEqual(backend, []); assert.deepEqual(bad, []); assert.deepEqual(errors, []);
        const ov = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
        assert.ok(ov <= 1, "horizontal overflow " + ov);
        if (p === "/live/core10-owner-control-centre.html") assert.match(await page.innerText("body"), /স্টেজিং এখনো যুক্ত হয়নি/);
        if (p === "/live/core10-build01.html") assert.equal(await page.locator('#b01-login-form button[type="submit"]').isDisabled(), true, "Build01 sign-in must stay disabled");
        if (p.startsWith("/live/docs/preview")) assert.match(await page.innerText("body"), /DEMO ONLY · NO REAL AUTH/);
        if (p.startsWith("/pack02.html")) {
          assert.match(await page.innerText("body"), /FIXTURE/);
          const nav = await page.$$eval(".p2-nav-item", (b) => b.map((x) => x.disabled));
          assert.ok(nav.every(Boolean), "unwired PACK-02 nav must stay disabled");
          if (p.endsWith("=staff")) assert.ok(!/demo-second-business/.test(await page.innerText("#ws")), "staff sees sister business");
        }
        if (SHOTS) { fs.mkdirSync(SHOTS, { recursive: true }); await page.screenshot({ path: path.join(SHOTS, `${width}${p.replace(/[^a-z0-9]+/gi, "_")}.png`), fullPage: true }); }
        await ctx.close();
      });
    }
  }

  await step("in-page negative: fetch to staging, legacy host and same-origin POST are all refused", async () => {
    const page = await browser.newPage(); await page.goto(base + "/");
    const out = await page.evaluate(async () => {
      const r = {};
      for (const [k, u] of [["staging", "https://rhrqhbyzrhaafynfhdaf.supabase.co/rest/v1/"], ["self", "/rest/v1/rpc/x"]]) {
        try { const x = await fetch(u, { method: "POST", body: "{}" }); r[k] = x.status; } catch (e) { r[k] = "blocked"; }
      }
      return r;
    });
    assert.equal(out.staging, "blocked"); assert.equal(out.self, "blocked"); // connect-src 'none' blocks even same-origin
    await page.close();
  });

  await step("hub: Bangla default, English toggle, every link and image resolves", async () => {
    const page = await browser.newPage(); await page.goto(base + "/");
    assert.equal(await page.getAttribute("html", "lang"), "bn");
    await page.click('[data-set-lang="en"]'); assert.equal(await page.getAttribute("html", "lang"), "en");
    assert.ok(await page.isVisible("text=Real Build Review"));
    const refs = await page.$$eval("a[href^='/'],img[src^='/']", (els) => els.map((e) => e.getAttribute("href") || e.getAttribute("src")));
    for (const r of new Set(refs)) assert.equal((await fetch(base + r)).status, 200, r);
    await page.close();
  });

  await browser.close(); if (server) server.close();
  const failed = results.filter((r) => r[0] === "FAIL").length;
  console.log((failed ? "FAIL" : "PASS") + " CORE10 BUILD REVIEW VERIFY: " + (results.length - failed) + "/" + results.length + " @ " + base);
  process.exit(failed ? 1 : 0);
})();
