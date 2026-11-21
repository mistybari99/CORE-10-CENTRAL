"use strict";
// B-021: Owner Control Centre client contract (no network; a recording stand-in for the signed client).
const test = require("node:test"), assert = require("node:assert");
const { create, errorCode, newKey, RPCS } = require("../core10-owner-control-client.js");
function fake(opts) {
  const calls = []; let users = [].concat(opts.users || ["u1"]); let i = 0;
  const client = {
    auth: { getUser: async () => { const id = users[Math.min(i++, users.length - 1)]; return id ? { data: { user: { id } } } : { data: { user: null }, error: { message: "x" } }; } },
    schema: (name) => { assert.strictEqual(name, "core10"); return {
      rpc: async (fn, args) => { calls.push([fn, args]); return opts.reply ? opts.reply(fn, args) : { data: { ok: true } }; },
      from: () => { throw Error("TABLE_ACCESS_FORBIDDEN"); } }; }
  };
  return { client, calls };
}
test("refuses without a signed client or session", async () => {
  await assert.rejects(create({}).read(1), /SIGNED_CLIENT_REQUIRED/);
  await assert.rejects(create({ client: fake({ users: [null] }).client }).read(1), /SIGNED_SESSION_REQUIRED/);
});
test("only allowlisted core10 RPCs, never tables", async () => {
  assert.deepStrictEqual(RPCS.slice().sort(), ["build01_context_v1", "control_approval_binding_v1", "control_audit_v1", "control_grant_override_v1",
    "control_history_v1", "control_overrides_v1", "control_read_bootstrap_policy_v1", "control_read_v1", "control_revert_v1",
    "control_revoke_override_v1", "control_set_bootstrap_policy_v1", "control_set_v1"]);
  const f = fake({}); const api = create({ client: f.client });
  await api.read(9101, null); await api.history(9101, "gov002.review"); await api.audit(9101);
  assert.deepStrictEqual(f.calls.map((c) => c[0]), ["control_read_v1", "control_history_v1", "control_audit_v1"]);
});
test("server errors become codes with detail", async () => {
  const f = fake({ reply: () => ({ error: { message: "CONTROL_PARAM_RANGE:max_rows" } }) });
  await assert.rejects(create({ client: f.client }).read(9101), (e) => e.code === "CONTROL_PARAM_RANGE" && e.detail === "max_rows");
  assert.deepStrictEqual(errorCode("permission denied for schema core10"), { code: "CONTROL_RPC_UNAVAILABLE", detail: "permission denied for schema core10" });
});
test("a session change between or during calls is refused", async () => {
  const between = create({ client: fake({ users: ["u1", "u1", "u2", "u2"] }).client });
  await between.read(9101);
  await assert.rejects(between.read(9101), /SESSION_CHANGED/);
  await assert.rejects(create({ client: fake({ users: ["u1", "u2"] }).client }).read(9101), /SESSION_CHANGED/);
});
test("set builds the canonical arguments; follow-business sends no values", async () => {
  const f = fake({}); const api = create({ client: f.client });
  await api.set({ business: 9101, site: null, feature: "gov002.review", enabled: false, stages: 0, params: { exception_escalation: true },
    expectedVersion: 0, reason: "Owner pauses review", requestKey: "fixed_key_0001" });
  assert.deepStrictEqual(f.calls[0][1], { p_business: 9101, p_site: null, p_feature: "gov002.review", p_enabled: false, p_stages: 0,
    p_params: { exception_escalation: true }, p_effective_from: null, p_inherit: false, p_expected_version: 0, p_reason: "Owner pauses review", p_request_key: "fixed_key_0001" });
  await api.set({ business: 9101, site: 9201, feature: "gov002.review", inherit: true, expectedVersion: 2, reason: "Follow the business" });
  const a = f.calls[1][1];
  assert.strictEqual(a.p_inherit, true); assert.strictEqual(a.p_enabled, null); assert.strictEqual(a.p_stages, null); assert.strictEqual(a.p_params, null);
  assert.match(a.p_request_key, /^ctl_[A-Za-z0-9_-]{8,}$/);
});
test("bad input is refused before any call", async () => {
  const f = fake({}); const api = create({ client: f.client });
  await assert.rejects(api.read("0"), /INVALID_BUSINESS_ID/);
  await assert.rejects(api.read("9101; drop"), /INVALID_BUSINESS_ID/);
  await assert.rejects(api.history(9101, "Bad Key"), /INVALID_FEATURE/);
  await assert.rejects(api.set({ business: 9101, feature: "gov002.review", enabled: true, stages: 1, expectedVersion: 0, reason: "no" }), /CONTROL_BAD_REASON/);
  await assert.rejects(api.grantOverride({ business: 9101, feature: "gov002.review", hours: 0, reason: "valid reason" }), /CONTROL_BAD_HOURS/);
  assert.strictEqual(f.calls.length, 0);
});
test("request keys fit the server rule", () => {
  for (let i = 0; i < 50; i++) assert.match(newKey("ctl"), /^[A-Za-z0-9_-]{8,128}$/);
});

test("tenant policy RPCs use signed scope and a versioned write", async () => {
  const f = fake({ reply: () => ({ data: { tenant_id: 901, enabled: false, latest_version: 0 } }) });
  const api = create({ client: f.client });
  await assert.rejects(api.readBootstrap(902), /CONTROL_SCOPE/);
  const policy = await api.readBootstrap(901);
  await api.setBootstrap({ tenant: 901, enabled: true, expectedVersion: policy.latest_version,
    reason: "Allow first Business setup", requestKey: "bootstrap_test_key" });
  assert.deepStrictEqual(f.calls.at(-1), ["control_set_bootstrap_policy_v1", {
    p_tenant: 901, p_enabled: true, p_expected_version: 0, p_effective_at: null,
    p_reason: "Allow first Business setup", p_request_key: "bootstrap_test_key"
  }]);
});
