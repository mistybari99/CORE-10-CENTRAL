"use strict";
/* C10-A025 registry + calculation runner. Pure: no I/O, no clock unless injected, sideEffects always []. */
const { Dec, D, SimError } = require("./decimal");
const { hashOf, sha256 } = require("./sha256");
const { convert } = require("./units");
const KINDS = ["actual", "estimate", "assumption", "scenario", "unknown"];
const STATUSES = ["implemented_tested", "partial", "research_only", "not_implemented"];
const REGISTRY = new Map(); // key model@version -> def
const LIMITS = { maxSeries: 120, maxList: 400, maxRunsPerBatch: 5000 };

function registerModel(def) {
  const key = def.id + "@" + def.version;
  if (REGISTRY.has(key)) throw new SimError("REGISTRY_IMMUTABLE", "Model version already registered: " + key);
  if (!STATUSES.includes(def.status)) throw new SimError("BAD_STATUS", def.status);
  if (def.status === "implemented_tested" && typeof def.calculate !== "function") throw new SimError("BAD_DEF", "implemented without calculate");
  def.formulaHash = def.calculate ? sha256(def.formulaText + "\n" + def.calculate.toString() + "\n" + hashOf(def.inputs || [])) : null;
  REGISTRY.set(key, Object.freeze(def));
  return def;
}
function getModel(id, version) {
  if (version) { const d = REGISTRY.get(id + "@" + version); if (!d) throw new SimError("UNKNOWN_MODEL", "Model/version not registered: " + id + "@" + version); return d; }
  const all = [...REGISTRY.values()].filter(d => d.id === id && !d.retired).sort((a, b) => cmpVer(b.version, a.version));
  if (!all.length) throw new SimError("UNKNOWN_MODEL", "Unknown model " + id); return all[0];
}
function cmpVer(a, b) { const x = a.split(".").map(Number), y = b.split(".").map(Number); for (let i = 0; i < 3; i++) { if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) - (y[i] || 0); } return 0; }
function listModels() { return [...REGISTRY.values()]; }

