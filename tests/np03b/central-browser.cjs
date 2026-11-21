"use strict";

// The actual packaged Build 01 shell and modules, with disposable PG17 RPCs
// and an inert Auth fixture. The client factory is counted on the page.
const assert = require("node:assert/strict");
const { chromium } = require("playwright");
const { setTimeout: sleep } = require("node:timers/promises");
const { createServer } = require("../e2e/static_server");
const { start } = require("./ui-gateway.cjs");

const OWNER = "11111111-1111-4111-8111-111111111111";
const MANAGER = "33333333-3333-4333-8333-333333333333";

async function launch() {
  const gateway = await start();
  const staticServer = createServer();
  await new Promise(resolve => staticServer.listen(0, "127.0.0.1", resolve));
  const base = "http://127.0.0.1:" + staticServer.address().port;
  const rpcBase = "http://127.0.0.1:" + gateway.address().port;
  const browser = await chromium.launch({ executablePath: process.env.NP03B_CHROMIUM || undefined });
  let passed = 0;
  async function open(width, persona) {
    const page = await browser.newPage({ viewport: { width, height: 900 } });
    page.setDefaultTimeout(12000);
    const errors = [];
    const calls = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.route("**/core10-build01-config.js", route => route.fulfill({
      contentType: "text/javascript",
      body: "window.CORE10_BUILD01_CONFIG=" + JSON.stringify({
        enabled: true, mode: "isolated-development", url: base, publishableKey: "disposable-fixture",
        operationsEnabled: true
      })
    }));
    await page.route("**/vendor/supabase.js", route => route.fulfill({
      contentType: "text/javascript",
      body: `window.centralClients=0;
        window.supabase={createClient(){
          window.centralClients++;
          let actor=null;
          const listeners=new Set();
          function signOut(){actor=null;for(const listener of listeners)listener("SIGNED_OUT",null);}
          window.centralFixtureSignOut=signOut;
          return {auth:{
            async getUser(){return {data:{user:actor?{id:actor}:null}};},
            async signInWithPassword(){actor=${JSON.stringify(persona)};return {data:{user:{id:actor}}};},
            async signOut(){signOut();return {};},
            onAuthStateChange(listener){listeners.add(listener);return {data:{subscription:{unsubscribe(){listeners.delete(listener);}}}};}
          },schema(name){
            if(name!=="core10")throw Error("TEST_WRONG_SCHEMA");
            return {async rpc(rpc,args){
              const response=await fetch("/central-fixture/"+rpc,{method:"POST",
                headers:{"content-type":"application/json","x-test-persona":actor||""},body:JSON.stringify(args)});
              const data=await response.json();
              return response.ok?{data}:{error:data};
            }};
          }};
        }};`
    }));
    let delay = null;
    await page.route("**/central-fixture/*", async route => {
      const rpc = new URL(route.request().url()).pathname.split("/").at(-1);
      calls.push({ rpc, args: route.request().postDataJSON() });
      if (rpc.startsWith("pack02_")) return route.fulfill({ status: 404, json: { message: "RPC_NOT_ALLOWED" } });
      const request = route.request();
      const response = await fetch(rpcBase + "/rpc/" + rpc, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-test-persona": request.headers()["x-test-persona"]
        },
        body: request.postData()
      });
      const body = await response.text();
      if (delay && delay.rpc === rpc) {
        delay.arrived();
        await delay.release;
      }
      if (!page.isClosed()) await route.fulfill({ status: response.status, contentType: "application/json", body });
    });
    await page.goto(base + "/core10-build01.html");
    await page.locator("#b01-email").fill("fixture@example.invalid");
    await page.locator("#b01-password").fill("disposable");
    await page.locator("#b01-login-form button").click();
    await page.waitForFunction(() => !document.querySelector("#b01-refresh").disabled);
    return {
      page, calls, errors,
      hold(rpc) {
        let resume, arrived;
        const waiting = new Promise(resolve => { arrived = resolve; });
        delay = { rpc, arrived, release: new Promise(resolve => { resume = resolve; }) };
        return { waiting, resume };
      }
    };
  }

  try {
    for (const width of [390, 1440]) {
      const { page, calls, errors, hold } = await open(width, OWNER);
      if (width === 1440) await page.locator("#b01-language").click();
      await page.locator("#b01-site").selectOption("1002");
      await page.locator("#b01-open-sales").click();
      await page.waitForFunction(() => !document.querySelector("#b01-operation-host").hidden &&
        document.querySelector("#b01-operation-host .so-order-list, #b01-operation-host .so-empty"));
      assert.equal(await page.locator("#b01-site").isDisabled(), true);
      assert.equal(await page.locator('[data-so-focus="site"]').inputValue(), "1002");
      assert.equal(await page.locator('[data-so-focus="site"]').isDisabled(), true);
      await page.locator("#b01-operation-host .so-list .primary").click();
      await page.locator('[data-so-focus="priceList"]').selectOption("7102");
      assert.equal(await page.locator('[data-field="unit_price"][data-line="0"]').inputValue(), "270");
      await page.locator('[data-action="save"]').click();
      await page.locator("#b01-operation-host .so-order[aria-pressed=true]").waitFor();
      const saved = calls.find(call => call.rpc === "save_sales_order_v1");
      assert.equal(saved.args.p_document.price_list_id, 7102);
      assert.equal(saved.args.p_site, 1002);

      await page.locator('[data-sales-view="invoices"]').click();
      await page.locator('[data-si-focus="site"]').waitFor();
      assert.equal(await page.locator('[data-si-focus="site"]').inputValue(), "1002");
      assert.equal(await page.locator('[data-si-focus="site"]').isDisabled(), true);
      await page.waitForFunction(() => document.querySelector("#b01-operation-host .si-workspace")?.getAttribute("aria-busy") === "false");
      await page.locator("#b01-close-operation").click();

      await page.locator("#b01-open-manufacturing").click();
      await page.getByText("CENTRAL-SITE-RECIPE · v1").waitFor();
      const operationHost = page.locator("#b01-operation-host");
      await operationHost.locator("[data-approve]:visible").click();
      const effective = width === 390 ? "2026-01-01T09:00" : "2026-01-02T09:00";
      await operationHost.locator("[name=effective]").fill(effective);
      await operationHost.locator("form button[type=submit]").click();
      const operationStatus = operationHost.getByRole("status");
      await page.waitForFunction(() => /#\d+/.test(
        document.querySelector("#b01-operation-host [role=status]").textContent));
      const requestId = (await operationStatus.textContent()).match(/#(\d+)/)[1];
      const approval = calls.find(call => call.rpc === "mfg_submit_approval_v1");
      assert.equal(approval.args.p_business, 101);
      assert.equal(approval.args.p_site, 1002);
      assert.equal(approval.args.p_operation, "recipe_approve");
      await operationHost.locator("[name=approval_action]").selectOption("apply");
      await operationHost.locator("[name=approval]").fill(requestId);
      await operationHost.locator("form button[type=submit]").click();
      await page.waitForFunction(() => document.querySelector("#b01-operation-host [role=status]")
        .textContent.includes("MFG_MAKER_CHECKER"));
      await operationHost.locator('[data-tab="recipes"]').click();
      await page.getByText("CENTRAL-SITE-RECIPE · v1").waitFor();
      const delayed = hold("mfg_inspect_v1");
      await page.locator("#b01-operation-host [data-refresh]").click();
      const timeout = new AbortController();
      try {
        await Promise.race([delayed.waiting, sleep(12000, undefined, { signal: timeout.signal })
          .then(() => { throw Error("Manufacturing did not dispatch its scoped read"); })]);
      } finally {
        timeout.abort();
      }
      assert.equal(await page.evaluate(() => window.centralClients), 1);
      assert.deepEqual(calls.filter(call => ["read_sales_orders_v1", "read_sales_invoice_drafts_v1", "mfg_inspect_v1"]
        .includes(call.rpc)).map(call => [call.args.p_business, call.args.p_site]).filter(
        ([business, site]) => business !== 101 || site !== 1002), []);
      assert.match(await page.locator("#b01-operation-host").innerText(), /NOT_CONNECTED/);
      for (const rpc of ["read_sales_orders_v1", "read_sales_invoice_drafts_v1", "mfg_inspect_v1"])
        assert.ok(calls.some(call => call.rpc === rpc), rpc);
      const input = page.locator('#mfg-recipe-form input[name="code"]');
      await input.fill("UNSAVED-DRAFT");
      page.once("dialog", dialog => dialog.dismiss());
      await page.locator("#b01-close-operation").click();
      assert.equal(await input.inputValue(), "UNSAVED-DRAFT");
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 2), true);
      await page.evaluate(() => window.centralFixtureSignOut());
      const response = page.waitForResponse("**/central-fixture/mfg_inspect_v1");
      delayed.resume();
      await response;
      await page.evaluate(() => new Promise(requestAnimationFrame));
      await page.waitForFunction(() => !document.querySelector("#b01-login").hidden);
      assert.equal(await page.locator("#b01-operation-host").innerText(), "");
      assert.equal(await page.locator("#b01-workspace").isVisible(), false);
      assert.equal(await page.locator("#b01-login-form button").isEnabled(), true);
      assert.deepEqual(errors, []);
      passed++;
      await page.close();
    }

    const { page, calls } = await open(390, MANAGER);
    assert.equal(await page.locator("#b01-operations").isVisible(), false);
    assert.equal(calls.some(call => call.rpc.startsWith("mfg_") || call.rpc.startsWith("read_sales_")), false);
    passed++;
    await page.close();
    console.log("CENTRAL_SHARED_SCOPE_BROWSER_PASS", passed);
  } finally {
    await browser.close();
    await Promise.all([staticServer, gateway].map(server => new Promise(resolve => server.close(resolve))));
  }
}
launch().catch(error => { console.error(error); process.exitCode = 1; });
