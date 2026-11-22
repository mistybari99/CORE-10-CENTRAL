"use strict";
// B-012 Purchase screen: real Chromium, real core10 procurement SQL functions in a disposable PostgreSQL, 390 and 1440 px, bn and en.
// Requires PG* for a loopback server with the migrations applied and tests/control-centre/pu-seed.sql loaded.
// Flow: buyer raises a PO, approver approves, godown staff receives with lot + expiry, quality check rejects part,
// posting adds only the accepted quantity to stock and leaves the PO partly received; Owner switch-off; approval steps;
// other tenant sees nothing.
const assert = require("node:assert");
const fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const { start } = require("./sql-gateway.cjs");
const { spawnSync } = require("node:child_process");
const sql = (q) => { const r = spawnSync("psql", ["-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"], { input: q, encoding: "utf8", env: process.env }); if (r.status !== 0) throw Error(r.stderr); return r.stdout.trim(); };
const asUser = (uid, q) => sql(`SET ROLE authenticated; SELECT set_config('request.jwt.claims','{"sub":"${uid}"}',false), set_config('request.jwt.claim.sub','${uid}',false) \\g /dev/null\n${q}`);

const P = { own: "e1611111-1111-4111-8111-111111111111", bo: "e1622222-2222-4222-8222-222222222222", buyer: "e1633333-3333-4333-8333-333333333333",
  staff: "e1644444-4444-4444-8444-444444444444", other: "e1655555-5555-4555-8555-555555555555", none: "e1677777-7777-4777-8777-777777777777" };
