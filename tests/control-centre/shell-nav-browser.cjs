"use strict";
// B-011: Central shell navigation contract for Owner Control and Master Data links (real Chromium, 390 and 1440 px).
// The legacy shell context is stubbed: it is navigation input only. Authority stays in CORE10 (tested in
// master-data-browser.cjs and the SQL suites); these checks prove the links never appear outside the contract.
const assert = require("node:assert"), fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const SRC = fs.readFileSync(path.join(__dirname, "../../core10-control-studio-entry.js"), "utf8");
const results = [];
async function step(name, fn) {
  try { await fn(); results.push(["PASS", name]); console.log("PASS " + name); }
  catch (e) { results.push(["FAIL", name]); console.log("FAIL " + name + " :: " + String(e.message).split("\n")[0]); }
}
// scenario: { master, ctx, cur, list, search }
async function render(browser, width, sc) {
  const page = await (await browser.newContext({ viewport: { width, height: 800 } })).newPage();
  page.on("pageerror", (e) => results.push(["FAIL", "page error: " + e.message]));
  const html = `<!doctype html><html><body ${sc.master ? 'data-core10-owner="1"' : ""}><div id="app"><header class="top"></header>
    <div class="bo-section"><div class="bo-actions"></div></div></div></body></html>`;
  await page.route("http://shell.test/**", (r) => r.fulfill({ contentType: "text/html", body: html }));
  await page.goto("http://shell.test/owner.html" + (sc.search ? "?" + sc.search : ""));
  await page.evaluate((s) => {
    window.BOS_APP = { S: { ctx: s.ctx } };
    window.BOS = { biz: { cur: () => s.cur, list: () => s.list } };
  }, sc);
  await page.addScriptTag({ content: SRC });
  await page.waitForTimeout(150);
  const ids = await page.$$eval("a[id]", (a) => a.map((x) => x.id + "=" + x.getAttribute("href")));
  await page.context().close();
  return ids.sort();
}
const signedIn = (extra) => Object.assign({ profile: { id: "p-1" } }, extra || {});

(async () => {
  const browser = await chromium.launch();
  for (const w of [390, 1440]) {
    await step(`${w}px signed-out: no links anywhere`, async () => {
      assert.deepStrictEqual(await render(browser, w, { master: true, ctx: null }), []);
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: { profile: null }, cur: 5, list: [{ id: 5 }], search: "workspace=business&biz=5" }), []);
    });
    await step(`${w}px owner shell: Owner Control, Master Data and Studio links`, async () => {
      const ids = await render(browser, w, { master: true, ctx: signedIn({ is_owner: true }) });
      assert.deepStrictEqual(ids, ["core10-master-data-entry=./core10-master-data.html", "core10-owner-control-centre-entry=./core10-owner-control-centre.html", "core10-studio-entry=./core10-control-studio.html"]);
    });
    await step(`${w}px owner shell as non-owner: no owner links`, async () => {
      assert.deepStrictEqual(await render(browser, w, { master: true, ctx: signedIn({ is_owner: false, roles: ["management"] }) }), []);
    });
    await step(`${w}px business workspace (own business): Master Data for that business, no owner links`, async () => {
      const ids = await render(browser, w, { master: false, ctx: signedIn({ is_owner: false }), cur: 7, list: [{ id: 7 }, { id: 8 }], search: "workspace=business&biz=7" });
      assert.deepStrictEqual(ids, ["core10-master-data-biz-entry=./core10-master-data.html?biz=7", "core10-studio-entry=./core10-business-controls.html?biz=7"]);
    });
    await step(`${w}px tampered ?biz (not the user's current/listed business): no links`, async () => {
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: signedIn(), cur: 7, list: [{ id: 7 }], search: "workspace=business&biz=99" }), []);
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: signedIn(), cur: 99, list: [{ id: 7 }], search: "workspace=business&biz=99" }), []);
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: signedIn(), cur: 7, list: [{ id: 7 }], search: "workspace=business&biz=7x" }), []);
    });
  }
  await browser.close();
  const failed = results.filter((r) => r[0] === "FAIL");
  console.log(`SHELL_NAV_BROWSER ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length) process.exit(1);
})().catch((e) => { console.error(e); process.exit(1); });