/* ---------- input normalization ---------- */
function unwrap(raw) {
  if (raw !== null && typeof raw === "object" && !Array.isArray(raw) && !(raw instanceof Dec) && ("value" in raw || "kind" in raw)) return raw;
  return { value: raw, kind: "assumption" };
}
function parseScalar(spec, v, path) {
  switch (spec.t) {
    case "money": case "decimal": case "percent": { const d = D(v); return bound(spec, d, path); }
    case "int": { const d = D(v); if (d.v % (10n ** 18n) !== 0n) throw new SimError("NOT_INTEGER", path + " must be an integer", { path }); return bound(spec, d, path); }
    case "qty": { let d = D(v.value !== undefined && typeof v === "object" ? v.value : v); return bound(spec, d, path); }
    case "enum": if (!spec.values.includes(v)) throw new SimError("BAD_ENUM", path + " must be one of " + spec.values.join("|"), { path }); return v;
    case "object": { if (v === null || typeof v !== "object" || Array.isArray(v) || JSON.stringify(v).length > 20000) throw new SimError("BAD_OBJECT", path + " must be a JSON object <= 20000 chars", { path }); return v; }
    case "bool": if (typeof v !== "boolean") throw new SimError("BAD_BOOL", path + " must be boolean", { path }); return v;
    case "text": if (typeof v !== "string" || v.length > 300) throw new SimError("BAD_TEXT", path, { path }); return v;
    default: throw new SimError("BAD_SPEC", "Unknown input type " + spec.t);
  }
}
function bound(spec, d, path) {
  if (spec.min != null && d.lt(spec.min)) throw new SimError("OUT_OF_RANGE", path + " below minimum " + spec.min, { path, min: spec.min });
  if (spec.max != null && d.gt(spec.max)) throw new SimError("OUT_OF_RANGE", path + " above maximum " + spec.max, { path, max: spec.max });
  return d;
}
function normalizeInputs(def, rawInputs, ctx) {
  const out = {}, prov = {}, missing = [];
  const currency = (ctx && ctx.currency) || "BDT";
  for (const spec of def.inputs) {
    const raw = rawInputs ? rawInputs[spec.k] : undefined;
    if (raw === undefined || raw === null || (raw && raw.kind === "unknown")) {
      if (spec.def !== undefined && (raw === undefined || raw === null)) { out[spec.k] = spec.t === "list" || spec.t === "series" ? spec.def : parseScalar(spec, spec.def, spec.k); prov[spec.k] = { kind: "assumption", defaulted: true }; continue; }
      if (spec.req) { missing.push({ key: spec.k, reason: raw && raw.kind === "unknown" ? "marked_unknown" : "absent" }); continue; }
      out[spec.k] = null; prov[spec.k] = { kind: "unknown" }; continue; // unknown is NEVER zero
    }
    const iv = Object.assign({ kind: "assumption" }, unwrap(raw));
    if (!KINDS.includes(iv.kind)) throw new SimError("BAD_KIND", spec.k + ": kind " + iv.kind);
    if (iv.currency && spec.t === "money" && iv.currency !== currency) throw new SimError("CURRENCY_MISMATCH", spec.k + " is " + iv.currency + " but run currency is " + currency, { key: spec.k });
    if (iv.periodBasis && spec.period && iv.periodBasis !== spec.period) throw new SimError("PERIOD_MISMATCH", spec.k + " period " + iv.periodBasis + " != " + spec.period, { key: spec.k });
    let v = iv.value;
    if (spec.t === "series") {
      if (!Array.isArray(v) || v.length > LIMITS.maxSeries) throw new SimError("BAD_SERIES", spec.k + " must be an array (<=" + LIMITS.maxSeries + ")", { key: spec.k });
      if (spec.minLen && v.length < spec.minLen) throw new SimError("BAD_SERIES", spec.k + " needs >= " + spec.minLen + " entries", { key: spec.k });
      out[spec.k] = v.map((x, i) => bound(spec, D(x), spec.k + "[" + i + "]"));
    } else if (spec.t === "list") {
      if (!Array.isArray(v) || v.length > LIMITS.maxList) throw new SimError("BAD_LIST", spec.k + " must be an array (<=" + LIMITS.maxList + ")", { key: spec.k });
      if (spec.minLen && v.length < spec.minLen) throw new SimError("BAD_LIST", spec.k + " needs >= " + spec.minLen + " rows", { key: spec.k });
      out[spec.k] = v.map((row, i) => {
        if (row === null || typeof row !== "object") throw new SimError("BAD_LIST", spec.k + "[" + i + "] must be an object", { key: spec.k });
        const o = {}; for (const f of spec.item) {
          const rv = row[f.k];
          if (rv === undefined || rv === null) { if (f.def !== undefined) { o[f.k] = f.t === "enum" || f.t === "text" || f.t === "bool" ? f.def : D(f.def); continue; } if (f.req) throw new SimError("MISSING_INPUT", spec.k + "[" + i + "]." + f.k + " required", { key: spec.k + "[" + i + "]." + f.k }); o[f.k] = null; continue; }
          o[f.k] = parseScalar(f, rv, spec.k + "[" + i + "]." + f.k);
        } return o; });
    } else if (spec.t === "qty") {
      const qv = D(v), from = iv.unit || spec.unit; out[spec.k] = bound(spec, convert(qv, from, spec.unit), spec.k);
    } else out[spec.k] = parseScalar(spec, v, spec.k);
    prov[spec.k] = { kind: iv.kind, source: iv.sourceReference || null, observedAt: iv.observedAt || null, unit: spec.unit || null };
  }
  return { values: out, provenance: prov, missing };
}

