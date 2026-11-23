"use strict";
// B-012 Purchase screen: real Chromium, real core10 procurement SQL functions in a disposable PostgreSQL, 390 and 1440 px, bn and en.
// Requires PG* for a loopback server with the migrations applied and tests/control-centre/pu-seed.sql loaded.
// Flow: buyer raises a PO, approver approves, godown staff receives with lot + expiry, quality check rejects part,
// posting adds only the accepted quantity to stock and leaves the PO partly received; 0207: a new receipt is cancelled
// before stock (reason required, quantity open again, stock unchanged), a return to the supplier is drafted within the
// server limits, the preparer cannot post it, the business owner posts it and stock goes down, a draft is cancelled with
// confirmation, the Owner switch-off of returns is shown in bn/en, the lot expiry list pages and filters by N days;
// store locations come from the 0208 list RPC (no table read); 0209: a return whose received lot no longer holds the
// quantity is refused with the stock message (bn/en), nothing moves; Owner switch-off; approval steps; other tenant sees nothing.
const assert = require("node:assert");
const fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const { start } = require("./sql-gateway.cjs");
const { spawnSync } = require("node:child_process");
const sql = (q) => { const r = spawnSync("psql", ["-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"], { input: q, encoding: "utf8", env: process.env }); if (r.status !== 0) throw Error(r.stderr); return r.stdout.trim(); };
// Internal engine call (not an API role): the posting function is not granted to authenticated, so it runs as the
// database owner with the actor claims set, exactly like a server-side command would.
const asActor = (uid, q) => sql(`SELECT set_config('request.jwt.claims','{"sub":"${uid}"}',false), set_config('request.jwt.claim.sub','${uid}',false) \\g /dev/null\n${q}`);
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
// Lot expiry dates are relative to the database's today so the flow never expires with the calendar (ghee first, then sugar).
const EXP_GHEE = sql("SELECT (current_date + 70)::text"), EXP_SUGAR = sql("SELECT (current_date + 160)::text");
const daysLeft = (d) => sql(`SELECT ('${d}'::date - current_date)::text`);
const balance = (loc, sku) => sql(`SELECT coalesce((SELECT b.on_hand FROM core10.stock_balances_v1 b JOIN core10.items i ON i.id=b.item_id WHERE b.location_id=${loc} AND i.sku='${sku}' AND i.business_id=16011),0)`);

