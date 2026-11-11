"use strict";
/* Engine vs the independent python reference (golden.json). Every model family needs >=2 fixtures incl. >=1 adverse. */
const assert = require("node:assert/strict");
const E = require("../../modules/simulation/index.js");
const fixtures = require("./golden.json");
function lookup(o, p) { return p.split(".").reduce((cur, part) => { if (cur == null) return undefined; const m = /^(\w+)\[(\d+)\]$/.exec(part); return m ? (cur[m[1]] || [])[Number(m[2])] : cur[part]; }, o); }
// keys the engine returns for an Array path with "[k]" inside the key itself (python flat form: offers[0].effective_total)
function get(o, key) { return lookup(o, key); }
let n = 0; const perModel = {};
for (const fx of fixtures) {
  const res = E.runModel(fx.model, fx.version, fx.inputs, { currency: "BDT", now: "2026-11-12T00:00:00Z" });
  assert.ok(["ok", "partial_unverified_rules"].includes(res.readiness), fx.id + " readiness " + res.readiness + JSON.stringify(res.requiredInputs));
  assert.deepEqual(res.sideEffects, [], fx.id + " must have no side effects");
  for (const [k, want] of Object.entries(fx.expect)) {
    const got = get(res.outputs, k); const norm = got === undefined ? null : got;
    assert.equal(norm, want, fx.id + " :: " + k + " engine=" + norm + " reference=" + want);
    n++;
  }
  perModel[fx.model] = perModel[fx.model] || { total: 0, adverse: 0 }; perModel[fx.model].total++; if (fx.adverse) perModel[fx.model].adverse++;
}
for (let i = 1; i <= 20; i++) { const id = "M" + String(i).padStart(2, "0"); const p = perModel[id]; assert.ok(p && p.total >= 2 && p.adverse >= 1, id + " needs >=2 goldens and >=1 adverse (has " + JSON.stringify(p) + ")"); }
// hand-verified anchors (independent of both implementations)
const loan = E.runModel("M13", null, { principal: "500000", annual_rate_nominal_pct: "12", term_months: 12, method: "amortized" });
assert.equal(loan.outputs.first_payment, "44424.39", "textbook 500k/12%/12m instalment");
const irr = E.runModel("M12", null, { cashflows: ["-1000", "400", "400", "400"], period: "year" });
assert.equal(irr.outputs.irr_pct_per_period, "9.701026", "textbook IRR");
assert.equal(E.D("0.1").add("0.2").toString(), "0.3", "no float drift");
console.log("PASS golden: " + fixtures.length + " fixtures, " + n + " numeric/string checks across M01-M20 vs independent python reference");
