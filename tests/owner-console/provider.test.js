// A036 Owner Command Center: provider, isolation, i18n and no-secret contracts (Node, no browser).
"use strict";
const assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path");
const dir = process.env.C10_CONSOLE_ROOT || path.join(__dirname, "..", "..", "experimental", "owner-console");
const P = require(path.join(dir, "providers.js")), I = require(path.join(dir, "i18n.js")), F = require(path.join(dir, "fixtures.js"));
const ok = (l) => console.log("PASS " + l);
async function denied(fn, code, label) { try { await fn(); } catch (e) { assert.equal(e.code, code, label + ": " + e.code); ok("DENIED " + label); return; } assert.fail(label + ": was allowed"); }
(async () => {
  assert.equal(F.SYNTHETIC, true); ok("fixtures are marked synthetic");
  const master = P.createFixtureProvider({ session: { role: "master_owner", tenantId: 1, businessIds: [101, 102] } });
  const own101 = P.createFixtureProvider({ session: { role: "business_owner", tenantId: 1, businessIds: [101] } });
  assert.deepEqual((await master.listBusinesses()).map(b => b.id), [101, 102]); ok("master sees only its tenant businesses");
  assert.deepEqual((await own101.listBusinesses()).map(b => b.id), [101]); ok("business owner sees only its own business");
  const cons = await master.getKpis();
  assert.equal(cons.visible_businesses, 2); assert.equal(cons.recorded_revenue, 1840500.5 + 215400);
  assert.equal(cons.enterprise_ready, false); ok("consolidated KPIs exclude the foreign tenant and are never 'enterprise ready'");
  await denied(() => own101.getKpis(), "CONSOLIDATED_REQUIRES_MASTER_OWNER", "business owner cannot read consolidated");
  for (const [who, p] of [["business owner", own101], ["master owner", master]]) {
    await denied(() => p.getKpis(201), "BUSINESS_NOT_AUTHORIZED", who + " cannot read a foreign-tenant business KPI");
    await denied(() => p.getHierarchy(201), "BUSINESS_NOT_AUTHORIZED", who + " cannot read foreign sites");
    await denied(() => p.getModules(201), "BUSINESS_NOT_AUTHORIZED", who + " cannot read foreign modules");
    await denied(() => p.getStock(201), "BUSINESS_NOT_AUTHORIZED", who + " cannot read foreign stock");
    await denied(() => p.getOperations(201), "BUSINESS_NOT_AUTHORIZED", who + " cannot read foreign operations");
    await denied(() => p.getSetupSummary(201), "BUSINESS_NOT_AUTHORIZED", who + " cannot read foreign setup");
  }
  await denied(() => own101.getStock(102), "BUSINESS_NOT_AUTHORIZED", "business owner cannot read sibling business stock");
  await denied(() => own101.getModules(102), "BUSINESS_NOT_AUTHORIZED", "business owner cannot read sibling modules");
  const ap = await own101.getApprovals(); assert.ok(ap.length && ap.every(a => a.business_id === 101 && a.tenant_id === 1)); ok("approvals are scoped to the business");
  assert.ok((await master.getApprovals()).every(a => a.tenant_id === 1)); ok("master approvals exclude the foreign tenant");
  const blob = JSON.stringify([await master.listBusinesses(), await master.getStock(101), await master.getStock(102), await master.getApprovals()]);
  assert.ok(!/999999|Independent Customer|CUSTOMER-SKU|Foreign tenant/.test(blob)); ok("no foreign tenant data leaks into any master response");
  // every provider method returns a Promise even on authorization failure
  const pr = own101.getKpis(102); assert.ok(pr instanceof Promise); await pr.catch(() => {}); ok("provider methods always return Promises");
  // read-only bridge is fail-closed
  await denied(() => P.createSupabaseReadOnlyProvider({}).getSession(), "ENTERPRISE_BACKEND_NOT_RELEASED", "bridge disabled by default");
  await denied(() => P.createSupabaseReadOnlyProvider({ experimentalRead: true }).getSession(), "SIGNED_SUPABASE_CLIENT_REQUIRED", "bridge needs a signed client");
  const calls = [], mk = (user) => ({ auth: { getUser: async () => ({ data: { user } }) }, schema(s) { calls.push("schema:" + s); const self = this; return { from(v) { calls.push("from:" + v); return { select() { return { eq() { return this; }, then(r) { r({ data: [{ ok: 1 }], error: null }); } }; } }; } }; } });
  await denied(() => P.createSupabaseReadOnlyProvider({ experimentalRead: true, client: mk(null) }).getSession(), "AUTHENTICATED_USER_REQUIRED", "bridge needs a real authenticated user");
  const bridge = P.createSupabaseReadOnlyProvider({ experimentalRead: true, client: mk({ id: "u-1" }) });
  assert.equal((await bridge.getKpis(101))?.ok, 1); assert.deepEqual(calls.slice(0, 2), ["schema:c10_demo", "from:owner_business_kpi_v1"]); ok("bridge reads only an allowlisted view from c10_demo");
  P.WRITE_METHODS.forEach(m => assert.equal(typeof bridge[m], "undefined", "bridge exposes write method " + m)); ok("bridge exposes no write/RPC method");
  await denied(() => bridge.getSetupSummary(101), "SETUP_SUMMARY_NOT_AVAILABLE_IN_READ_BRIDGE", "bridge cannot invent unsupported data");
  // i18n parity
  assert.deepEqual(Object.keys(I.en).sort(), Object.keys(I.bn).sort()); ok("Bangla and English define identical keys");
  Object.entries(I.bn).forEach(([k, v]) => assert.ok(String(v).trim().length > 0, "empty bn " + k));
  assert.notEqual(I.bn["nav.overview"], I.en["nav.overview"]); ok("Bangla strings are really translated");
  // no secrets / network / service-role in shipped files
  for (const f of fs.readdirSync(dir)) { const s = fs.readFileSync(path.join(dir, f), "utf8");
    if (!/\.(js)$/.test(f)) continue;
    const code = s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, ""); // scan code, not explanatory comments
    assert.ok(!/service[_-]?role|eyJ[A-Za-z0-9_-]{20,}|sb_secret|apikey|api_key|fetch\(|XMLHttpRequest|localStorage|sessionStorage|document\.cookie|eval\(|new Function/i.test(code), "forbidden token in code of " + f); }
  ok("no secret, key, storage or network call in the shipped files");
  console.log("A036 provider tests: all passed");
})().catch(e => { console.error(e); process.exit(1); });
