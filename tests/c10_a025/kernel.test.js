"use strict";
const assert = require("node:assert/strict"); const E = require("../../modules/simulation/index.js"); const { D, Dec, SimError, allocate } = E; const A = require("../../modules/simulation/lib/analysis");
const code = (fn) => { try { fn(); } catch (e) { return e.code || ("JS:" + e.message); } return null; };
/* decimal exactness & refusal of unsafe input */
assert.equal(D("0.1").add("0.2").toString(), "0.3"); assert.equal(D("1000000000000.1234").mul("3").toString(), "3000000000000.3702");
assert.equal(D("2.675").round(2).toString(), "2.68", "half-up, not binary-float 2.67"); assert.equal(D("-2.5").round(0).toString(), "-3"); assert.equal(D("2.5").round(0, "half_even").toString(), "2"); assert.equal(D("3.5").round(0, "half_even").toString(), "4");
assert.equal(D("10").div(3).toString(2), "3.33"); assert.equal(D("-0.004").toString(2), "0.00", "no negative zero");
for (const bad of ["1e3", "NaN", "Infinity", "1,000", "", " ", "1.2.3", "0x10", "--1", "1.1234567890123456789"]) assert.equal(code(() => D(bad)), "BAD_DECIMAL", "must refuse " + bad);
assert.equal(code(() => D(0.1)), "BAD_DECIMAL", "non-integer JS numbers refused"); assert.equal(code(() => D(1).div(0)), "DIV_ZERO"); assert.equal(D("2").sqrt().toString(), "1.414213562373095048");
const al = allocate("100", ["1", "1", "1"]); assert.equal(al.reduce((a, b) => a.add(b), D(0)).toString(), "100", "allocation conserves total"); assert.equal(al.map(String).join(","), "33.34,33.33,33.33");
/* units */
const { convert } = E.units; assert.equal(convert("5000", "g", "kg").toString(), "5"); assert.equal(convert("1", "dozen", "piece").toString(), "12"); assert.equal(code(() => convert("1", "kg", "l")), "UNIT_DIMENSION_MISMATCH"); assert.equal(code(() => convert("1", "kg", "parsec")), "UNKNOWN_UNIT");
/* unknown is not zero; required missing withheld, never computed */
let r = E.runModel("M02", null, { fixed_costs: "1000", unit_price: { kind: "unknown" }, variable_cost_per_unit: "5" }); assert.equal(r.readiness, "needs_input"); assert.equal(r.outputs, null); assert.deepEqual(r.requiredInputs.map(x => x.key), ["unit_price"]);
r = E.runModel("M03", null, { revenue: "100", cogs: "60", operating_expenses: "10" }); assert.equal(r.outputs.tax_amount, null, "absent tax = unknown, not 0"); assert.equal(r.outputs.operating_cash_estimate, null, "bridge withheld without WC changes");
/* validation: ranges, malformed, currency, period, enum */
assert.equal(code(() => E.runModel("M01", null, { unit_cost: "-1", selling_price: "10" })), "OUT_OF_RANGE"); assert.equal(code(() => E.runModel("M01", null, { unit_cost: "x", selling_price: "10" })), "BAD_DECIMAL");
assert.equal(code(() => E.runModel("M01", null, { unit_cost: { value: "5", currency: "USD" }, selling_price: "10" })), "CURRENCY_MISMATCH"); assert.equal(code(() => E.runModel("M01", null, { unit_cost: "5", selling_price: "10", discount_pct: "101" })), "OUT_OF_RANGE");
assert.equal(code(() => E.runModel("M13", null, { principal: "1000", annual_rate_nominal_pct: "5", term_months: "12.5", method: "amortized" })), "NOT_INTEGER"); assert.equal(code(() => E.runModel("M13", null, { principal: "1000", annual_rate_nominal_pct: "5", term_months: 12, method: "magic" })), "BAD_ENUM");
assert.equal(code(() => E.runModel("M12", null, { cashflows: ["-1", "2"], period: "year", discount_rate_pct: "10", discount_rate_basis: "annual_nominal_for_monthly" })), "PERIOD_MISMATCH", "annual nominal for monthly requires monthly cashflows");
assert.equal(code(() => E.runModel("M04", null, { opening_cash: "0", monthly_revenue: ["1", "2"], monthly_operating_cost: ["1"] })), "SERIES_LENGTH_MISMATCH"); assert.equal(code(() => E.runModel("M04", null, { opening_cash: "0", monthly_revenue: Array(121).fill("1"), monthly_operating_cost: Array(121).fill("1") })), "BAD_SERIES", "series bounded");
assert.equal(code(() => E.runModel("M10", null, { revenue: "0", cogs: "1", avg_receivables: "1", avg_inventory: "1", avg_payables: "1" })), "OUT_OF_RANGE"); assert.equal(code(() => E.runModel("M15", null, { contract_value: "0", boq: [{ item: "a", category: "labor", qty: "1", unit_rate: "1" }], progress_pct_cumulative: ["100"] })), "OUT_OF_RANGE");
assert.equal(code(() => E.runModel("M15", null, { contract_value: "10", boq: [{ item: "a", category: "labor", qty: "1", unit_rate: "1" }], progress_pct_cumulative: ["50", "40"] })), "OUT_OF_RANGE", "progress cannot go backwards");
assert.equal(code(() => E.runModel("M99", null, {})), "UNKNOWN_MODEL"); assert.equal(code(() => E.runModel("M14", null, { amount_raised: "1", opening_cash: "0", projected_monthly_profit: ["1"], structures: [{ name: "x", type: "profit_participation" }] })), "MISSING_INPUT");
/* determinism + provenance + data quality */
const inp = { unit_cost: { value: "60", kind: "actual", sourceReference: "MOCK" }, selling_price: "100" }; const a = E.runModel("M01", null, inp, { now: "t" }), b = E.runModel("M01", null, inp, { now: "t" }); assert.deepEqual(a, b, "deterministic"); assert.equal(a.dataQuality.level, "MIXED_ACTUAL_AND_ASSUMED"); assert.equal(a.dataQuality.certifiedFinancialFact, false);
assert.equal(E.runModel("M01", null, { unit_cost: "60", selling_price: "100" }).dataQuality.level, "ASSUMED_ONLY"); assert.notEqual(a.inputHash, E.runModel("M01", null, { unit_cost: "61", selling_price: "100" }).inputHash);
assert.deepEqual(a.sideEffects, []);
/* semantics: markup != margin; profit != cash; principal != expense; profit share != interest */
const m = E.runModel("M01", null, { unit_cost: "60", selling_price: "100" }).outputs; assert.equal(m.margin_on_revenue_pct, "40.0000"); assert.equal(m.markup_on_cost_pct, "66.6667");
const pnl = E.runModel("M03", null, { revenue: "100", cogs: "50", operating_expenses: "10" }); assert.ok(pnl.warnings[0].includes("principal"), "P&L warns principal is not an expense"); assert.equal(pnl.outputs.operating_profit, "40.00");
const c14 = E.runModel("M14", null, { amount_raised: "1000000", opening_cash: "0", projected_monthly_profit: ["100000", "100000"], structures: [{ name: "pp", type: "profit_participation", profit_share_bps: "1400" }] }).outputs.comparison[0];
assert.equal(c14.total_paid, "28000.00", "14% of positive PROFIT (not 14% of principal)"); assert.equal(c14.guaranteed_return, false); assert.equal(c14.legal_or_sharia_classification, "NOT_ASSERTED");
/* property tests (seeded PRNG, deterministic) */
let seed = 20261112; const rnd = (n) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n; };
for (let i = 0; i < 60; i++) { const cost = 1 + rnd(900), price = cost + 1 + rnd(900), k = 2 + rnd(9);
  const x = E.runModel("M01", "1.0.0", { unit_cost: String(cost), selling_price: String(price) }).outputs, y = E.runModel("M01", "1.0.0", { unit_cost: String(cost * k), selling_price: String(price * k) }).outputs;
  assert.equal(D(y.contribution_per_unit).toString(2), D(x.contribution_per_unit).mul(k).toString(2), "scale: contribution scales with k"); assert.equal(y.margin_on_revenue_pct, x.margin_on_revenue_pct, "scale: margin % invariant");
  const f1 = 1000 + rnd(9000); const b1 = E.runModel("M02", null, { fixed_costs: String(f1), unit_price: String(price), variable_cost_per_unit: String(cost) }).outputs, b2 = E.runModel("M02", null, { fixed_costs: String(f1 + 500), unit_price: String(price), variable_cost_per_unit: String(cost) }).outputs;
  assert.ok(D(b2.break_even_units).gt(b1.break_even_units), "monotone: more fixed cost => more break-even units");
  const P = 10000 + rnd(900000), t = 3 + rnd(36), meth = ["amortized", "fixed_principal", "bullet"][rnd(3)]; const L = E.runModel("M13", null, { principal: String(P), annual_rate_nominal_pct: String(rnd(30)), term_months: t, method: meth }).outputs;
  assert.equal(L.total_principal_repaid, D(P).toString(2), "conservation: principal repaid == principal (" + meth + ")"); assert.equal(L.schedule[t - 1].closing, "0.00", "balance closes to exactly 0");
  const n = 3 + rnd(8), rev = Array.from({ length: n }, () => String(rnd(100000))), oc = Array.from({ length: n }, () => String(rnd(100000))), open = String(rnd(50000)); const cf = E.runModel("M04", null, { opening_cash: open, monthly_revenue: rev, monthly_operating_cost: oc }).outputs;
  const exp = rev.reduce((s, v, j) => s.add(v).sub(oc[j]), D(open)); assert.equal(cf.closing_cash, exp.toString(2), "conservation: closing = opening + sum(in-out)"); }
/* analysis helpers guard */
assert.equal(code(() => A.sensitivity({ modelId: "M01", inputs: { unit_cost: "1", selling_price: "2" }, outputKey: "net_price", drivers: Array(120).fill("unit_cost"), deltasPct: [1, 2, 3, 4] })), "BOUND_EXCEEDED");
console.log("PASS kernel: decimal/units/validation/unknown/determinism/semantics + 60 seeded property iterations");