const SHOTS = process.env.PU_SHOTS || path.join(require("node:os").tmpdir(), "pu-shots");
const results = [];
async function step(name, fn) {
  try { await fn(); results.push(["PASS", name]); console.log("PASS " + name); }
  catch (e) { results.push(["FAIL", name + " :: " + String(e.message).split("\n")[0]]); console.log("FAIL " + name + " :: " + String(e.message).split("\n")[0]); }
}
const controlVersion = (feature) => Number(sql(`SELECT coalesce(max(version),0) FROM core10.control_setting_versions_v1 WHERE business_id=16011 AND site_id IS NULL AND feature_key='${feature}'`));
const setControl = (feature, enabled, stages, key) => asUser(P.own, `SELECT core10.control_set_v1(16011,NULL,'${feature}',${enabled},${stages}::smallint,'{}',NULL,false,${controlVersion(feature)},'browser test','${key}') \\g /dev/null`);
const balance = (loc, sku) => sql(`SELECT coalesce((SELECT b.on_hand FROM core10.stock_balances_v1 b JOIN core10.items i ON i.id=b.item_id WHERE b.location_id=${loc} AND i.sku='${sku}' AND i.business_id=16011),0)`);

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
    await page.goto(base + "/pu-harness.html?persona=" + persona + (lang ? "&lang=" + lang : "") + (biz ? "&biz=" + biz : ""));
    await page.waitForSelector("body[data-ready='1']", { timeout: 15000 });
    return page;
  }
  const noOverflow = async (page) => assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), "horizontal overflow");
  const rows = (page) => page.$$eval(".occ-list .occ-row", (b) => b.length);
  const noJargon = async (page) => { const body = await page.textContent("body");
    assert.ok(!/NP0|B-0|PR #|CI |NOT_CONNECTED|PROC_|CONTROL_|RPC|undefined|null|NaN|\[object/.test(body), "no developer text on the screen: " + (body.match(/NP0|B-0|PR #|CI |NOT_CONNECTED|PROC_|CONTROL_|RPC|undefined|null|NaN|\[object/) || [])[0]); };
  const shot = (page, n) => page.screenshot({ path: path.join(SHOTS, n + ".png"), fullPage: true });
  const statusCode = (page) => page.getAttribute(".occ-status", "data-code");
  const fillLine = async (form, i, sku, q, p) => {
    const fsl = form.locator("fieldset.pu-line").nth(i);
    const value = await fsl.locator("select[data-k=item] option", { hasText: sku }).first().getAttribute("value");
    await fsl.locator("select[data-k=item]").selectOption(value);
    await fsl.locator("input[data-k=qty]").fill(q); await fsl.locator("input[data-k=price]").fill(p);
  };
  let po1 = null, po2 = null;

  for (const width of [390, 1440]) {
    await step(`owner ${width}px bn: orders list, paging, status filter, detail, no overflow`, async () => {
      const page = await open(P.own, width);
      assert.match(await page.textContent("h1"), /ক্রয় ও মাল গ্রহণ/);
      assert.strictEqual(await rows(page), 20, "first page is 20");
      await page.click("[data-k=more]"); await page.waitForFunction(() => document.querySelectorAll(".occ-list .occ-row").length === 24);
      assert.strictEqual(await page.$("[data-k=more]"), null, "no more pages");
      await page.click("[data-status=draft]"); await page.waitForFunction(() => document.querySelectorAll(".occ-list .occ-row").length === 12);
      await page.click("[data-status=approved]"); await page.waitForFunction(() => document.querySelectorAll(".occ-list .occ-row").length === 12);
      await page.click(".occ-list .occ-row >> nth=0"); await page.waitForSelector(".occ-detail[data-status=approved]");
      const d = await page.textContent(".occ-detail");
      assert.match(d, /চিনি কল/); assert.match(d, /আটা/); assert.match(d, /অনুমোদিত/); assert.match(d, /৳ /);
      await noJargon(page); await noOverflow(page);
      await shot(page, `pu-owner-${width}-bn`);
      await page.context().close();
    });
  }

  await step("buyer 390px bn: raises a draft order with two lines, live total, cannot approve", async () => {
    const page = await open(P.buyer, 390);
    await page.click("[data-k=new]");
    const form = page.locator("form.occ-panel");
    await form.locator("select").first().selectOption("160111");
    await form.locator("select").nth(1).selectOption({ label: "চিনি কল · SUP-SUGAR" });
    // the customer and the blocked supplier are never offered
    const supOpts = await form.locator("select").nth(1).locator("option").allTextContents();
    assert.ok(!supOpts.some((o) => /CUS-001|SUP-OLD/.test(o)), "only active suppliers");
    assert.ok(supOpts.some((o) => /SUP-DAIRY/.test(o)), "a 'both' party is a supplier too");
    await fillLine(form, 0, "SUGAR", "১০০", "52.50");
    await form.locator("button", { hasText: "লাইন যোগ করুন" }).click();
    await fillLine(form, 1, "GHEE", "20", "800");
    assert.match(await form.locator(".pu-total").textContent(), /৳ ২১২৫০\.০০/, "total 100 × 52.50 + 20 × 800");
    const itemOpts = await form.locator("fieldset.pu-line select[data-k=item]").first().locator("option").allTextContents();
    assert.ok(!itemOpts.some((o) => /OLD-DYE/.test(o)), "inactive item not offered");
    await noOverflow(page);
    await shot(page, "pu-buyer-new-390-bn");
    await form.locator("button[type=submit]").click();
    await page.waitForSelector(".occ-detail[data-status=draft]");
    po1 = Number(await page.getAttribute(".occ-detail", "data-po"));
    const d = await page.textContent(".occ-detail");
    assert.match(d, /খসড়া/); assert.match(d, /২১২৫০\.০০/); assert.match(d, /তৈরি করেছেন: আপনি/);
    assert.strictEqual(await page.$(".occ-detail button:has-text('অনুমোদন করুন')"), null, "buyer has no approve button");
    await noJargon(page); await noOverflow(page);
    await shot(page, "pu-buyer-draft-390-bn");
    await page.context().close();
  });

  await step("approver 1440px en: approves the buyer's order", async () => {
    const page = await open(P.bo, 1440, "en");
    await page.click(`.occ-row[data-po='${po1}']`); await page.waitForSelector(".occ-detail[data-status=draft]");
    await page.click(".occ-detail button:has-text('Approve')");
    await page.waitForSelector(".occ-detail[data-status=approved]");
    assert.match(await page.textContent(".occ-status"), /Approved/);
    assert.match(await page.textContent(".occ-detail"), /Approved/);
    await noJargon(page);
    await shot(page, "pu-approver-1440-en");
    await page.context().close();
  });

  await step("godown staff 390px bn: sees only godown orders, receives with lot and expiry", async () => {
    const page = await open(P.staff, 390);
    assert.strictEqual(await rows(page), 1, "only the order for their godown");
    assert.strictEqual(await page.$("[data-k=new]"), null, "staff cannot raise orders");
    assert.match(await page.textContent(".occ-list"), /শুধু মাল গ্রহণ ও যাচাই/);
    await page.click(`.occ-row[data-po='${po1}']`); await page.waitForSelector(".occ-detail[data-status=approved]");
    await page.click(".occ-detail button:has-text('মাল গ্রহণ (GRN)')");
    const form = page.locator("form.occ-panel");
    const locs = await form.locator("select").first().locator("option").allTextContents();
    assert.deepStrictEqual(locs, ["G-MAIN", "G-COLD"], "store locations of this godown only");
    await form.locator("input[type=text]").first().fill("CH-7781");
    const sugar = form.locator("fieldset.pu-line").nth(0), ghee = form.locator("fieldset.pu-line").nth(1);
    assert.match(await sugar.textContent(), /বাকি ১০০/);
    await sugar.locator("input[data-k=lot]").fill("SUG-2611"); await sugar.locator("input[data-k=mfg]").fill("2026-11-01");
    await sugar.locator("input[data-k=exp]").fill("2027-05-01");
    await ghee.locator("input[data-k=qty]").fill("15"); await ghee.locator("input[data-k=lot]").fill("GHEE-01"); await ghee.locator("input[data-k=exp]").fill("2027-01-31");
    await noOverflow(page);
    await shot(page, "pu-staff-receive-390-bn");
    await form.locator("button[type=submit]").click();
    await page.waitForSelector(".pu-grn[data-status=received]");
    assert.match(await page.textContent(".occ-status"), /মান যাচাই বাকি/);
    const g = await page.textContent(".pu-grn");
    assert.match(g, /SUG-2611/); assert.match(g, /২০২৭-০৫-০১/); assert.match(g, /CH-7781/);
    await page.context().close();
  });

  await step("godown staff 390px bn: quality check rejects 5 sugar, posting adds only accepted stock, order partly received", async () => {
    const page = await open(P.staff, 390);
    await page.click(`.occ-row[data-po='${po1}']`); await page.waitForSelector(".pu-grn[data-status=received]");
    await page.click(".pu-grn button:has-text('মান যাচাই')");
    const form = page.locator("form.occ-panel");
    const sugar = form.locator("fieldset.pu-line").nth(0);
    await sugar.locator("input[data-k=accepted]").fill("95"); await sugar.locator("input[data-k=notes]").fill("5 bags wet");
    assert.match(await sugar.textContent(), /বাতিল: ৫/);
    await shot(page, "pu-staff-qc-390-bn");
    await form.locator("button[type=submit]").click();
    await page.waitForSelector(".pu-grn[data-status=inspected]");
    await page.click(".pu-grn button:has-text('স্টকে তুলুন')");
    await page.waitForSelector(".occ-detail[data-status=partially_received]");
    assert.match(await page.textContent(".occ-status"), /স্টকে তোলা হয়েছে/);
    const d = await page.textContent(".occ-detail");
    assert.match(d, /আংশিক গৃহীত/);
    const lines = await page.$$eval(".occ-detail > .md-table tbody tr", (r) => r.map((x) => Array.from(x.cells).map((c) => c.textContent)));
    assert.deepStrictEqual(lines[0].slice(1), ["১০০", "৫২.৫০", "৫২৫০.০০", "৯৫", "৫", "৫"], "sugar: 95 accepted, 5 rejected, 5 still open for a replacement delivery");
    assert.deepStrictEqual(lines[1].slice(4), ["১৫", "০", "৫"], "ghee: 15 accepted, 5 open");
    assert.strictEqual(balance(1601111, "SUGAR"), "95.000", "only accepted sugar is in stock");
    assert.strictEqual(balance(1601111, "GHEE"), "15.000");
    assert.strictEqual(sql(`SELECT count(*) FROM core10.inventory_lots_v1 WHERE business_id=16011 AND lot_code IN ('SUG-2611','GHEE-01') AND expires_on IS NOT NULL`), "2", "lots registered with expiry");
    await noJargon(page); await noOverflow(page);
    await shot(page, "pu-staff-posted-390-bn");
    await page.context().close();
  });

  await step("owner switch-off: receiving shows the Bangla switched-off message and writes nothing", async () => {
    setControl("procurement.goods_receipt", false, 0, "pu-ctl-grn-off");
    try {
      const before = sql("SELECT count(*) FROM core10.goods_receipts_v1 WHERE business_id=16011");
      const page = await open(P.staff, 390);
      await page.click(`.occ-row[data-po='${po1}']`); await page.waitForSelector(".occ-detail[data-status=partially_received]");
      await page.click(".occ-detail button:has-text('মাল গ্রহণ (GRN)')");
      await page.locator("form.occ-panel button[type=submit]").click();
      await page.waitForSelector(".occ-field-error[data-code=CONTROL_DISABLED]");
      assert.match(await page.textContent(".occ-field-error"), /মালিক এই সুবিধাটি বন্ধ রেখেছেন: মাল গ্রহণ ও মান যাচাই/);
      assert.strictEqual(sql("SELECT count(*) FROM core10.goods_receipts_v1 WHERE business_id=16011"), before, "nothing written");
      await noJargon(page); await noOverflow(page);
      await shot(page, "pu-switch-off-390-bn");
      await page.context().close();
      const en = await open(P.staff, 1440, "en");
      await en.click(`.occ-row[data-po='${po1}']`); await en.waitForSelector(".occ-detail[data-status=partially_received]");
      await en.click(".occ-detail button:has-text('Receive goods (GRN)')"); await en.locator("form.occ-panel button[type=submit]").click();
      await en.waitForSelector(".occ-field-error[data-code=CONTROL_DISABLED]");
      assert.match(await en.textContent(".occ-field-error"), /The owner has switched this off: Goods receipt and quality check/);
      await en.context().close();
    } finally { setControl("procurement.goods_receipt", true, 0, "pu-ctl-grn-on"); }
  });

  await step("approval steps on: approve asks for approval first, the creator sends it, approve works after the decision", async () => {
    setControl("procurement.purchase_order", true, 1, "pu-ctl-po-stage1");
    try {
      const buyer = await open(P.buyer, 1440, "en");
      await buyer.click("[data-k=new]");
      const form = buyer.locator("form.occ-panel");
      await form.locator("select").first().selectOption("160111");
      await form.locator("select").nth(1).selectOption({ label: "Dairy House · SUP-DAIRY" });
      await fillLine(form, 0, "FLOUR", "10", "40");
      await form.locator("button[type=submit]").click();
      await buyer.waitForSelector(".occ-detail[data-status=draft]");
      po2 = Number(await buyer.getAttribute(".occ-detail", "data-po"));
      const bo = await open(P.bo, 390);
      await bo.click(`.occ-row[data-po='${po2}']`); await bo.waitForSelector(".occ-detail[data-status=draft]");
      await bo.click(".occ-detail button:has-text('অনুমোদন করুন')");
      await bo.waitForSelector(".occ-status[data-code=PROC_APPROVAL_REQUIRED]");
      assert.match(await bo.textContent(".occ-status"), /অনুমোদনের ধাপ চালু আছে/);
      assert.match(await bo.textContent(".occ-detail .pu-flash[data-code=PROC_APPROVAL_REQUIRED]"), /অনুমোদনের জন্য পাঠান/, "guidance next to the buttons");
      await noJargon(bo); await noOverflow(bo);
      await shot(bo, "pu-approval-required-390-bn");
      await buyer.click(".occ-detail button:has-text('Send for approval')");
      await buyer.waitForFunction(() => /Sent for approval/.test(document.querySelector(".occ-status").textContent));
      await shot(buyer, "pu-approval-requested-1440-en");
      const req = sql(`SELECT approval_request_id FROM core10.purchase_orders_v1 WHERE id=${po2}`);
      assert.ok(/^[0-9]+$/.test(req), "approval request recorded on the order");
      asUser(P.own, `SELECT core10.decide_approval(${req},'approve','pu-decide-0001') \\g /dev/null`);
      await bo.click(".occ-detail button:has-text('অনুমোদন করুন')");
      await bo.waitForSelector(".occ-detail[data-status=approved]");
      await buyer.context().close(); await bo.context().close();
    } finally { setControl("procurement.purchase_order", true, 0, "pu-ctl-po-stage0"); }
  });

  await step("buyer cancels a draft and owner closes the partly received order (with confirmation)", async () => {
    const buyer = await open(P.buyer, 390);
    await buyer.click("[data-status=draft]"); await buyer.waitForFunction(() => document.querySelectorAll(".occ-list .occ-row").length === 12);
    await buyer.click(".occ-list .occ-row >> nth=0"); await buyer.waitForSelector(".occ-detail[data-status=draft]");
    await buyer.click(".occ-detail button:has-text('আদেশ বাতিল')");
    await buyer.click(".pu-confirm button:has-text('না')"); assert.strictEqual(await buyer.$(".pu-confirm"), null, "No keeps the order");
    await buyer.click(".occ-detail button:has-text('আদেশ বাতিল')"); await buyer.click(".pu-confirm button:has-text('হ্যাঁ, নিশ্চিত')");
    await buyer.waitForSelector(".occ-detail[data-status=cancelled]");
    await buyer.context().close();
    const own = await open(P.own, 1440, "en");
    await own.click(`.occ-row[data-po='${po1}']`); await own.waitForSelector(".occ-detail[data-status=partially_received]");
    await own.click(".occ-detail button:has-text('Close order')"); await own.click(".pu-confirm button:has-text('Yes, confirm')");
    await own.waitForSelector(".occ-detail[data-status=closed]");
    assert.strictEqual(await own.$(".occ-detail button:has-text('Receive goods (GRN)')"), null, "a closed order takes no more goods");
    await shot(own, "pu-owner-closed-1440-en");
    await own.context().close();
  });

  await step("site filter: Main godown shows only godown orders; other business has its own empty list", async () => {
    const page = await open(P.own, 1440);
    await page.selectOption("select[data-k=site]", "160111"); await page.waitForFunction(() => document.querySelectorAll(".occ-list .occ-row").length === 2);
    await page.selectOption("select[data-k=business]", "16012"); await page.waitForSelector(".occ-list .occ-empty");
    assert.match(await page.textContent(".occ-list"), /কোনো ক্রয় আদেশ নেই/);
    await page.context().close();
  });

  await step("other tenant 1440px: sees only its own business and no orders of tenant 1601", async () => {
    const page = await open(P.other, 1440);
    const biz = await page.$$eval("select[data-k=business] option", (o) => o.map((x) => x.textContent));
    assert.deepStrictEqual(biz, ["other-co"]);
    assert.match(await page.textContent(".occ-list"), /কোনো ক্রয় আদেশ নেই/);
    const body = await page.textContent("body");
    assert.ok(!/misti-sweets|চিনি কল|Sugar Mills|Main godown/.test(body), "nothing of the other tenant");
    // a direct read of a foreign order is refused by the server
    const denied = await page.evaluate(async (po) => { const r = await fetch("/rpc/procurement_get_po_v1", { method: "POST",
      headers: { "content-type": "application/json", "x-test-persona": new URLSearchParams(location.search).get("persona") }, body: JSON.stringify({ p_po: po }) });
      return (await r.json()).message; }, po1);
    assert.strictEqual(denied, "PROC_SCOPE");
    await shot(page, "pu-other-tenant-1440-bn");
    await page.context().close();
  });

  await step("account with no business gets the empty state; without a session the page shows the sign-in error", async () => {
    const page = await open(P.none, 390);
    assert.match(await page.textContent("body"), /আপনার দেখার মতো কোনো ব্যবসা নেই/);
    await page.context().close();
    const anon = await open("", 390);
    assert.match(await anon.textContent(".occ-status"), /সাইন-ইন প্রয়োজন/);
    assert.strictEqual(await anon.$(".occ-row"), null);
    await anon.context().close();
  });

  await browser.close(); server.close();
  const failed = results.filter((r) => r[0] !== "PASS");
  const passed = results.length - failed.length;
  if (failed.length) { console.log("FAIL PURCHASE BROWSER: " + passed + "/" + results.length); failed.forEach((f) => console.log(f[1])); process.exit(1); }
  console.log("PASS PURCHASE BROWSER: " + passed + "/" + results.length + " · screenshots in " + SHOTS);
})().catch((e) => { console.error(e); process.exit(1); });
