"use strict";
const assert = require("node:assert/strict");
const http = require("node:http");
const fs = require("node:fs/promises");
const path = require("node:path");
const { chromium } = require("playwright");

(async () => {
  const { default: worker } = await import("../../preview/worker.mjs");
  const root = path.resolve(__dirname, "../..");
  const priorFetch = globalThis.fetch;
  globalThis.fetch = async url => {
    const parsed = new URL(String(url));
    assert.equal(parsed.hostname, "raw.githubusercontent.com");
    const name = parsed.pathname.split("/").pop();
    assert.match(name, /^core10-[a-z-]+\.(?:html|js|css)$/);
    return new Response(await fs.readFile(path.join(root, name)), { status: 200 });
  };
  const server = http.createServer(async (req, res) => {
    try {
      const response = await worker.fetch(new Request("http://127.0.0.1" + req.url, { method: req.method }));
      res.writeHead(response.status, Object.fromEntries(response.headers));
      res.end(Buffer.from(await response.arrayBuffer()));
    } catch (error) { res.writeHead(500); res.end(error.message); }
  });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  const base = "http://127.0.0.1:" + server.address().port;
  const browser = await chromium.launch({ headless: true, ...(process.env.CORE10_CHROMIUM_PATH ? { executablePath: process.env.CORE10_CHROMIUM_PATH } : {}) });
  try {
    for (const width of [390, 1440]) {
      const page = await browser.newPage({ viewport: { width, height: 900 } });
      const errors = [], external = [];
      page.on("pageerror", e => errors.push(e.message));
      page.on("request", r => { if (!r.url().startsWith(base + "/")) external.push(r.url()); });
      await page.goto(base + "/");
      await page.getByRole("link", { name: "Purchase & Sales · Original UI snapshot" }).click();
      await page.locator("[data-order]").first().waitFor();
      assert.equal(await page.locator("[data-order]").count(), 3);
      assert.match(await page.locator("#op-status").innerText(), /Read-only A049 regression snapshot/);
      assert.equal(await page.locator('#op-form button[type="submit"]').isDisabled(), true);
      await page.locator("#op-business").selectOption("102");
      await page.waitForFunction(() => document.querySelectorAll("[data-order]").length === 1);
      assert.match(await page.locator("[data-order]").innerText(), /20 units/);
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth) <= 2, "overflow operations " + width);
      await page.getByRole("link", { name: "Inventory", exact: true }).first().click();
      await page.locator(".iv-card").first().waitFor();
      assert.equal(await page.locator(".iv-card").count(), 2);
      assert.equal(await page.locator('#iv-form button[type="submit"]').isDisabled(), true);
      assert.match(await page.locator("#iv-status").innerText(), /Read-only A049 regression snapshot/);
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth - innerWidth) <= 2, "overflow inventory " + width);
      await page.screenshot({ path: "/tmp/core10-preview-module-" + width + ".png", fullPage: true });
      assert.deepEqual(errors, []);
      assert.deepEqual(external, []);
      await page.close();
      console.log("PASS original A048/A049 read-only module UI " + width + "px, scope switch, disabled writes, navigation and no external requests");
    }
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
    globalThis.fetch = priorFetch;
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
