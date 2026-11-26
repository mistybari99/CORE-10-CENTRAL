"use strict";
// B-021 Owner Control Centre: real browser, real core10 SQL functions (disposable PostgreSQL), 390 and 1440 px.
// Requires PG* for a loopback server with the migrations applied and tests/control-centre/seed.sql loaded.
const assert = require("node:assert");
const fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const { start } = require("./sql-gateway.cjs");

const P = { own: "91111111-1111-4111-8111-111111111111", bo: "92222222-2222-4222-8222-222222222222",
  mgr: "93333333-3333-4333-8333-333333333333", stf: "95555555-5555-4555-8555-555555555555",
  out: "96666666-6666-4666-8666-666666666666", non: "97777777-7777-4777-8777-777777777777" };
const SHOTS = process.env.OCC_SHOTS || path.join(require("node:os").tmpdir(), "occ-shots");
const results = [];
async function step(name, fn) {
  try { await fn(); results.push(["PASS", name]); console.log("PASS " + name); }
  catch (e) { results.push(["FAIL", name + " :: " + String(e.message).split("\n")[0]]); console.log("FAIL " + name + " :: " + String(e.message).split("\n")[0]); }
}

(async () => {
  fs.mkdirSync(SHOTS, { recursive: true });
  const server = await start(0);
  const base = "http://127.0.0.1:" + server.address().port;
  const browser = await chromium.launch();
  async function open(persona, width, lang) {
    const ctx = await browser.newContext({ viewport: { width, height: width < 500 ? 844 : 900 }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    page.setDefaultTimeout(8000);
    page.on("pageerror", (e) => results.push(["FAIL", "page error: " + e.message]));
    await page.goto(base + "/harness.html?persona=" + persona + (lang ? "&lang=" + lang : ""));
    await page.waitForSelector("body[data-ready='1']", { timeout: 15000 });
    return page;
  }
  const status = (page) => page.textContent(".occ-status");
  const pick = async (page, key) => { await page.click(`[data-feature="${key}"]`); await page.waitForSelector("#occ-detail-title"); };
  async function confirm(page, reason) {
    await page.waitForSelector("[role=dialog]");
    if (reason) await page.fill("#occ-dialog-reason", reason);
    await page.click(".occ-dialog .occ-primary");
    await page.waitForSelector("[role=dialog]", { state: "detached" });
  }
  async function saveWith(page, reason) {
    await page.fill("#occ-reason", reason);
    await page.click("#occ-save");
    await confirm(page);
    await page.waitForFunction(() => !document.querySelector(".occ[aria-busy]"));
  }
  const rowHas = (page, key, cls) => page.$(`[data-feature="${key}"] .${cls}`);

  const own = await open(P.own, 1440, "en");
  await step("owner sees the business, its sites and the 9 baseline features", async () => {
    const keys = await own.$$eval(".occ-row", (r) => r.map((x) => x.dataset.feature));
    for (const k of ["audit.immutability", "tenant.isolation", "access.expiry_revocation", "gov002.approval_policy", "gov002.review",
      "gov003.review_export", "setup001.profile_preview", "setup001.provision", "inventory.stock_event"]) assert.ok(keys.includes(k), "missing " + k);
    assert.ok((await own.$$eval("#occ-business option", (o) => o.map((x) => x.value))).includes("9101"));
    assert.deepStrictEqual(await own.$$eval("#occ-site option", (o) => o.map((x) => x.value)), ["", "9201", "9202"]);
  });
  await step("owner switches a feature off with a reason and confirmation", async () => {
    await pick(own, "gov002.review");
    await own.uncheck("#occ-enabled");
    await saveWith(own, "Owner pauses review for the audit week");
    assert.match(await status(own), /version 1$/);
    assert.ok(await rowHas(own, "gov002.review", "occ-chip-off"));
  });
  await step("owner switches it on with two approval stages", async () => {
    await own.check("#occ-enabled");
    await own.selectOption("#occ-stages", "2");
    await saveWith(own, "Resume with two approval stages");
    assert.match(await status(own), /version 2$/);
    assert.ok(await rowHas(own, "gov002.review", "occ-chip-on"));
  });
  await step("history lists both versions and revert restores version 1 as version 3", async () => {
    await own.click("#occ-tab-history");
    assert.strictEqual(await own.$$eval(".occ-hist", (r) => r.length), 2);
    await own.click('[data-revert="1"]');
    await confirm(own, "Restore the paused state again");
    await own.waitForFunction(() => /version 3$/.test(document.querySelector(".occ-status").textContent));
    assert.ok(await rowHas(own, "gov002.review", "occ-chip-off"));
  });
  await step("audit tab shows the changes and an intact hash chain", async () => {
    await pick(own, "gov002.review");
    await own.click("#occ-tab-audit");
    await own.waitForSelector(".occ-hist");
    assert.ok((await own.$$eval(".occ-hist", (r) => r.length)) >= 3);
    assert.match(await own.textContent(".occ-panel .occ-note"), /intact/);
  });
  await step("one-time exception is granted, listed open, then revoked", async () => {
    await own.click("#occ-tab-exceptions");
    await own.fill("#occ-hours", "2");
    await own.click("#occ-grant");
    await confirm(own, "Urgent approval during the audit");
    await own.waitForSelector(".occ-chip-open");
    await own.click("[data-revoke]");
    await confirm(own, "No longer needed today");
    await own.waitForSelector(".occ-chip-revoked");
  });
  await step("site override takes effect at that site, follow-business returns to the business setting", async () => {
    await own.selectOption("#occ-site", "9201");
    await own.waitForFunction(() => !document.querySelector(".occ[aria-busy]"));
    await pick(own, "gov002.review");
    await own.check("#occ-scope-site");
    await own.check("#occ-enabled");
    await own.selectOption("#occ-stages", "3");
    await saveWith(own, "Showroom keeps three stages");
    assert.ok(await rowHas(own, "gov002.review", "occ-chip-on"));
    assert.match(await own.textContent('[data-feature="gov002.review"] .occ-chip-src'), /Site/);
    await own.check("#occ-scope-inherit");
    await saveWith(own, "Showroom follows the business again");
    assert.match(await own.textContent('[data-feature="gov002.review"] .occ-chip-src'), /Business/);
    assert.ok(await rowHas(own, "gov002.review", "occ-chip-off"));
    await own.selectOption("#occ-site", "");
    await own.waitForFunction(() => !document.querySelector(".occ[aria-busy]"));
  });
  await step("a scheduled change is stored and shown, not yet effective", async () => {
    await pick(own, "gov003.review_export");
    await own.check("#occ-enabled");
    await own.check("#occ-when-schedule");
    const at = await own.evaluate(() => { const d = new Date(Date.now() + 86400000); d.setSeconds(0, 0);
      return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16); });
    await own.fill("#occ-when-at", at);
    await saveWith(own, "Turn exports on from tomorrow");
    assert.ok(await rowHas(own, "gov003.review_export", "occ-chip-sched"));
    assert.ok(await rowHas(own, "gov003.review_export", "occ-chip-off"));
  });
  await step("an out-of-range parameter is refused by the server and shown at the field", async () => {
    await pick(own, "gov003.review_export");
    await own.fill("#occ-p-max_rows", "20000");
    await saveWith(own, "Try a very large export");
    await own.waitForSelector(".occ-field-error");
    assert.match(await own.textContent(".occ-field-error"), /max_rows/);
    assert.match(await own.textContent('label[for="occ-p-max_rows"]'), /Maximum rows/);
  });
  await step("an invariant is locked with no save, history or exception", async () => {
    await pick(own, "audit.immutability");
    assert.ok(await own.$(".occ-lock"));
    assert.strictEqual(await own.$("#occ-save"), null);
    assert.strictEqual(await own.$$eval(".occ-tabs [role=tab]", (t) => t.length), 1);
  });
  await step("a change made elsewhere is detected, reloaded, and the retry succeeds", async () => {
    await pick(own, "gov002.review");
    const r = await fetch(base + "/rpc/control_set_v1", { method: "POST", headers: { "content-type": "application/json", "x-test-persona": P.bo },
      body: JSON.stringify({ p_business: 9101, p_site: null, p_feature: "gov002.review", p_enabled: true, p_stages: 1, p_params: {},
        p_effective_from: null, p_inherit: false, p_expected_version: 3, p_reason: "Business owner changes it meanwhile", p_request_key: "occ_bo_concurrent_1" }) });
    assert.strictEqual(r.status, 200);
    await own.check("#occ-enabled");
    await saveWith(own, "Owner saves on an old screen");
    assert.strictEqual(await own.getAttribute(".occ-status", "data-kind"), "error");
    assert.match(await status(own), /Someone else changed this/);
    await saveWith(own, "Owner saves again after reload");
    assert.match(await status(own), /version 5$/);
  });
  await step("language switches between Bangla and English", async () => {
    await own.click("#occ-lang");
    assert.strictEqual(await own.textContent("h1"), "মালিক নিয়ন্ত্রণ কেন্দ্র");
    await own.click("#occ-lang");
    assert.strictEqual(await own.textContent("h1"), "Owner Control Centre");
  });
  await step("every form control has a label; status is live; dialog is modal and Escape closes it", async () => {
    await pick(own, "gov002.review");
    const unlabeled = await own.$$eval(".occ input, .occ select, .occ textarea", (els) => els.filter((e) =>
      !e.getAttribute("aria-label") && !(e.id && document.querySelector(`label[for="${e.id}"]`)) && !e.closest("label")).map((e) => e.id || e.type));
    assert.deepStrictEqual(unlabeled, []);
    assert.strictEqual(await own.getAttribute(".occ-status", "aria-live"), "polite");
    await own.fill("#occ-reason", "Open and close the dialog");
    await own.click("#occ-save");
    assert.strictEqual(await own.getAttribute("[role=dialog]", "aria-modal"), "true");
    await own.keyboard.press("Escape");
    await own.waitForSelector("[role=dialog]", { state: "detached" });
  });
  await own.screenshot({ path: path.join(SHOTS, "owner-1440.png"), fullPage: true });

  const mob = await open(P.own, 390, "bn");
  await step("390 px: no horizontal scrolling, list and detail stack, dialog fits", async () => {
    await pick(mob, "gov002.review");
    assert.ok(await mob.evaluate(() => document.documentElement.scrollWidth <= 390));
    await mob.fill("#occ-reason", "মোবাইল থেকে যাচাই");
    await mob.click("#occ-save");
    const w = await mob.$eval(".occ-dialog", (d) => d.getBoundingClientRect().width);
    assert.ok(w <= 390, "dialog width " + w);
    await mob.screenshot({ path: path.join(SHOTS, "owner-390-dialog.png") });
    await mob.keyboard.press("Escape");
    assert.ok(await mob.evaluate(() => document.documentElement.scrollWidth <= 390));
  });
  await mob.screenshot({ path: path.join(SHOTS, "owner-390.png"), fullPage: true });

  for (const [who, persona] of [["manager", P.mgr], ["site staff", P.stf]]) {
    const pg = await open(persona, 1440, "en");
    await step(who + " sees view-only controls without history, exceptions or audit", async () => {
      assert.ok(await pg.$("#occ-view-only"));
      await pick(pg, "gov002.review");
      assert.strictEqual(await pg.$("#occ-save"), null);
      assert.ok(await pg.$eval("#occ-enabled", (e) => e.disabled));
      assert.strictEqual(await pg.$$eval(".occ-tabs [role=tab]", (t) => t.length), 1);
      assert.deepStrictEqual(await pg.$$eval("#occ-business option", (o) => o.map((x) => x.value)), ["9101"]);
    });
    if (who === "manager") await pg.screenshot({ path: path.join(SHOTS, "manager-1440.png"), fullPage: true });
  }
  const out = await open(P.out, 1440, "en");
  await step("a foreign tenant owner sees only their own business", async () => {
    assert.deepStrictEqual(await out.$$eval("#occ-business option", (o) => o.map((x) => x.value)), ["9102"]);
    assert.strictEqual(await out.$("#occ-view-only"), null);
  });
  const non = await open(P.non, 390, "bn");
  await step("an account with no access gets the empty state", async () => {
    assert.ok(await non.$("#occ-no-business"));
  });
  const anon = await (await browser.newContext()).newPage();
  await anon.goto(base + "/harness.html?lang=en");
  await anon.waitForSelector("body[data-ready='1']");
  await step("without a session the page shows the sign-in error and no data", async () => {
    assert.match(await anon.textContent(".occ-status"), /sign in/i);
    assert.strictEqual(await anon.$(".occ-row"), null);
  });

  await browser.close();
  server.close();
  const failed = results.filter((r) => r[0] === "FAIL").length;
  console.log((failed ? "FAIL" : "PASS") + " OWNER CONTROL CENTRE BROWSER: " + (results.length - failed) + "/" + results.length + " · screenshots in " + SHOTS);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
