"use strict";
/* Scoped JSON/CSV export with CSV formula-injection defence and redaction. */
const { SimError } = require("./decimal");
const { hashOf } = require("./sha256");
const DANGEROUS = /^[=+\-@\t\r]/;
function csvCell(v) { let s = v === null || v === undefined ? "" : String(v); if (DANGEROUS.test(s)) s = "'" + s; if (/[",\n\r]/.test(s)) s = '"' + s.replace(/"/g, '""') + '"'; return s; }
function toCsv(rows) { return rows.map(r => r.map(csvCell).join(",")).join("\r\n") + "\r\n"; }
function flatten(prefix, v, acc) { if (v === null || typeof v !== "object") { acc.push([prefix, v]); return acc; } if (Array.isArray(v)) { if (v.every(x => x === null || typeof x !== "object")) acc.push([prefix, v.join(" | ")]); else v.forEach((x, i) => flatten(prefix + "[" + (i + 1) + "]", x, acc)); return acc; } for (const k of Object.keys(v)) flatten(prefix ? prefix + "." + k : k, v[k], acc); return acc; }
function buildReport(sc, run, opts) {
  const full = !!opts.full; const r = run.result; const rep = { reportVersion: "1.0.0", label: "SIMULATION — HYPOTHETICAL, ADVISORY ONLY", scope: { tenantId: sc.tenantId, businessId: sc.businessId, siteId: sc.siteId }, actor: opts.actorId, scenario: { id: sc.id, name: sc.name, kind: sc.kind, revisionAtRun: run.revisionAtRun, status: sc.status },
    model: { id: run.modelId, version: run.modelVersion, formulaHash: run.formulaHash }, currency: r.currency, outputs: r.outputs, feasibility: r.feasibility, warnings: r.warnings, assumptions: r.assumptions, limitations: r.limitations, dataQuality: r.dataQuality, hashes: { inputHash: run.inputHash, sourceHash: run.sourceHash }, computedAt: run.computedAt, sideEffects: [], redacted: !full };
  if (full) { rep.formulaBreakdown = r.breakdown; rep.inputs = run.inputs; } else rep.redactionNote = "Inputs and formula breakdown withheld: requires sim.export_full.";
  rep.reportHash = hashOf(rep); return rep;
}
function reportCsv(rep) { const rows = [["field", "value"]]; flatten("", rep, rows); return toCsv(rows); }
module.exports = { csvCell, toCsv, buildReport, reportCsv };
