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

test("B01 home offers module shortcuts from verified setup and stock scope", { timeout: 60000 }, async () => {
  await withContextPage(async (page, base) => {
    await page.goto(base + "/#/home");
    await page.getByRole("button", { name: "EN", exact: true }).click();
    const status = page.locator("#c10-entry-status");
    const setup = page.locator("#c10-entry-setup");
    const stock = page.locator("#c10-entry-stock");
    await waitForText(status, "Sign in to see shortcuts");
    assert.equal(await setup.isVisible(), false);
    await page.getByRole("button", { name: "Sign in", exact: true }).click();
    await page.locator("#c10-shell-email").fill("operator@example.test");
    await page.locator("#c10-shell-password").fill("test-only");
    await page.locator("#c10-shell-submit").click();
    await waitForText(status, "Checking business context");
    assert.equal(await stock.isVisible(), false);
    await page.evaluate(() => window.fixture.releaseContext());

    await waitForText(status, "Demo Sweets · Manager");
    assert.equal(await setup.isVisible(), true);
    assert.equal(await stock.isVisible(), true);
    await stock.click();
    await page.waitForURL("**/#/stock");
    await page.locator("#c10-entry").waitFor({ state: "hidden" });
    await page.locator('.c10-nav [data-route="home"]').click();

    await page.locator("#c10-business").selectOption("20");
    await waitForText(status, "Demo Paint · Investor");
    assert.match(await status.innerText(), /no shortcuts/i);
    assert.equal(await stock.isVisible(), false);
    assert.equal(await setup.isVisible(), false);
    assert.equal(await page.locator('.c10-nav [data-route="stock"]').isVisible(), true);

    await page.locator("#c10-group").selectOption("2");
    await waitForText(status, "There are no businesses to show");
    assert.equal(await setup.isVisible(), true);
    assert.equal(await stock.isVisible(), false);
    await setup.click();
    await page.waitForURL("**/#/setup");
    await waitForText(page.locator("#c10-data-status .en"), "separate setup sign-in");

    await page.locator('.c10-nav [data-route="approvals"]').click();
    await waitForText(page.locator("#c10-data-status .en"), "sample approvals");
    await page.locator('.c10-nav [data-route="home"]').click();
    await page.evaluate(() => { window.fixture.contextError = true; });
    await page.locator("#c10-context-refresh").click();
    await waitForText(status, "Business context could not be verified");
    assert.equal(await setup.isVisible(), false);
    await page.locator('[data-set-lang="bn"]').click();
    await waitForText(status, "ব্যবসার প্রসঙ্গ যাচাই করা যায়নি");
  });
});

test("B01 Master Data opens on the shell's verified business through its own signed context", { timeout: 60000 }, async () => {
  await withContextPage(async (page, base) => {
    await page.goto(base + "/#/home");
    await page.getByRole("button", { name: "EN", exact: true }).click();
    await page.evaluate(() => window.fixture.releaseContext());
    await page.getByRole("button", { name: "Sign in", exact: true }).click();
    await page.locator("#c10-shell-email").fill("operator@example.test");
    await page.locator("#c10-shell-password").fill("test-only");
    await page.locator("#c10-shell-submit").click();
    await page.locator("#c10-context-signed").waitFor();
    await page.locator("#c10-business").selectOption("20");
    await page.waitForFunction(() => document.querySelector("#c10-site").selectedOptions[0]?.textContent === "Demo Branch · #201");

    const frame = page.frameLocator("#c10-frame");
    const master = frame.locator(".occ-controls select");
    const goTo = route => page.locator(`.c10-nav [data-route="${route}"]`).click();
    await goTo("master");
    await master.locator("option:checked").filter({ hasText: "Demo Paint" }).waitFor({ state: "attached" });
    assert.equal(await master.inputValue(), "20");
    assert.deepEqual(await page.evaluate(() => window.fixture.masterBusinesses), [20]);

    await page.locator("#c10-business").selectOption("10");
    await page.waitForFunction(() => document.querySelector("#c10-site").selectedOptions[0]?.textContent === "Demo Store · #101");
    assert.equal(await master.inputValue(), "20", "changing shell context must keep the open Master workspace intact");
    await goTo("home");
    await waitForText(page.locator("#c10-entry-status"), "Demo Sweets");
    await goTo("master");
    await master.locator("option:checked").filter({ hasText: "Demo Sweets" }).waitFor({ state: "attached" });
    assert.equal(await master.inputValue(), "10");
    assert.deepEqual(await page.evaluate(() => window.fixture.masterBusinesses), [20, 10]);

    await page.goto(base + "/view/master-signed.html");
    await page.evaluate(() => window.fixture.releaseContext());
    await page.locator("#md-email").fill("operator@example.test");
    await page.locator("#md-password").fill("test-only");
    await page.locator("#md-login button[type=submit]").click();
    assert.equal(await page.locator(".occ-controls select").inputValue(), "10");
    assert.deepEqual(await page.evaluate(() => window.fixture.masterBusinesses), [10]);
  });
});

