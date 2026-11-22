"use strict";
// B-011: Central shell navigation contract for Owner Control and Master Data links (real Chromium, 390 and 1440 px).
// NP03A: plus the Owner-only Owner dashboard / Stock operations / Purchases links (owner header + per-business ?biz).
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
async function render(browser, width, sc, inspect) {
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
  const ids = inspect
    ? await page.$$eval("a[id]", (a) => a.map((x) => {
        const r = x.getBoundingClientRect();
        return { id: x.id, href: x.getAttribute("href"), text: x.textContent, label: x.getAttribute("aria-label") || "",
          w: r.width, h: r.height, left: r.left, right: r.right, vw: window.innerWidth,
          scroll: document.documentElement.scrollWidth, visible: getComputedStyle(x).visibility !== "hidden" && getComputedStyle(x).display !== "none" };
      }))
    : await page.$$eval("a[id]", (a) => a.map((x) => x.id + "=" + x.getAttribute("href")));
  await page.context().close();
  return inspect ? ids : ids.sort();
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
      assert.deepStrictEqual(ids, ["core10-master-data-entry=./core10-master-data.html", "core10-owner-control-centre-entry=./core10-owner-control-centre.html",
        "core10-owner-dashboard-entry=./core10-owner-dashboard.html", "core10-purchase-entry=./core10-purchase.html",
        "core10-stock-ops-entry=./core10-stock-ops.html", "core10-studio-entry=./core10-control-studio.html"]);
    });
    await step(`${w}px owner shell: Owner dashboard / Stock operations / Purchases are visible, bn+en labelled, tappable, no overflow`, async () => {
      const links = await render(browser, w, { master: true, ctx: signedIn({ is_owner: true }) }, true);
      const want = { "core10-owner-dashboard-entry": ["মালিকের ড্যাশবোর্ড", "Owner dashboard"],
        "core10-stock-ops-entry": ["স্টক কাজ", "Stock operations"], "core10-purchase-entry": ["ক্রয়", "Purchases"] };
      for (const [id, [bn, en]] of Object.entries(want)) {
        const l = links.find((x) => x.id === id);
        assert.ok(l, id + " missing");
        assert.ok(l.text.includes(bn) && l.text.includes(en), id + " label: " + l.text);
        assert.ok(l.label.length > 10, id + " aria-label");
        assert.ok(l.visible && l.w > 0 && l.h >= 40, id + " not visible/tappable: " + l.w + "x" + l.h);
        assert.ok(l.left >= 0 && l.right <= l.vw + 0.5, id + " outside viewport");
      }
      assert.ok(links[0].scroll <= links[0].vw, "horizontal overflow " + links[0].scroll + ">" + links[0].vw);
    });
    await step(`${w}px owner shell as non-owner: no owner links`, async () => {
      assert.deepStrictEqual(await render(browser, w, { master: true, ctx: signedIn({ is_owner: false, roles: ["management"] }) }), []);
      // only a literal boolean true counts; truthy look-alikes never show owner navigation
      assert.deepStrictEqual(await render(browser, w, { master: true, ctx: signedIn({ is_owner: "true" }) }), []);
      assert.deepStrictEqual(await render(browser, w, { master: true, ctx: signedIn({ is_owner: 1 }) }), []);
    });
    await step(`${w}px business workspace (own business): Master Data for that business, no owner links`, async () => {
      const ids = await render(browser, w, { master: false, ctx: signedIn({ is_owner: false }), cur: 7, list: [{ id: 7 }, { id: 8 }], search: "workspace=business&biz=7" });
      assert.deepStrictEqual(ids, ["core10-master-data-biz-entry=./core10-master-data.html?biz=7", "core10-studio-entry=./core10-business-controls.html?biz=7"]);
      // non-owner with a truthy look-alike still gets no Owner-only business links
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: signedIn({ is_owner: "true" }), cur: 7, list: [{ id: 7 }], search: "workspace=business&biz=7" }),
        ["core10-master-data-biz-entry=./core10-master-data.html?biz=7", "core10-studio-entry=./core10-business-controls.html?biz=7"]);
    });
    await step(`${w}px business workspace as Owner: Stock operations and Purchases pre-select that business only`, async () => {
      const ids = await render(browser, w, { master: false, ctx: signedIn({ is_owner: true }), cur: 7, list: [{ id: 7 }, { id: 8 }], search: "workspace=business&biz=7" });
      assert.deepStrictEqual(ids, ["core10-master-data-biz-entry=./core10-master-data.html?biz=7", "core10-purchase-biz-entry=./core10-purchase.html?biz=7",
        "core10-stock-ops-biz-entry=./core10-stock-ops.html?biz=7", "core10-studio-entry=./core10-business-controls.html?biz=7"]);
      const links = await render(browser, w, { master: false, ctx: signedIn({ is_owner: true }), cur: 7, list: [{ id: 7 }], search: "workspace=islamia&biz=7" }, true);
      for (const [id, bn, en] of [["core10-stock-ops-biz-entry", "স্টক কাজ", "Stock operations"], ["core10-purchase-biz-entry", "ক্রয়", "Purchases"]]) {
        const l = links.find((x) => x.id === id);
        assert.ok(l, id + " missing");
        assert.ok(l.text.includes(bn) && l.text.includes(en), id + " label: " + l.text);
        assert.ok(l.visible && l.w > 0 && l.h >= 44 && l.right <= l.vw + 0.5, id + " not visible/tappable");
      }
      assert.ok(!links.some((x) => x.id === "core10-owner-dashboard-entry"), "owner header link leaked into business workspace");
    });
    await step(`${w}px tampered ?biz (not the user's current/listed business): no links`, async () => {
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: signedIn(), cur: 7, list: [{ id: 7 }], search: "workspace=business&biz=99" }), []);
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: signedIn(), cur: 99, list: [{ id: 7 }], search: "workspace=business&biz=99" }), []);
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: signedIn(), cur: 7, list: [{ id: 7 }], search: "workspace=business&biz=7x" }), []);
    });
    await step(`${w}px tampered/foreign ?biz as Owner: no Stock operations / Purchases links pre-select it`, async () => {
      const owner = signedIn({ is_owner: true });
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: owner, cur: 7, list: [{ id: 7 }], search: "workspace=business&biz=99" }), []);
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: owner, cur: 99, list: [{ id: 7 }], search: "workspace=business&biz=99" }), []);
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: owner, cur: 7, list: [{ id: 7 }], search: "workspace=business&biz=7x" }), []);
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: owner, cur: 7, list: [{ id: 7 }], search: "workspace=business&biz=0" }), []);
      assert.deepStrictEqual(await render(browser, w, { master: false, ctx: owner, cur: 7, list: [{ id: 7 }], search: "biz=7" }), []);
    });
  }
  await browser.close();
  const failed = results.filter((r) => r[0] === "FAIL");
  console.log(`SHELL_NAV_BROWSER ${results.length - failed.length}/${results.length} PASS`);
  if (failed.length) process.exit(1);
})().catch((e) => { console.error(e); process.exit(1); });