(async () => {
  fs.mkdirSync(SHOTS, { recursive: true });
  const server = await start(0);
  const base = "http://127.0.0.1:" + server.address().port;
  const browser = await chromium.launch();
  async function open(persona, width, lang, biz, extra) {
    const ctx = await browser.newContext({ viewport: { width, height: width < 500 ? 844 : 900 }, deviceScaleFactor: 1 });
    const page = await ctx.newPage(); page.setDefaultTimeout(8000);
    page.on("pageerror", (e) => results.push(["FAIL", "page error: " + e.message]));
    page.on("console", (m) => { if (m.type() === "error" && !/status of 400/.test(m.text())) results.push(["FAIL", "console error: " + m.text()]); });
    await page.goto(base + "/pu-harness.html?persona=" + persona + (lang ? "&lang=" + lang : "") + (biz ? "&biz=" + biz : "") + (extra || ""));
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
    await sugar.locator("input[data-k=exp]").fill(EXP_SUGAR);
    await ghee.locator("input[data-k=qty]").fill("15"); await ghee.locator("input[data-k=lot]").fill("GHEE-01"); await ghee.locator("input[data-k=exp]").fill(EXP_GHEE);
    await noOverflow(page);
    await shot(page, "pu-staff-receive-390-bn");
    await form.locator("button[type=submit]").click();
    await page.waitForSelector(".pu-grn[data-status=received]");
    assert.match(await page.textContent(".occ-status"), /মান যাচাই বাকি/);
    const g = await page.textContent(".pu-grn");
    assert.match(g, /SUG-2611/); assert.match(g, new RegExp(EXP_SUGAR.replace(/[0-9]/g, (d) => "০১২৩৪৫৬৭৮৯"[d]))); assert.match(g, /CH-7781/);
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
    assert.deepStrictEqual(lines[0].slice(1), ["১০০", "৫২.৫০", "৫২৫০.০০", "৯৫", "৫", "৫", "০"], "sugar: 95 accepted, 5 rejected, 5 still open for a replacement delivery, nothing returned");
    assert.deepStrictEqual(lines[1].slice(4), ["১৫", "০", "৫", "০"], "ghee: 15 accepted, 5 open, nothing returned");
    assert.strictEqual(balance(1601111, "SUGAR"), "95.000", "only accepted sugar is in stock");
    assert.strictEqual(balance(1601111, "GHEE"), "15.000");
    assert.strictEqual(sql(`SELECT count(*) FROM core10.inventory_lots_v1 WHERE business_id=16011 AND lot_code IN ('SUG-2611','GHEE-01') AND expires_on IS NOT NULL`), "2", "lots registered with expiry");
    await noJargon(page); await noOverflow(page);
    await shot(page, "pu-staff-posted-390-bn");
    await page.context().close();
  });

  // ---------- 0207: receipt cancel before stock, returns to the supplier, lot expiry list ----------
  const poLines = (page) => page.$$eval(".occ-detail > .md-table tbody tr", (r) => r.map((x) => Array.from(x.cells).map((c) => c.textContent)));
  const returns = () => Number(sql("SELECT count(*) FROM core10.supplier_returns_v1 WHERE business_id=16011"));
  await step("godown staff 390px bn: cancels a new receipt before stock with a reason; its quantity is open again and stock is unchanged", async () => {
    const page = await open(P.staff, 390);
    await page.click(`.occ-row[data-po='${po1}']`); await page.waitForSelector(".occ-detail[data-status=partially_received]");
    await page.click(".occ-detail button:has-text('মাল গ্রহণ (GRN)')");
    const form = page.locator("form.occ-panel");
    assert.deepStrictEqual(await form.locator("select").first().locator("option").allTextContents(), ["G-MAIN", "G-COLD"], "store locations from the server list");
    await form.locator("fieldset.pu-line").nth(0).locator("input[data-k=qty]").fill("5");
    await form.locator("fieldset.pu-line").nth(1).locator("input[data-k=qty]").fill("");
    await form.locator("button[type=submit]").click();
    await page.waitForSelector(".pu-grn[data-status=received]");
    assert.strictEqual((await poLines(page))[0][6], "০", "the new receipt holds the 5 open sugar");
    const grn2 = Number(await page.getAttribute(".pu-grn[data-status=received]", "data-grn"));
    assert.strictEqual(await page.$(".pu-grn[data-status=posted] [data-k=grn-cancel]"), null, "a receipt already in stock cannot be cancelled");
    // a buyer-manager who did not receive the goods is not offered the cancel button
    const buyer = await open(P.buyer, 390);
    await buyer.click(`.occ-row[data-po='${po1}']`); await buyer.waitForSelector(".pu-grn[data-status=received]");
    assert.strictEqual(await buyer.$("[data-k=grn-cancel]"), null, "buyer has no cancel button on another person's receipt");
    await buyer.context().close();
    await page.click(`.pu-grn[data-grn='${grn2}'] [data-k=grn-cancel]`);
    const cf = page.locator("form.occ-panel");
    assert.match(await cf.textContent(), /স্টক বদলাবে না/);
    await cf.locator("button[type=submit]").click();
    assert.match(await cf.locator(".occ-field-error").textContent(), /কারণ লিখুন \(৩–৩০০ অক্ষর\)/, "a reason is required");
    assert.strictEqual(sql(`SELECT status FROM core10.goods_receipts_v1 WHERE id=${grn2}`), "received", "nothing written without a reason");
    await cf.locator("input[data-k=reason]").fill("ভুল চালান এসেছে");
    await noOverflow(page);
    await shot(page, "pu-grn-cancel-390-bn");
    await cf.locator("button[type=submit]").click();
    await page.waitForSelector(`.pu-grn[data-grn='${grn2}'][data-status=cancelled]`);
    assert.match(await page.textContent(".occ-status"), /রসিদ বাতিল হয়েছে — পরিমাণ আবার বাকি/);
    assert.match(await page.textContent(`.pu-grn[data-grn='${grn2}']`), /বাতিল করা হয়েছে[\s\S]*কারণ: ভুল চালান এসেছে/);
    assert.strictEqual((await poLines(page))[0][6], "৫", "the 5 sugar is open again");
    assert.strictEqual(sql(`SELECT status||'|'||cancel_reason FROM core10.goods_receipts_v1 WHERE id=${grn2}`), "cancelled|ভুল চালান এসেছে");
    assert.strictEqual(balance(1601111, "SUGAR"), "95.000", "a cancelled receipt never reaches stock");
    await noJargon(page); await noOverflow(page);
    await shot(page, "pu-grn-cancelled-390-bn");
    await page.context().close();
  });

  await step("return to supplier: staff drafts with server limits, cannot post own draft, business owner posts and stock goes down", async () => {
    const page = await open(P.staff, 390);
    await page.click(`.occ-row[data-po='${po1}']`); await page.waitForSelector(".pu-grn[data-status=posted]");
    await page.click(".pu-grn[data-status=posted] [data-k=return]");
    const form = page.locator("form.occ-panel");
    const sugar = form.locator("fieldset.pu-line").nth(0);
    assert.match(await sugar.textContent(), /গ্রহণযোগ্য ৯৫ · ফেরত ০ · ফেরতযোগ্য ৯৫/);
    assert.match(await form.locator("fieldset.pu-line").nth(1).textContent(), /ফেরতযোগ্য ১৫/);
    assert.match(await form.textContent(), /ফেরতযোগ্য = গ্রহণযোগ্য − আগে ফেরত − খসড়া ফেরতে রাখা পরিমাণ/, "formula shown");
    await form.locator("button[type=submit]").click();
    assert.match(await form.locator(".occ-field-error").textContent(), /অন্তত একটি লাইনে ফেরতের পরিমাণ দিন/);
    await sugar.locator("input[data-k=rqty]").fill("200"); await form.locator("input[data-k=reason]").fill("ভেজা বস্তা");
    await form.locator("button[type=submit]").click();
    await page.waitForSelector(".occ-field-error[data-code=PROC_RETURN_EXCEEDS_ACCEPTED]");
    assert.match(await form.locator(".occ-field-error").textContent(), /ফেরতের পরিমাণ ফেরতযোগ্য পরিমাণের বেশি/);
    assert.strictEqual(returns(), 0, "the server refused: nothing written");
    await sugar.locator("input[data-k=rqty]").fill("১০");
    await noOverflow(page);
    await shot(page, "pu-return-form-390-bn");
    await form.locator("button[type=submit]").click();
    await page.waitForSelector(".pu-return[data-ret-status=draft]");
    assert.match(await page.textContent(".occ-status"), /ফেরতের খসড়া তৈরি হয়েছে — পোস্ট করলে স্টক কমবে/);
    assert.match(await page.textContent(".pu-return"), /চিনি ১০[\s\S]*তৈরি করেছেন: আপনি[\s\S]*কারণ: ভেজা বস্তা/);
    assert.strictEqual(balance(1601111, "SUGAR"), "95.000", "a draft does not move stock");
    await page.click(".pu-return [data-k=ret-post]");
    await page.waitForSelector(".occ-detail .pu-flash[data-code=PROC_SAME_ACTOR]");
    assert.match(await page.textContent(".occ-detail .pu-flash"), /যিনি ফেরতের খসড়া করেছেন তিনি নিজে পোস্ট করতে পারবেন না/);
    assert.strictEqual(sql("SELECT status FROM core10.supplier_returns_v1 WHERE business_id=16011"), "draft");
    await noJargon(page); await noOverflow(page);
    await shot(page, "pu-return-same-person-390-bn");
    await page.context().close();
    const bo = await open(P.bo, 1440, "en");
    await bo.click(`.occ-row[data-po='${po1}']`); await bo.waitForSelector(".pu-return[data-ret-status=draft]");
    await bo.click(".pu-return [data-k=ret-post]");
    await bo.waitForSelector(".pu-return[data-ret-status=posted]");
    assert.match(await bo.textContent(".occ-status"), /Return posted — stock reduced/);
    assert.strictEqual(balance(1601111, "SUGAR"), "85.000", "the return took 10 sugar out of the store");
    assert.strictEqual(sql("SELECT l.returned_qty FROM core10.goods_receipt_lines_v1 l JOIN core10.goods_receipts_v1 g ON g.id=l.grn_id JOIN core10.items i ON i.id=l.item_id WHERE g.po_id=" + po1 + " AND g.status='posted' AND i.sku='SUGAR'"), "10.000");
    assert.strictEqual((await poLines(bo))[0][7], "10", "order line shows the returned quantity");
    assert.match(await bo.textContent(".pu-grn[data-status=posted]"), /Returned/);
    assert.strictEqual(await bo.$(".pu-return[data-ret-status=posted] [data-k=ret-post]"), null, "a posted return has no more actions");
    await noJargon(bo); await noOverflow(bo);
    await shot(bo, "pu-return-posted-1440-en");
    await bo.context().close();
  });

  await step("return draft holds quantity until cancelled; cancelling (with confirmation) moves no stock", async () => {
    const page = await open(P.staff, 390);
    await page.click(`.occ-row[data-po='${po1}']`); await page.waitForSelector(".pu-grn[data-status=posted]");
    await page.click(".pu-grn[data-status=posted] [data-k=return]");
    let form = page.locator("form.occ-panel");
    assert.match(await form.locator("fieldset.pu-line").nth(0).textContent(), /ফেরত ১০ · ফেরতযোগ্য ৮৫/, "accepted 95 − returned 10");
    await form.locator("fieldset.pu-line").nth(1).locator("input[data-k=rqty]").fill("5"); await form.locator("input[data-k=reason]").fill("মোড়ক ছেঁড়া");
    await form.locator("button[type=submit]").click();
    await page.waitForSelector(".pu-return[data-ret-status=draft]");
    await page.click(".pu-grn[data-status=posted] [data-k=return]");
    form = page.locator("form.occ-panel");
    assert.match(await form.locator("fieldset.pu-line").nth(1).textContent(), /ফেরতযোগ্য ১০/, "the draft holds 5 of the 15 ghee");
    await form.locator("button", { hasText: "ফিরে যান" }).click();
    await page.click(".pu-return[data-ret-status=draft] [data-k=ret-cancel]");
    await page.click(".pu-confirm button:has-text('না')");
    assert.strictEqual(await page.$(".pu-return[data-ret-status=draft] .pu-confirm"), null, "No keeps the draft");
    await page.click(".pu-return[data-ret-status=draft] [data-k=ret-cancel]");
    assert.match(await page.textContent(".pu-confirm"), /কোনো স্টক বদলাবে না/);
    await page.click(".pu-confirm button:has-text('হ্যাঁ, নিশ্চিত')");
    await page.waitForFunction(() => document.querySelectorAll(".pu-return[data-ret-status=cancelled]").length === 1);
    assert.match(await page.textContent(".occ-status"), /ফেরতের খসড়া বাতিল হয়েছে/);
    assert.strictEqual(balance(1601111, "GHEE"), "15.000", "cancelled draft moved nothing");
    assert.strictEqual(sql("SELECT string_agg(status,',' ORDER BY id) FROM core10.supplier_returns_v1 WHERE business_id=16011"), "posted,cancelled");
    await noJargon(page); await noOverflow(page);
    await shot(page, "pu-return-cancelled-390-bn");
    await page.context().close();
  });

  await step("owner switch-off of returns to the supplier: Bangla and English message, nothing written", async () => {
    setControl("procurement.supplier_return", false, 0, "pu-ctl-ret-off");
    try {
      const before = returns();
      for (const [width, lang, re] of [[390, null, /মালিক এই সুবিধাটি বন্ধ রেখেছেন: সরবরাহকারীকে মাল ফেরত/], [1440, "en", /The owner has switched this off: Returns to supplier/]]) {
        const page = await open(P.staff, width, lang);
        await page.click(`.occ-row[data-po='${po1}']`); await page.waitForSelector(".pu-grn[data-status=posted]");
        await page.click(".pu-grn[data-status=posted] [data-k=return]");
        const form = page.locator("form.occ-panel");
        await form.locator("fieldset.pu-line").nth(0).locator("input[data-k=rqty]").fill("1"); await form.locator("input[data-k=reason]").fill("test return");
        await form.locator("button[type=submit]").click();
        await page.waitForSelector(".occ-field-error[data-code=CONTROL_DISABLED]");
        assert.match(await form.locator(".occ-field-error").textContent(), re);
        await noJargon(page); await noOverflow(page);
        await shot(page, `pu-return-switch-off-${width}-${lang || "bn"}`);
        await page.context().close();
      }
      assert.strictEqual(returns(), before, "nothing written while switched off");
    } finally { setControl("procurement.supplier_return", true, 0, "pu-ctl-ret-on"); }
  });

  await step("lot expiry list: earliest expiry first, net after returns, keyset paging, N-days filter, other tenant sees none", async () => {
    const lotRows = (page) => page.$$eval(".pu-lots tbody tr", (r) => r.map((x) => [x.dataset.lot].concat(Array.from(x.cells).map((c) => c.textContent))));
    const en = await open(P.own, 1440, "en", null, "&lotpage=1");
    await en.click("[data-view=lots]"); await en.waitForSelector(".pu-lots tbody tr");
    assert.deepStrictEqual((await lotRows(en)).map((r) => r[0]), ["GHEE-01"], "page size 1: the earliest expiry first");
    await en.click("[data-k=lots-more]"); await en.waitForFunction(() => document.querySelectorAll(".pu-lots tbody tr").length === 2);
    await en.click("[data-k=lots-more]"); await en.waitForFunction(() => !document.querySelector("[data-k=lots-more]"));
    const rows2 = await lotRows(en);
    assert.deepStrictEqual(rows2.map((r) => r[0]), ["GHEE-01", "SUG-2611"], "paging ends after the last lot, no duplicates");
    assert.deepStrictEqual(rows2[1].slice(3), [EXP_SUGAR, daysLeft(EXP_SUGAR), "85", "95", "10", "Main godown"], "sugar lot: net = 95 accepted − 10 returned");
    assert.match(await en.textContent(".pu-lots"), /Days left = expiry date − today/);
    await noJargon(en); await noOverflow(en);
    await shot(en, "pu-lots-1440-en");
    await en.context().close();
    const bn = await open(P.staff, 390);
    await bn.click("[data-view=lots]"); await bn.waitForSelector(".pu-lots tbody tr");
    assert.strictEqual((await lotRows(bn)).length, 2, "godown staff sees the lots received at the godown");
    await bn.fill("input[data-k=days]", "৯৯৯৯"); await bn.click("[data-k=days-go]");
    assert.match(await bn.textContent(".pu-lots .occ-field-error"), /দিনের সংখ্যা ০ থেকে ৩৬৫০ এর মধ্যে দিন/);
    const n = daysLeft(EXP_GHEE);
    await bn.fill("input[data-k=days]", n.replace(/[0-9]/g, (d) => "০১২৩৪৫৬৭৮৯"[d])); await bn.click("[data-k=days-go]");
    await bn.waitForFunction(() => document.querySelectorAll(".pu-lots tbody tr").length === 1);
    assert.deepStrictEqual((await lotRows(bn)).map((r) => r[0]), ["GHEE-01"], "only the lot expiring within N days");
    await noJargon(bn); await noOverflow(bn);
    await shot(bn, "pu-lots-filter-390-bn");
    await bn.click("[data-k=days-all]"); await bn.waitForFunction(() => document.querySelectorAll(".pu-lots tbody tr").length === 2);
    await bn.context().close();
    const other = await open(P.other, 390);
    await other.click("[data-view=lots]"); await other.waitForSelector(".pu-lots .occ-empty");
    assert.match(await other.textContent(".pu-lots"), /কোনো লট নেই/);
    assert.ok(!/SUG-2611|GHEE-01/.test(await other.textContent("body")), "no lot of the other tenant");
    await other.context().close();
  });

  await step("0209 lot-aware return: the lot no longer holds the quantity, posting is refused with the stock message in en/bn, nothing moves", async () => {
    const lotOnHand = () => sql(`SELECT coalesce(sum(b.on_hand),0) FROM core10.stock_lot_balances_v1 b JOIN core10.inventory_lots_v1 l ON l.id=b.lot_id WHERE l.business_id=16011 AND l.lot_code='SUG-2611' AND b.location_id=1601111`);
    const sugarId = sql("SELECT id FROM core10.items WHERE business_id=16011 AND sku='SUGAR'");
    assert.strictEqual(lotOnHand(), "85.000", "lot SUG-2611 carries the store's 85 sugar after the posted return");
    // 80 sugar issued without a lot (FEFO takes it from SUG-2611), then 80 untracked sugar arrives: the store still
    // has 85 sugar, but the received lot has only 5 left.
    asActor(P.own, `SELECT core10.post_stock_event(1601111,${sugarId},-80,'pu-lot-issue-0001'), core10.post_stock_event(1601111,${sugarId},80,'pu-untracked-0001') \\g /dev/null`);
    assert.strictEqual(balance(1601111, "SUGAR"), "85.000"); assert.strictEqual(lotOnHand(), "5.000", "FEFO issue took 80 from the lot");
    const staff = await open(P.staff, 390);
    await staff.click(`.occ-row[data-po='${po1}']`); await staff.waitForSelector(".pu-grn[data-status=posted]");
    await staff.click(".pu-grn[data-status=posted] [data-k=return]");
    const form = staff.locator("form.occ-panel");
    await form.locator("fieldset.pu-line").nth(0).locator("input[data-k=rqty]").fill("১০"); await form.locator("input[data-k=reason]").fill("দেরিতে পাওয়া ত্রুটি");
    await form.locator("button[type=submit]").click();
    await staff.waitForSelector(".pu-return[data-ret-status=draft]");
    await staff.context().close();
    const posted = () => sql("SELECT count(*) FROM core10.supplier_returns_v1 WHERE business_id=16011 AND status='posted'");
    const before = posted(), moves = sql("SELECT count(*) FROM core10.stock_movements WHERE business_id=16011");
    for (const [width, lang, re] of [[1440, "en", /This store does not have that much stock — this quantity cannot be returned/], [390, null, /এই গুদামে এত মজুদ নেই — এই পরিমাণ ফেরত দেওয়া যাবে না/]]) {
      const bo = await open(P.bo, width, lang);
      await bo.click(`.occ-row[data-po='${po1}']`); await bo.waitForSelector(".pu-return[data-ret-status=draft]");
      await bo.click(".pu-return[data-ret-status=draft] [data-k=ret-post]");
      await bo.waitForSelector(".occ-detail .pu-flash[data-code=PROC_INSUFFICIENT_STOCK]");
      assert.match(await bo.textContent(".occ-detail .pu-flash"), re);
      await noJargon(bo); await noOverflow(bo);
      assert.ok(!/insufficient_lot_stock/.test(await bo.textContent("body")), "no raw engine message on the screen");
      await shot(bo, `pu-return-lot-short-${width}-${lang || "bn"}`);
      await bo.context().close();
    }
    assert.strictEqual(posted(), before, "the return was not posted");
    assert.strictEqual(sql("SELECT count(*) FROM core10.stock_movements WHERE business_id=16011"), moves, "no stock movement written");
    assert.strictEqual(balance(1601111, "SUGAR"), "85.000"); assert.strictEqual(lotOnHand(), "5.000");
    const r = sql("SELECT id||','||version FROM core10.supplier_returns_v1 WHERE business_id=16011 AND status='draft'").split(",");
    asUser(P.staff, `SELECT core10.procurement_advance_return_v1(${r[0]},'cancel',${r[1]},'pu-ret-lot-cancel-01') \\g /dev/null`);
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