/* ---------- data quality (U02): honest grading, never "certified" ---------- */
function grade(prov) {
  const c = { actual: 0, estimate: 0, assumption: 0, scenario: 0, unknown: 0, defaulted: 0 };
  for (const k of Object.keys(prov)) { c[prov[k].kind] = (c[prov[k].kind] || 0) + 1; if (prov[k].defaulted) c.defaulted++; }
  const n = Object.keys(prov).length;
  let level = "ASSUMED_ONLY";
  if (c.unknown > 0) level = "PARTIAL_UNKNOWN_INPUTS";
  else if (c.actual === n && n > 0) level = "ALL_INPUTS_MARKED_ACTUAL_UNVERIFIED"; // marking != verifying; mock provider only in draft
  else if (c.actual > 0) level = "MIXED_ACTUAL_AND_ASSUMED";
  return { level, counts: c, certifiedFinancialFact: false, note: "Draft engine: no input is reconciled to a signed production source." };
}

/* ---------- run ---------- */
function fmtOut(spec, v) {
  if (v === null || v === undefined) return null;
  if (v instanceof Dec) return v.toString(spec && spec.places != null ? spec.places : 2);
  return v;
}
function runModel(modelId, version, rawInputs, ctx) {
  ctx = ctx || {};
  const def = version ? getModel(modelId, version) : getModel(modelId);
  if (def.status === "not_implemented" || def.status === "research_only") throw new SimError("MODEL_NOT_IMPLEMENTED", def.id + " is " + def.status + ": " + def.reason, { modelId: def.id, status: def.status });
  if (def.retired && !ctx.allowRetired) throw new SimError("MODEL_RETIRED", def.id + "@" + def.version + " retired; pass allowRetired for historical reproduction");
  const norm = normalizeInputs(def, rawInputs, ctx);
  const base = {
    modelId: def.id, modelVersion: def.version, formulaHash: def.formulaHash, currency: ctx.currency || "BDT",
    scenarioKind: ctx.scenarioKind || "custom", sideEffects: [], status: def.status
  };
  const inputHash = hashOf({ m: def.id, v: def.version, inputs: serializeInputs(rawInputs), cur: base.currency });
  if (norm.missing.length) return Object.assign(base, { readiness: "needs_input", requiredInputs: norm.missing, outputs: null, inputHash, dataQuality: grade(norm.provenance), warnings: ["Unknown is not zero: result withheld until inputs are supplied."], breakdown: [], computedAt: ctx.now || null });
  const r = def.calculate(norm.values, Object.assign({}, ctx, { currency: base.currency }));
  const outputs = {}; for (const o of def.outputs) { if (r.outputs[o.k] !== undefined) outputs[o.k] = r.outputs[o.k] instanceof Dec ? fmtOut(o, r.outputs[o.k]) : r.outputs[o.k]; }
  for (const k of Object.keys(r.outputs)) if (!(k in outputs)) outputs[k] = r.outputs[k] instanceof Dec ? r.outputs[k].toString(2) : jsonSafe(r.outputs[k]);
  const exact = {}; for (const k of Object.keys(r.outputs)) if (r.outputs[k] instanceof Dec) exact[k] = r.outputs[k].toString();
  return Object.assign(base, {
    readiness: r.readiness || "ok", requiredInputs: [], outputs, exact, feasibility: r.feasibility || "n/a",
    breakdown: (r.breakdown || []).map(b => ({ label: b.label, formula: b.formula, value: b.value instanceof Dec ? b.value.toString(2) : b.value })),
    warnings: r.warnings || [], assumptions: def.assumptions, limitations: def.limitations,
    dataQuality: grade(norm.provenance), provenance: norm.provenance, inputHash, computedAt: ctx.now || null
  });
}
function jsonSafe(v) {
  if (v instanceof Dec) return v.toString(2);
  if (Array.isArray(v)) return v.map(jsonSafe);
  if (v && typeof v === "object") { const o = {}; for (const k of Object.keys(v)) o[k] = jsonSafe(v[k]); return o; }
  return v;
}
function serializeInputs(raw) { return jsonSafe(raw || {}); }
module.exports = { registerModel, getModel, listModels, runModel, normalizeInputs, grade, jsonSafe, KINDS, STATUSES, LIMITS, cmpVer };
