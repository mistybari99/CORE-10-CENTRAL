"use strict";
// B-012 Owner dashboard: real Chromium, real core10 SQL read functions in a disposable PostgreSQL, 390 and 1440 px, bn and en.
// Requires PG* for a loopback server with the migrations applied and tests/control-centre/od-seed.sql loaded.
const assert = require("node:assert");
const fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const { start } = require("./sql-gateway.cjs");
const P = { own: "a8811111-1111-4111-8111-111111111111", mgr: "a8833333-3333-4333-8333-333333333333",
  other: "a8855555-5555-4555-8555-555555555555", none: "a8877777-7777-4777-8777-777777777777" };
const SHOTS = process.env.OD_SHOTS || path.join(require("node:os").tmpdir(), "od-shots");
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
    const page = await ctx.newPage(); page.setDefaultTimeout(8000);
    page.on("pageerror", (e) => results.push(["FAIL", "page error: " + e.message]));
    page.on("console", (m) => { if (m.type() === "error" && !/status of 400/.test(m.text())) results.push(["FAIL", "console error: " + m.text()]); });
    await page.goto(base + "/od-harness.html?persona=" + persona + (lang ? "&lang=" + lang : ""));
    await page.waitForSelector("body[data-ready='1']", { timeout: 15000 });
    return page;
  }
  const noOverflow = async (page) => assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), "horizontal overflow");
  const siteRows = (page) => page.$$eval(".md-table tbody tr", (b) => b.length);

  for (const width of [390, 1440]) {
    await step(`owner ${width}px bn: all businesses, drill to business and site, paging, no overflow`, async () => {
      const page = await open(P.own, width);
      assert.match(await page.textContent("h1"), /মালিকের ড্যাশবোর্ড/);
      assert.strictEqual(await page.$$eval(".od-card", (c) => c.length), 3, "three businesses");
      const body = await page.textContent("body");
      assert.match(body, /বিক্রি ও নগদ: এখনো যুক্ত নয়/, "short not-connected line");
      assert.ok(!/NP0|B-0|PR #|CI |NOT_CONNECTED/.test(body), "no developer references on the screen");
      assert.match(await page.textContent(".od-card[data-business='8811']"), /৬০/, "60 sites in Bangla digits");
      await noOverflow(page);
      await page.screenshot({ path: path.join(SHOTS, `od-portfolio-${width}-bn.png`), fullPage: true });
      await page.click(".od-card[data-business='8811']"); await page.waitForSelector(".md-table");
      assert.strictEqual(await siteRows(page), 50, "first page of sites");
      await page.click("text=আরও দেখুন"); await page.waitForFunction(() => document.querySelectorAll(".md-table tbody tr").length === 60);
      await page.click("[data-kind=factory]"); await page.waitForFunction(() => document.querySelectorAll(".md-table tbody tr").length === 1);
      await noOverflow(page);
      await page.screenshot({ path: path.join(SHOTS, `od-business-${width}-bn.png`), fullPage: true });
      await page.click("[data-site='881101']"); await page.waitForSelector("h2:has-text('Central factory')");
      const d = await page.textContent(".od-main");
      assert.match(d, /চিনি/); assert.match(d, /চিনি কল/); assert.match(d, /স্থানান্তর/);
      await noOverflow(page);
      await page.screenshot({ path: path.join(SHOTS, `od-site-${width}-bn.png`), fullPage: true });
      await page.click(".od-crumbs button:has-text('misti-sweets')"); await page.waitForSelector(".md-table");
      await page.click(".od-crumbs button:has-text('সব ব্যবসা')"); await page.waitForSelector(".od-card");
      await page.context().close();
    });
  }
  await step("owner 1440px en: English labels and figures", async () => {
    const page = await open(P.own, 1440, "en");
    assert.match(await page.textContent("h1"), /Owner dashboard/);
    const card = await page.textContent(".od-card[data-business='8811']");
    assert.match(card, /Open purchase orders1/); assert.match(card, /Total quantity565/); assert.match(card, /Waiting for approval0/);
    assert.match(await page.textContent("body"), /Sales and cash: not connected yet/);
    await page.click("text=বাংলা"); assert.match(await page.textContent("h1"), /মালিকের ড্যাশবোর্ড/);
    await page.context().close();
  });
  await step("manager 390px: only the business they manage, no approval figure", async () => {
    const page = await open(P.mgr, 390);
    assert.strictEqual(await page.$$eval(".od-card", (c) => c.length), 1);
    const card = await page.textContent(".od-card");
    assert.match(card, /rong-paint/); assert.ok(!/অনুমোদনের অপেক্ষায়/.test(card), "no approval count for a manager");
    await page.context().close();
  });
  await step("other tenant: sees only its own business", async () => {
    const page = await open(P.other, 1440);
    assert.strictEqual(await page.$$eval(".od-card", (c) => c.length), 1);
    assert.match(await page.textContent(".od-card"), /other-co/);
    assert.ok(!/misti-sweets/.test(await page.textContent("body")));
    await page.context().close();
  });
  await step("account with no business gets the empty state", async () => {
    const page = await open(P.none, 390);
    assert.match(await page.textContent("body"), /আপনার দেখার মতো কোনো ব্যবসা নেই/);
    await page.context().close();
  });
  await step("without a session the page shows the sign-in error and no data", async () => {
    const page = await open("", 390);
    assert.match(await page.textContent(".occ-status"), /সাইন-ইন প্রয়োজন/);
    assert.strictEqual(await page.$(".od-card"), null);
    await page.context().close();
  });
  await browser.close(); server.close();
  const failed = results.filter((r) => r[0] !== "PASS");
  const passed = results.length - failed.length;
  if (failed.length) { console.log("FAIL OWNER DASHBOARD BROWSER: " + passed + "/" + results.length); failed.forEach((f) => console.log(f[1])); process.exit(1); }
  console.log("PASS OWNER DASHBOARD BROWSER: " + passed + "/" + results.length + " · screenshots in " + SHOTS);
})().catch((e) => { console.error(e); process.exit(1); });
