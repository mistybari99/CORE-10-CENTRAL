"use strict";
/* Decision lifecycle (U15) + advisory-only application gateway (U24) + approval adapter CONTRACT (U16). */
const { SimError } = require("./decimal");
const TRANSITIONS = { draft: ["simulated"], simulated: ["simulated", "reviewed", "draft"], reviewed: ["approved", "rejected", "simulated"], approved: ["proposal", "closed"], rejected: ["closed", "draft"], proposal: ["monitored", "closed"], monitored: ["closed"], closed: [] };
const REQUIRED_CAP = { reviewed: "sim.review", approved: "sim.review", rejected: "sim.review", proposal: "sim.propose" };
function assertTransition(from, to) { if (!(TRANSITIONS[from] || []).includes(to)) throw new SimError("BAD_TRANSITION", from + " -> " + to + " is not allowed", { from, to }); }
/* U16: a CONTRACT. The real approval engine (A021 etc.) is not wired; module-visibility mutations are explicitly refused. */
class MockApprovalAdapter {
  constructor() { this.submitted = []; this.status = "CONTRACT_ONLY_REAL_APPROVAL_ENGINE_NOT_CONNECTED"; }
  submit(req) { if (!req || req.kind !== "scenario_advisory_proposal") throw new SimError("WRONG_APPROVAL_KIND", "Only scenario_advisory_proposal is accepted; module visibility/generic mutations are refused"); this.submitted.push({ kind: req.kind, scenarioId: req.scenarioId, advisoryOnly: true }); return { accepted: true, mock: true, advisoryOnly: true, appliedToLive: false }; }
}
function buildAdvisoryProposal(sc, run, actorId, at) {
  return Object.freeze({ kind: "scenario_advisory_proposal", scenarioId: sc.id, runId: run.runId, modelId: run.modelId, modelVersion: run.modelVersion, inputHash: run.inputHash, proposedBy: actorId, proposedAt: at,
    advisoryOnly: true, applyState: "DISABLED", summary: "Advisory plan derived from simulation " + run.modelId + "@" + run.modelVersion + ". Review manually; nothing is applied to live records.",
    outputsSnapshot: run.result.outputs, warnings: run.result.warnings, notGuaranteed: true });
}
/* Apply-to-live is ALWAYS disabled in this draft. There is deliberately no code path that writes operations. */
function applyToLive() { return { applied: false, reason: "DISABLED_ADVISORY_ONLY", detail: "REV-010/C10-A025: application gateway locked; attach authorized canonical domain commands only after real approvals, idempotency and signed-auth E2E." }; }
module.exports = { TRANSITIONS, REQUIRED_CAP, assertTransition, MockApprovalAdapter, buildAdvisoryProposal, applyToLive };
