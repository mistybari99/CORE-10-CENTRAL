/* CORE 10 CENTRAL | B-012 Owner multi-business dashboard client (NP03A).
 * Calls only canonical read RPCs: 0204 portfolio/site summaries, 0201 stock reads, 0203 purchase reads.
 * No table access, no local permission decision, no stored token, no simulated figures.
 */
(function (root, factory) {
  "use strict";
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.CORE10_OWNER_DASHBOARD_API = api;
})(typeof window !== "undefined" ? window : globalThis, function () {
  "use strict";
  const RPCS = new Set(["owner_portfolio_v1", "owner_business_sites_v1", "inventory_list_balances_v1", "inventory_list_commands_v1", "procurement_list_pos_v1"]);
  const KINDS = ["showroom", "factory", "godown", "warehouse", "project"];
  function fail(code, detail) { const e = new Error(code); e.code = code; if (detail) e.detail = detail; throw e; }
  function posInt(x, code) {
    if (!(typeof x === "number" || typeof x === "string") || !/^[1-9][0-9]*$/.test(String(x)) || !Number.isSafeInteger(Number(x))) fail(code || "INVALID_ID");
    return Number(x);
  }
  const optInt = (x) => (x === null || x === undefined || x === "" ? null : posInt(x));
  const limit = (x, d) => { const n = Number(x || d); return Number.isInteger(n) && n >= 1 && n <= 200 ? n : d; };
  function errorCode(message) {
    const m = String(message || "").match(/^((?:DASH|INV|PROC|CONTROL|SESSION|SIGNED|INVALID|RPC)_[A-Z_]+)(?::(.*))?$/);
    if (m) return { code: m[1], detail: m[2] || null };
    return { code: "DASH_RPC_UNAVAILABLE", detail: String(message || "").slice(0, 160) };
  }
  function create(options) {
    const client = options && options.client; let sessionUser = null;
    async function currentUser() {
      if (!client || !client.auth || typeof client.auth.getUser !== "function" || typeof client.schema !== "function") fail("SIGNED_CLIENT_REQUIRED");
      const r = await client.auth.getUser(); const id = r && !r.error && r.data && r.data.user && r.data.user.id;
      if (typeof id !== "string" || !id) fail("SIGNED_SESSION_REQUIRED"); return id;
    }
    async function call(name, args) {
      if (!RPCS.has(name)) fail("RPC_NOT_ALLOWED");
      const before = await currentUser();
      if (sessionUser && sessionUser !== before) { sessionUser = before; fail("SESSION_CHANGED"); }
      sessionUser = before;
      const schema = client.schema("core10"); if (!schema || typeof schema.rpc !== "function") fail("DASH_SCHEMA_UNAVAILABLE");
      const r = await schema.rpc(name, args || {});
      const after = await currentUser(); if (after !== before) { sessionUser = after; fail("SESSION_CHANGED"); }
      if (!r || r.error) { const e = errorCode(r && r.error && r.error.message); fail(e.code, e.detail); }
      return r.data;
    }
    return {
      portfolio: async () => call("owner_portfolio_v1", {}),
      sites: async (b, o) => {
        const kind = o && o.kind ? String(o.kind) : null; if (kind && !KINDS.includes(kind)) fail("INVALID_KIND");
        return call("owner_business_sites_v1", { p_business: posInt(b), p_kind: kind, p_after_site: optInt(o && o.after), p_limit: limit(o && o.limit, 50) });
      },
      balances: async (b, site, o) => call("inventory_list_balances_v1", { p_business: posInt(b), p_site: posInt(site),
        p_after_location: optInt(o && o.afterLocation), p_after_item: optInt(o && o.afterItem), p_limit: limit(o && o.limit, 50) }),
      commands: async (b, site) => call("inventory_list_commands_v1", { p_business: posInt(b), p_site: posInt(site), p_limit: 20 }),
      purchases: async (b, site) => call("procurement_list_pos_v1", { p_business: posInt(b), p_site: posInt(site), p_limit: 20 })
    };
  }
  return { create, errorCode, KINDS, RPCS: Array.from(RPCS) };
});
