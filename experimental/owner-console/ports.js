/* CORE 10 Owner Connections (P6) — synthetic ports provider. Rules mirror scripts/c10_a038_integration_core_v1.sql:
 *  - accounts start OFF; mode<>off needs status 'connected'; live needs a PASSED test no older than 30 days
 *  - a failed test forces mode off; reconnect/disconnect return the port to off and clear the test
 *  - kill switch turns every account of one business off; audit is append-only, owner-only, business-scoped
 *  - only owners (master owner of the tenant, or the business owner) may do anything; others get integration_denied
 * SECRETS: secret field values are validated and then DROPPED. They are never stored, returned, audited or logged;
 * only an opaque secret_ref NAME ("ib_<business>_<provider>_v<n>") is kept. There is no method that returns a secret.
 * This is a browser-side fixture: no network, no storage, no real provider call. */
(function (root, factory) {
  "use strict";
  var api = factory(root && root.C10CONSOLE && root.C10CONSOLE.fixtures || (typeof require === "function" ? require("./fixtures.js") : null),
    root && root.C10CONSOLE && root.C10CONSOLE.portsFixtures || (typeof require === "function" ? require("./ports-fixtures.js") : null));
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) { root.C10CONSOLE = root.C10CONSOLE || {}; root.C10CONSOLE.ports = api; }
})(typeof window !== "undefined" ? window : (typeof globalThis !== "undefined" ? globalThis : null), function (F, PF) {
  "use strict";
  var DAY = 86400000, TEST_VALID_DAYS = 30, MODES = ["off", "dry_run", "live"];
  var SECRET_KEY_RE = /(secret|token|password|passwd|api_?key|private)/i; // same idea as the SQL CHECK on public_config
  function fail(code) { var e = new Error(code); e.code = code; throw e; }
  function clone(v) { return v == null ? v : JSON.parse(JSON.stringify(v)); }
  function iso(ms) { return ms == null ? null : new Date(ms).toISOString(); }
  function tenantOf(businessId) { var b = F.businesses.filter(function (x) { return x.id === businessId; })[0]; return b ? b.tenant_id : null; }

  function createStore(opts) {
    opts = opts || {};
    var S = { now: opts.now || function () { return Date.now(); }, seq: 0, aseq: 0, accounts: [], audit: [], sim: { nextTestFails: false } };
    PF.seedAccounts.forEach(function (s) {
      S.accounts.push({ id: ++S.seq, tenant_id: tenantOf(s.business_id), business_id: s.business_id, provider_code: s.provider_code, mode: s.mode, status: s.status,
        secret_version: s.secret_version, public_config: clone(s.public_config), daily_cap: 200, quiet_start_hour: 22, quiet_end_hour: 8, last_test_ok_ms: null, last_test_detail: null });
    });
    PF.seedAudit.forEach(function (a) {
      S.audit.push({ id: ++S.aseq, business_id: a.business_id, provider_code: a.provider_code, actor: a.actor, action: a.action,
        before: clone(a.before), after: clone(a.after), at: a.at });
    });
    return { _s: S, snapshot: function () { return clone({ accounts: S.accounts, audit: S.audit, sim: S.sim }); } };
  }

  function createPortsProvider(o) {
    o = o || {};
    var session = o.session || { role: "master_owner", tenantId: 1, businessIds: [101, 102] };
    var store = o.store || createStore(), S = store._s;
    function guard(businessId) {
      var t = tenantOf(businessId);
      if (t == null || t !== session.tenantId) fail("integration_denied");
      if (session.role === "master_owner") return businessId;
      if (session.role === "business_owner" && session.businessIds.indexOf(businessId) !== -1) return businessId;
      fail("integration_denied");
    }
    function providerOf(code) { var p = PF.providers.filter(function (x) { return x.code === code; })[0]; if (!p) fail("integration_unknown_provider"); return p; }
    function find(b, code) { return S.accounts.filter(function (a) { return a.business_id === b && a.provider_code === code; })[0] || null; }
    function liveReady(a) { return !!a && a.status === "connected" && a.last_test_ok_ms != null && (S.now() - a.last_test_ok_ms) <= TEST_VALID_DAYS * DAY; }
    function view(b, pv, a) {
      return { id: a ? a.id : null, business_id: b, provider_code: pv.code, family: pv.family, label_en: pv.label_en, label_bn: pv.label_bn,
        needs_fields: pv.needs_fields.slice(), secret_fields: pv.secret_fields.slice(), needs_secret: pv.needs_secret,
        mode: a ? a.mode : "off", status: a ? a.status : "not_connected", secret_saved: !!(a && a.secret_version > 0 && pv.needs_secret),
        public_config: a ? clone(a.public_config) : {}, daily_cap: a ? a.daily_cap : 200, quiet_start_hour: a ? a.quiet_start_hour : 22, quiet_end_hour: a ? a.quiet_end_hour : 8,
        last_test_ok_at: a ? iso(a.last_test_ok_ms) : null, last_test_detail: a ? a.last_test_detail : null,
        dry_run_ready: !!a && a.status === "connected", live_ready: liveReady(a) };
    }
    function audit(b, pvCode, action, before, after) {
      S.audit.push({ id: ++S.aseq, business_id: b, provider_code: pvCode, actor: session.role, action: action, before: clone(before), after: clone(after), at: iso(S.now()) });
    }
    var api = {
      mode: "ports-fixture", synthetic: true,
      listProviders: function () { return clone(PF.providers); },
      listAccounts: function (businessId) {
        guard(businessId);
        return PF.providers.map(function (pv) { return view(businessId, pv, find(businessId, pv.code)); });
      },
      getAccount: function (businessId, code) { guard(businessId); var pv = providerOf(code); return view(businessId, pv, find(businessId, code)); },
      /* fields: { needs_field_name: string }. Secret values are checked, then discarded; they are not retained anywhere. */
      connect: function (businessId, code, fields) {
        guard(businessId); var pv = providerOf(code); fields = fields || {};
        Object.keys(fields).forEach(function (n) { if (pv.needs_fields.indexOf(n) === -1) fail("integration_unknown_field"); });
        var pub = {}, secrets = 0;
        pv.needs_fields.forEach(function (n) {
          var v = fields[n];
          if (typeof v !== "string" || !v.trim()) fail("integration_field_required");
          if (v.length > 500) fail("integration_field_invalid");
          if (pv.secret_fields.indexOf(n) !== -1) { secrets++; return; }
          if (v.trim().length > 200) fail("integration_field_invalid");
          pub[n] = v.trim();
        });
        Object.keys(pub).forEach(function (k) { if (SECRET_KEY_RE.test(k)) fail("integration_secret_in_public_config"); });
        if (pv.needs_secret && secrets === 0) fail("integration_secret_ref_required");
        var a = find(businessId, code), before = a ? { mode: a.mode, status: a.status } : null;
        var version = pv.needs_secret ? (a ? a.secret_version : 0) + 1 : 0;
        if (!a) { a = { id: ++S.seq, tenant_id: tenantOf(businessId), business_id: businessId, provider_code: code, daily_cap: 200, quiet_start_hour: 22, quiet_end_hour: 8 }; S.accounts.push(a); }
        a.status = "connected"; a.mode = "off"; a.secret_version = version; a.public_config = pub; a.last_test_ok_ms = null; a.last_test_detail = null;
        audit(businessId, code, "connect", before, { provider: code, secret_ref: pv.needs_secret ? "ib_" + businessId + "_" + code + "_v" + version : null, mode: "off" });
        return view(businessId, pv, a);
      },
      test: function (businessId, code) {
        guard(businessId); providerOf(code); var a = find(businessId, code);
        if (!a || a.status === "not_connected") fail("integration_not_connected");
        var ok = !S.sim.nextTestFails; S.sim.nextTestFails = false;
        if (ok) { a.status = "connected"; a.last_test_ok_ms = S.now(); a.last_test_detail = "synthetic test passed"; }
        else { a.status = "test_failed"; a.mode = "off"; a.last_test_ok_ms = null; a.last_test_detail = "synthetic test failed"; }
        audit(businessId, code, "test", null, { ok: ok });
        return ok ? "passed" : "failed";
      },
      setMode: function (businessId, code, mode) {
        guard(businessId); providerOf(code);
        if (MODES.indexOf(mode) === -1) fail("integration_invalid_mode");
        var a = find(businessId, code); if (!a) fail("integration_not_connected");
        if (mode !== "off" && a.status !== "connected") fail("integration_not_connected");
        if (mode === "live" && !liveReady(a)) fail("integration_live_needs_recent_test");
        var before = a.mode; a.mode = mode; audit(businessId, code, "mode", { mode: before }, { mode: mode });
        return mode;
      },
      disconnect: function (businessId, code) {
        guard(businessId); providerOf(code); var a = find(businessId, code); if (!a) fail("integration_not_connected");
        var before = { mode: a.mode, status: a.status };
        a.mode = "off"; a.status = "not_connected"; a.secret_version = 0; a.public_config = {}; a.last_test_ok_ms = null; a.last_test_detail = null;
        audit(businessId, code, "disconnect", before, { mode: "off", status: "not_connected" });
        return "disconnected";
      },
      killSwitch: function (businessId) {
        guard(businessId); var n = 0;
        S.accounts.forEach(function (a) { if (a.business_id === businessId && a.mode !== "off") { a.mode = "off"; n++; } });
        audit(businessId, null, "kill_switch", null, { turned_off: n });
        return n;
      },
      listAudit: function (businessId) {
        guard(businessId);
        return S.audit.filter(function (r) { return r.business_id === businessId; }).sort(function (x, y) { return y.id - x.id; }).map(clone);
      },
      /* fixture-only control: make the NEXT test fail so the failure path can be previewed. Owners only. */
      setSimulation: function (businessId, nextTestFails) { guard(businessId); S.sim.nextTestFails = !!nextTestFails; return S.sim.nextTestFails; },
      getSimulation: function (businessId) { guard(businessId); return S.sim.nextTestFails; }
    };
    Object.keys(api).forEach(function (k) {
      if (typeof api[k] !== "function") return;
      var f = api[k];
      api[k] = function () { try { return Promise.resolve(f.apply(api, arguments)); } catch (e) { return Promise.reject(e); } };
    });
    return api;
  }
  return { TEST_VALID_DAYS: TEST_VALID_DAYS, MODES: MODES, createStore: createStore, createPortsProvider: createPortsProvider };
});
