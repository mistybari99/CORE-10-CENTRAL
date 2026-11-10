// P6 Owner Connections: browser tests (three breakpoints, Bangla-first, secret hygiene, ladder, kill switch, role gating,
// keyboard, states, no dead buttons, no external requests). Synthetic fixture only.
// Local run: NODE_PATH=$(npm root -g) node tests/owner-console/ports.ui.e2e.js
"use strict";
const assert = require("node:assert/strict"), http = require("node:http"), fs = require("node:fs"), path = require("node:path");
const { chromium } = require("playwright");
const root = process.env.C10_CONSOLE_ROOT || path.join(__dirname, "..", "..", "experimental", "owner-console");
const types = { ".js": "text/javascript", ".html": "text/html", ".css": "text/css" };
const server = http.createServer((q, r) => { const u = new URL(q.url, "http://x"); const f = path.join(root, u.pathname === "/" ? "index.html" : u.pathname);
  if (!f.startsWith(root) || !fs.existsSync(f)) { r.statusCode = 404; return r.end("nf"); }
  r.setHeader("content-type", types[path.extname(f)] || "application/octet-stream"); r.end(fs.readFileSync(f)); });
const ok = (l) => console.log("PASS " + l);
const SECRET = "SYNTHETIC-SECRET-VALUE-9f3a1c77", SECRET_B = "SYNTHETIC-SECRET-OTHER-5d21", FAMILIES = ["messaging", "payments", "delivery", "ai", "storefront"];
const BP = [["desktop-1440", { width: 1440, height: 900 }], ["tablet-768", { width: 768, height: 1024 }], ["mobile-360", { width: 360, height: 740 }]];
(async () => {
  await new Promise(r => server.listen(0, r)); const base = "http://127.0.0.1:" + server.address().port + "/";
  const browser = await chromium.launch(); const errs = [];
  // open the Connections view for a business (default 101), or as a given role
  async function open(vp, opts) {
    opts = opts || {}; const ctx = await browser.newContext({ viewport: vp }); const page = await ctx.newPage();
    page.on("pageerror", e => errs.push(String(e))); page.on("console", m => { if (m.type() === "error") errs.push(m.text()); });
    page.on("request", rq => { if (!rq.url().startsWith(base)) errs.push("EXTERNAL REQUEST " + rq.url()); });
    await page.goto(base + "?view=connections" + (opts.lang ? "&lang=" + opts.lang : "") + (opts.state ? "&state=" + opts.state : ""), { waitUntil: "load" });
    if (opts.state) return { ctx, page };
    await page.waitForSelector("#view h2");
    if (opts.role) await page.selectOption("#roleSel", opts.role);
    else await page.selectOption("#bizSel", String(opts.biz || 101));
    await page.waitForSelector(opts.role === "staff_101" ? "#cxDenied" : "#cxKill");
    return { ctx, page };
  }
  const modes = (page) => page.$$eval("[data-port-row]", rs => Object.fromEntries(rs.map(r => [r.dataset.portRow, r.querySelector("[data-mode]").dataset.mode])));
  const manage = async (page, code) => { await page.click('[data-port="' + code + '"]'); await page.waitForSelector("#cxPortTitle"); };
  const flash = (page) => page.textContent("#cxFlash");

  // ---- 1) responsive, three breakpoints: list + detail + confirm, no overflow, 44px targets ----
  for (const [name, vp] of BP) {
    const { ctx, page } = await open(vp, { lang: "en" });
    const chk = async (what) => {
      const m = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
      assert.ok(m.sw <= m.cw + 1, name + "/" + what + ": horizontal overflow " + m.sw + ">" + m.cw);
      const small = await page.evaluate(() => [...document.querySelectorAll("button,select,label.sim")].filter(e => e.offsetParent !== null).map(e => ({ t: (e.textContent || e.id).trim().slice(0, 24), h: e.getBoundingClientRect().height })).filter(x => x.h < 43.5));
      assert.deepEqual(small, [], name + "/" + what + ": tap targets under 44px " + JSON.stringify(small));
    };
    await chk("list");
    const kill = await page.$eval("#cxKill", e => { const r = e.getBoundingClientRect(); return { h: r.height, w: r.width }; });
    assert.ok(kill.h >= 56 && kill.w >= Math.min(vp.width - 60, 300), name + ": kill switch must be big " + JSON.stringify(kill));
    await manage(page, "whatsapp"); await chk("detail-not-connected");
    for (const [f, secret] of [["business_account_id", false], ["phone_number_id", false], ["access_token", true]]) await page.fill("#cx-f-" + f, secret ? SECRET : "pub-" + f);
    await page.click("#cxConnect"); await page.waitForSelector("#cxFlash.ok"); await chk("detail-connected");
    await page.click("#cxTest"); await page.waitForSelector("#cxFlash.ok"); await page.click("#cxMode-live"); await page.waitForSelector("#cxLiveConfirm"); await chk("live-confirm");
    await page.click("#cxLiveCancel"); await page.click("#cxBack"); await page.waitForSelector(".ports");
    const fits = await page.evaluate(() => [...document.querySelectorAll(".port")].every(p => p.scrollWidth <= p.clientWidth + 1)); assert.ok(fits, name + ": a port row overflows");
    ok(name + ": list/detail/confirm have no horizontal overflow, 44px targets, big kill switch"); await ctx.close();
  }

  // ---- 2) Bangla-first, grouped list, badges, all OFF by default ----
  { const { ctx, page } = await open({ width: 1440, height: 900 });
    assert.equal(await page.getAttribute("html", "lang"), "bn", "Connections deep link must default to Bangla"); assert.equal(await page.getAttribute("#langBn", "aria-pressed"), "true");
    assert.ok(/[ঀ-৿]/.test(await page.textContent("#viewTitle")), "title is Bangla"); assert.ok(/[ঀ-৿]/.test(await page.textContent("#view")));
    assert.deepEqual(await page.$$eval(".fam h3", h => h.map(x => x.id.replace("fam-", ""))), FAMILIES, "ports are grouped by family in order");
    assert.equal(await page.$$eval("[data-port-row]", r => r.length), 20); const m = await modes(page); assert.ok(Object.values(m).every(v => v === "off"), "something is not OFF by default: " + JSON.stringify(m));
    assert.equal(await page.$$eval("[data-mode]", e => [...new Set(e.map(x => x.textContent))].join()), "বন্ধ", "OFF badge reads বন্ধ");
    assert.equal(await page.$$eval(".fam", s => s.map(x => x.querySelectorAll(".port").length).join()), "4,7,4,4,1");
    await manage(page, "sms"); await page.fill("#cx-f-sender_id", "DEMOSHOP2"); await page.fill("#cx-f-api_key", SECRET);
    await page.click("#cxConnect"); await page.waitForSelector("#cxFlash.ok"); await page.click("#cxTest"); await page.waitForSelector("#cxFlash.ok");
    await page.click("#cxMode-dry_run"); await page.waitForSelector('#cxMode-dry_run[aria-pressed="true"]');
    assert.equal(await page.textContent("#view [data-mode]"), "ডেমো", "dry-run badge reads ডেমো");
    await page.click("#cxMode-live"); await page.click("#cxLiveGo"); await page.waitForSelector('#cxMode-live[aria-pressed="true"]');
    assert.equal(await page.textContent("#view [data-mode]"), "চালু", "live badge reads চালু");
    await page.click("#langEn"); assert.equal(await page.textContent("#view [data-mode]"), "Live"); assert.equal(await page.getAttribute("html", "lang"), "en");
    await page.click("#langBn"); assert.equal(await page.textContent("#view [data-mode]"), "চালু");
    ok("Bangla-first deep link; 5 family groups (20 ports); all OFF (বন্ধ) by default; ডেমো / চালু badges; locale switch keeps state"); await ctx.close(); }

  // ---- 3) connect form: only needs_fields; secrets write-only, never echoed anywhere ----
  { const { ctx, page } = await open({ width: 1440, height: 900 }, { lang: "en" });
    const wanted = { whatsapp: ["business_account_id", "phone_number_id", "access_token"], bkash: ["merchant_id", "app_key", "app_secret"], cod: [], ai_openai_compat: ["base_url", "api_key", "monthly_budget"], rocket: ["merchant_id"] };
    for (const [code, fields] of Object.entries(wanted)) {
      await manage(page, code); const ids = await page.$$eval("#cxForm input", i => i.map(x => x.dataset.field)); assert.deepEqual(ids, fields, code + " form fields = needs_fields");
      const sec = await page.$$eval("#cxForm input[data-secret]", i => i.map(x => ({ t: x.type, ac: x.autocomplete, n: x.getAttribute("name"), v: x.getAttribute("value") })));
      sec.forEach(s => { assert.equal(s.t, "password"); assert.equal(s.ac, "new-password"); assert.equal(s.n, null); assert.equal(s.v, null); });
      await page.click("#cxBack"); await page.waitForSelector(".ports"); }
    await manage(page, "whatsapp");
    await page.click("#cxConnect"); await page.waitForSelector("#cxFlash.err"); assert.ok(/every field/i.test(await flash(page))); ok("empty submit shows a plain error and saves nothing");
    await page.fill("#cx-f-business_account_id", "BIZ-ACCT-1"); await page.fill("#cx-f-phone_number_id", "PHONE-ID-1"); await page.fill("#cx-f-access_token", SECRET);
    const urlBefore = page.url(); await page.click("#cxConnect"); await page.waitForSelector("#cxFlash.ok");
    const leak = async (label, needles) => {
      const dump = await page.evaluate(() => ({
        html: document.documentElement.outerHTML, text: document.body.innerText, url: location.href,
        values: [...document.querySelectorAll("input,textarea")].map(i => i.value), attrs: [...document.querySelectorAll("*")].flatMap(e => [...e.attributes].map(a => a.name + "=" + a.value)),
        ls: JSON.stringify(Object.entries(localStorage)), ss: JSON.stringify(Object.entries(sessionStorage)), cookie: document.cookie, title: document.title, live: document.getElementById("live").textContent }));
      for (const n of needles) { for (const k of ["html", "text", "url", "ls", "ss", "cookie", "title", "live"]) assert.ok(!dump[k].includes(n), label + ": secret found in " + k); assert.ok(!dump.attrs.join("|").includes(n), label + ": secret in an attribute"); assert.ok(dump.values.every(v => !v.includes(n)), label + ": secret in an input value"); } };
    await leak("after connect", [SECRET]); assert.equal(page.url(), urlBefore, "URL must not change on submit");
    assert.ok((await page.$$eval("#cxForm input", i => i.every(x => x.value === ""))), "form inputs are cleared after submit");
    assert.ok(/hidden/.test(await page.textContent("#view")), "UI says the secret is saved but hidden"); assert.ok((await page.textContent("#view")).includes("BIZ-ACCT-1"), "public (non-secret) settings are shown");
    await page.click("#cxBack"); await page.waitForSelector(".ports"); assert.equal((await modes(page)).whatsapp, "off", "connect leaves the port OFF");
    // typing a secret then leaving without submit must not persist it either
    await manage(page, "whatsapp"); await page.fill("#cx-f-access_token", SECRET_B); await page.click("#cxBack"); await page.waitForSelector(".ports");
    await manage(page, "whatsapp"); assert.equal(await page.inputValue("#cx-f-access_token"), ""); await leak("after abandon", [SECRET, SECRET_B]);
    // rotate with a second secret; neither shows up anywhere, incl. audit text
    await page.fill("#cx-f-business_account_id", "BIZ-ACCT-1"); await page.fill("#cx-f-phone_number_id", "PHONE-ID-1"); await page.fill("#cx-f-access_token", SECRET_B);
    await page.click("#cxConnect"); await page.waitForSelector("#cxFlash.ok"); await leak("after rotate", [SECRET, SECRET_B]);
    ok("secret fields are write-only: password inputs, cleared on submit/leave, never in DOM text/attributes/values, URL, storage, cookies or live region"); await ctx.close(); }

  // ---- 4) test + enable ladder + live confirm + failed test ----
  { const { ctx, page } = await open({ width: 1440, height: 900 }, { lang: "en" });
    await manage(page, "sms");   // seeded: connected, OFF, never tested
    assert.equal(await page.isDisabled("#cxMode-live"), true, "LIVE must be disabled before a passed test"); assert.ok(/locked/i.test(await page.textContent("#cxLiveNote")));
    assert.equal(await page.isDisabled("#cxMode-dry_run"), false); assert.equal(await page.getAttribute("#cxMode-off", "aria-pressed"), "true");
    await page.click("#cxMode-dry_run"); await page.waitForSelector('#cxMode-dry_run[aria-pressed="true"]'); assert.equal(await page.isDisabled("#cxMode-live"), true, "dry-run alone does not unlock LIVE");
    await page.click("#cxTest"); await page.waitForSelector("#cxFlash.ok"); assert.ok(/passed/i.test(await flash(page))); assert.equal(await page.isDisabled("#cxMode-live"), false, "LIVE unlocks after a passed test");
    await page.click("#cxMode-live"); await page.waitForSelector("#cxLiveConfirm"); assert.equal(await page.getAttribute("#cxMode-dry_run", "aria-pressed"), "true", "nothing changes before confirm");
    assert.equal(await page.evaluate(() => document.activeElement.id), "cxLiveCancel", "focus lands on the safe choice");
    await page.click("#cxLiveCancel"); assert.equal(await page.getAttribute("#cxMode-live", "aria-pressed"), "false"); assert.equal(await page.$("#cxLiveConfirm"), null);
    await page.click("#cxMode-live"); await page.click("#cxLiveGo"); await page.waitForSelector('#cxMode-live[aria-pressed="true"]'); assert.equal(await page.getAttribute("#view .pbadges [data-mode]", "data-mode"), "live");
    // failed test forces OFF and re-locks LIVE
    await page.check("#cxSim"); await page.waitForSelector("#cxSim:checked");
    await page.click("#cxTest"); await page.waitForSelector("#cxFlash.ok"); assert.ok(/failed/i.test(await flash(page)));
    assert.equal(await page.getAttribute("#cxMode-off", "aria-pressed"), "true", "failed test forces OFF"); assert.equal(await page.isDisabled("#cxMode-live"), true); assert.equal(await page.isDisabled("#cxMode-dry_run"), true, "test_failed port cannot be enabled");
    assert.equal(await page.getAttribute("#view .pbadges [data-status]", "data-status"), "test_failed"); assert.equal(await page.isChecked("#cxSim"), false, "simulation is consumed");
    await page.click("#cxTest"); await page.waitForSelector("#cxFlash.ok"); assert.ok(/passed/i.test(await flash(page))); assert.equal(await page.getAttribute("#cxMode-off", "aria-pressed"), "true", "a new pass does not turn the port back on");
    const audit = await page.$$eval("#cxAudit li", l => l.map(x => x.dataset.action)); assert.ok(["mode", "test"].every(a => audit.includes(a)), "audit shows mode and test: " + audit);
    ok("ladder: LIVE locked until a passed test; live needs explicit confirm; failed test forces OFF + re-locks; every step audited"); await ctx.close(); }

  // ---- 5) kill switch, disconnect ----
  { const { ctx, page } = await open({ width: 360, height: 740 }, { lang: "en" });
    await manage(page, "sms"); await page.click("#cxTest"); await page.waitForSelector("#cxFlash.ok"); await page.click("#cxMode-live"); await page.click("#cxLiveGo"); await page.waitForSelector('#cxMode-live[aria-pressed="true"]');
    await page.click("#cxBack"); await manage(page, "cod"); await page.click("#cxMode-dry_run"); await page.waitForSelector('#cxMode-dry_run[aria-pressed="true"]'); await page.click("#cxBack"); await page.waitForSelector(".ports");
    let m = await modes(page); assert.equal(m.sms, "live"); assert.equal(m.cod, "dry_run");
    // business 102 gets its own dry-run port, which 101's kill switch must not touch
    await page.selectOption("#bizSel", "102"); await page.waitForSelector("#cxKill"); await manage(page, "cod"); await page.click("#cxConnect"); await page.waitForSelector("#cxFlash.ok");
    await page.click("#cxMode-dry_run"); await page.waitForSelector('#cxMode-dry_run[aria-pressed="true"]'); await page.selectOption("#bizSel", "101"); await page.waitForSelector("#cxKill");
    await page.click("#cxKill"); await page.waitForSelector("#cxFlash.ok"); assert.ok(/2/.test(await flash(page)));
    m = await modes(page); assert.ok(Object.values(m).every(v => v === "off"), "kill switch must turn everything off: " + JSON.stringify(m));
    assert.equal(await page.$$eval("#cxAudit li", l => l[0].dataset.action), "kill_switch"); assert.equal(await page.$eval('[data-port-row="sms"] [data-status]', e => e.dataset.status), "connected", "kill keeps the connection");
    await page.selectOption("#bizSel", "102"); await page.waitForSelector("#cxKill"); assert.equal((await modes(page)).cod, "dry_run", "kill of 101 must not touch 102");
    await manage(page, "cod"); await page.click("#cxDisconnect"); await page.waitForSelector("#cxFlash.ok"); assert.equal(await page.getAttribute("#view .pbadges [data-status]", "data-status"), "not_connected");
    assert.equal(await page.getAttribute("#cxMode-off", "aria-pressed"), "true"); assert.equal(await page.isDisabled("#cxDisconnect"), true); assert.equal(await page.isDisabled("#cxTest"), true); assert.equal(await page.isDisabled("#cxMode-dry_run"), true);
    ok("kill switch: one press turns all of the business OFF (connection kept), other business untouched; disconnect returns to not connected + OFF"); await ctx.close(); }

  // ---- 6) role gating ----
  { const { ctx, page } = await open({ width: 1440, height: 900 }, { role: "staff_101", lang: "en" });
    assert.equal(await page.getAttribute("#cxDenied", "role"), "alert"); assert.ok(/denied/i.test(await page.textContent("#cxDenied")));
    assert.equal(await page.$$eval("#view button", b => b.length), 0, "non-owner sees no actions"); assert.equal(await page.$("#cxKill"), null); assert.equal(await page.$("[data-port]"), null); assert.equal(await page.$("#cxForm"), null);
    await page.click("#langBn"); await page.waitForSelector("#cxDenied"); assert.ok(/[ঀ-৿]/.test(await page.textContent("#cxDenied"))); assert.ok(!(await page.textContent("#view")).includes("DEMOSHOP"), "denied state leaks no data");
    await page.selectOption("#roleSel", "business_owner_101"); await page.waitForSelector("#cxKill"); assert.equal((await page.$$("[data-port-row]")).length, 20);
    const t101 = await page.textContent("#main"); assert.ok(!/CUSTOMER-MERCHANT|Independent Customer|Demo Second Business/.test(t101));
    await page.selectOption("#roleSel", "business_owner_102"); await page.waitForSelector("#cxKill"); assert.equal(await page.$eval('[data-port-row="sms"] [data-status]', e => e.dataset.status), "not_connected", "owner 102 must not see 101's account");
    assert.equal((await page.$$eval("#bizSel option", o => o.map(x => x.value))).join(), "102"); assert.ok(!/DEMOSHOP/.test(await page.textContent("#main")));
    await page.selectOption("#roleSel", "master_owner"); await page.waitForSelector("#view h2"); const all = [];
    for (const b of ["101", "102"]) { await page.selectOption("#bizSel", b); await page.waitForSelector("#cxKill"); all.push(await page.textContent("#main")); }
    assert.ok(all.every(x => !/CUSTOMER-MERCHANT|Independent Customer/.test(x)), "foreign tenant data must never appear");
    ok("role gating: staff gets an access-denied alert with no actions or data; business owners see only their business; foreign tenant never visible"); await ctx.close(); }

  // ---- 7) keyboard ----
  { const { ctx, page } = await open({ width: 1440, height: 900 }, { lang: "en" });
    await page.focus('[data-port="whatsapp"]'); await page.keyboard.press("Enter"); await page.waitForSelector("#cxPortTitle");
    assert.equal(await page.evaluate(() => document.activeElement.id), "cxBack", "focus moves into the detail");
    await page.focus("#cx-f-business_account_id");
    await page.keyboard.type("BIZ-KB"); await page.keyboard.press("Tab"); await page.keyboard.type("PH-KB"); await page.keyboard.press("Tab"); await page.keyboard.type(SECRET);
    assert.equal(await page.evaluate(() => document.activeElement.type), "password"); await page.keyboard.press("Enter"); await page.waitForSelector("#cxFlash.ok");
    assert.equal(await page.evaluate(() => document.activeElement.id), "cxFlash", "focus moves to the result message");
    assert.ok(!(await page.textContent("body")).includes(SECRET));
    await page.focus("#cxTest"); await page.keyboard.press("Space"); await page.waitForSelector("#cxFlash.ok"); assert.ok(/passed/i.test(await flash(page)));
    await page.focus("#cxMode-live"); await page.keyboard.press("Enter"); await page.waitForSelector("#cxLiveConfirm"); await page.keyboard.press("Tab"); assert.equal(await page.evaluate(() => document.activeElement.id), "cxLiveGo");
    await page.keyboard.press("Shift+Tab"); await page.keyboard.press("Enter"); await page.waitForSelector("#cxMode-live"); assert.equal(await page.getAttribute("#cxMode-live", "aria-pressed"), "false");
    assert.equal(await page.evaluate(() => document.activeElement.id), "cxMode-live", "cancel returns focus to the Go-live button");
    await page.focus("#cxBack"); await page.keyboard.press("Enter"); await page.waitForSelector(".ports"); await page.focus("#cxKill"); await page.keyboard.press("Enter"); await page.waitForSelector("#cxFlash.ok");
    assert.equal(await page.evaluate(() => document.activeElement.id), "cxKill", "focus stays on the kill switch");
    const named = await page.$$eval("#view button", b => b.filter(x => !(x.getAttribute("aria-label") || x.textContent).trim()).length); assert.equal(named, 0, "every button has an accessible name");
    assert.equal(await page.getAttribute("#cxFlash", "role"), "status"); assert.equal(await page.getAttribute("#live", "aria-live"), "polite");
    ok("keyboard: Enter/Space/Tab drive connect, test, ladder, confirm, kill; focus management; accessible names"); await ctx.close(); }

  // ---- 8) states ----
  for (const [s, re] of [["loading", /Loading/], ["empty", /Nothing to show/], ["error", /Could not load/]]) {
    const { ctx, page } = await open({ width: 1440, height: 900 }, { lang: "en", state: s }); await page.waitForSelector("#view .state");
    assert.ok(re.test(await page.textContent("#view")), s + " state text");
    if (s === "error") { assert.equal(await page.getAttribute("#view .state", "role"), "alert"); await page.click("#retryBtn"); await page.waitForSelector("#view h2"); }
    await ctx.close(); }
  { const { ctx, page } = await open({ width: 1440, height: 900 }, { lang: "en" }); await page.selectOption("#bizSel", ""); await page.waitForSelector("#view button[data-open]");
    await page.click('#view button[data-open="102"]'); await page.waitForSelector("#cxKill"); assert.ok(/No audit/.test(await page.textContent("#cxAuditEmpty")), "empty audit state");
    ok("loading / empty / error states, Retry, empty audit, master picks a business"); await ctx.close(); }

  // ---- 9) no dead buttons ----
  { const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } }); const page = await ctx.newPage(); await page.goto(base + "?view=connections&lang=en"); await page.waitForSelector("#view h2");
    const cdp = await ctx.newCDPSession(page); let checked = 0;
    const VIS = "Array.from(document.querySelectorAll('button')).filter(e=>e.offsetParent!==null)";
    async function audit(label) {
      const n = (await cdp.send("Runtime.evaluate", { expression: VIS + ".length", returnByValue: true })).result.value;
      for (let i = 0; i < n; i++) {
        const el = await cdp.send("Runtime.evaluate", { expression: VIS + "[" + i + "]" });
        const name = (await cdp.send("Runtime.evaluate", { expression: VIS + "[" + i + "].textContent.trim()||" + VIS + "[" + i + "].id", returnByValue: true })).result.value;
        const { listeners } = await cdp.send("DOMDebugger.getEventListeners", { objectId: el.result.objectId });
        assert.ok(listeners.some(l => l.type === "click"), label + ": DEAD BUTTON '" + name + "'"); checked++; } }
    await page.selectOption("#bizSel", "101"); await page.waitForSelector("#cxKill"); await audit("list");
    await manage(page, "sms"); await audit("detail connected"); await page.click("#cxTest"); await page.waitForSelector("#cxFlash.ok"); await page.click("#cxMode-live"); await page.waitForSelector("#cxLiveConfirm"); await audit("live confirm");
    await page.click("#cxLiveCancel"); await page.click("#cxBack"); await manage(page, "whatsapp"); await audit("detail not connected");
    await page.selectOption("#roleSel", "staff_101"); await page.waitForSelector("#cxDenied"); await audit("staff denied");
    assert.ok(checked > 40, "audited too few buttons: " + checked); ok("no dead buttons: " + checked + " visible buttons all have click handlers (list, detail, confirm, denied)"); await ctx.close(); }

  // ---- 10) Connections sits in the existing navigation; other views unaffected ----
  { const { ctx, page } = await open({ width: 1440, height: 900 }, { lang: "en" }); await page.click('#nav button[data-view="overview"]'); await page.waitForSelector("#view .grid");
    assert.equal(await page.getAttribute('#nav button[data-view="connections"]', "data-view"), "connections"); ok("Connections sits in the existing console navigation; other views unaffected"); await ctx.close(); }

  assert.deepEqual(errs, [], "browser errors / external requests: " + JSON.stringify(errs.slice(0, 5)));
  ok("no JS errors, no CSP violations and no external network requests");
  await browser.close(); server.close(); console.log("P6 ports UI tests: all passed");
})().catch(e => { console.error(e); process.exit(1); });