function waitForText(locator, text) {
  return locator.filter({ hasText: text }).waitFor({ state: "visible" });
}

async function withContextPage(run) {
  const { chromium } = require("playwright");
  const { serve } = await import(path.join(ROOT, "apps/central/local-serve.mjs"));
  const server = await serve(0);
  try {
    const browser = await chromium.launch({ headless: true });
    try {
      const base = "http://127.0.0.1:" + server.address().port;
      const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
      await page.context().route("**/*", route => {
        const url = new URL(route.request().url());
        if (url.origin !== base) return route.abort("blockedbyclient");
        if (url.pathname === "/live/vendor/supabase.js") {
          return route.fulfill({ contentType: "application/javascript", body: CONTEXT_FIXTURE });
        }
        return route.continue();
      });
      await run(page, base);
    } finally {
      await browser.close();
    }
  } finally {
    await new Promise((resolve, reject) => server.close(err => err ? reject(err) : resolve()));
  }
}

const CONTEXT_FIXTURE = `
  if (window === top) {
    window.fixture = {
      actor: null,
      pendingContext: new Promise(resolve => { window.releaseFixtureContext = resolve; }),
      releaseContext() { window.releaseFixtureContext(); },
      contextError: false,
      masterBusinesses: [],
      scope: {
        tenants: [
          { id: 1, slug: "Demo Group", can_manage_bootstrap: false },
          { id: 2, slug: "Setup Group", can_manage_bootstrap: true }
        ],
        businesses: [
          { id: 10, tenant_id: 1, label: "Demo Sweets", can_manage: true, role: "manager" },
          { id: 20, tenant_id: 1, label: "Demo Paint", can_manage: false, role: "investor" }
        ],
        sites: [
          { id: 101, tenant_id: 1, business_id: 10, label: "Demo Store" },
          { id: 201, tenant_id: 1, business_id: 20, label: "Demo Branch" }
        ]
      }
    };
  }
  window.supabase = { createClient: () => ({
    auth: {
      getUser: async () => ({ data: { user: top.fixture.actor && { id: top.fixture.actor } } }),
      signInWithPassword: async () => {
        top.fixture.actor = "test-signed-user";
        return { data: { user: { id: top.fixture.actor } } };
      },
      signOut: async () => { top.fixture.actor = null; },
      onAuthStateChange() {}
    },
    schema: () => ({
      rpc: async (name, args) => {
        if (name === "build01_context_v1") {
          await top.fixture.pendingContext;
          return top.fixture.contextError
            ? { error: { message: "Fixture temporarily unavailable" } }
            : { data: { actor_uid: top.fixture.actor, ...top.fixture.scope } };
        }
        if (name === "master_list_categories_v1") return { data: [] };
        if (name === "master_list_uoms_v1") return { data: { uoms: [] } };
        if (name === "master_list_items_v1") {
          top.fixture.masterBusinesses.push(args.p_business);
          return { data: { rows: [], next_after_id: null } };
        }
        throw new Error("Unexpected fixture RPC " + name);
      }
    })
  }) };
`;
