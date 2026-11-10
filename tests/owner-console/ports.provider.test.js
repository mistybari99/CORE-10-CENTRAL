// P6 Owner Connections: provider-level contracts (Node, no browser). Rules must match scripts/c10_a038_integration_core_v1.sql.
// Local run: node tests/owner-console/ports.provider.test.js
"use strict";
const assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path");
const dir = process.env.C10_CONSOLE_ROOT || path.join(__dirname, "..", "..", "experimental", "owner-console");
const PORTS = require(path.join(dir, "ports.js")), PF = require(path.join(dir, "ports-fixtures.js")), I = require(path.join(dir, "i18n.js"));
const ok = (l) => console.log("PASS " + l);
async function denied(fn, code, label) { try { await fn(); } catch (e) { assert.equal(e.code, code, label + ": got " + e.code); ok("DENIED " + label); return; } assert.fail(label + ": was allowed"); }
const SECRET = "SYNTHETIC-SECRET-VALUE-9f3a1c77", SECRET2 = "ANOTHER-SYNTHETIC-SECRET-42b8";
const DAY = 86400000;
const OWNER = { role: "master_owner", tenantId: 1, businessIds: [101, 102] };
const BO101 = { role: "business_owner", tenantId: 1, businessIds: [101] };
const BO102 = { role: "business_owner", tenantId: 1, businessIds: [102] };
const STAFF = { role: "staff", tenantId: 1, businessIds: [101] };
function mk(session, clock) { const store = PORTS.createStore({ now: () => clock.t }); return { store, p: PORTS.createPortsProvider({ session, store }) }; }
// Fill every needs_field of a provider; secret fields get the synthetic secret, others a plain value.
function fieldsFor(acc, secret) { const f = {}; acc.needs_fields.forEach(n => { f[n] = acc.secret_fields.includes(n) ? (secret || SECRET) : "pub-" + n; }); return f; }
// SQL catalog (A038): code -> needs_fields
const SQL_CATALOG = {
  whatsapp: "business_account_id,phone_number_id,access_token", facebook: "page_id,page_access_token,app_secret", sms: "sender_id,api_key", email: "from_address,api_key",
  bkash: "merchant_id,app_key,app_secret", nagad: "merchant_id,merchant_key", rocket: "merchant_id", gateway: "store_id,store_password", card: "store_id,store_password",
  manual_pay: "", cod: "", pathao: "client_id,client_secret", steadfast: "api_key,secret_key", redx: "access_token", own_rider: "",
  ai_anthropic: "api_key,monthly_budget", ai_gemini: "api_key,monthly_budget", ai_openai_compat: "base_url,api_key,monthly_budget", ai_local_rules: "", web_storefront: "domain"
};
(async () => {
  // ---- catalog ----
  assert.equal(PF.SYNTHETIC, true); assert.equal(PF.providers.length, 20); ok("fixture is synthetic with 20 providers");
  assert.deepEqual(PF.providers.map(p => p.code).sort(), Object.keys(SQL_CATALOG).sort());
  PF.providers.forEach(p => { assert.equal(p.needs_fields.join(","), SQL_CATALOG[p.code], "needs_fields of " + p.code); assert.ok(PF.FAMILIES.includes(p.family));
    p.secret_fields.forEach(f => assert.ok(p.needs_fields.includes(f), "secret field must be a needs_field: " + p.code + "/" + f)); });
  ok("catalog and needs_fields match the A038 seed exactly");
  const fixtureText = fs.readFileSync(path.join(dir, "ports-fixtures.js"), "utf8");
  assert.ok(!/eyJ[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{16,}|AKIA[0-9A-Z]{12,}|sb_secret|-----BEGIN/.test(fixtureText)); ok("fixture file holds no key-shaped value");

  // ---- all OFF by default, every business, every provider ----
  const clock = { t: Date.UTC(2026, 10, 10, 6, 0, 0) };
  for (const [who, s, bs] of [["master", OWNER, [101, 102]], ["bo101", BO101, [101]], ["bo102", BO102, [102]]]) {
    const { p } = mk(s, clock);
    for (const b of bs) { const rows = await p.listAccounts(b); assert.equal(rows.length, 20); assert.ok(rows.every(r => r.mode === "off"), who + "/" + b + " has a non-off port"); }
  }
  ok("all 20 ports are OFF by default for every business");
  assert.ok(PF.seedAccounts.every(a => a.mode === "off")); ok("seed accounts are all OFF");

  // ---- connect: only needs_fields, secret write-only ----
  { const { p, store } = mk(OWNER, clock);
    const rows = await p.listAccounts(102), wa = rows.find(r => r.provider_code === "whatsapp");
    assert.equal(wa.status, "not_connected"); assert.equal(wa.mode, "off"); assert.equal(wa.secret_saved, false);
    await denied(() => p.connect(102, "whatsapp", Object.assign(fieldsFor(wa), { extra_field: "x" })), "integration_unknown_field", "unknown field is rejected");
    const missing = fieldsFor(wa); delete missing.phone_number_id;
    await denied(() => p.connect(102, "whatsapp", missing), "integration_field_required", "missing required field is rejected");
    await denied(() => p.connect(102, "whatsapp", Object.assign(fieldsFor(wa), { access_token: "   " })), "integration_field_required", "blank secret is rejected");
    await denied(() => p.connect(102, "no_such_provider", {}), "integration_unknown_provider", "unknown provider is rejected");
    await denied(() => p.connect(102, "whatsapp", Object.assign(fieldsFor(wa), { phone_number_id: "x".repeat(201) })), "integration_field_invalid", "oversized public value is rejected");
    const got = await p.connect(102, "whatsapp", fieldsFor(wa)); assert.equal(got.status, "connected"); assert.equal(got.mode, "off"); assert.equal(got.secret_saved, true);
    assert.deepEqual(got.public_config, { business_account_id: "pub-business_account_id", phone_number_id: "pub-phone_number_id" }); ok("connect stores only non-secret fields, stays OFF, flags secret_saved");
    // providers without credentials connect with an empty form
    const cod = await p.connect(102, "cod", {}); assert.equal(cod.status, "connected"); assert.equal(cod.secret_saved, false); ok("no-credential provider connects with no fields");
    // secret never retrievable
    const everything = JSON.stringify([got, await p.listAccounts(102), await p.getAccount(102, "whatsapp"), await p.listAudit(102), store.snapshot(), await p.listProviders()]);
    assert.ok(!everything.includes(SECRET) && !everything.includes("access_token\":\"" + SECRET), "secret value leaked");
    assert.ok(/ib_102_whatsapp_v1/.test(everything), "audit should carry only the opaque secret_ref name");
    const ownKeys = Object.keys(p).concat(Object.getOwnPropertyNames(store)); assert.ok(!ownKeys.some(k => /secret|token|password|vault|credential/i.test(k) && !/connect|snapshot/.test(k)), "provider exposes a secret-ish accessor: " + ownKeys);
    assert.ok(!JSON.stringify(Object.values(store._s)).includes(SECRET)); ok("secret value is not in any provider response, audit, state or snapshot; only secret_ref name is kept");
    // reconnect (rotation) -> new version, back to off, test cleared
    await p.test(102, "whatsapp"); await p.setMode(102, "whatsapp", "dry_run");
    const re = await p.connect(102, "whatsapp", fieldsFor(wa, SECRET2));
    assert.equal(re.mode, "off"); assert.equal(re.last_test_ok_at, null); assert.equal(re.live_ready, false);
    const snap = JSON.stringify([store.snapshot(), await p.listAudit(102)]); assert.ok(!snap.includes(SECRET2) && !snap.includes(SECRET) && /ib_102_whatsapp_v2/.test(snap)); ok("rotation returns the port to OFF, clears the test, bumps secret_ref version, leaks nothing");
    // returned views are copies
    const v = await p.getAccount(102, "whatsapp"); v.mode = "live"; v.public_config.hack = "1"; assert.equal((await p.getAccount(102, "whatsapp")).mode, "off"); ok("returned objects are copies, state cannot be mutated from outside"); }

  // ---- test + enable ladder rules (SQL: live needs passed test <= 30 days) ----
  { const c = { t: Date.UTC(2026, 10, 10, 6, 0, 0) }, { p } = mk(OWNER, c);
    await denied(() => p.test(101, "whatsapp"), "integration_not_connected", "cannot test a port that is not connected");
    await denied(() => p.setMode(101, "whatsapp", "dry_run"), "integration_not_connected", "cannot enable demo before connect");
    await denied(() => p.setMode(101, "sms", "bogus"), "integration_invalid_mode", "invalid mode rejected");
    await denied(() => p.setMode(101, "sms", "live"), "integration_live_needs_recent_test", "LIVE is blocked without a passed test");
    assert.equal(await p.setMode(101, "sms", "dry_run"), "dry_run"); ok("dry-run is allowed for a connected port without a test");
    await denied(() => p.setMode(101, "sms", "live"), "integration_live_needs_recent_test", "LIVE is still blocked after dry-run alone");
    assert.equal(await p.test(101, "sms"), "passed"); assert.equal((await p.getAccount(101, "sms")).live_ready, true);
    assert.equal(await p.setMode(101, "sms", "live"), "live"); assert.equal((await p.getAccount(101, "sms")).mode, "live"); ok("LIVE works only after a passed test");
    c.t += 30 * DAY; assert.equal(await p.setMode(101, "sms", "off"), "off"); assert.equal(await p.setMode(101, "sms", "live"), "live"); ok("a test is still valid on day 30");
    await p.setMode(101, "sms", "off"); c.t += 1000;
    await denied(() => p.setMode(101, "sms", "live"), "integration_live_needs_recent_test", "a test older than 30 days no longer unlocks LIVE");
    assert.equal(await p.setMode(101, "sms", "dry_run"), "dry_run"); ok("expired test still allows dry-run; a new test is required for live");
    // failed test forces off and clears the pass
    await p.test(101, "sms"); await p.setMode(101, "sms", "live");
    await p.setSimulation(101, true); assert.equal(await p.test(101, "sms"), "failed");
    let a = await p.getAccount(101, "sms"); assert.equal(a.mode, "off"); assert.equal(a.status, "test_failed"); assert.equal(a.live_ready, false); assert.equal(a.last_test_ok_at, null);
    assert.equal(await p.getSimulation(101), false, "simulation flag is consumed by one test"); ok("a failed test forces the port OFF, marks test_failed, clears the pass and consumes the simulation");
    await denied(() => p.setMode(101, "sms", "dry_run"), "integration_not_connected", "a test_failed port cannot be enabled");
    await denied(() => p.setMode(101, "sms", "live"), "integration_not_connected", "a test_failed port cannot go live");
    assert.equal(await p.test(101, "sms"), "passed"); a = await p.getAccount(101, "sms"); assert.equal(a.status, "connected"); assert.equal(a.mode, "off"); ok("a later passing test restores 'connected' but the port stays OFF"); }

  // ---- disconnect ----
  { const c = { t: 1e12 }, { p } = mk(OWNER, c);
    await p.test(101, "sms"); await p.setMode(101, "sms", "live");
    assert.equal(await p.disconnect(101, "sms"), "disconnected"); const a = await p.getAccount(101, "sms");
    assert.equal(a.mode, "off"); assert.equal(a.status, "not_connected"); assert.equal(a.secret_saved, false); assert.equal(a.last_test_ok_at, null); assert.deepEqual(a.public_config, {});
    await denied(() => p.disconnect(102, "sms"), "integration_not_connected", "disconnect of a never-connected port"); ok("disconnect drops the secret flag, config and test and returns to OFF"); }

  // ---- kill switch ----
  { const c = { t: 1e12 }, { p } = mk(OWNER, c);
    await p.test(101, "sms"); await p.setMode(101, "sms", "live"); await p.setMode(101, "cod", "dry_run");
    const w = (await p.listAccounts(102)).find(r => r.provider_code === "web_storefront"); await p.connect(102, "web_storefront", fieldsFor(w)); await p.setMode(102, "web_storefront", "dry_run");
    assert.equal(await p.killSwitch(101), 2); assert.ok((await p.listAccounts(101)).every(r => r.mode === "off"), "kill switch left a port on");
    assert.equal((await p.getAccount(102, "web_storefront")).mode, "dry_run", "kill switch must not touch another business");
    assert.equal(await p.killSwitch(101), 0); const last = (await p.listAudit(101))[0]; assert.equal(last.action, "kill_switch"); assert.deepEqual(last.after, { turned_off: 0 });
    assert.ok((await p.listAccounts(101)).find(r => r.provider_code === "sms").status === "connected", "kill keeps connection and test");
    ok("kill switch turns every port of the business OFF, audited, other business untouched, connection kept"); }

  // ---- owner-only + tenant isolation ----
  { const c = { t: 1e12 };
    const calls = [p => p.listAccounts(101), p => p.getAccount(101, "sms"), p => p.connect(101, "cod", {}), p => p.test(101, "sms"), p => p.setMode(101, "sms", "dry_run"),
      p => p.disconnect(101, "sms"), p => p.killSwitch(101), p => p.listAudit(101), p => p.setSimulation(101, true), p => p.getSimulation(101)];
    const staff = mk(STAFF, c).p; for (const f of calls) await denied(() => f(staff), "integration_denied", "staff (non-owner) is denied: " + f.toString().slice(8, 40));
    const bo101 = mk(BO101, c).p;
    for (const b of [102, 201]) { await denied(() => bo101.listAccounts(b), "integration_denied", "business owner 101 cannot read business " + b);
      await denied(() => bo101.killSwitch(b), "integration_denied", "business owner 101 cannot kill business " + b);
      await denied(() => bo101.listAudit(b), "integration_denied", "business owner 101 cannot read audit of " + b); }
    const master = mk(OWNER, c).p; await denied(() => master.listAccounts(201), "integration_denied", "master owner cannot read a foreign-tenant business");
    await denied(() => master.killSwitch(201), "integration_denied", "master owner cannot kill a foreign-tenant business");
    await denied(() => master.listAccounts(999), "integration_denied", "unknown business is denied");
    assert.ok(!JSON.stringify(await master.listAudit(101)).includes("CUSTOMER-MERCHANT")); assert.ok(!JSON.stringify(await master.listAccounts(101)).includes("CUSTOMER"));
    assert.ok((await master.listAudit(101)).every(r => r.business_id === 101)); ok("owner-only, business-scoped and tenant-isolated for every method");
    assert.ok(master.listAccounts(101) instanceof Promise); await staff.listAccounts(101).catch(() => {}); ok("every method returns a Promise"); }

  // ---- audit ----
  { const c = { t: Date.UTC(2026, 10, 10) }, { p } = mk(OWNER, c);
    await p.test(101, "sms"); await p.setMode(101, "sms", "dry_run"); await p.setMode(101, "sms", "off"); await p.disconnect(101, "cod");
    const au = await p.listAudit(101); assert.deepEqual(au.slice(0, 4).map(r => r.action), ["disconnect", "mode", "mode", "test"]); assert.ok(au[0].id > au[1].id);
    assert.deepEqual(au[1], Object.assign({}, au[1], { before: { mode: "dry_run" }, after: { mode: "off" } })); assert.equal(au[0].actor, "master_owner");
    au[0].action = "tampered"; assert.notEqual((await p.listAudit(101))[0].action, "tampered"); ok("audit is newest-first, records before/after, and cannot be edited from outside"); }

  // ---- i18n coverage for everything the UI will show ----
  PF.providers.forEach(p => p.needs_fields.forEach(f => { assert.ok(I.en["f." + f] && I.bn["f." + f], "missing label for field " + f); }));
  PF.FAMILIES.forEach(f => assert.ok(I.bn["fam." + f] && I.en["fam." + f]));
  ["off", "dry_run", "live"].forEach(m => assert.ok(I.bn["mode." + m] && I.en["mode." + m]));
  assert.equal(I.bn["mode.off"], "বন্ধ"); assert.ok(I.bn["mode.dry_run"].startsWith("ডেমো")); assert.equal(I.bn["mode.live"], "চালু");
  ["connect", "test", "mode", "disconnect", "kill_switch"].forEach(a => assert.ok(I.bn["act." + a]));
  ["integration_denied", "integration_not_connected", "integration_live_needs_recent_test", "integration_field_required"].forEach(e => assert.ok(I.bn["cx.err." + e]));
  PF.providers.forEach(p => assert.ok(p.label_bn && /[ঀ-৿]/.test(p.label_bn)));
  ok("Bangla/English labels exist for every field, family, mode, audit action and error; mode badges are বন্ধ / ডেমো / চালু");

  // ---- no storage/network/keys in the new shipped files ----
  for (const f of ["ports.js", "ports-fixtures.js", "ports-ui.js"]) {
    const code = fs.readFileSync(path.join(dir, f), "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
    assert.ok(!/localStorage|sessionStorage|indexedDB|document\.cookie|fetch\(|XMLHttpRequest|WebSocket|sendBeacon|eval\(|new Function|innerHTML|history\.(push|replace)State|location\.(search|hash|href)\s*=/.test(code), "forbidden API in " + f);
  }
  ok("new files use no storage, network, innerHTML, URL writes or eval");
  console.log("P6 ports provider tests: all passed");
})().catch(e => { console.error(e); process.exit(1); });
