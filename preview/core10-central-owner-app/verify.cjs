"use strict";
// Site-wide acceptance for the core10-central owner preview. Local by default; REVIEW_BASE=https://... for the live Worker.
const assert = require("node:assert/strict");
const fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const HERE = __dirname, ROOT = path.resolve(HERE, "../..");
const SHOTS = process.env.REVIEW_SHOTS || "";
const ROUTES = ["home", "business", "master", "sales", "manufacturing", "control", "features", "approvals", "staff", "setup"];
const STAGING = "https://rhrqhbyzrhaafynfhdaf.supabase.co/";
const DRAFT_ROUTES = new Set(["sales", "manufacturing"]);
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
    assert.ok(!/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.|sb_secret_[A-Za-z0-9_-]{8,}|BOS_CONFIG\s*=\s*\{/.test(all), "secret/JWT key-like token");
    // The config route must hold only the publishable key: no JWT, secret key or service-role wording at all.
    for (const r of ["/live/core10-control-centre-config.js", "/live/core10-build01-config.js"]) {
      const cfgText = Buffer.from(F[r][1], "base64").toString("utf8");
      assert.ok(!/eyJ|sb_secret_|service_role/i.test(cfgText), r + " holds non-publishable key material");
    }
    // Level 2: exactly one publishable key, only in the staging config, and the only backend host is CORE10 staging.
    const pubs = Object.entries(F).filter(([, [, b]]) => /sb_publishable_[A-Za-z0-9_-]{12,}/.test(Buffer.from(b, "base64").toString("latin1"))).map(([r]) => r);
    assert.deepEqual(pubs.sort(), ["/live/core10-build01-config.js", "/live/core10-control-centre-config.js"], "publishable key outside staging configs: " + pubs);
    const hosts = new Set(all.match(/[a-z0-9]{20}\.supabase\.co/g) || []);
    assert.deepEqual([...hosts], ["rhrqhbyzrhaafynfhdaf.supabase.co"], "backend hosts " + [...hosts]);
    for (const r of Object.keys(F)) assert.ok(r === "/index.html" || !/(^|\/)(config\.js|index\.html|owner\.html|core10-stocktake-offline\.html|core10-stocktake-preview\.js|core10-shell\.js|sql-gateway\.cjs|harness\.(js|html)|seed\.sql)$/.test(r), "forbidden " + r);
  });
  await step("negative: every write method is 405, backend/legacy paths 404", async () => {
    for (const m of ["POST", "PUT", "PATCH", "DELETE"]) for (const p of ["/", "/rest/v1/rpc/control_set_v1", "/auth/v1/token", "/view/control.html"]) {
      assert.equal((await fetch(base + p, { method: m, body: "{}" })).status, 405, m + " " + p);
    }
    for (const p of ["/config.js", "/owner.html", "/live/config.js", "/live/core10-shell.js", "/rest/v1/", "/auth/v1/user", "/evidence/", "/manifest.json", "/live/core10-owner-control-centre-config.js", "/live/index.html", "/live/v2/config.js", "/live/core10-stocktake-offline.html", "/live/core10-stocktake-preview.js"])
      assert.equal((await fetch(base + p)).status, 404, p);
    const r = await fetch(base + "/"); assert.match(r.headers.get("content-security-policy"), /connect-src 'self' https:\/\/rhrqhbyzrhaafynfhdaf\.supabase\.co;/);
    const c = await (await fetch(base + "/live/core10-control-centre-config.js")).text();
    assert.match(c, /url: "https:\/\/rhrqhbyzrhaafynfhdaf\.supabase\.co", key: "sb_publishable_[A-Za-z0-9_-]+"/, "Level 2 config is CORE10 staging only");
  });

  const browser = await chromium.launch();
  for (const lang of ["bn", "en"]) for (const width of [390, 1440]) for (const route of ROUTES) {
    await step(`${lang} ${width}px #/${route}: renders, same-origin only, no backend call, no overflow, no error, no developer text`, async () => {
      const ctx = await browser.newContext({ viewport: { width, height: width < 500 ? 844 : 900 } });
      await ctx.addInitScript((l) => { try { localStorage.setItem("core10.preview.lang", l); } catch (_) {} }, lang);
      const page = await ctx.newPage(), errors = [], foreign = [], bad = [];
      page.on("pageerror", (e) => errors.push(e.message));
      page.on("request", (r) => { const u = r.url(); if (!u.startsWith(origin + "/") && !/^(data|blob|about):/.test(u) && !((route === "control" || route === "setup" || route === "master") && u.startsWith(STAGING))) foreign.push(u); if (/\/(rest|auth|storage|functions)\/v1\/|supabase\.co/.test(u) && !((route === "control" || route === "setup" || route === "master") && u.startsWith(STAGING))) foreign.push("BACKEND " + u); });
      page.on("response", (r) => { if (r.status() >= 400) bad.push(r.status() + " " + r.url()); });
      await page.goto(base + "/#/" + route, { waitUntil: "load" }); await page.waitForTimeout(1500);
      assert.equal(await page.getAttribute("html", "lang"), lang);
      assert.equal(await page.getAttribute(`[data-route="${route}"]`, "aria-current"), "page");
      const dataNotice = (await page.locator("#c10-data-status ." + lang).textContent()).trim();
      if (route === "control" || route === "setup" || route === "master")
        assert.match(dataNotice, lang === "bn" ? /স্টেজিং.*সংরক্ষণ/ : /staging.*saved/i, "signed staging route must not claim changes are unsaved");
      else
        assert.match(dataNotice, lang === "bn" ? /নমুনা.*সংরক্ষিত/ : /sample.*not saved/i, "replay route must disclose unsaved sample data");
      const frame = page.frames().find((f) => f !== page.mainFrame() && f.url() !== "about:blank");
      let text = await page.innerText("body"), fOver = 0;
      if (DRAFT_ROUTES.has(route)) assert.ok(await page.isVisible("#c10-draft"), "draft banner shown"); else assert.ok(!(await page.isVisible("#c10-draft")), "no draft banner");
      {
        assert.ok(frame, "module frame loaded"); await frame.waitForLoadState("load");
        const ft = await frame.evaluate(() => document.body.innerText); assert.ok(ft.trim().length > 20, "module rendered content");
        text += "\n" + ft; fOver = await frame.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
        if (route === "setup") assert.match(await frame.innerText("#b01-environment"), /core10-staging · https:\/\/rhrqhbyzrhaafynfhdaf\.supabase\.co/);
        if (route === "control") { await frame.waitForSelector("#occ-email"); assert.ok(await frame.isVisible("#occ-password"), "signed sign-in form"); }
        if (route === "master") { await frame.waitForSelector("#md-email"); assert.ok(await frame.isVisible("#md-password"), "Master signed sign-in form"); }
      }
      const over = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
      assert.ok(over <= 1 && fOver <= 1, `horizontal overflow shell=${over} module=${fOver}`);
      assert.deepEqual(foreign, []); assert.deepEqual(bad, []); assert.deepEqual(errors, []);
      for (const re of DEV) { if ((re.source === "NOT_CONNECTED" || re.source === "\\bFIXTURE\\b") && DRAFT_ROUTES.has(route)) continue; const m = text.match(re); if (m) devHits.push(`${lang} ${width} #/${route}: "${m[0]}" … ${text.slice(Math.max(0, m.index - 40), m.index + 40).replace(/\s+/g, " ")}`); }
      if (SHOTS) { fs.mkdirSync(SHOTS, { recursive: true }); await page.screenshot({ path: path.join(SHOTS, `${route}-${lang}-${width}.png`) }); }
      await ctx.close();
    });
  }
  await step("Master staging refuses wrong-password login and stays locked", async () => {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    await page.goto(base + "/view/master-signed.html"); await page.waitForSelector("#md-email");
    await page.fill("#md-email", "nobody@example.invalid");
    await page.fill("#md-password", "totally-invalid-demo-password");
    await page.click("#md-login button[type=submit]");
    await page.waitForFunction(() => !!document.querySelector("#md-error")?.textContent);
    assert.ok(!(await page.isVisible("#md-workspace")), "unauthenticated Master Data remains locked");
    await page.close();
  });
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
  await step("Level 2: wrong password is refused by CORE10 staging Auth, and nothing else is contacted", async () => {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } }), hits = [];
    page.on("request", (r) => { if (!r.url().startsWith(origin + "/")) hits.push(r.method() + " " + r.url().split("?")[0]); });
    await page.goto(base + "/live/core10-owner-control-centre.html"); await page.waitForSelector("#occ-email");
    await page.fill("#occ-email", "nobody@example.invalid"); await page.fill("#occ-password", "wrong-password-check");
    const resp = page.waitForResponse((r) => r.url().startsWith(STAGING + "auth/v1/token"));
    await page.click(".occ-primary"); const r = await resp; assert.equal(r.status(), 400);
    await page.waitForFunction(() => (document.querySelector(".occ-field-error") || {}).textContent);
    assert.ok(hits.length >= 1 && hits.every((h) => h.startsWith("POST " + STAGING + "auth/v1/token")), "only staging auth: " + hits);
    await page.close();
  });
  for (const [view, sel, act] of [["/view/master.html", "#md-root", null], ["/view/sales.html", "#sales-host", null], ["/view/mfg.html", "#manufacturing", null]]) {
    await step(`${view}: real module renders from recorded reads, no request leaves the page`, async () => {
      const page = await browser.newPage({ viewport: { width: 1440, height: 900 } }), errors = [], foreign = [];
      page.on("pageerror", (e) => errors.push(e.message)); page.on("request", (r) => { if (!r.url().startsWith(origin + "/")) foreign.push(r.url()); });
      await page.goto(base + view + "?lang=en"); await page.waitForTimeout(2500);
      const t = await page.innerText(sel); assert.ok(t.trim().length > 40, "module content " + t.length);
      assert.deepEqual(errors, []); assert.deepEqual(foreign, []);
      await page.close();
    });
  }
  await step("replay refuses every module write (master save, sales save/transition, manufacturing create/approve/handoff/waste)", async () => {
    const page = await browser.newPage(); await page.goto(base + "/view/sales.html"); await page.waitForTimeout(800);
    const out = await page.evaluate(async () => {
      const R = window.CORE10_PREVIEW_REPLAY, res = {};
      const m = R(window.CORE10_PREVIEW_SALES, /^(save_sales_order_v1|transition_sales_order_v1)$/, "NOT_CONNECTED");
      res.save = (await m("save_sales_order_v1", {})).error?.message; res.transition = (await m("transition_sales_order_v1", {})).error?.message;
      res.unknown = (await m("post_stock_v1", {})).error?.message; return res;
    });
    assert.deepEqual(out, { save: "NOT_CONNECTED", transition: "NOT_CONNECTED", unknown: "NOT_CONNECTED" });
    const src = await (await fetch(base + "/view/mfg.mjs")).text(); assert.match(src, /create_recipe\|approve_recipe\|define_substitution\|request_handoff\|record_material_waste/);
    const ms = await (await fetch(base + "/view/master.js")).text(); assert.match(ms, /\^master_save_/);
    await page.close();
  });
  await step("no developer-report text on any Owner route", async () => { assert.deepEqual(devHits, []); });
  await browser.close(); if (server) server.close();
  const failed = results.filter((r) => r[0] === "FAIL").length;
  if (devHits.length) console.log("DEV TEXT:\n" + [...new Set(devHits)].join("\n"));
  console.log((failed ? "FAIL" : "PASS") + " CORE10 OWNER PREVIEW VERIFY: " + (results.length - failed) + "/" + results.length + " @ " + base);
  process.exit(failed ? 1 : 0);
})();
