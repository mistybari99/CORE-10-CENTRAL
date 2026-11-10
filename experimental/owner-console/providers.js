/* CORE 10 Owner Command Center — data providers.
 * 1) fixture provider (default): synthetic data, authorization filtering done in the provider itself.
 * 2) read-only Supabase bridge (optional): DISABLED unless experimentalRead===true AND a signed Supabase client with a
 *    real authenticated user is supplied. Select-only on a fixed allowlist of views. No write method exists.
 * UI role selection is NEVER authorization: the bridge relies on RLS/security_invoker views; the fixture provider
 * imitates that scope for previews. No secret or service-role key is ever accepted or stored here. */
(function (root, factory) {
  "use strict";
  var api = factory(root && root.C10CONSOLE && root.C10CONSOLE.fixtures || (typeof require === "function" ? require("./fixtures.js") : null));
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) { root.C10CONSOLE = root.C10CONSOLE || {}; root.C10CONSOLE.providers = api; }
})(typeof window !== "undefined" ? window : (typeof globalThis !== "undefined" ? globalThis : null), function (F) {
  "use strict";
  var SCHEMA = "c10_demo";
  var VIEW_ALLOWLIST = ["tenant_consolidated_kpi_v1", "owner_business_kpi_v1", "owner_business_control_board_v1",
    "business_module_settings_v1", "business_inventory_report_v1", "operational_business_report_v1", "owner_module_requests_v1",
    "sites", "businesses"];
  function fail(code) { var e = new Error(code); e.code = code; throw e; }
  function clone(v) { return JSON.parse(JSON.stringify(v)); }

  /* ---------- fixture provider ---------- */
  function createFixtureProvider(opts) {
    opts = opts || {};
    var session = opts.session || { role: "master_owner", tenantId: 1, businessIds: [101, 102] };
    function inScope(row) {
      if (row.tenant_id !== session.tenantId) return false;
      if (session.role === "master_owner") return true;
      return session.businessIds.indexOf(row.business_id) !== -1;
    }
    function bizOf(row) { return F.businesses.filter(function (b) { return b.id === row.business_id; })[0]; }
    function guardBusiness(id) {
      var b = F.businesses.filter(function (x) { return x.id === id; })[0];
      if (!b || !inScope({ tenant_id: b.tenant_id, business_id: b.id })) fail("BUSINESS_NOT_AUTHORIZED");
      return b;
    }
    var api = {
      mode: "fixture", synthetic: true,
      getSession: function () { return Promise.resolve(clone(session)); },
      listBusinesses: function () {
        return Promise.resolve(F.businesses.filter(function (b) { return inScope({ tenant_id: b.tenant_id, business_id: b.id }); }).map(clone));
      },
      getKpis: function (businessId) {
        if (businessId != null) { guardBusiness(businessId); var k = clone(F.kpi[businessId]); k.business_id = businessId; return Promise.resolve(k); }
        if (session.role !== "master_owner") fail("CONSOLIDATED_REQUIRES_MASTER_OWNER");
        var ids = F.businesses.filter(function (b) { return inScope({ tenant_id: b.tenant_id, business_id: b.id }); }).map(function (b) { return b.id; });
        var t = { visible_businesses: ids.length, recorded_revenue: 0, recorded_costs: 0, net_manual_profit: 0, unpaid_investor_balance: 0,
          stock_integrity_failures: 0, pending_owner_decisions: 0, enterprise_ready: false };
        ids.forEach(function (id) { var k = F.kpi[id]; t.recorded_revenue += k.recorded_revenue; t.recorded_costs += k.recorded_costs;
          t.net_manual_profit += k.net_manual_profit; t.unpaid_investor_balance += k.unpaid_investor_balance;
          t.stock_integrity_failures += k.unreconciled_location_items; t.pending_owner_decisions += k.pending_owner_decisions; });
        return Promise.resolve(t);
      },
      getHierarchy: function (businessId) {
        guardBusiness(businessId);
        return Promise.resolve(F.sites.filter(function (s) { return s.business_id === businessId && s.tenant_id === session.tenantId; }).map(clone));
      },
      getModules: function (businessId) {
        guardBusiness(businessId);
        return Promise.resolve(F.modules.filter(function (m) { return m.business_id === businessId; }).map(clone));
      },
      getStock: function (businessId) {
        guardBusiness(businessId);
        return Promise.resolve(F.stock.filter(function (s) { return s.business_id === businessId && inScope(s); }).map(clone));
      },
      getOperations: function (businessId) { guardBusiness(businessId); return Promise.resolve(clone(F.operations[businessId])); },
      getApprovals: function (businessId) {
        return Promise.resolve(F.approvals.filter(function (a) { return inScope(a) && (businessId == null || a.business_id === businessId); }).map(clone));
      },
      getSetupSummary: function (businessId) { guardBusiness(businessId); return Promise.resolve(clone(F.setup[businessId])); }
    };
    // Every method always returns a Promise (sync authorization errors become rejections).
    Object.keys(api).forEach(function (k) {
      if (typeof api[k] !== "function") return;
      var f = api[k];
      api[k] = function () { try { return Promise.resolve(f.apply(api, arguments)); } catch (e) { return Promise.reject(e); } };
    });
    return api;
  }

  /* ---------- optional read-only Supabase bridge (fail-closed) ---------- */
  function createSupabaseReadOnlyProvider(config) {
    config = config || {};
    var client = config.client;
    function ready() {
      if (config.experimentalRead !== true) fail("ENTERPRISE_BACKEND_NOT_RELEASED");
      if (!client || !client.auth || typeof client.auth.getUser !== "function" || typeof client.schema !== "function") fail("SIGNED_SUPABASE_CLIENT_REQUIRED");
    }
    async function user() {
      ready();
      var r = await client.auth.getUser();
      if (!r || !r.data || !r.data.user || !r.data.user.id) fail("AUTHENTICATED_USER_REQUIRED");
      return r.data.user;
    }
    async function select(view, filters) {
      if (VIEW_ALLOWLIST.indexOf(view) === -1) fail("VIEW_NOT_ALLOWED");
      await user();
      var q = client.schema(SCHEMA).from(view).select("*");
      Object.keys(filters || {}).forEach(function (k) { q = q.eq(k, filters[k]); });
      var r = await q;
      if (r.error) fail("BACKEND_READ_DENIED");
      return r.data || [];
    }
    return {
      mode: "supabase-readonly", synthetic: false,
      getSession: async function () { var u = await user(); return { userId: u.id, role: "server_decided", note: "role is derived by RLS, not by this UI" }; },
      listBusinesses: function () { return select("owner_business_control_board_v1"); },
      getKpis: async function (businessId) {
        if (businessId != null) { var r = await select("owner_business_kpi_v1", { business_id: businessId }); return r[0] || null; }
        var t = await select("tenant_consolidated_kpi_v1"); return t[0] || null;
      },
      getHierarchy: function (businessId) { return select("sites", { business_id: businessId }); },
      getModules: function (businessId) { return select("business_module_settings_v1", { business_id: businessId }); },
      getStock: function (businessId) { return select("business_inventory_report_v1", { business_id: businessId }); },
      getOperations: async function (businessId) { var r = await select("operational_business_report_v1", { business_id: businessId }); return r[0] || null; },
      getApprovals: function (businessId) { return select("owner_module_requests_v1", businessId == null ? {} : { business_id: businessId }); },
      getSetupSummary: function () { fail("SETUP_SUMMARY_NOT_AVAILABLE_IN_READ_BRIDGE"); }
    };
  }
  var WRITE_METHODS = ["create", "insert", "update", "delete", "upsert", "rpc", "post", "approve", "reject"];
  return { SCHEMA: SCHEMA, VIEW_ALLOWLIST: VIEW_ALLOWLIST, WRITE_METHODS: WRITE_METHODS,
    createFixtureProvider: createFixtureProvider, createSupabaseReadOnlyProvider: createSupabaseReadOnlyProvider };
});
