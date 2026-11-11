"use strict";
/* C10-A056 real-DOM browser test (390px Android + 1440px desktop) against the SYNTHETIC TEST ADAPTER demo backend.
 * Proves UI wiring, journey, consent blocking, injection safety, tenant isolation, responsive layout. Not real backend proof. */
const assert = require("node:assert/strict");
const fs = require("fs"), os = require("os"), path = require("path");
const { chromium } = require("playwright");
const { createServer } = require("./static_server");
const SHOTS = process.env.A056_SHOTS || path.join(os.tmpdir(), "a056-shots");
fs.mkdirSync(SHOTS, { recursive: true });
const HOSTILE = "<img src=x onerror=window.__xss=1>";
(async () => {
  const server = createServer(); await new Promise(r => server.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + server.address().port;
  const browser = await chromium.launch();
  try {
    for (const width of [390, 1440]) {
      const page = await browser.newPage({ viewport: { width, height: 900 } });
      const errors = [], external = [];
      page.on("pageerror", e => errors.push("pageerror " + e.message));
      page.on("console", m => { if (m.type() === "error") errors.push("console " + m.text()); });
      page.on("request", r => { const u = r.url(); if (!u.startsWith(base) && !u.startsWith("data:") && !u.startsWith("blob:")) external.push(u); });
      const ready = async (route) => page.waitForSelector('#crm-root[data-ready="' + route + '"]', { timeout: 10000 });
      const go = async (route, arg) => { await page.evaluate(h => { location.hash = h; }, "#/" + route + (arg ? "/" + arg : "")); await ready(route); await page.waitForTimeout(60); };
      const toast = async () => (await page.locator("#toast").innerText());
      const noOverflow = async (label) => { const o = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth); assert.ok(o <= 2, label + " @" + width + " overflow " + o); };
      const shot = async (n) => page.screenshot({ path: path.join(SHOTS, "a056-" + n + "-" + width + ".png"), fullPage: true });
      await page.goto(base + "/core10-crm-lifecycle.html"); await ready("dashboard");
      assert.match(await page.locator("#syn-banner").innerText(), /SYNTHETIC TEST ADAPTER/);
      assert.equal(await page.locator("#kpi-tickets").count(), 1);
      await noOverflow("dashboard"); await shot("dashboard");
      // help what/why/when
      await page.locator('button.help').first().click();
      assert.match(await page.locator(".helpbox:not([hidden])").first().innerText(), /What:[\s\S]*Why:[\s\S]*When:/);
      // Bangla toggle
      await page.locator("#lang-btn").click(); await page.waitForFunction(() => document.documentElement.lang === "bn");
      assert.match(await page.locator("h1").innerText(), /ড্যাশবোর্ড/); await noOverflow("dashboard-bn"); await shot("dashboard-bn");
      await page.locator("#lang-btn").click(); await page.waitForFunction(() => document.documentElement.lang === "en");

      // ---- Journey: Lead (hostile payload) -> Enquiry -> Opportunity
      await go("intake");
      await page.selectOption("#in-source", "website"); await page.fill("#in-name", HOSTILE); await page.fill("#in-contact", "+8801799000" + width); await page.fill("#in-note", "Wedding sweets for 200 guests");
      await page.click("#in-submit"); await ready("leads");
      assert.match(await page.locator("main").innerText(), /<img src=x onerror=window.__xss=1>/, "payload shown as text");
      assert.equal(await page.locator("main img").count(), 0, "no injected element");
      assert.equal(await page.evaluate(() => window.__xss), undefined, "XSS did not run");
      await noOverflow("leads"); await shot("leads");
      const lrow = page.locator("tr", { hasText: "Wedding sweets" }).first();
      await lrow.locator('button[value="convert"]').click(); await page.waitForSelector("#toast");
      assert.match(await toast(), /Enquiry created/);
      await page.locator("tr", { hasText: "Wedding sweets" }).last().locator("button", { hasText: "Create opportunity" }).click(); await ready("opp");
      assert.equal(await page.evaluate(() => window.__xss), undefined);
      // ---- Quotation: unpriced line blocks send, then versions
      const rows = page.locator(".qrow");
      await rows.nth(0).locator('[name="desc"]').fill("Sweet box x"); await rows.nth(0).locator('[name="qty"]').fill("100"); await rows.nth(0).locator('[name="price"]').fill("50");
      await rows.nth(1).locator('[name="desc"]').fill("Delivery (price unknown)"); await rows.nth(1).locator('[name="qty"]').fill("1");
      await page.click("#q-save"); await page.waitForSelector("#toast");
      assert.match(await page.locator("main").innerText(), /unpriced/);
      await page.click("#q-submit"); await page.waitForSelector("#toast.err");
      assert.match(await toast(), /UNPRICED/, "unpriced blocks send");
      await page.click("#q-add"); assert.equal(await page.locator(".qrow").count(), 3);
      await page.locator(".qrow").nth(1).locator('[name="price"]').fill("500"); await page.fill("#q-disc", "15"); await page.click("#q-save");
      await page.waitForSelector("#toast.okm"); assert.equal(await page.locator("table tbody tr", { hasText: "15%" }).count() >= 1, true);
      await page.click("#q-submit"); await page.waitForSelector("#q-approve", { timeout: 5000 });
      // role sales cannot approve a >10% discount; owner can
      await page.selectOption("#role-sel", "sales"); await page.waitForSelector("#role-sel");
      await page.waitForFunction(() => !document.querySelector("#q-approve")); await page.selectOption("#role-sel", "owner");
      await page.waitForSelector("#q-approve"); await page.click("#q-approve"); await page.waitForSelector("#q-accept");
      await noOverflow("opp"); await shot("quote");
      await page.click("#q-accept"); await page.waitForSelector("#order-request"); await page.click("#order-request"); await page.waitForSelector("#adapter");
      assert.match(await page.locator("#adapter").innerText(), /SYNTHETIC TEST ADAPTER[\s\S]*NOT CERTIFIED/);
      for (const s of ["approve", "pick", "dispatch", "deliver", "invoice", "pay"]) { await page.click("#ad-" + s); await page.waitForFunction(x => document.querySelector("#toast") && /Adapter step done/.test(document.querySelector("#toast").textContent), s); }
      assert.match(await page.locator("#adapter").innerText(), /PAID/); assert.match(await page.locator("#journey-steps").innerText(), /PAID/);
      await noOverflow("adapter"); await shot("order");
      // customer 360 (new customer, created from lead): balance, timeline, support
      await page.locator('a[href^="#/customer/"]').first().click(); await ready("customer");
      assert.match(await page.locator("#timeline").innerText(), /Opportunity .* opened/); assert.match(await page.locator("#timeline").innerText(), /Adapter \(SYNTHETIC\) step 'pay'/);
      assert.match(await page.locator("main").innerText(), /SYNTHETIC adapter figure - NOT CERTIFIED/);
      const custHash = await page.evaluate(() => location.hash);
      await go("support"); const cid = custHash.split("/").pop();
      await page.selectOption("#tk-c", cid); await page.fill("#tk-s", "Sweets arrived late <b>x</b>"); await page.selectOption("#tk-t", "return_request"); await page.selectOption("#tk-p", "urgent"); await page.click("#tk-create");
      await page.waitForSelector("#toast.okm"); const tr = page.locator("tr", { hasText: "arrived late" });
      assert.match(await tr.innerText(), /<b>x<\/b>/, "ticket html inert"); assert.equal(await tr.locator("b").count(), 0);
      await tr.locator("button", { hasText: "Start" }).click(); await page.waitForSelector("tr:has-text('IN_PROGRESS')");
      await tr.locator('[name="resolution"]').fill("Credit note requested"); await tr.locator('[name="evidence"]').fill("Call log #77"); await tr.locator("button", { hasText: "Resolve" }).click();
      await page.waitForSelector("tr:has-text('Call log #77')"); await noOverflow("support"); await shot("support");

      // ---- Missing balance never zero: Karim has no invoiced order in this tenant? (seed has ISSUED history) -> use T2 org without invoice
      // ---- Consent blocks send
      await go("segments"); await page.fill("#sg-n", "Everyone SMS"); await page.fill("#sg-m", "0"); await page.selectOption("#sg-c", "sms"); await page.click('form[data-form="seg_create"] button[type=submit]');
      await page.waitForSelector("#toast.okm");
      await go("campaigns");
      assert.match(await page.locator("#providers").innerText(), /DISABLED \(no-op\)/);
      await page.fill("#cp-n", "Eid offer"); await page.locator("#cp-s").selectOption({ label: "Everyone SMS" }); await page.selectOption("#cp-c", "sms"); await page.fill("#cp-m", "Eid sweets 10% off"); await page.click("#cp-create");
      await page.waitForSelector("button:has-text('Send (consent-checked)')"); await page.locator("button", { hasText: "Send (consent-checked)" }).last().click();
      await page.waitForSelector("[id^=res-]"); const res = await page.locator("[id^=res-]").first().innerText();
      assert.match(res, /external messages sent: 0/); assert.match(res, /Karim Uddin - no consent/); assert.match(res, /Dhanmondi Event Planners Ltd - opted out/); assert.match(res, /Salma Begum - consent expired/);
      await noOverflow("campaigns"); await shot("campaigns");
      // consent change flips eligibility
      await go("customers"); await page.locator("a", { hasText: "Karim Uddin" }).click(); await ready("customer");
      await page.click("#cons-C-1002-sms-granted"); await page.waitForSelector("#toast.okm:has-text('Consent updated')");
      assert.match(await page.locator("main").innerText(), /yes/); await noOverflow("customer"); await shot("customer");
      // loyalty
      await page.fill('form[data-form="loy"] [name="points"]', "25"); await page.fill('form[data-form="loy"] [name="reason"]', "goodwill"); await page.click('form[data-form="loy"] button'); await page.waitForSelector("#toast.okm:has-text('Points adjusted')");
      assert.match(await page.locator("#loy-points").innerText(), /^\d+/);
      // follow-up
      await page.fill('form[data-form="fu_create"] [name="note"]', "Call back"); await page.click('form[data-form="fu_create"] button'); await page.waitForSelector("#toast.okm:has-text('Follow-up scheduled')");
      await go("followups"); await page.locator("tr", { hasText: "Call back" }).locator("button", { hasText: "Done" }).click(); await page.waitForSelector("tr:has-text('Call back'):has-text('done')");
      // ---- Reports
      await go("reports"); assert.match(await page.locator("#rep-profit").innerText(), /NOT CERTIFIED/); assert.match(await page.locator("#rep-tickets").innerText(), /resolved/);
      await noOverflow("reports"); await shot("reports");
      // CSV injection neutral
      await go("customers"); await page.fill("#cc-name", "=HYPERLINK(\"http://evil\")"); await page.click("#cc-save"); await ready("customer");
      await go("reports"); await page.click("#cust-export"); await page.waitForFunction(() => !!window.CORE10_LAST_CSV);
      const csv = await page.evaluate(() => window.CORE10_LAST_CSV); assert.match(csv, /"'=HYPERLINK/); assert.ok(!/(^|\n)"?=HYPERLINK/.test(csv));
      // ---- Settings: custom stage, permission, locked owner
      await go("settings"); assert.equal(await page.locator('#perm-matrix input[disabled][data-role="owner"]').count() > 0, true);
      await page.fill('form[data-form="stage_add"] [name="key"]', "site_visit"); await page.fill('form[data-form="stage_add"] [name="en"]', "Site visit"); await page.fill('form[data-form="stage_add"] [name="bn"]', "সাইট ভিজিট"); await page.click("#stg-add");
      await page.waitForSelector("#stg-site_visit-save"); await noOverflow("settings"); await shot("settings");
      await go("pipeline"); assert.match(await page.locator("#board").innerText(), /Site visit/); await noOverflow("pipeline"); await shot("pipeline");
      for (const r of ["followups", "quotes", "segments", "loyalty", "journey", "leads"]) { await go(r); assert.equal(await page.locator("#view-error").count(), 0, r + " error"); await noOverflow(r); }
      // standalone entry pages load
      for (const f of ["customers", "pipeline", "support", "campaigns", "reports", "settings", "intake"]) { await page.goto(base + "/core10-crm-lifecycle-" + f + ".html"); await ready(f); await noOverflow("entry-" + f); }
      // ---- Tenant isolation
      await page.goto(base + "/core10-crm-lifecycle-customers.html"); await ready("customers");
      assert.match(await page.locator("main").innerText(), /Nusrat Jahan/);
      await page.selectOption("#tenant-sel", "T2"); await page.waitForFunction(() => /Meghna/.test(document.querySelector("main").innerText));
      const t2 = await page.locator("main").innerText(); assert.ok(!/Nusrat|Karim|img src|Everyone SMS/.test(t2), "no tenant leakage"); 
      await go("customer", cid); // T1-only id under T2 -> not found
      assert.match(await page.locator("#view-error").innerText(), /NOT_FOUND|not found/i);
      assert.deepEqual(errors.filter(e => !/NOT_FOUND|404/.test(e)), [], "console/page errors");
      assert.deepEqual(external, [], "external requests");
      await page.close();
    }
    console.log("A056 CRM browser test PASS (390 + 1440); screenshots in " + SHOTS);
  } finally { await browser.close(); server.close(); }
})().catch(e => { console.error(e); process.exit(1); });
