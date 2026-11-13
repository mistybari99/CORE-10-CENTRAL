"use strict";
const assert = require("node:assert/strict");
const E = require("../core10-crm-lifecycle-engine.js");

// HTML / CSV injection
assert.equal(E.escapeHtml('<img src=x onerror="a()">'), "&lt;img src=x onerror=&quot;a()&quot;&gt;");
assert.equal(E.csvCell('=HYPERLINK("http://x","y")'), '"\'=HYPERLINK(""http://x"",""y"")"');
for (const c of ["+1", "-1", "@SUM(A1)", "\tcmd", "\rcmd"]) assert.ok(E.csvCell(c).startsWith('"\''), c);
assert.equal(E.csvCell(null), '""'); assert.equal(E.csvCell("plain"), '"plain"');
// normalisation + control chars
assert.equal(E.normalizeEmail(" Sales@Acme.EXAMPLE "), "sales@acme.example");
assert.throws(() => E.normalizeEmail("nope"), /A056_INVALID/);
assert.equal(E.normalizePhone("+880 1711-000001"), "8801711000001");
assert.throws(() => E.normalizePhone("12"), /A056_INVALID/); assert.throws(() => E.text("a\u0001b", 10), /A056_INVALID/);
assert.ok(E.REQ.test(E.requestKey("cust")) && E.REQ.test(E.requestKey("")));
// quotation maths identical to SQL: 10 x 100.00 @15% = 850.00, approval over 10%
let q = E.quoteTotals([{ description: "Paint", quantity: "10", unit_price: "100", discount_pct: "15" }], { discount_pct_over: 10, total_over: null });
assert.equal(q.total, "850.00"); assert.equal(q.requires_approval, true); assert.equal(q.lines[0].net_unit_price, "85.00");
q = E.quoteTotals([{ description: "x", quantity: "0.333", unit_price: "0.10" }], { discount_pct_over: 10, total_over: "500" });
assert.equal(q.total, "0.03"); assert.equal(q.requires_approval, false);
q = E.quoteTotals([{ description: "Retainer", quantity: 1, unit_price: 600 }], { total_over: 500 }); assert.equal(q.requires_approval, true);
assert.throws(() => E.quoteTotals([], {}), /A056_INVALID/); assert.throws(() => E.quoteTotals([{ description: "x", quantity: -1, unit_price: 1 }], {}), /A056_INVALID/);
assert.throws(() => E.quoteTotals([{ description: "x", quantity: 1, unit_price: 1.234 }], {}), /A056_INVALID/);
// money: null is never zero
assert.equal(E.formatMoney(null), "NOT CERTIFIED"); assert.equal(E.formatMoney(undefined, "Unavailable"), "Unavailable"); assert.equal(E.formatMoney(0), "BDT 0.00");
assert.equal(E.financeLabel({ status: "NOT_CERTIFIED", balance_due: null }).text, "NOT CERTIFIED"); assert.equal(E.financeLabel({ status: "CERTIFIED", balance_due: 1200.5, test_source: true }).text, "BDT 1,200.50");
assert.equal(E.financeLabel({ status: "UNAVAILABLE" }).certified, false);
// duplicates
assert.deepEqual(E.dedupeScore({ email: "A@x.test" }, { email: "a@X.test" }), { score: 100, reason: "email_match" });
assert.equal(E.dedupeScore({ phone: "01711000002" }, { phone: "+8801711000002" }).score, 0); // different national format is not guessed
assert.equal(E.dedupeScore({ kind: "person", display_name: "Ann" }, { kind: "person", display_name: "ann" }).reason, "name_match");
// consent: no consent => no send; opt-out precedence; expiry; service not blocked by marketing opt-out
const cust = { status: "active" }, now = new Date("2026-11-11T00:00:00Z");
const d = (o) => E.consentDecision(Object.assign({ customer: cust, channel: "email", purpose: "marketing", events: [], suppressions: [] }, o), now);
assert.equal(d({}).reason, "no_consent");
assert.equal(d({ events: [{ id: 1, channel: "email", purpose: "marketing", status: "granted" }] }).can_send, true);
assert.equal(d({ events: [{ id: 1, channel: "email", purpose: "marketing", status: "granted" }], suppressions: [{ channel: "email", purpose: "marketing" }] }).reason, "opt_out_precedence");
assert.equal(d({ events: [{ id: 1, channel: "email", purpose: "marketing", status: "granted" }], suppressions: [{ channel: "email", purpose: "marketing", lifted: true }] }).can_send, true);
assert.equal(d({ events: [{ id: 1, channel: "email", purpose: "marketing", status: "granted" }, { id: 2, channel: "email", purpose: "marketing", status: "revoked" }] }).reason, "revoked");
assert.equal(d({ events: [{ id: 1, channel: "email", purpose: "marketing", status: "granted", valid_until: "2026-11-10T00:00:00Z" }] }).reason, "expired");
assert.equal(d({ purpose: "service", events: [{ id: 1, channel: "email", purpose: "service", status: "granted" }], suppressions: [{ channel: "email", purpose: "marketing" }] }).can_send, true);
assert.equal(d({ purpose: "marketing", events: [{ id: 1, channel: "email", purpose: "marketing", status: "granted" }], suppressions: [{ channel: "email", purpose: "service" }] }).reason, "opt_out_precedence");
assert.equal(d({ customer: { status: "redacted" } }).reason, "customer_inactive"); assert.throws(() => d({ channel: "fax" }), /A056_INVALID/);
// SLA
const t0 = "2026-11-11T00:00:00Z"; assert.equal(E.slaDue(t0, 4), "2026-11-11T04:00:00.000Z");
assert.equal(E.slaState({ status: "open", sla_due_at: "2026-11-11T04:00:00Z", sla_hours: 4 }, new Date("2026-11-11T01:00:00Z")), "ok");
assert.equal(E.slaState({ status: "open", sla_due_at: "2026-11-11T04:00:00Z", sla_hours: 4 }, new Date("2026-11-11T03:30:00Z")), "at_risk");
assert.equal(E.slaState({ status: "open", sla_due_at: "2026-11-11T04:00:00Z", sla_hours: 4 }, new Date("2026-11-11T05:00:00Z")), "breached");
assert.equal(E.slaState({ status: "resolved", resolved_at: "2026-11-11T03:00:00Z", sla_due_at: "2026-11-11T04:00:00Z", sla_hours: 4 }), "met");
// reports: null not zero
const f = E.funnel({ enquiries: 4, leads: 2, qualified_leads: 1, opportunities: 1, quotes_sent: 1, quotes_accepted: 1, orders_created: 1, orders_posted: 0 });
assert.equal(f[0].rate_from_prev, null); assert.equal(f[1].rate_from_prev, 0.5); assert.equal(f[7].rate_from_prev, 0);
assert.equal(E.funnel({})[1].rate_from_prev, null); assert.equal(E.rate(1, 0), null); assert.equal(E.avg([]), null); assert.equal(E.avg([1, 2]), 1.5);
// config invariants
const base = { stages: [{ code: "new", label: "New", kind: "open" }, { code: "won", label: "Won", kind: "won" }, { code: "lost", label: "Lost", kind: "lost" }],
  permissions: { "settings.write": "owner", "customer.redact": "owner", "finance.register": "owner", "customer.merge": "manager" }, sla: { urgent: 4, standard: 24, low: 72 } };
