"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const site = (p) => fs.readFileSync(path.join(ROOT, "apps/central/site", p), "utf8");
const EXPECTED = ["home", "business", "master", "stock", "sales", "manufacturing", "control", "features", "approvals", "staff", "setup"].sort();

test("§7b.4 keeps every original route in desktop + mobile nav without adding a new auth or backend", () => {
  const html = site("index.html");
  const app = site("app.js");
  const desktop = [...html.matchAll(/data-route="([^"]+)"/g)].map((m) => m[1]).sort();
  const mobile = [...html.matchAll(/data-mobile-route="([^"]+)"/g)].map((m) => m[1]).sort();
  assert.deepEqual(desktop, EXPECTED, "desktop keeps the exact 11 existing routes");
  assert.deepEqual(mobile, EXPECTED, "mobile must expose the same 11 routes");
  assert.equal((html.match(/class="c10-nav-section"/g) || []).length, 3);
  assert.equal((html.match(/class="c10-mobilebar"/g) || []).length, 1);
  assert.match(app, /var DRAFT = \{ sales: true, manufacturing: true \}/);
  assert.doesNotMatch([html, app, site("app.css")].join("\n"), /BOS_CONFIG|kbuhnpqooycqbzrfejcs|luoeyyngayxpqecuuijb/);
  assert.ok(!/auth\/v1|rest\/v1|fetch\(/.test(app), "shell has no new backend/client auth calls");
});

test("§7b.4 browser: mobile More, keyboard Escape, back, bn/en and desktop groups", { timeout: 120000 }, async () => {
  const { chromium } = require("playwright");
  const { serve } = await import(path.join(ROOT, "apps/central/local-serve.mjs"));
  const server = await serve(0);
  const browser = await chromium.launch({ headless: true });
  const base = "http://127.0.0.1:" + server.address().port;
  let mobile, desktop;
  try {
    mobile = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    mobile.on("pageerror", (e) => errors.push(e.message));
    await mobile.goto(base + "/#/home", { waitUntil: "load" });
    assert.equal(await mobile.locator(".c10-mobilebar").isVisible(), true);
    assert.equal(await mobile.locator(".c10-nav").isVisible(), false);
    assert.equal(await mobile.locator(".c10-mobilebar a").count(), 4);
    assert.equal(await mobile.locator("#c10-mobile-more").isVisible(), false);
    assert.equal(await mobile.locator('[data-mobile-route="home"]').first().getAttribute("aria-current"), "page");
    assert.equal(await mobile.getByRole("navigation", { name: "মোবাইলের প্রধান নেভিগেশন" }).isVisible(), true);
    assert.equal(await mobile.locator('.c10-mobilebar [data-mobile-route="approvals"]').innerText(), "অনুমোদন");
    assert.equal(await mobile.locator(".c10-nav [data-route='approvals'] .bn").textContent(), "অনুমোদন");

    const workspaceBody = mobile.frameLocator("#c10-frame").locator("body");
    await workspaceBody.waitFor();
    const palette = [
      ["light", "rgb(244, 245, 247)", "rgb(23, 32, 43)"],
      ["dark", "rgb(16, 20, 24)", "rgb(231, 235, 240)"],
    ];
    for (const [colorScheme, background, foreground] of palette) {
      await mobile.emulateMedia({ colorScheme });
      for (const body of [mobile.locator("body"), workspaceBody]) {
        const style = await body.evaluate(node => {
          const { backgroundColor, color, fontFamily } = getComputedStyle(node);
          return { backgroundColor, color, fontFamily };
        });
        assert.equal(style.backgroundColor, background);
        assert.equal(style.color, foreground);
        assert.match(style.fontFamily, /Noto Sans Bengali/);
      }
    }

    await mobile.locator("#c10-more-toggle").click();
    assert.equal(await mobile.locator("#c10-more-toggle").getAttribute("aria-expanded"), "true");
    assert.equal(await mobile.locator("#c10-mobile-more").isVisible(), true);
    await mobile.keyboard.press("Escape");
    assert.equal(await mobile.locator("#c10-mobile-more").isVisible(), false);
    assert.equal(await mobile.locator("#c10-more-toggle").getAttribute("aria-expanded"), "false");
    assert.equal(await mobile.evaluate(() => document.activeElement?.id), "c10-more-toggle");

    await mobile.locator("#c10-more-toggle").click();
    await mobile.locator('#c10-mobile-more [data-mobile-route="master"]').click();
    await mobile.waitForFunction(() => document.body.dataset.view === "master");
    assert.equal(new URL(mobile.url()).hash, "#/master");
    assert.equal(await mobile.locator("#c10-mobile-more").isVisible(), false);
    assert.equal(await mobile.locator("#c10-more-toggle").getAttribute("aria-current"), "page");

    await mobile.locator('.c10-mobilebar [data-mobile-route="stock"]').click();
    await mobile.waitForFunction(() => document.body.dataset.view === "stock");
    assert.equal(await mobile.locator('.c10-mobilebar [data-mobile-route="stock"]').getAttribute("aria-current"), "page");
    // Hash-only navigation does not fire another page load. Verify the actual History API result.
    await mobile.evaluate(() => history.back());
    await mobile.waitForFunction(() => document.body.dataset.view === "master");
    assert.equal(await mobile.locator("#c10-more-toggle").getAttribute("aria-current"), "page");
    await mobile.locator('[data-set-lang="en"]').click();
    assert.equal(await mobile.locator("html").getAttribute("lang"), "en");
    assert.equal(await mobile.getByRole("navigation", { name: "Mobile primary navigation" }).isVisible(), true);
    assert.equal(await mobile.locator('.c10-mobilebar [data-mobile-route="approvals"]').innerText(), "Approvals");
    assert.equal(await mobile.locator(".c10-nav [data-route='approvals'] .en").textContent(), "Approvals");
    assert.equal(await mobile.locator("#c10-business").getAttribute("aria-label"), "Business");
    assert.equal(await mobile.locator("#c10-more-toggle").getAttribute("aria-current"), "page");
    assert.equal(await mobile.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true);
    assert.deepEqual(errors, []);

    desktop = await browser.newPage({ viewport: { width: 1440, height: 900 } });
    await desktop.goto(base + "/#/home", { waitUntil: "load" });
    assert.equal(await desktop.locator(".c10-nav").isVisible(), true);
    assert.equal(await desktop.locator(".c10-mobilebar").isVisible(), false);
    assert.equal(await desktop.locator(".c10-nav-section").count(), 3);
    assert.equal(await desktop.locator(".c10-nav [data-route]").count(), 11);
    assert.equal(await desktop.getByRole("navigation", { name: "প্রধান নেভিগেশন" }).isVisible(), true);
    assert.equal(await desktop.locator("#c10-business").getAttribute("aria-label"), "ব্যবসা");
    await desktop.getByRole("button", { name: "EN", exact: true }).click();
    assert.equal(await desktop.getByRole("navigation", { name: "Main" }).isVisible(), true);
    assert.equal(await desktop.getByRole("link", { name: "Setup & access" }).isVisible(), true);
    assert.equal(await desktop.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true);
  } finally {
    if (mobile) await mobile.close();
    if (desktop) await desktop.close();
    await browser.close();
    await new Promise((resolve, reject) => server.close((err) => err ? reject(err) : resolve()));
  }
});
