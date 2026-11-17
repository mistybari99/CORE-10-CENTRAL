"use strict";
// B-011 Master Data: real Chromium, real core10 SQL functions in a disposable PostgreSQL, 390 and 1440 px, bn and en.
// Requires PG* for a loopback server with the migrations applied and tests/control-centre/md-seed.sql loaded.
const assert = require("node:assert");
const fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const { start } = require("./sql-gateway.cjs");
const { spawnSync } = require("node:child_process");
const sql = (q) => { const r = spawnSync("psql", ["-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"], { input: q, encoding: "utf8", env: process.env }); if (r.status !== 0) throw Error(r.stderr); return r.stdout.trim(); };

const P = { own: "c1111111-1111-4111-8111-111111111111", bo: "c2222222-2222-4222-8222-222222222222", mgr: "c3333333-3333-4333-8333-333333333333",
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
  async function open(persona, width, lang, biz) {
    const ctx = await browser.newContext({ viewport: { width, height: width < 500 ? 844 : 900 }, deviceScaleFactor: 1 });
    const page = await ctx.newPage(); page.setDefaultTimeout(8000);
    page.on("pageerror", (e) => results.push(["FAIL", "page error: " + e.message]));
    page.on("console", (m) => { if (m.type() === "error" && !/status of 400/.test(m.text())) results.push(["FAIL", "console error: " + m.text()]); });
    await page.goto(base + "/md-harness.html?persona=" + persona + (lang ? "&lang=" + lang : "") + (biz ? "&biz=" + biz : ""));
    await page.waitForSelector("body[data-ready='1']", { timeout: 15000 });
    return page;
  }
  const noOverflow = async (page) => assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), "horizontal overflow");
  const rows = (page) => page.$$eval(".occ-list .occ-row", (b) => b.length);

  for (const width of [390, 1440]) {
    await step(`owner ${width}px bn: catalog, paging, detail, NOT_CONNECTED, no overflow`, async () => {
      const page = await open(P.own, width);
      assert.match(await page.textContent("h1"), /মাস্টার ডেটা/);
      assert.strictEqual(await page.$("[data-state=NOT_CONNECTED]"), null, "no developer dependency banner on the ERP screen");
      assert.ok(!/NP0|B-0|PR #|CI /.test(await page.textContent("body")), "no internal build references on the screen");
      assert.strictEqual(await rows(page), 50, "first page is 50");
      await page.click("text=আরও দেখুন"); await page.waitForFunction(() => document.querySelectorAll(".occ-list .occ-row").length === 56);
      assert.strictEqual(await page.$("text=আরও দেখুন"), null, "no more pages");
      await page.click(".occ-row:has-text('রসগোল্লা')"); await page.waitForSelector(".occ-detail h2");
      const d = await page.textContent(".occ-detail");
      assert.match(d, /8901234567890/); assert.match(d, /RETAIL/); assert.match(d, /LARGE/); assert.match(d, /স্টক পরিমাণ/);
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

  const f = (page) => page.locator("form.occ-panel");
  const submit = async (page) => f(page).locator("button[type=submit]").click();

  await step("units: create, required-field and dimension validation, conversion, edit (390 en)", async () => {
    const page = await open(P.own, 390, "en");
    await page.click("[data-tab=units]"); await page.click("text=New unit");
    await submit(page); await page.waitForSelector("form.occ-panel .occ-field-error:has-text('Please fill in this field')");
    await f(page).getByLabel("Code *").fill("kg"); await f(page).getByLabel("Name (English) *").fill("Kilogram");
    await f(page).getByLabel("Measure").selectOption("mass"); await f(page).getByLabel("Decimals *").fill("3");
    await submit(page); await page.waitForSelector(".occ-detail h2:has-text('Kilogram')");
    assert.match(await page.textContent(".occ-detail .occ-meta"), /KG · mass · Decimals 3/);
    await page.click("text=New unit");
    await f(page).getByLabel("Code *").fill("G"); await f(page).getByLabel("Name (English) *").fill("Gram");
    await f(page).getByLabel("Measure").selectOption("mass"); await f(page).getByLabel("Decimals *").fill("0");
    await submit(page); await page.waitForSelector(".occ-detail h2:has-text('Gram')");
    await page.click("text=Add conversion");
    assert.strictEqual(await f(page).getByLabel("To", { exact: true }).locator("option", { hasText: /^G · / }).count(), 0, "a unit cannot convert to itself");
    await f(page).getByLabel("To", { exact: true }).selectOption({ label: "KG · Kilogram" });
    await f(page).getByLabel(/Factor/).fill("abc"); await submit(page);
    await page.waitForSelector("form.occ-panel .occ-field-error:has-text('INVALID_FACTOR')");
    await f(page).getByLabel(/Factor/).fill("0.001"); await submit(page);
    await page.waitForSelector(".occ-detail .md-table");
    await page.click(".occ-row:has-text('Piece')"); await page.click("text=Add conversion");
    assert.strictEqual(await f(page).getByLabel("To", { exact: true }).locator("option", { hasText: "KG" }).count(), 0, "cross-measure unit not offered");
    await page.click("form.occ-panel button:has-text('Cancel')");
    await page.click(".occ-detail > button:has-text('Edit')");
    assert.ok(await f(page).getByLabel("Measure").isDisabled(), "measure locked after creation");
    await f(page).getByLabel("Name (English) *").fill("Piece (single)"); await submit(page);
    await page.waitForSelector(".occ-detail .occ-meta:has-text('Version 2')");
    await noOverflow(page); await page.screenshot({ path: path.join(SHOTS, "md-units-390-en.png"), fullPage: true });
    await page.context().close();
  });

  await step("variants and barcodes: add, edit, duplicate barcode refused (1440 bn)", async () => {
    const page = await open(P.own, 1440);
    await page.click(".occ-row:has-text('রসগোল্লা')"); await page.click("text=ধরন যোগ করুন");
    await f(page).getByLabel("কোড *").fill("SMALL"); await f(page).getByLabel("নাম (ইংরেজি) *").fill("Small"); await submit(page);
    await page.waitForSelector(".occ-detail td:has-text('SMALL')");
    await page.click("text=বারকোড যোগ করুন");
    await f(page).getByLabel("বারকোড *").fill("8901234567890"); await submit(page);
    await page.waitForSelector("form.occ-panel .occ-field-error:has-text('MASTER_DUPLICATE')");
    await f(page).getByLabel("বারকোড *").fill("8901234567999"); await f(page).getByLabel("ধরন").selectOption({ label: "SMALL · Small" }); await submit(page);
    await page.waitForSelector(".occ-detail td:has-text('8901234567999')");
    const row = page.locator(".occ-detail tr", { hasText: "8901234567999" }); await row.locator("button").click();
    assert.ok(await f(page).getByLabel("বারকোড *").isDisabled(), "barcode value is the key");
    await f(page).getByLabel("সক্রিয়").uncheck(); await submit(page);
    await page.waitForSelector(".occ-detail tr:has-text('8901234567999') td:has-text('✗')");
    await page.screenshot({ path: path.join(SHOTS, "md-item-1440-bn.png"), fullPage: true });
    await page.context().close();
  });

  await step("price lists: create, add item price, edit price, invalid amount refused (390 en)", async () => {
    const page = await open(P.own, 390, "en");
    await page.click("[data-tab=prices]"); await page.click("text=New price list");
    await f(page).getByLabel("Code *").fill("WHOLESALE"); await f(page).getByLabel("Name (English) *").fill("Wholesale"); await submit(page);
    await page.waitForSelector(".occ-detail h2:has-text('Wholesale')");
    await page.click("text=Add price");
    await f(page).getByLabel("Item").selectOption({ label: "RASGULLA · Rasgulla" });
    await f(page).getByLabel(/Unit price/).fill("-5"); await submit(page);
    await page.waitForSelector("form.occ-panel .occ-field-error:has-text('INVALID_AMOUNT')");
    await f(page).getByLabel(/Unit price/).fill("20.50"); await submit(page);
    await page.waitForSelector(".occ-detail td:has-text('20.5')");
    await page.locator(".occ-detail tr", { hasText: "RASGULLA" }).locator("button").click();
    await f(page).getByLabel(/Unit price/).fill("21"); await submit(page);
    await page.waitForSelector(".occ-detail td:has-text('21')");
    await page.click(".occ-detail > button:has-text('Edit')");
    assert.ok(await f(page).getByLabel("Currency *").isDisabled() && await f(page).getByLabel("List type").isDisabled(), "kind and currency locked");
    await page.click("form.occ-panel button:has-text('Cancel')");
    await noOverflow(page); await page.screenshot({ path: path.join(SHOTS, "md-prices-390-en.png"), fullPage: true });
    await page.context().close();
  });

  await step("Owner Control switched off: save refused with a clear message, nothing written", async () => {
    sql(`SET ROLE authenticated; SELECT set_config('request.jwt.claims','{"sub":"${P.own}"}',false);
      SELECT core10.control_set_v1(9311,NULL,'master.price',false,0::smallint,'{}'::jsonb,NULL,false,0,'Owner pauses price edits in UI test','md-ui-ctl-off-01');`);
    const before = sql("SELECT count(*) FROM core10.master_price_lists_v1 WHERE business_id=9311");
    const page = await open(P.own, 1440, "en");
    await page.click("[data-tab=prices]"); await page.click("text=New price list");
    await f(page).getByLabel("Code *").fill("BLOCKED"); await f(page).getByLabel("Name (English) *").fill("Blocked"); await submit(page);
    await page.waitForSelector("form.occ-panel .occ-field-error:has-text('switched this feature off')");
    assert.strictEqual(sql("SELECT count(*) FROM core10.master_price_lists_v1 WHERE business_id=9311"), before);
    await page.context().close();
  });

  await step("direct page with ?biz: owner preselects own second business; param is only a preference", async () => {
    const page = await open(P.own, 1440, "en", 9312);
    assert.strictEqual(await page.$eval(".occ-controls select", (s) => s.value), "9312");
    assert.ok(!/RASGULLA/.test(await page.textContent(".occ-list")), "9312 starts empty");
    await page.context().close();
  });

  for (const width of [390, 1440]) await step(`business owner ${width}px: edits own business; foreign ?biz ignored, no leak`, async () => {
    const page = await open(P.bo, width, "en", 9311);
    const opts = await page.$$eval(".occ-controls select option", (o) => o.map((x) => x.value));
    assert.deepStrictEqual(opts, ["9312"], "business owner sees only the business CORE10 returns");
    assert.ok(!/RASGULLA|Rasgulla|8901234567890/.test(await page.textContent("body")), "foreign business data leaked");
    await page.click("text=New item");
    await f(page).getByLabel("SKU *").fill("BO-" + width); await f(page).getByLabel("Name (English) *").fill("Business owner item " + width); await submit(page);
    await page.waitForSelector(`.occ-detail h2:has-text('Business owner item ${width}')`);
    await noOverflow(page); await page.context().close();
  });

  await step("other tenant with ?biz of a foreign business sees none of it", async () => {
    const page = await open(P.other, 390, "en", 9311);
    assert.ok(!/RASGULLA|Rasgulla|md-sweets/.test(await page.textContent("body")));
    await page.context().close();
  });

  await step("manager reads but gets no create/edit controls", async () => {
    const page = await open(P.mgr, 390);
    assert.ok((await rows(page)) > 0);
    assert.strictEqual(await page.$("text=নতুন পণ্য"), null);
    await page.click(".occ-row:has-text('রসগোল্লা')"); await page.waitForSelector(".occ-detail h2");
    assert.strictEqual(await page.$(".occ-detail button"), null, "no edit/add buttons for manager");
    for (const tab of ["parties", "prices", "units"]) { await page.click(`[data-tab=${tab}]`); await page.waitForSelector(".occ-list .occ-meta");
      assert.strictEqual(await page.$(".occ-list .occ-primary"), null, "no create button on " + tab); }
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