assert.equal(E.validateConfig(base), true);
assert.throws(() => E.validateConfig({ ...base, permissions: { ...base.permissions, "settings.write": "site" } }), /A056_CONFIG_INVARIANT/);
assert.throws(() => E.validateConfig({ ...base, permissions: { ...base.permissions, "customer.redact": "manager" } }), /A056_CONFIG_INVARIANT/);
assert.throws(() => E.validateConfig({ ...base, stages: base.stages.slice(0, 2) }), /A056_CONFIG_INVALID/);
assert.throws(() => E.validateConfig({ ...base, sla: { urgent: 0, standard: 24, low: 72 } }), /A056_CONFIG_INVALID/);
assert.throws(() => E.validateConfig({ ...base, permissions: { ...base.permissions, "evil.action": "site" } }), /A056_CONFIG_INVALID/);
// segments
const c1 = { status: "active", kind: "organization", tags: ["vip"], site_id: 1001 };
assert.equal(E.segmentMatch(c1, { tags_any: ["vip"], min_posted_orders: 1 }, { posted_orders: 1 }), true);
assert.equal(E.segmentMatch(c1, { min_posted_orders: 2 }, { posted_orders: 1 }), false);
assert.equal(E.segmentMatch(c1, { has_consent: { channel: "email", purpose: "marketing" } }, { consent: { can_send: false } }), false);
assert.throws(() => E.segmentMatch(c1, { raw_sql: "1=1" }, {}), /A056_INVALID/);
assert.match(E.errorText("A056_OPT_OUT_PRECEDENCE"), /opted out/); assert.match(E.errorText("X"), /Request failed/);
console.log("PASS A056 engine: injection, money, quotes, consent precedence, SLA, null-not-zero reports, config invariants");
