import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import fs from "node:fs";
import worker from "../../preview/worker.mjs";
import { SNAPSHOT_SCRIPT, snapshotHTML } from "../../preview/operations-snapshot.mjs";

test("actual module HTML retains its original renderer and omits auth/network bootstraps", () => {
  for (const name of ["operational-flow", "inventory-operations"]) {
    const source = fs.readFileSync(new URL(`../../core10-${name}.html`, import.meta.url), "utf8");
    const html = snapshotHTML(source);
    assert.ok(html.includes(`./core10-${name}.js`));
    assert.ok(html.includes("preview-snapshot.js"));
    assert.ok(html.includes("Read-only synthetic regression snapshot"));
    assert.doesNotMatch(html, /src="\.\/(?:config\.js|vendor\/supabase\.js|core10-.*-client\.js)"/);
  }
  assert.throws(() => snapshotHTML("<body>unrecognized source</body>"), /UNRECOGNIZED_ORIGINAL_MODULE_HTML/);
});

test("snapshot cannot mutate or cross the advertised presentation scope", async () => {
  const document = { getElementById: () => null, addEventListener() {}, body: {} };
  const context = { window: {}, document, MutationObserver: class { observe() {} } };
  vm.runInNewContext(SNAPSHOT_SCRIPT, context);
  const api = context.window.CORE10_OPERATIONS_API.create();
  const a = await api.read(101);
  assert.deepEqual(JSON.parse(JSON.stringify(a.items.map(x => x.quantity))), [60, 12, 1]);
  assert.equal(a.items.find(x => x.kind === "production_plan").status, "confirmed");
  const b = await api.read(102);
  assert.ok(b.items.every(x => x.business_id === 102));
  await assert.rejects(api.read(201), /PREVIEW_SCOPE_UNAVAILABLE/);
  await assert.rejects(api.draft(), /READ_ONLY_SNAPSHOT/);
  await assert.rejects(api.advance(), /READ_ONLY_SNAPSHOT/);
  a.items[0].quantity = 999;
  assert.equal((await api.read(101)).items[0].quantity, 60);
  assert.doesNotMatch(SNAPSHOT_SCRIPT, /fetch\(|\.rpc\(|auth\.getUser\(\)\s*\{/);
});

test("Worker serves explicit snapshot routes but never authenticated client/config routes", async () => {
  const previous = globalThis.fetch;
  globalThis.fetch = async () => new Response(fs.readFileSync(new URL("../../core10-operational-flow.html", import.meta.url), "utf8"));
  try {
    const response = await worker.fetch(new Request("https://example.test/core10-operational-flow.html"));
    assert.equal(response.status, 200);
    assert.match(response.headers.get("content-security-policy"), /connect-src 'none'/);
    assert.match(await response.text(), /Read-only synthetic regression snapshot/);
    for (const path of ["/config.js", "/vendor/supabase.js", "/core10-operational-flow-client.js", "/internal/demo-factory/index.js"]) {
      assert.equal((await worker.fetch(new Request("https://example.test" + path))).status, 404);
    }
  } finally { globalThis.fetch = previous; }
});

test("CRM demo routes use only the pinned PR66 synthetic adapter assets", async () => {
  const seen = [], previous = globalThis.fetch;
  globalThis.fetch = async url => { seen.push(String(url)); return new Response("original CRM fixture"); };
  try {
    const allowed = ["core10-crm-lifecycle.html", "core10-crm-lifecycle-demo-backend.js", "core10-crm-lifecycle-app.js", "core10-crm-lifecycle.css", ...["customers", "pipeline", "support", "campaigns", "reports", "settings", "intake"].map(x => `core10-crm-lifecycle-${x}.html`)];
    for (const asset of allowed) {
      const response = await worker.fetch(new Request("https://example.test/" + asset));
      assert.equal(response.status, 200);
      assert.equal(await response.text(), "original CRM fixture");
      assert.match(response.headers.get("content-security-policy"), /connect-src 'none'/);
    }
    assert.equal(seen.length, allowed.length);
    assert.ok(seen.every(url => url.includes("/3936e1e7bf10320e1164252ec5fa73c0b6945759/")));
    for (const route of ["/core10-crm-lifecycle-client.js", "/core10-crm-lifecycle-engine.js", "/core10-crm-lifecycle-secret.js", "/api/crm"]) {
      assert.equal((await worker.fetch(new Request("https://example.test" + route))).status, 404);
    }
  } finally { globalThis.fetch = previous; }
});
