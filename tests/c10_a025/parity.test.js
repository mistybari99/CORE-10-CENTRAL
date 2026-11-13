"use strict";
/* Lab (ScenarioService.run) and Quick Simulation must call the SAME registered model/version and produce identical results. */
const assert = require("node:assert/strict"); const E = require("../../modules/simulation/index.js"); const { ScenarioService } = require("../../modules/simulation/lib/scenario"); const { createQuickSimulation, CONTEXTS } = require("../../modules/simulation/lib/quick"); const D = require("../../modules/simulation/lib/demo-data"); const g = require("./golden.json");
const code = fn => { try { fn(); } catch (e) { return e.code || e.message; } return null; };
const a = D.makeAuthority(), svc = new ScenarioService({ authority: a, now: () => "2026-11-12T00:00:00Z" }), quick = createQuickSimulation({ authority: a }); const owner = a.login("u_bizowner_a1");
const pick = { item: "M01-base-v1", inventory: "M05-base", purchasing: "M06-early-discount", production: "M07-sweet-batch", sales_pricing: "M17-mix", branch: "M16-branch-funded-loan", transfer: "M09-van-vs-truck", construction: "M15-delay", staffing: "M08-bottleneck", financing: "M14-four-structures", expansion: "M12-single-root" };
assert.deepEqual(Object.keys(pick).sort(), Object.keys(CONTEXTS).sort(), "every contextual entry point is exercised");
let n = 0; for (const [ctxKind, fxId] of Object.entries(pick)) { const fx = g.find(x => x.id === fxId); const modelId = CONTEXTS[ctxKind].modelId; assert.equal(fx.model, modelId, ctxKind + " maps to " + modelId);
  const sc = svc.create(owner, { businessId: "B-A1", name: ctxKind, requestKey: "par-" + ctxKind, modelId, inputs: fx.inputs }); const lab = svc.run(owner, sc.id).result;
  const q = quick.run(owner, ctxKind, fx.inputs, { raw: true, scope: { businessId: "B-A1" }, now: "2026-11-12T00:00:00Z" });
  assert.equal(q.modelId, lab.modelId); assert.equal(q.modelVersion, lab.modelVersion, "same model version"); assert.equal(q.formulaHash, lab.formulaHash, "same formula"); assert.equal(q.inputHash, lab.inputHash, "same input hash");
  assert.deepEqual(q.outputs, lab.outputs, ctxKind + ": identical outputs"); assert.deepEqual(q.exact, lab.exact); assert.equal(q.entryPoint, "quick:" + ctxKind); n++; }
/* host values: only authorised reads count as 'actual' */
const q1 = quick.run(owner, "item", { unit_cost: "60", selling_price: "100" }, { scope: { businessId: "B-A1" } }); assert.equal(q1.dataQuality.level, "ASSUMED_ONLY"); const q2 = quick.run(owner, "item", { unit_cost: "60", selling_price: "100" }, { scope: { businessId: "B-A1" }, fromAuthorizedSource: true }); assert.equal(q2.dataQuality.level, "MIXED_ACTUAL_AND_ASSUMED", "defaulted optional inputs count as assumptions"); assert.equal(q2.dataQuality.counts.actual, 2); assert.equal(q2.dataQuality.certifiedFinancialFact, false);
/* quick availability follows backend authorisation and enabled modules */
assert.equal(quick.available(owner, "item", { businessId: "B-A1" }, ["item"]), true); assert.equal(quick.available(owner, "item", { businessId: "B-A1" }, ["inventory"]), false, "host module not enabled"); assert.equal(quick.available(a.login("u_cash_a1s1"), "item", { businessId: "B-A1" }, ["item"]), false); assert.equal(quick.available(a.login("u_owner_b"), "item", { businessId: "B-A1" }), false);
assert.equal(code(() => quick.run(a.login("u_owner_b"), "item", {}, { scope: { businessId: "B-A1" } })), "FORBIDDEN"); assert.equal(code(() => quick.run(owner, "item", {}, { scope: { businessId: "B-A1", tenantId: "T-BRAVO" } })), "SCOPE_OVERRIDE_REJECTED"); assert.equal(code(() => quick.run(owner, "nope", {}, { scope: { businessId: "B-A1" } })), "UNKNOWN_CONTEXT");
assert.equal(quick.contexts().length, 11);
console.log("PASS parity: " + n + " contextual Quick entry points == Lab (same model/version/formula/input hash/outputs)");
