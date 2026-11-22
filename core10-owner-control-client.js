/* CORE 10 CENTRAL | B-021 Owner Control Centre client (DEC-08).
 * Calls only the canonical core10 Control RPCs and the Build01 access context. No table access,
 * no local permission decision, no service key, no stored token, no simulated success:
 * the server decides who may read or change a control.
 */
(function (root, factory) {
  "use strict";
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.CORE10_OWNER_CONTROL_API = api;
})(typeof window !== "undefined" ? window : globalThis, function () {
  "use strict";
  const RPCS = new Set([
    "build01_context_v1", "control_read_v1", "control_set_v1", "control_revert_v1",
    "control_history_v1", "control_overrides_v1", "control_grant_override_v1",
    "control_revoke_override_v1", "control_audit_v1", "control_approval_binding_v1",
    "control_read_bootstrap_policy_v1", "control_set_bootstrap_policy_v1"
  ]);

  function fail(code, detail) {
    const e = new Error(code);
    e.code = code;
    if (detail) e.detail = detail;
    throw e;
  }
  function posInt(x, code) {
    if (!(typeof x === "number" || typeof x === "string") || !/^[1-9][0-9]*$/.test(String(x)) ||
        !Number.isSafeInteger(Number(x))) fail(code || "INVALID_ID");
    return Number(x);
  }
  function optSite(x) { return x === null || x === undefined || x === "" ? null : posInt(x, "INVALID_SITE_ID"); }
  function feature(x) {
    if (typeof x !== "string" || !/^[a-z][a-z0-9_]{1,40}(\.[a-z][a-z0-9_]{1,60}){1,3}$/.test(x)) fail("INVALID_FEATURE");
    return x;
  }
  function reason(x) {
    const s = typeof x === "string" ? x.trim() : "";
    if (s.length < 5 || s.length > 500) fail("CONTROL_BAD_REASON");
    return s;
  }
  // One key per confirmed Owner action; reuse it when retrying the same action.
  function newKey(prefix) {
    const c = globalThis.crypto;
    const raw = c && typeof c.randomUUID === "function" ? c.randomUUID()
      : Date.now().toString(36) + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
    return (String(prefix || "ctl") + "_" + raw).replace(/[^A-Za-z0-9_-]/g, "").slice(0, 100);
  }
  function errorCode(message) {
    const m = String(message || "").match(/^((?:CONTROL|SESSION|SIGNED|INVALID|RPC|BOOTSTRAP)_[A-Z_]+)(?::(.*))?$/);
    return m ? { code: m[1], detail: m[2] || null } : { code: "CONTROL_RPC_UNAVAILABLE", detail: String(message || "").slice(0, 160) };
  }

  function create(options) {
    const client = options && options.client;
    let sessionUser = null;
    async function currentUser() {
      if (!client || !client.auth || typeof client.auth.getUser !== "function" || typeof client.schema !== "function")
        fail("SIGNED_CLIENT_REQUIRED");
      const r = await client.auth.getUser();
      const id = r && !r.error && r.data && r.data.user && r.data.user.id;
      if (typeof id !== "string" || !id) fail("SIGNED_SESSION_REQUIRED");
      return id;
    }
    async function call(name, args) {
      if (!RPCS.has(name)) fail("RPC_NOT_ALLOWED");
      const before = await currentUser();
      if (sessionUser && sessionUser !== before) { sessionUser = before; fail("SESSION_CHANGED"); }
      sessionUser = before;
      const schema = client.schema("core10");
      if (!schema || typeof schema.rpc !== "function") fail("CONTROL_SCHEMA_UNAVAILABLE");
      const r = await schema.rpc(name, args || {});
      const after = await currentUser();
      if (after !== before) { sessionUser = after; fail("SESSION_CHANGED"); }
      if (!r || r.error) { const e = errorCode(r && r.error && r.error.message); fail(e.code, e.detail); }
      return r.data;
    }
    return {
      userId: () => sessionUser,
      context: async () => call("build01_context_v1", {}),
      readBootstrap: async (tenant) => {
        const id = posInt(tenant, "INVALID_TENANT_ID");
        const policy = await call("control_read_bootstrap_policy_v1", { p_tenant: id });
        if (!policy || Number(policy.tenant_id) !== id || typeof policy.enabled !== "boolean")
          fail("CONTROL_SCOPE");
        return policy;
      },
      setBootstrap: async (o) => {
        if (typeof o.enabled !== "boolean") fail("CONTROL_BAD_INPUT");
        return call("control_set_bootstrap_policy_v1", {
          p_tenant: posInt(o.tenant, "INVALID_TENANT_ID"),
          p_enabled: o.enabled, p_effective_at: null,
          p_expected_version: nonNegative(o.expectedVersion), p_reason: reason(o.reason),
          p_request_key: o.requestKey || newKey("bootstrap")
        });
      },
      read: async (business, site) => call("control_read_v1", { p_business: posInt(business, "INVALID_BUSINESS_ID"), p_site: optSite(site) }),
      history: async (business, featureKey, limit) => call("control_history_v1", {
        p_business: posInt(business, "INVALID_BUSINESS_ID"), p_feature: featureKey ? feature(featureKey) : null, p_limit: limit || 100 }),
      overrides: async (business) => call("control_overrides_v1", { p_business: posInt(business, "INVALID_BUSINESS_ID") }),
      audit: async (business, limit) => call("control_audit_v1", { p_business: posInt(business, "INVALID_BUSINESS_ID"), p_limit: limit || 100 }),
      binding: async (business, featureKey, site) => call("control_approval_binding_v1", {
        p_business: posInt(business, "INVALID_BUSINESS_ID"), p_feature: feature(featureKey), p_site: optSite(site) }),
      set: async (o) => call("control_set_v1", {
        p_business: posInt(o.business, "INVALID_BUSINESS_ID"), p_site: optSite(o.site), p_feature: feature(o.feature),
        p_enabled: o.inherit ? null : !!o.enabled, p_stages: o.inherit ? null : posIntOrZero(o.stages),
        p_params: o.inherit ? null : (o.params || {}), p_effective_from: o.effectiveFrom || null,
        p_inherit: !!o.inherit, p_expected_version: nonNegative(o.expectedVersion), p_reason: reason(o.reason),
        p_request_key: o.requestKey || newKey("ctl") }),
      revert: async (o) => call("control_revert_v1", {
        p_business: posInt(o.business, "INVALID_BUSINESS_ID"), p_site: optSite(o.site), p_feature: feature(o.feature),
        p_to_version: posInt(o.toVersion, "INVALID_VERSION"), p_expected_version: nonNegative(o.expectedVersion),
        p_reason: reason(o.reason), p_request_key: o.requestKey || newKey("rev") }),
      grantOverride: async (o) => call("control_grant_override_v1", {
        p_business: posInt(o.business, "INVALID_BUSINESS_ID"), p_site: optSite(o.site), p_feature: feature(o.feature),
        p_hours: posInt(o.hours, "CONTROL_BAD_HOURS"), p_reason: reason(o.reason), p_request_key: o.requestKey || newKey("ovr") }),
      revokeOverride: async (o) => call("control_revoke_override_v1", {
        p_business: posInt(o.business, "INVALID_BUSINESS_ID"), p_override_id: posInt(o.overrideId, "INVALID_ID"),
        p_reason: reason(o.reason), p_request_key: o.requestKey || newKey("rvk") })
    };
  }
  function posIntOrZero(x) {
    if (x === 0 || x === "0") return 0;
    return posInt(x, "CONTROL_STAGES");
  }
  function nonNegative(x) {
    if (x === 0 || x === "0") return 0;
    return posInt(x, "INVALID_VERSION");
  }

  return { create, errorCode, newKey, RPCS: Array.from(RPCS) };
});
