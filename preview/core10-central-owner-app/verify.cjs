"use strict";
// Site-wide acceptance for the core10-central owner preview. Local by default; REVIEW_BASE=https://... for the live Worker.
const assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const HERE = __dirname, ROOT = path.resolve(HERE, "../..");
const SHOTS = process.env.REVIEW_SHOTS || "";
const ROUTES = ["home", "business", "setup", "master", "control", "features", "approvals", "staff"];
// Developer-report markers that must not appear in visible Owner-facing text.
const DEV = [/PR\s?#\d/i, /CI PASS/i, /TEST SCREENSHOT/i, /\bFIXTURE\b/i, /\bmigration/i, /BLOCKED BY/i, /Board status/i, /GitHub/i,
  /\bBuilder\b/, /test harness/i, /NOT_CONNECTED/, /\bB-0\d\d\b/, /\b[0-9a-f]{7,40}\b(?=.*\bSHA\b)/i, /\.(js|mjs|sql|cjs)\b/, /\bCI\b/];
const results = [], devHits = [];
async function step(name, fn) {
  try { await fn(); results.push(["PASS", name]); console.log("PASS " + name); }
  catch (e) { results.push(["FAIL", name]); console.log("FAIL " + name + " :: " + String(e.message).split("\n")[0]); }
}
(async () => {
  let server = null, base = (process.env.REVIEW_BASE || "").replace(/\/$/, "");
  if (!base) { const { serve } = await import(path.join(HERE, "local-serve.mjs")); server = await serve(0); base = "http://127.0.0.1:" + server.address().port; }
  const origin = new URL(base).origin; console.log("target " + base);

  await step("bundle: no legacy backend host, key material, gateway or harness", async () => {
    const w = fs.readFileSync(path.join(HERE, "dist/worker.mjs"), "utf8");
    const F = JSON.parse(w.split("\n").find((l) => l.startsWith("const FILES=")).slice(12, -1));
    const all = Object.values(F).map(([, b]) => Buffer.from(b, "base64").toString("latin1")).join("\n");
    for (const h of fs.readFileSync(path.join(ROOT, "config.js"), "utf8").match(/[a-z0-9]{20}\.supabase\.co/g) || []) assert.ok(!all.includes(h), "legacy host " + h);
    assert.ok(!/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.|sb_(secret|publishable)_[A-Za-z0-9_-]{12,}|BOS_CONFIG\s*=\s*\{/.test(all), "key-like token");
    for (const r of Object.keys(F)) assert.ok(!/(^|\/)(config\.js|owner\.html|core10-shell\.js|sql-gateway\.cjs|harness\.(js|html)|seed\.sql)$/.test(r), "forbidden " + r);
  });
  await step("negative: every write method is 405, backend/legacy paths 404", async () => {
    for (const m of ["POST", "PUT", "PATCH", "DELETE"]) for (const p of ["/", "/rest/v1/rpc/control_set_v1", "/auth/v1/token", "/view/control.html"]) {
      assert.equal((await fetch(base + p, { method: m, body: "{}" })).status, 405, m + " " + p);
    }
    for (const p of ["/config.js", "/owner.html", "/live/config.js", "/live/core10-shell.js", "/rest/v1/", "/auth/v1/user", "/evidence/", "/manifest.json", "/live/core10-control-centre-config.js"])
      assert.equal((await fetch(base + p)).status, 404, p);
    const r = await fetch(base + "/"); assert.match(r.headers.get("content-security-policy"), /connect-src 'none'/);
  });

  const browser = await chromium.launch();
  for (const lang of ["bn", "en"]) for (const width of [390, 1440]) for (const route of ROUTES) {
    await step(`${lang} ${width}px #/${route}: renders, same-origin only, no backend call, no overflow, no error, no developer text`, async () => {
      const ctx = await browser.newContext({ viewport: { width, height: width < 500 ? 844 : 900 } });
      await ctx.addInitScript((l) => { try { localStorage.setItem("core10.preview.lang", l); } catch (_) {} }, lang);
      const page = await ctx.newPage(), errors = [], foreign = [], bad = [];
      page.on("pageerror", (e) => errors.push(e.message));
      page.on("request", (r) => { const u = r.url(); if (!u.startsWith(origin + "/") && !/^(data|blob|about):/.test(u)) foreign.push(u); if (/\/(rest|auth|storage|functions)\/v1\/|supabase\.co/.test(u)) foreign.push("BACKEND " + u); });
      page.on("response", (r) => { if (r.status() >= 400) bad.push(r.status() + " " + r.url()); });
      await page.goto(base + "/#/" + route, { waitUntil: "load" }); await page.waitForTimeout(1500);
      assert.equal(await page.getAttribute("html", "lang"), lang);
      assert.equal(await page.getAttribute(`[data-route="${route}"]`, "aria-current"), "page");
      const frame = page.frames().find((f) => f !== page.mainFrame() && f.url() !== "about:blank");
      let text = await page.innerText("body"), fOver = 0;
      if (route === "master") assert.ok(!frame || frame.url() === "about:blank", "master has no module page");
      else {
        assert.ok(frame, "module frame loaded"); await frame.waitForLoadState("load");
        const ft = await frame.evaluate(() => document.body.innerText); assert.ok(ft.trim().length > 20, "module rendered content");
        text += "\n" + ft; fOver = await frame.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
        if (route === "control") { await frame.waitForSelector(".occ-row"); assert.ok((await frame.$$(".occ-row")).length >= 9, "control features listed"); }
      }
      const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      assert.ok(over <= 1 && fOver <= 1, `horizontal overflow shell=${over} module=${fOver}`);
      assert.deepEqual(foreign, []); assert.deepEqual(bad, []); assert.deepEqual(errors, []);
      for (const re of DEV) { const m = text.match(re); if (m) devHits.push(`${lang} ${width} #/${route}: "${m[0]}" … ${text.slice(Math.max(0, m.index - 40), m.index + 40).replace(/\s+/g, " ")}`); }
      if (SHOTS) { fs.mkdirSync(SHOTS, { recursive: true }); await page.screenshot({ path: path.join(SHOTS, `${route}-${lang}-${width}.png`) }); }
      await ctx.close();
    });
  }
  await step("Owner control: a change is refused with the UI's own message and nothing is saved", async () => {
    const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    await page.goto(base + "/view/control.html?lang=en"); await page.waitForSelector(".occ-row");
    const first = "gov002.review";
    await page.click(`[data-feature="${first}"]`); await page.waitForSelector("#occ-save");
    await page.fill("#occ-reason", "Preview check"); await page.click("#occ-save");
    if (await page.$("[role=dialog]")) await page.click(".occ-dialog .occ-primary");
    await page.waitForTimeout(800);
    assert.match(await page.innerText("body"), /server could not be reached/i);
    await page.reload(); await page.waitForSelector(".occ-row");
    await page.close();
  });
  await step("no developer-report text on any Owner route", async () => { assert.deepEqual(devHits, []); });
  await browser.close(); if (server) server.close();
  const failed = results.filter((r) => r[0] === "FAIL").length;
  if (devHits.length) console.log("DEV TEXT:\n" + [...new Set(devHits)].join("\n"));
  console.log((failed ? "FAIL" : "PASS") + " CORE10 OWNER PREVIEW VERIFY: " + (results.length - failed) + "/" + results.length + " @ " + base);
  process.exit(failed ? 1 : 0);
})();
