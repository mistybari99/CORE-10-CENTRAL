"use strict";
/* Trusted simulation gateway. Authenticates the caller (synthetic tokens in this draft), then talks to the c10_sim schema.
   KEY PROPERTY: results are NEVER accepted from a client. `run` reads the saved scenario as the user (RLS), re-computes with the pinned
   model version in this process and writes via record_run as the trusted role sim_gateway. */
const E = require("../index.js"); const { esc, json, UUID, ID } = require("./db-psql"); const { reportCsv } = E.lib.reports;
class HttpError extends Error { constructor(status, code, message) { super(message || code); this.status = status; this.code = code; } }
const MAP = [[/UNAUTHENTICATED/, 401, "UNAUTHENTICATED"], [/SCOPE_OVERRIDE_REJECTED/, 403, "SCOPE_OVERRIDE_REJECTED"], [/SEPARATION_OF_DUTIES/, 403, "SEPARATION_OF_DUTIES"], [/FORBIDDEN/, 403, "FORBIDDEN"], [/NOT_FOUND/, 404, "NOT_FOUND"], [/REVISION_CONFLICT/, 409, "REVISION_CONFLICT"], [/LOCKED/, 409, "LOCKED"], [/ARCHIVED/, 409, "ARCHIVED"], [/BAD_TRANSITION/, 422, "BAD_TRANSITION"], [/NO_RUN|NOT_APPROVED|MODEL_NOT_IMPLEMENTED|REQUEST_KEY_REQUIRED|SHARE_TARGET_OUT_OF_TENANT|violates check/, 422, "UNPROCESSABLE"], [/permission denied/, 403, "FORBIDDEN"]];
function fail(r) { for (const [re, st, code] of MAP) if (re.test(r.err)) throw new HttpError(st, code, (r.err.split("\n")[0] || "").replace(/^psql:.*?ERROR:\s*/, "").slice(0, 200)); throw new HttpError(500, "DB_ERROR", "database error"); }
function checks() { return { id: v => { if (!UUID.test(String(v))) throw new HttpError(400, "BAD_ID", "invalid scenario id"); return v; }, ident: (v, k) => { if (!ID.test(String(v))) throw new HttpError(400, "BAD_FIELD", k + " invalid"); return v; }, str: (v, k, max) => { if (typeof v !== "string" || !v || v.length > (max || 200)) throw new HttpError(400, "BAD_FIELD", k + " invalid"); return v; }, int: (v, k) => { if (!Number.isInteger(v) || v < 1 || v > 1e6) throw new HttpError(400, "BAD_FIELD", k + " invalid"); return v; } }; }
class Gateway {
  constructor(o) { this.db = o.db; this.tokens = o.tokens; this.now = o.now || (() => null); this.v = checks(); }
  /* synthetic bearer token -> user id (a signed GoTrue JWT verifier replaces this in staging) */
  authenticate(header) { const m = /^Bearer\s+(\S{1,200})$/.exec(header || ""); const sub = m && this.tokens.get(m[1]); if (!sub) throw new HttpError(401, "UNAUTHENTICATED", "missing or unknown token"); return sub; }
  q(role, sub, sql) { const r = this.db.exec({ role, sub, sql }); if (!r.ok) fail(r); return r.out; }
  create(sub, b) { const v = this.v; const sql = "select c10_sim.create_scenario(" + [esc(v.ident(b.businessId, "businessId")), b.siteId ? esc(v.ident(b.siteId, "siteId")) : "null", esc(v.str(b.name, "name", 120)), esc(["baseline", "conservative", "optimistic", "custom"].includes(b.kind) ? b.kind : "custom"), esc(v.str(b.requestKey, "requestKey", 120)), esc(v.ident(b.modelId, "modelId")), esc(v.str(b.modelVersion, "modelVersion", 20)), json(b.inputs || {}), esc(b.currency || "BDT"), b.tenantId ? esc(v.ident(b.tenantId, "tenantId")) : "null"].join(",") + ");"; return { id: this.q("sim_authenticated", sub, sql) }; }
  saveInputs(sub, id, b) { this.v.id(id); return { revision: Number(this.q("sim_authenticated", sub, "select c10_sim.save_inputs('" + id + "'," + this.v.int(b.expectedRevision, "expectedRevision") + "," + json(b.inputs || {}) + ");")) }; }
  read(sub, id) { this.v.id(id); const out = this.q("sim_authenticated", sub, "select coalesce((select row_to_json(d) from (select id, tenant_id as \"tenantId\", business_id as \"businessId\", site_id as \"siteId\", name, kind, status, revision, model_id as \"modelId\", model_version as \"modelVersion\", inputs, currency, archived, shared_with as \"sharedWith\" from c10_sim.scenario_drafts where id='" + id + "') d), 'null'::json);"); const o = JSON.parse(out); if (!o) throw new HttpError(404, "NOT_FOUND", "scenario not found"); return o; }
  list(sub, businessId) { const w = businessId ? " where business_id = " + esc(this.v.ident(businessId, "businessId")) : ""; return JSON.parse(this.q("sim_authenticated", sub, "select coalesce(json_agg(d order by d.created_at), '[]') from (select id, business_id as \"businessId\", site_id as \"siteId\", name, kind, status, revision, model_id as \"modelId\", model_version as \"modelVersion\", created_at from c10_sim.scenario_drafts" + w + ") d;")); }
  run(sub, id) {
    const sc = this.read(sub, id); /* RLS: invisible => 404 */
    const can = cap => this.q("sim_authenticated", sub, "select c10_sim.can(" + esc(cap) + "," + esc(sc.businessId) + "," + (sc.siteId ? esc(sc.siteId) : "null") + ");") === "t";
    if (!can("sim.run")) throw new HttpError(403, "FORBIDDEN", "sim.run required"); if (sc.modelId === "M20" && !can("sim.template_author")) throw new HttpError(403, "FORBIDDEN", "sim.template_author required");
    let res; try { res = E.runModel(sc.modelId, sc.modelVersion, sc.inputs, { currency: sc.currency, tenantId: sc.tenantId, scenarioKind: sc.kind, now: this.now() }); } catch (e) { if (e instanceof E.SimError) throw new HttpError(422, e.code, e.message); throw e; }
    const runId = this.q("sim_gateway", sub, "select c10_sim.record_run('" + id + "'," + [esc(res.formulaHash), esc(res.inputHash), esc("NO_SOURCE_SNAPSHOT_ASSUMPTIONS_ONLY"), json(sc.inputs), json(res)].join(",") + ");");
    return { runId, readiness: res.readiness, feasibility: res.feasibility, outputs: res.outputs, warnings: res.warnings, modelVersion: res.modelVersion, formulaHash: res.formulaHash, inputHash: res.inputHash, recomputedByGateway: true };
  }
  transition(sub, id, b) { this.v.id(id); return { status: this.q("sim_authenticated", sub, "select c10_sim.transition_scenario('" + id + "'," + esc(this.v.ident(b.to, "to")) + "," + (b.note ? esc(this.v.str(b.note, "note", 500)) : "null") + ");") }; }
  propose(sub, id) { this.v.id(id); return { proposalId: this.q("sim_authenticated", sub, "select c10_sim.propose_scenario('" + id + "');"), advisoryOnly: true, applyState: "DISABLED" }; }
  applyToLive(sub, id) { this.v.id(id); return JSON.parse(this.q("sim_authenticated", sub, "select c10_sim.apply_to_live('" + id + "');")); }
  share(sub, id, b) { this.v.id(id); this.q("sim_authenticated", sub, "select c10_sim.share_scenario('" + id + "'," + esc(this.v.ident(b.userId, "userId")) + ");"); return { shared: true }; }
  comment(sub, id, b) { this.v.id(id); return { id: this.q("sim_authenticated", sub, "select c10_sim.add_annotation('" + id + "'," + esc(this.v.str(b.text, "text", 1000)) + ");") }; }
  archive(sub, id) { this.v.id(id); this.q("sim_authenticated", sub, "select c10_sim.archive_scenario('" + id + "');"); return { archived: true }; }
  export(sub, id, fmt) { this.v.id(id); const o = JSON.parse(this.q("sim_authenticated", sub, "select c10_sim.export_scenario('" + id + "');")); return fmt === "csv" ? { csv: reportCsv(o) } : o; }
}
module.exports = { Gateway, HttpError };
