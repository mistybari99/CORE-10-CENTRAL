"use strict";
// B-011 Master Data: real Chromium, real core10 SQL functions in a disposable PostgreSQL, 390 and 1440 px, bn and en.
// Requires PG* for a loopback server with the migrations applied and tests/control-centre/md-seed.sql loaded.
const assert = require("node:assert");
const fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const { start } = require("./sql-gateway.cjs");

const P = { own: "c1111111-1111-4111-8111-111111111111", mgr: "c3333333-3333-4333-8333-333333333333",
  other: "c6666666-6666-4666-8666-666666666666", none: "c7777777-7777-4777-8777-777777777777" };
const SHOTS = process.env.MD_SHOTS || path.join(require("node:os").tmpdir(), "md-shots");
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
    await page.goto(base + "/md-harness.html?persona=" + persona + (lang ? "&lang=" + lang : ""));
    await page.waitForSelector("body[data-ready='1']", { timeout: 15000 });
    return page;
  }
  const noOverflow = async (page) => assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), "horizontal overflow");
  const rows = (page) => page.$$eval(".occ-list .occ-row", (b) => b.length);

  for (const width of [390, 1440]) {
    await step(`owner ${width}px bn: catalog, paging, detail, NOT_CONNECTED, no overflow`, async () => {
      const page = await open(P.own, width);
      assert.match(await page.textContent("h1"), /মাস্টার ডেটা/);
      assert.match(await page.textContent("[data-state=NOT_CONNECTED]"), /B-012/);
      assert.strictEqual(await rows(page), 50, "first page is 50");
      await page.click("text=আরও দেখুন"); await page.waitForFunction(() => document.querySelectorAll(".occ-list .occ-row").length === 56);
      assert.strictEqual(await page.$("text=আরও দেখুন"), null, "no more pages");
      await page.click(".occ-row:has-text('রসগোল্লা')"); await page.waitForSelector(".occ-detail h2");
      const d = await page.textContent(".occ-detail");
      assert.match(d, /8901234567890/); assert.match(d, /RETAIL/); assert.match(d, /LARGE/);
      await noOverflow(page);
      await page.screenshot({ path: path.join(SHOTS, `md-owner-${width}-bn.png`), fullPage: true });
      await page.context().close();
    });
  }

  await step("owner 1440px en: search by barcode, units tab with conversion, price list detail", async () => {
    const page = await open(P.own, 1440, "en");
    assert.match(await page.textContent("h1"), /Master Data/);
    await page.fill("input[type=search]", "8901234567890"); await page.press("input[type=search]", "Enter");
    await page.waitForFunction(() => document.querySelectorAll(".occ-list .occ-row").length === 1);
    await page.click("[data-tab=units]"); await page.waitForSelector(".occ-row:has-text('BOX')");
    await page.click(".occ-row:has-text('BOX')"); assert.match(await page.textContent(".occ-detail"), /12/);
    await page.click("[data-tab=prices]"); await page.click(".occ-row:has-text('RETAIL')");
    await page.waitForSelector(".occ-detail .md-table"); assert.match(await page.textContent(".occ-detail"), /RASGULLA/);
    await page.screenshot({ path: path.join(SHOTS, "md-owner-1440-en-prices.png"), fullPage: true });
    await page.context().close();
  });

  await step("owner creates a party, then edits it (version 1 -> 2)", async () => {
    const page = await open(P.own, 390, "en");
    await page.click("[data-tab=parties]"); await page.click("text=New party");
    const f = page.locator("form.occ-panel");
    await f.getByLabel("Code").fill("S-777"); await f.getByLabel("Kind").selectOption("supplier");
    await f.getByLabel("Name (English)").fill("Sugar Mill"); await f.getByLabel("Name (Bangla)").fill("চিনিকল");
    await f.locator("button[type=submit]").click();
    await page.waitForSelector(".occ-detail h2:has-text('Sugar Mill')");
    assert.match(await page.textContent(".occ-detail .occ-meta"), /Version 1/);
    await page.click(".occ-detail button:has-text('Edit')");
    await page.locator("form.occ-panel").getByLabel("Phone").fill("+880 1711-000000");
    await page.locator("form.occ-panel button[type=submit]").click();
    await page.waitForSelector(".occ-detail .occ-meta:has-text('Version 2')");
    await noOverflow(page); await page.context().close();
  });

  await step("duplicate SKU is refused with a clear message (no row created)", async () => {
    const page = await open(P.own, 1440, "en");
    await page.click("text=New item");
    const f = page.locator("form.occ-panel");
    await f.getByLabel("SKU").fill("RASGULLA"); await f.getByLabel("Name (English)").fill("Dup");
    await f.locator("button[type=submit]").click();
    await page.waitForSelector("form.occ-panel .occ-field-error:has-text('MASTER_DUPLICATE')");
    await page.context().close();
  });

  await step("stale edit from a second tab is refused (optimistic version)", async () => {
    const a = await open(P.own, 1440, "en"), b = await open(P.own, 1440, "en");
    for (const p of [a, b]) { await p.click(".occ-row:has-text('Bulk item 1')"); await p.click(".occ-detail button:has-text('Edit')"); }
    await a.locator("form.occ-panel").getByLabel("Name (English)").fill("Bulk item 1 (A)"); await a.locator("form.occ-panel button[type=submit]").click();
    await a.waitForSelector(".occ-detail h2:has-text('Bulk item 1 (A)')");
    await b.locator("form.occ-panel").getByLabel("Name (English)").fill("Bulk item 1 (B)"); await b.locator("form.occ-panel button[type=submit]").click();
    await b.waitForSelector("form.occ-panel .occ-field-error:has-text('MASTER_STALE_OR_MISSING')");
    await a.context().close(); await b.context().close();
  });

  await step("manager reads but gets no create/edit controls", async () => {
    const page = await open(P.mgr, 390);
    assert.ok((await rows(page)) > 0);
    assert.strictEqual(await page.$("text=নতুন পণ্য"), null);
    await page.click(".occ-row:has-text('রসগোল্লা')"); await page.waitForSelector(".occ-detail h2");
    assert.strictEqual(await page.$(".occ-detail button:has-text('সম্পাদনা')"), null);
    await page.context().close();
  });

  await step("other tenant never sees this business's data", async () => {
    const page = await open(P.other, 1440, "en");
    const txt = await page.textContent("body");
    assert.ok(!/RASGULLA|Rasgulla|8901234567890/.test(txt), "foreign data leaked");
    await page.context().close();
  });

  await step("no-membership user sees no business and no data", async () => {
    const page = await open(P.none, 390, "en");
    assert.ok(!/RASGULLA|Rasgulla/.test(await page.textContent("body")));
    await page.context().close();
  });

  await browser.close(); server.close();
  const failed = results.filter((r) => r[0] === "FAIL");
  console.log(`MASTER_DATA_BROWSER ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length) { failed.forEach((f) => console.log(f[1])); process.exit(1); }
})().catch((e) => { console.error(e); process.exit(1); });
