"use strict";
/* Contextual Quick Simulation adapter. It is a THIN mapping: same registry, same kernel, same results as the Lab.
   Host screens supply values; values are marked 'actual' ONLY when the host says they came through an authorised read
   (fromAuthorizedSource:true). Anything else is an assumption. Nothing here mutates host or ERP state. */
const { runModel, getModel } = require("./kernel");
const { SimError } = require("./decimal");
const CONTEXTS = {
  item: { modelId: "M01", label: ["Item pricing", "আইটেম মূল্য"] }, inventory: { modelId: "M05", label: ["Inventory reorder", "মজুত রিঅর্ডার"] }, purchasing: { modelId: "M06", label: ["Purchasing offers", "ক্রয় অফার"] },
  production: { modelId: "M07", label: ["Production / BOM", "উৎপাদন / BOM"] }, sales_pricing: { modelId: "M17", label: ["Sales mix & pricing", "বিক্রয় মিশ্রণ ও মূল্য"] }, branch: { modelId: "M16", label: ["Branch opening", "শাখা চালু"] },
  transfer: { modelId: "M09", label: ["Transfer / logistics", "স্থানান্তর / লজিস্টিক"] }, construction: { modelId: "M15", label: ["Construction project", "নির্মাণ প্রকল্প"] }, staffing: { modelId: "M08", label: ["Staffing / capacity", "কর্মী / সক্ষমতা"] },
  financing: { modelId: "M14", label: ["Financing structures", "অর্থায়ন কাঠামো"] }, expansion: { modelId: "M12", label: ["Expansion ROI / NPV", "সম্প্রসারণ ROI / NPV"] } };
function wrapHost(values, fromAuthorizedSource) { const o = {}; for (const k of Object.keys(values || {})) o[k] = fromAuthorizedSource ? { value: values[k], kind: "actual", sourceReference: "HOST_AUTHORIZED_READ" } : { value: values[k], kind: "assumption" }; return o; }
function createQuickSimulation(deps) {
  const auth = deps.authority;
  return {
    contexts: () => Object.keys(CONTEXTS).map(k => ({ id: k, modelId: CONTEXTS[k].modelId, label: CONTEXTS[k].label, modelVersion: getModel(CONTEXTS[k].modelId).version })),
    /* enabled only when the host module is enabled AND the backend authorises the operation */
    available: (session, contextKind, scope, enabledModules) => { const c = CONTEXTS[contextKind]; if (!c) return false; if (enabledModules && !enabledModules.includes(contextKind)) return false; return auth.can(session, "sim.run", scope); },
    run(session, contextKind, hostValues, opts) { opts = opts || {}; const c = CONTEXTS[contextKind]; if (!c) throw new SimError("UNKNOWN_CONTEXT", contextKind); const scope = opts.scope || {}; auth.require(session, "sim.run", { businessId: scope.businessId, siteId: scope.siteId || null }); const ctx = auth.resolveContext(session, scope);
      const inputs = opts.raw ? hostValues : wrapHost(hostValues, !!opts.fromAuthorizedSource); const res = runModel(c.modelId, opts.modelVersion || null, inputs, { currency: opts.currency || "BDT", tenantId: ctx.tenantId, scenarioKind: "custom", now: opts.now || null }); res.entryPoint = "quick:" + contextKind; return res; }
  };
}
module.exports = { createQuickSimulation, CONTEXTS };
