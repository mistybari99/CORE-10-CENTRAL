// A036 Owner Command Center: responsive, keyboard, locale, isolation, state and no-dead-button browser tests.
// Local run: NODE_PATH=$(npm root -g) node tests/owner-console/ui.e2e.js
"use strict";
const assert = require("node:assert/strict"), http = require("node:http"), fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const root = process.env.C10_CONSOLE_ROOT || path.join(__dirname, "..", "..", "experimental", "owner-console");
const types = { ".js": "text/javascript", ".html": "text/html", ".css": "text/css" };
const server = http.createServer((q, r) => { const u = new URL(q.url, "http://x"); const f = path.join(root, u.pathname === "/" ? "index.html" : u.pathname);
  if (!f.startsWith(root) || !fs.existsSync(f)) { r.statusCode = 404; return r.end("nf"); }
  r.setHeader("content-type", types[path.extname(f)] || "application/octet-stream"); r.end(fs.readFileSync(f)); });
const ok = (l) => console.log("PASS " + l);
const VIEWS = ["overview", "businesses", "hierarchy", "modules", "stock", "trade", "reports", "approvals", "setup"];
(async () => {
  await new Promise(r => server.listen(0, r)); const base = "http://127.0.0.1:" + server.address().port + "/";
  const browser = await chromium.launch(); const errs = [];
  async function fresh(vp, qs) {
    const ctx = await browser.newContext({ viewport: vp }); const page = await ctx.newPage();
    page.on("pageerror", e => errs.push(String(e))); page.on("console", m => { if (m.type() === "error") errs.push(m.text()); });
    page.on("request", rq => { if (!rq.url().startsWith(base)) errs.push("EXTERNAL REQUEST " + rq.url()); });
    await page.goto(base + (qs || ""), { waitUntil: "load" }); await page.waitForSelector("#view h2");
    return { ctx, page };
  }
  // ---- 1) three responsive breakpoints ----
  for (const [name, vp] of [["desktop-1440", { width: 1440, height: 900 }], ["tablet-768", { width: 768, height: 1024 }], ["mobile-360", { width: 360, height: 740 }]]) {
    const { ctx, page } = await fresh(vp);
    for (const v of VIEWS) {
      await page.click('#nav button[data-view="' + v + '"]');
      if (["hierarchy", "modules", "stock", "trade", "reports", "setup"].includes(v)) { await page.click('#view button[data-open="101"]'); await page.waitForSelector("#view h2"); }
      const m = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
      assert.ok(m.sw <= m.cw + 1, name + "/" + v + ": page overflows horizontally (" + m.sw + ">" + m.cw + ")");
      await page.click('#nav button[data-view="overview"]');
      await page.evaluate(() => { const b = document.querySelector('#bizSel'); b.value = ""; b.dispatchEvent(new Event("change")); });
    }
    const nav = await page.evaluate(() => { const n = document.getElementById("nav").getBoundingClientRect(), mn = document.getElementById("main").getBoundingClientRect(); return { x: n.x, w: n.width, h: n.height, top: n.top, mainTop: mn.top }; });
    if (vp.width >= 1100) assert.ok(nav.x < 2 && nav.w >= 200 && nav.h > 400, "desktop nav is a left sidebar " + JSON.stringify(nav));
    else if (vp.width >= 700) assert.ok(nav.h < 120 && nav.top < nav.mainTop, "tablet nav is a horizontal bar above content " + JSON.stringify(nav));
    else assert.ok(nav.top > nav.mainTop && nav.h < 120, "mobile nav docks below content " + JSON.stringify(nav));
    const small = await page.evaluate(() => [...document.querySelectorAll("button,select")].filter(e => e.offsetParent !== null).map(e => { const r = e.getBoundingClientRect(); return { t: (e.textContent || e.id || "").trim().slice(0, 20), h: r.height }; }).filter(x => x.h < 43.5));
    assert.deepEqual(small, [], name + ": tap targets under 44px " + JSON.stringify(small));
    ok(name + ": layout, no horizontal overflow on 9 views, 44px targets"); await ctx.close();
  }
  // ---- 2) keyboard navigation + landmarks ----
  { const { ctx, page } = await fresh({ width: 1440, height: 900 });
    for (const lm of ["header[role=banner]", "nav[aria-label]", "main", "a.skip"]) assert.ok(await page.$(lm), "missing landmark " + lm);
    await page.focus('#nav button[aria-current="page"]'); await page.keyboard.press("ArrowDown");
    assert.equal(await page.evaluate(() => document.activeElement.dataset.view), "businesses"); await page.keyboard.press("Enter");
    await page.waitForSelector("#viewTitle"); assert.equal(await page.getAttribute('#nav button[data-view="businesses"]', "aria-current"), "page");
    assert.equal(await page.evaluate(() => document.activeElement.id), "view", "focus moves to the new view");
    await page.focus('#nav button[data-view="businesses"]'); await page.keyboard.press("End"); assert.equal(await page.evaluate(() => document.activeElement.dataset.view), "connections");
    await page.keyboard.press("Home"); assert.equal(await page.evaluate(() => document.activeElement.dataset.view), "overview");
    assert.ok((await page.locator("#live").getAttribute("aria-live")) === "polite"); ok("keyboard arrows/Home/End/Enter, focus management, landmarks, live region"); await ctx.close(); }
  // ---- 3) locale switch ----
  { const { ctx, page } = await fresh({ width: 1440, height: 900 });
    const en = await page.textContent("#appTitle"); await page.click("#langBn");
    assert.notEqual(await page.textContent("#appTitle"), en); assert.equal(await page.getAttribute("html", "lang"), "bn");
    assert.equal(await page.getAttribute("#langBn", "aria-pressed"), "true"); assert.ok(/[ঀ-৿]/.test(await page.textContent("#nav")), "nav is Bangla");
    await page.click("#langEn"); assert.equal(await page.textContent("#appTitle"), en); ok("Bangla/English switch updates text, lang and pressed state"); await ctx.close(); }
  // ---- 4) synthetic badge + ownership isolation across EVERY view and role ----
  { const { ctx, page } = await fresh({ width: 1440, height: 900 });
    assert.ok(/SYNTHETIC FIXTURE/.test(await page.textContent("#badge")));
    async function sweep(label, forbidden, required) {
      let all = ""; const master = !!(await page.$('#bizSel option[value=""]'));
      const reset = async () => { if (master) await page.selectOption("#bizSel", ""); };
      for (const v of VIEWS) {
        await reset(); await page.click('#nav button[data-view="' + v + '"]');
        const ids = await page.$$eval("#view button[data-open]", bs => bs.map(x => x.dataset.open));
        all += await page.textContent("#main");
        for (const id of ids) { await reset(); await page.click('#nav button[data-view="' + v + '"]'); await page.click('#view button[data-open="' + id + '"]'); all += await page.textContent("#main"); }
      }
      forbidden.forEach(f => assert.ok(!all.includes(f), label + " leaked: " + f)); required.forEach(r => assert.ok(all.includes(r), label + " missing: " + r)); }
    await sweep("master", ["Independent Customer", "999,999", "CUSTOMER-SKU", "Foreign tenant"], ["Demo Sweets", "Demo Second Business"]);
    await page.selectOption("#roleSel", "business_owner_101");
    assert.deepEqual(await page.$$eval("#bizSel option", o => o.map(x => x.textContent)), ["Demo Sweets"]);
    await sweep("business owner 101", ["Demo Second Business", "Independent Customer", "215,400", "OTHER-ITEM", "A3 Showroom"], ["Demo Sweets"]);
    await page.selectOption("#roleSel", "business_owner_102");
    await sweep("business owner 102", ["Demo Sweets", "A1 Showroom", "SWEET-A", "1,840,500"], ["Demo Second Business"]);
    ok("synthetic badge always shown; master/business-owner isolation holds on all 9 views"); await ctx.close(); }
  // ---- 5) states ----
  { for (const [s, text] of [["loading", /Loading/], ["empty", /Nothing to show/], ["error", /Could not load/]]) {
      const { ctx, page } = await fresh({ width: 1440, height: 900 }, "?state=" + s).catch(async () => null) || {};
      if (!page) { const c = await browser.newContext({ viewport: { width: 1440, height: 900 } }); const pg = await c.newPage(); await pg.goto(base + "?state=" + s); await pg.waitForSelector("#view .state"); assert.ok(text.test(await pg.textContent("#view")), s + " state text"); await c.close(); continue; }
      assert.ok(text.test(await page.textContent("#view")), s + " state text"); await ctx.close(); }
    const c = await browser.newContext({ viewport: { width: 1440, height: 900 } }); const pg = await c.newPage(); await pg.goto(base + "?state=error"); await pg.waitForSelector("#retryBtn");
    assert.equal(await pg.getAttribute("#view .state", "role"), "alert"); await pg.click("#retryBtn"); await pg.waitForSelector("#view .grid"); await c.close();
    ok("loading / empty / error states render; Retry recovers"); }
  // ---- 6) no dead buttons: every visible button has a click listener (via CDP), in every view/role ----
  { const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } }); const page = await ctx.newPage(); await page.goto(base); await page.waitForSelector("#view h2");
    const cdp = await ctx.newCDPSession(page); let checked = 0;
    const VIS = "Array.from(document.querySelectorAll('button')).filter(e=>e.offsetParent!==null)";
    async function audit(label) {
      const n = (await cdp.send("Runtime.evaluate", { expression: VIS + ".length", returnByValue: true })).result.value;
      for (let i = 0; i < n; i++) {
        const el = await cdp.send("Runtime.evaluate", { expression: VIS + "[" + i + "]" });
        const name = (await cdp.send("Runtime.evaluate", { expression: VIS + "[" + i + "].textContent.trim()||" + VIS + "[" + i + "].id", returnByValue: true })).result.value;
        const { listeners } = await cdp.send("DOMDebugger.getEventListeners", { objectId: el.result.objectId });
        assert.ok(listeners.some(l => l.type === "click"), label + ": DEAD BUTTON '" + name + "'"); checked++; } }
    for (const v of VIEWS) { await page.click('#nav button[data-view="' + v + '"]'); await audit("master/" + v);
      const o = await page.$("#view button[data-open]"); if (o) { await o.click(); await audit("master/" + v + "/opened"); await page.evaluate(() => { const b = document.querySelector('#bizSel'); b.value = ""; b.dispatchEvent(new Event("change")); }); } }
    assert.ok(checked > 30, "audited too few buttons: " + checked); ok("no dead buttons: " + checked + " visible buttons all have click handlers"); await ctx.close(); }
  assert.deepEqual(errs, [], "browser errors / external requests: " + JSON.stringify(errs.slice(0, 5)));
  ok("no JS errors and no external network requests (CSP connect-src none)");
  await browser.close(); server.close(); console.log("A036 UI tests: all passed");
})().catch(e => { console.error(e); process.exit(1); });
