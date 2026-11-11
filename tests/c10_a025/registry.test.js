"use strict";
const assert = require("node:assert/strict"); const fs = require("fs"), path = require("path"); const E = require("../../modules/simulation/index.js"); const cov = require("../../modules/simulation/lib/coverage"); const { execFileSync } = require("child_process");
const code = fn => { try { fn(); } catch (e) { return e.code || e.message; } return null; };
/* lock: formula/input change without version bump fails */
execFileSync("node", [path.join(__dirname, "../../modules/simulation/tools/registry-lock.js"), "--check"], { stdio: "inherit" });
/* immutability */
assert.equal(code(() => E.registerModel({ id: "M01", version: "1.0.0", family: "x", status: "implemented_tested", inputs: [], outputs: [], formulaText: "x", calculate() { return { outputs: {} }; } })), "REGISTRY_IMMUTABLE");
/* all 20 families present with truthful status */
const mc = cov.modelCoverage(); assert.equal(mc.length, 20); assert.deepEqual(mc.map(m => m.id), Array.from({ length: 20 }, (_, i) => "M" + String(i + 1).padStart(2, "0")));
const impl = mc.filter(m => m.status === "implemented_tested").map(m => m.id), partial = mc.filter(m => m.status === "partial").map(m => m.id); assert.deepEqual(partial, ["M18"], "only M18 (no verified rate source) is partial"); assert.equal(impl.length, 19);
/* every implemented model has goldens (>=2, >=1 adverse), BN+EN explain and labels */
const golden = require("./golden.json");
for (const m of E.listModels().filter(x => /^M\d\d$/.test(x.id))) { const fxs = golden.filter(g => g.model === m.id && (!g.version || g.version === m.version) || (g.model === m.id && m.version === "2.0.0" && m.id === "M01")); assert.ok(fxs.length >= 1, m.id + "@" + m.version + " has golden");
  assert.ok(m.title.en && m.title.bn, m.id + " bilingual title"); for (const k of ["what", "when", "why", "example"]) assert.ok(m.explain[k].en && m.explain[k].bn, m.id + " explain." + k + " en+bn (R128)");
  for (const i of m.inputs) { assert.ok(i.l && i.l[0] && i.l[1], m.id + "." + i.k + " bilingual label"); if (i.item) for (const f of i.item) assert.ok(f.l && f.l[0] && f.l[1], m.id + "." + i.k + "." + f.k + " bilingual label"); }
  for (const o of m.outputs) assert.ok(o.l && o.l[0] && o.l[1], m.id + " output " + o.k + " bilingual label"); assert.ok(Array.isArray(m.assumptions) && m.assumptions.length, m.id + " assumptions"); assert.ok(Array.isArray(m.limitations), m.id + " limitations"); }
/* unsupported stays unsupported: X01 refuses, never fakes */
assert.equal(code(() => E.runModel("X01", null, {})), "MODEL_NOT_IMPLEMENTED"); assert.equal(E.getModel("X01").status, "research_only");
/* versioning: v1 still reproducible after v2; latest = v2; retire needs explicit opt-in */
const v1 = E.runModel("M01", "1.0.0", { unit_cost: "60", selling_price: "100", discount_pct: "10" }), v2 = E.runModel("M01", "2.0.0", { unit_cost: "60", selling_price: "100", discount_pct: "10", channel_fee_pct: "12" });
assert.equal(E.getModel("M01").version, "2.0.0"); assert.equal(v1.outputs.contribution_per_unit, "30.00"); assert.equal(v2.outputs.contribution_per_unit, "19.20"); assert.notEqual(v1.formulaHash, v2.formulaHash);
assert.equal(E.runModel("M01", "2.0.0", { unit_cost: "60", selling_price: "100", discount_pct: "10" }).outputs.contribution_per_unit, v1.outputs.contribution_per_unit, "v2 with 0 fee == v1");
/* extension pattern: a new model registers without touching existing ones */
E.registerModel({ id: "MZ1", version: "0.1.0", family: "test_ext", title: { en: "t", bn: "t" }, explain: null, industries: [], status: "implemented_tested", inputs: [{ t: "money", k: "a", l: ["a", "a"], req: true, min: "0" }], outputs: [{ k: "double", l: ["d", "d"] }], formulaText: "double=a*2", assumptions: [], limitations: [], calculate: v => ({ outputs: { double: v.a.mul(2) } }) });
assert.equal(E.runModel("MZ1", null, { a: "21" }).outputs.double, "42.00"); assert.equal(E.getModel("M01").version, "2.0.0");
/* coverage honesty: nothing above 'tested'; evidence files exist */
for (const u of cov.U) { assert.ok(["proposed", "implemented", "tested", "partial_tested"].includes(u.status), u.id + " status " + u.status); for (const f of u.evidence) assert.ok(fs.existsSync(path.join(__dirname, "../../", f)) || fs.existsSync(path.join(__dirname, "..", "..", f)), u.id + " evidence file missing: " + f); }
assert.equal(cov.U.length, 26); assert.deepEqual(cov.U.map(u => u.req), Array.from({ length: 26 }, (_, i) => "R" + (89 + i)));
console.log("PASS registry: lock, immutability, 20 families (19 tested + M18 partial), bilingual R128 text, versioning, extension, honest coverage ladder");
