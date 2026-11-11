"use strict";
const assert = require("node:assert/strict"); const E = require("../../modules/simulation/index.js"); const { D } = E; const g = require("./golden.json"); const fx = id => JSON.parse(JSON.stringify(g.find(x => x.id === id).inputs)); const run = (m, i, c) => E.runModel(m, null, i, c);
const code = fn => { try { fn(); } catch (e) { return e.code || e.message; } return null; };
/* B: branch opening — two fictional branches, 12 months */
const funded = run("M16", fx("M16-branch-funded-loan")), unfunded = run("M16", fx("M16-branch-infeasible"));
assert.equal(funded.outputs.table.length, 13, "setup row + 12 months"); assert.equal(unfunded.feasibility, "INFEASIBLE_CASH_SHORTFALL", "setup outflows exceed funding => feasibility failure"); assert.equal(unfunded.outputs.lowest_cash_month, "0");
assert.ok(D(funded.outputs.profitable_months_with_negative_cash_change).gte(1), "at least one profitable month with negative cash (loan+investor payments)");
const row2 = funded.outputs.table[2]; assert.ok(D(row2.operating_profit).isPos() && D(row2.cash_change).isNeg(), "month 2: profit>0 but cash<0");
/* separation: deposit/capex/principal are NOT P&L; changing deposit changes cash but not profit */
const noDep = fx("M16-branch-funded-loan"); noDep.refundable_deposit = "0"; noDep.deposit_refund_month = 0; const a = run("M16", noDep);
assert.equal(a.outputs.cumulative_net_profit, funded.outputs.cumulative_net_profit, "deposit never touches profit"); assert.notEqual(a.outputs.lowest_cash, funded.outputs.lowest_cash);
const noCapex = fx("M16-branch-funded-loan"); noCapex.fitout_capex = "0"; assert.equal(run("M16", noCapex).outputs.cumulative_net_profit, funded.outputs.cumulative_net_profit, "capex is not an expense");
const noLoanP = fx("M16-branch-funded-loan"); noLoanP.loan_principal = "300000"; const lp = run("M16", noLoanP); const expectedProfitDelta = lp.outputs.cumulative_net_profit; assert.notEqual(expectedProfitDelta, funded.outputs.cumulative_net_profit, "only INTEREST moves profit when loan size changes");
const noInv = fx("M16-branch-funded-loan"); noInv.fixed_investor_payment_monthly = "0"; assert.equal(run("M16", noInv).outputs.cumulative_net_profit, funded.outputs.cumulative_net_profit, "fixed investor payment is financing, not P&L");
/* scenario kinds as explicit multipliers: conservative < baseline < optimistic */
const kinds = ["80", "100", "120"].map(m => { const i = fx("M16-branch-funded-loan"); i.sales_multiplier_pct = m; return D(run("M16", i).outputs.cumulative_net_profit); }); assert.ok(kinds[0].lt(kinds[1]) && kinds[1].lt(kinds[2]));
/* opening inventory consumed by COGS — no duplicate inventory expense */
const ni = fx("M16-branch-funded-loan"); ni.opening_inventory_investment = "0"; const withInv = funded.outputs.table.slice(1).reduce((s, t) => s.add(t.cash_change), D(0)), without = run("M16", ni).outputs.table.slice(1).reduce((s, t) => s.add(t.cash_change), D(0));
assert.ok(withInv.gt(without), "opening stock reduces later cash COGS (consumed once, not double counted)");
/* production & food: ingredient qty/UOM, waste/yield; no inventory posting */
const bom = run("M07", fx("M07-sweet-batch")); assert.equal(bom.outputs.ingredient_cost_per_batch, "2436.73"); assert.equal(bom.outputs.lines[1].cost, "600.00", "5000 g sugar at 120/kg = 600"); assert.ok(bom.warnings.some(w => /no inventory movement/i.test(w)));
const cap = run("M08", fx("M08-bottleneck")); assert.equal(cap.outputs.bottleneck, "packing_staff_hours"); assert.equal(cap.outputs.shortfall_units, "100.0000"); assert.equal(cap.feasibility, "OVER_CAPACITY");
/* raw price sensitivity on production cost */
const A = require("../../modules/simulation/lib/analysis"); const s = A.sensitivity({ modelId: "M07", inputs: fx("M07-sweet-batch"), outputKey: "cost_per_sellable_unit", drivers: ["spoilage_pct", "labor_rate_per_hour", "energy_cost_per_batch"], deltasPct: [-10, 10] }); assert.equal(s.drivers.length, 3);
/* paint & wholesale: supplier quote, packaging, discount, transport, credit terms, no double inventory expense */
const q = run("M06", fx("M06-overbuy-volume")); assert.equal(q.outputs.offers[0].overbuy_qty_base, "80.0000", "must buy 2 drums (200kg) for 120kg"); assert.equal(q.outputs.offers[0].volume_discount_applied, true); assert.equal(q.outputs.best_offer, "Bag");
const early = run("M06", fx("M06-early-discount")); assert.equal(early.outputs.offers[0].take_early_payment_discount, true); assert.ok(early.warnings[0].includes("Landed-cost prerequisites"));
/* construction: BOQ, progress, variation, retention, delay, cash gap */
const con = run("M15", fx("M15-delay")); assert.equal(con.feasibility, "CASH_GAP"); assert.equal(con.outputs.unapproved_variation_excluded, "200000.00"); assert.ok(con.warnings.some(w => /No tax/.test(w)), "no assumed Bangladesh tax rule");
const ret = fx("M15-supplier-credit"); ret.retention_pct = "0"; const noRet = run("M15", ret), withRet = run("M15", fx("M15-supplier-credit")); assert.ok(D(withRet.outputs.peak_funding_gap).gte(noRet.outputs.peak_funding_gap), "retention cannot reduce the funding gap");
/* loan / investor: three structurally different contracts, never labelled guaranteed */
const c = run("M14", fx("M14-four-structures")).outputs.comparison; const by = n => c.find(x => x.name === n); assert.equal(by("PP14").paid_in_loss_months, "0.00", "profit share pays nothing in loss months"); assert.ok(D(by("Fixed").paid_in_loss_months).isPos(), "fixed contractual still paid in loss months");
assert.ok(c.every(x => x.guaranteed_return === false && x.legal_or_sharia_classification === "NOT_ASSERTED")); assert.equal(by("PP14").classification, "variable_profit_share_not_interest_not_guaranteed"); assert.equal(by("Fixed").classification, "fixed_contractual_obligation_liability");
const stress = run("M14", fx("M14-loss-stress")).outputs.comparison; assert.ok(D(stress[1].minimum_cash).lt(stress[0].minimum_cash), "fixed obligation worsens liquidity in loss months vs profit share");
/* A022 caution: 1400 bps is NOT 14% annual interest on principal */
const pp = run("M14", { amount_raised: "1000000", opening_cash: "0", projected_monthly_profit: Array(12).fill("10000"), structures: [{ name: "pp", type: "profit_participation", profit_share_bps: "1400" }] }).outputs.comparison[0]; assert.equal(pp.total_paid, "16800.00"); assert.notEqual(pp.total_paid, "140000.00");
/* tax/fee: nothing unverified is ever computed */
const tf = run("M18", fx("M18-verified-and-not")); assert.equal(tf.outputs.unverified_rule_count, "1"); assert.equal(tf.outputs.rules[2].amount, null); assert.equal(E.getModel("M18").status, "partial");
/* M19: elimination, cross-tenant, no double count */
const cons = E.runModel("M19", null, fx("M19-balanced"), { tenantId: "T1" }); assert.equal(cons.outputs.consolidated_revenue, "130000.00"); assert.equal(cons.outputs.naive_revenue_with_double_count, "230000.00"); assert.equal(code(() => E.runModel("M19", null, fx("M19-balanced"), { tenantId: "T-OTHER" })), "CROSS_TENANT_REJECTED");
assert.equal(run("M19", fx("M19-mismatch")).feasibility, "ELIMINATION_MISMATCH");
/* M20: no code execution, bounded, valid templates only */
const evil = ["process.exit(1)", "a.constructor", "a;b", "1e9", "unknown+1", "a/(a-a)", "(".repeat(30) + "a" + ")".repeat(30), "a" + "+a".repeat(200), "max(a)", "x=1"]; for (const e of evil) { const c2 = code(() => E.runModel("M20", null, { template: { inputs: ["a"], outputs: [{ k: "x", expr: e }] }, values: { a: "5" } })); assert.ok(c2 && /TEMPLATE_INVALID|DIV_ZERO/.test(c2), "template must be refused: " + e + " got " + c2); }
assert.equal(code(() => E.runModel("M20", null, { template: { inputs: ["__proto__"], outputs: [{ k: "x", expr: "1" }] }, values: {} })), "TEMPLATE_INVALID"); assert.equal(run("M20", { template: { inputs: ["a", "b"], outputs: [{ k: "s", expr: "round2(a/b)*2 - -1" }] }, values: { a: "10", b: "3" } }).outputs.results.s, "7.66");
/* working capital & capex & ROI semantics */
assert.equal(run("M10", fx("M10-long-credit")).outputs.cash_conversion_cycle_days, "344.72"); assert.equal(run("M11", fx("M11-never")).feasibility, "NOT_RECOVERED_IN_HORIZON"); assert.equal(run("M12", fx("M12-multiple-roots")).outputs.irr_status, "MULTIPLE_ROOTS"); assert.equal(run("M12", fx("M12-no-sign-change")).outputs.irr_pct_per_period, null);
/* inventory */
assert.equal(run("M05", fx("M05-stockout")).feasibility, "STOCKOUT_BEFORE_REPLENISHMENT");
console.log("PASS models: 8 business journeys (branch x2, production, paint, construction, loan/investor, multi-site, tax) with semantics checks");
