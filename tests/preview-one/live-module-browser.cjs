"use strict";
// Public deployed Preview One verification. No route interception or backend mocks.
const assert = require("node:assert/strict");
const { chromium } = require("playwright");
const BASE = "https://core10-central-preview-v1.mistybari99.workers.dev";

(async () => {
  let proxy;
  if (process.env.CORE10_PREVIEW_USE_PROXY === "1") {
    const address = new URL(process.env.HTTPS_PROXY || process.env.HTTP_PROXY);
    proxy = { server: address.protocol + "//" + address.host };
    if (address.username) proxy.username = decodeURIComponent(address.username);
    if (address.password) proxy.password = decodeURIComponent(address.password);
  }
  const browser = await chromium.launch({
    headless: true,
    ...(proxy ? { proxy } : {}),
    ...(process.env.CORE10_CHROMIUM_PATH ? { executablePath: process.env.CORE10_CHROMIUM_PATH } : {})
  });
  try {
    for (const width of [390, 1440]) {
      const page = await browser.newPage({
        viewport: { width, height: 900 },
        ignoreHTTPSErrors: process.env.CORE10_PREVIEW_IGNORE_HTTPS_ERRORS === "1"
      });
      const errors = [], external = [], failed = [];
      page.on("pageerror", error => errors.push(error.message));
      page.on("request", request => {
        if (!request.url().startsWith(BASE + "/")) external.push(request.url());
      });
      page.on("requestfailed", request => failed.push(request.url() + ":" + request.failure()?.errorText));
      const goto = path => page.goto(BASE + path, { waitUntil: "load", timeout: 45000 });
      const noOverflow = async label => assert.ok(
        await page.evaluate(() => document.documentElement.scrollWidth - innerWidth) <= 2,
        label + " overflow at " + width
      );
      const ready = route => page.locator('#crm-root[data-ready="' + route + '"]').waitFor({ timeout: 20000 });

      await goto("/");
      await page.locator('a[href="/core10-operational-flow.html"]').click();
      await page.locator("[data-order]").first().waitFor({ timeout: 20000 });
      assert.equal(await page.locator("[data-order]").count(), 3);
      assert.match(await page.locator("#op-status").innerText(), /Read-only A049 regression snapshot/);
      assert.equal(await page.locator('#op-form button[type="submit"]').isDisabled(), true);
      await page.locator("#op-business").selectOption("102");
      await page.waitForFunction(() => document.querySelectorAll("[data-order]").length === 1);
      assert.match(await page.locator("[data-order]").innerText(), /20 units/);
      await noOverflow("original operations");
      await page.screenshot({ path: "/tmp/core10-preview-live-operations-" + width + ".png", fullPage: true });

      await page.getByRole("link", { name: "Inventory", exact: true }).first().click();
      await page.locator(".iv-card").first().waitFor({ timeout: 20000 });
      assert.equal(await page.locator(".iv-card").count(), 2);
      assert.equal(await page.locator('#iv-form button[type="submit"]').isDisabled(), true);
      assert.match(await page.locator("#iv-status").innerText(), /Read-only A049 regression snapshot/);
      await noOverflow("original inventory");
      await page.screenshot({ path: "/tmp/core10-preview-live-inventory-" + width + ".png", fullPage: true });

      await goto("/");
      await page.locator('a[href="/core10-crm-lifecycle.html"]').click();
      await ready("dashboard");
      assert.match(await page.locator("#syn-banner").innerText(), /SYNTHETIC TEST ADAPTER/);
      await noOverflow("CRM dashboard");
      await page.evaluate(() => { location.hash = "#/intake"; });
      await ready("intake");
      await page.selectOption("#in-source", "website");
      await page.fill("#in-name", "DEMO Public Preview " + width);
      await page.fill("#in-contact", "+8801799000" + width);
      await page.fill("#in-note", "DEMO public browser journey " + width);
      await page.click("#in-submit");
      await ready("leads");
      await page.locator("tr", { hasText: "DEMO public browser journey " + width }).first().locator('button[value="convert"]').click();
      await page.waitForSelector("#toast");
      assert.match(await page.locator("#toast").innerText(), /Enquiry created/);
      await page.locator("tr", { hasText: "DEMO public browser journey " + width }).last().getByRole("button", { name: "Create opportunity" }).click();
      await ready("opp");
      assert.ok(await page.locator(".qrow").count() > 0);
      await noOverflow("CRM opportunity");
      await page.screenshot({ path: "/tmp/core10-preview-live-crm-journey-" + width + ".png", fullPage: true });

      for (const route of ["customers", "pipeline", "support", "campaigns", "reports", "settings", "intake"]) {
        await goto("/core10-crm-lifecycle-" + route + ".html");
        await ready(route);
        await noOverflow("CRM " + route);
      }
      await goto("/core10-crm-lifecycle-customers.html");
      await ready("customers");
      await page.selectOption("#tenant-sel", "T2");
      await page.waitForFunction(() => /Meghna/.test(document.querySelector("main").innerText));
      assert.doesNotMatch(await page.locator("main").innerText(), /Nusrat|Karim|DEMO Public Preview/);
      assert.deepEqual(errors, [], "public page errors");
      assert.deepEqual(external, [], "external browser requests");
      assert.deepEqual(failed, [], "failed browser requests");
      await page.close();
      console.log("PASS deployed Preview One " + width + "px: original inventory/operations snapshots; CRM lead→enquiry→opportunity; all CRM entry pages; tenant switch; no page errors, external/failed requests or overflow");
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
