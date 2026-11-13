"use strict";
/* Honest coverage map. Statuses ladder: proposed < implemented < tested < integrated < signed_auth_verified < production_approved.
   Nothing in this draft is above "tested". integrated / signed_auth_verified / production_approved are ALWAYS false here. */
const { listModels } = require("./kernel");
const LADDER = ["proposed", "implemented", "tested", "integrated", "signed_auth_verified", "production_approved"];
const T = (id, req, name, status, evidence, gaps) => ({ id, req, name, status, evidence, gaps });
const U = [
  T("U01", "R089", "Trusted baseline snapshots", "implemented", ["tests/c10_a025/scenario.test.js"], "Mock provider only (hash + cutoff + stale flag); no real A048/A049/A050 source contract verified"),
  T("U02", "R090", "Data quality & readiness grading", "tested", ["tests/c10_a025/kernel.test.js"], "Grades provenance kind; does not reconcile to a real source"),
  T("U03", "R091", "Certified model registry", "tested", ["tests/c10_a025/registry.test.js"], "Fixture-certified only; no independent actuarial/audit certification"),
  T("U04", "R092", "Financial definition engine", "tested", ["tests/c10_a025/models.test.js"], "Definitions encoded in formulas/glossary; no tax rate registry"),
  T("U05", "R093", "Scenario provenance & immutability", "tested", ["tests/c10_a025/scenario.test.js", "tests/c10_a025/persistence.test.js", "tests/c10_a025/gateway.test.js"], "Hashes are integrity aids, not signatures"),
  T("U06", "R094", "Cross-module impact graph", "implemented", ["tests/c10_a025/analysis.test.js"], "Declared dependency graph + model links; source modules (A048/A049/A050) are NOT connected"),
  T("U07", "R095", "Feasibility & constraints", "tested", ["tests/c10_a025/analysis.test.js"], "Rule-based on model outputs; no solver over real capacity data"),
  T("U08", "R096", "Integrated finance (P&L ↔ cash)", "tested", ["tests/c10_a025/models.test.js"], "No balance sheet, no tax timing"),
  T("U09", "R097", "Sensitivity & drivers", "tested", ["tests/c10_a025/analysis.test.js"], "One-way and tornado; no variance decomposition"),
  T("U10", "R098", "Stress testing", "tested", ["tests/c10_a025/analysis.test.js"], "Named presets are user-supplied shocks; no calibrated scenarios"),
  T("U11", "R099", "Reverse goal planning", "tested", ["tests/c10_a025/analysis.test.js"], "Single-driver monotone bisection only"),
  T("U12", "R100", "Constraint optimisation", "partial_tested", ["tests/c10_a025/analysis.test.js"], "Bounded grid search (<=3 variables, <=5000 runs); not an LP/MIP solver"),
  T("U13", "R101", "Multi-scenario portfolio", "partial_tested", ["tests/c10_a025/scenario.test.js"], "Compare within authorised scope; no concurrent capex/cash portfolio roll-up"),
  T("U14", "R102", "Calibrated uncertainty", "partial_tested", ["tests/c10_a025/uncertainty.test.js"], "Seeded Monte Carlo runs ONLY with structurally validated calibration evidence (refuses 9 weak-evidence cases); evidence is declared by the caller, not verified against real data; correlations normal-only; <=2000 runs; output is conditional, never a forecast"),
  T("U15", "R103", "Decision lifecycle", "tested", ["tests/c10_a025/scenario.test.js", "tests/c10_a025/persistence.test.js"], "Eligible-to-apply/applied states intentionally absent (apply disabled)"),
  T("U16", "R104", "Approval adapter", "implemented", ["tests/c10_a025/scenario.test.js"], "CONTRACT + mock only; real ERP approval engine NOT connected; module-visibility mutation refused"),
  T("U17", "R105", "Actual vs plan", "tested", ["tests/c10_a025/analysis.test.js"], "Synthetic actuals only"),
  T("U18", "R106", "Decision performance review", "partial_tested", ["tests/c10_a025/uncertainty.test.js"], "Verdict MET/PARTIALLY_MET/MISSED over ACTUAL-kind values only, constraint incidence, mechanical input-deviation reasons; synthetic actuals; no ROI/payback inference"),
  T("U19", "R107", "Forecast accuracy & bias", "tested", ["tests/c10_a025/analysis.test.js"], "Needs >=3 comparable actuals; synthetic only"),
  T("U20", "R108", "Early warning & replan", "tested", ["tests/c10_a025/analysis.test.js"], "Threshold rules on synthetic actuals"),
  T("U21", "R109", "Collaborative review", "partial_tested", ["tests/c10_a025/scenario.test.js", "tests/c10_a025/persistence.test.js"], "Comments + reviewer permissions; no attachments or notifications"),
  T("U22", "R110", "Consolidation & elimination", "tested", ["tests/c10_a025/models.test.js", "tests/c10_a025/bench.test.js"], "No unrealised-profit elimination"),
  T("U23", "R111", "Funding / partner semantics", "tested", ["tests/c10_a025/models.test.js"], "Not wired to real A022 agreements; A022 values are MANUAL_UNVERIFIED seeds"),
  T("U24", "R112", "Safe application gateway", "tested", ["tests/c10_a025/scenario.test.js", "tests/c10_a025/persistence.test.js", "tests/c10_a025/gateway.test.js"], "Apply is DISABLED by design"),
  T("U25", "R113", "Lab + Quick UX, BN/EN, reports", "tested", ["tests/c10_a025/browser.test.js", "tests/c10_a025/parity.test.js"], "Synthetic demo harness; not mounted in live navigation"),
  T("U26", "R114", "Security, licensing & scale", "partial_tested", ["tests/c10_a025/persistence.test.js", "tests/c10_a025/gateway.test.js", "tests/c10_a025/dbscale.test.js", "tests/c10_a025/bench.test.js"], "Synthetic jwt-claim RLS only (NOT signed GoTrue); licensing = design only; trusted gateway recomputes results; measured: 320 sites / 10,000 scenarios under RLS on a throwaway PostgreSQL (see handover) — not a production load test")
];
const R_ORIG = [
  ["R081", "One reusable engine + Lab inside the existing repo", "tested", "Single registry/kernel; no new app"],
  ["R082", "Quick Simulation in workflow menus", "partial_tested", "Reusable adapter + isolated harness for 11 contexts; no live screen modified (by mandate)"],
  ["R083", "Deterministic typed math, assumptions, missing data", "tested", "BigInt decimal kernel; unknown != zero"],
  ["R084", "Scenarios separated from real records", "tested", "sideEffects=[] everywhere; SQL no-mutation test on sentinel tables"],
  ["R085", "Permission/RLS/audit/export scope", "partial_tested", "Tested on synthetic claims; signed-auth not verified"],
  ["R086", "Platform licensing/entitlements", "proposed", "Design-only; no entitlement enforcement (C10-A024 separate)"],
  ["R087", "Sequencing (REV-010 isolated draft)", "tested", "Process: separate Claude branch + Draft PR, no main merge"],
  ["R088", "Industry templates, responsive UX, BN/EN, save/compare/export", "tested", "10 canonical industry packs as data (recommended models + verified guided journeys), BN/EN, save/compare/export"]
];
function modelCoverage() { const latest = new Map(); for (const m of listModels()) { const cur = latest.get(m.id); if (!cur || m.version > cur.version) latest.set(m.id, m); } return [...latest.values()].filter(m => /^M\d\d$/.test(m.id)).sort((a, b) => (a.id < b.id ? -1 : 1)).map(m => ({ id: m.id, version: m.version, family: m.family, status: m.status, reason: m.reason || null, formulaHash: m.formulaHash })); }
module.exports = { LADDER, U, R_ORIG, modelCoverage };
