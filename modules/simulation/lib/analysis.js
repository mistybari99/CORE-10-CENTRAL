"use strict";
/* C10-A025 analysis layer: sensitivity, stress, reverse planning, bounded optimisation, feasibility graph,
   deterministic insights, actual-vs-plan, forecast accuracy, early warning. Pure functions over runModel(). */
const { Dec, D, SimError, sum, ZERO } = require("./decimal");
const { runModel, KINDS } = require("./kernel");
const { hashOf } = require("./sha256");
const MAX_RUNS = 5000;
const clone = o => JSON.parse(JSON.stringify(o));
function getLeaf(obj, path) { const parts = path.split("."); let cur = obj; for (const p of parts) { if (cur == null) return undefined; cur = cur[p]; } return cur; }
function setLeaf(obj, path, val) { const parts = path.split("."); let cur = obj; for (let i = 0; i < parts.length - 1; i++) { if (cur[parts[i]] == null) throw new SimError("BAD_DRIVER", "driver path not found: " + path); cur = cur[parts[i]]; } const last = parts[parts.length - 1]; const old = cur[last]; if (old === undefined) throw new SimError("BAD_DRIVER", "driver path not found: " + path); if (old !== null && typeof old === "object" && !Array.isArray(old) && "value" in old) cur[last] = Object.assign({}, old, { value: val }); else cur[last] = val; }
function leafValue(inputs, path) { let v = getLeaf(inputs, path); if (v !== null && typeof v === "object" && "value" in v) v = v.value; if (typeof v === "object" || v === undefined) throw new SimError("BAD_DRIVER", "driver is not a scalar: " + path); return D(v); }
function withDriver(inputs, path, val) { const c = clone(inputs); setLeaf(c, path, val.toString()); return c; }
function out(res, key) { if (res.outputs === null) throw new SimError("NEEDS_INPUT", "run needs inputs: " + res.requiredInputs.map(x => x.key).join(",")); const v = res.exact && res.exact[key] !== undefined ? res.exact[key] : res.outputs[key]; if (v === null || v === undefined) return null; return D(v); }
function safeRun(model, version, inputs, ctx) { try { return runModel(model, version, inputs, ctx); } catch (e) { if (e instanceof SimError) return { error: e }; throw e; } }

function sensitivity(spec, ctx) {
  const { modelId, version, inputs, outputKey, drivers, deltasPct } = spec; const deltas = (deltasPct || [-20, -10, 10, 20]).map(D);
  if (drivers.length * deltas.length + 1 > 400) throw new SimError("BOUND_EXCEEDED", "sensitivity bounded to 400 runs");
  const base = runModel(modelId, version, inputs, ctx), baseOut = out(base, outputKey); const rows = [];
  for (const d of drivers) { const bv = leafValue(inputs, d); const pts = []; let lo = null, hi = null;
    for (const dl of deltas) { const nv = bv.mul(D(1).add(dl.pct())); const r = safeRun(modelId, version, withDriver(inputs, d, nv), ctx); if (r.error) { pts.push({ deltaPct: dl.toString(), driverValue: nv.toString(6), error: r.error.code }); continue; } const o = out(r, outputKey); pts.push({ deltaPct: dl.toString(), driverValue: nv.toString(6), output: o === null ? null : o.toString(4), change: o === null || baseOut === null ? null : o.sub(baseOut).toString(4) }); if (o !== null) { lo = lo === null || o.lt(lo) ? o : lo; hi = hi === null || o.gt(hi) ? o : hi; } }
    rows.push({ driver: d, baseValue: bv.toString(6), points: pts, swing: lo === null ? null : hi.sub(lo).toString(4), _s: lo === null ? ZERO : hi.sub(lo) }); }
  rows.sort((a, b) => (b._s.cmp(a._s)) || (a.driver < b.driver ? -1 : 1)); rows.forEach((r, i) => { r.rank = i + 1; delete r._s; });
  return { kind: "one_way_sensitivity", modelId: base.modelId, modelVersion: base.modelVersion, outputKey, baseOutput: baseOut === null ? null : baseOut.toString(4), drivers: rows, runs: drivers.length * deltas.length + 1, note: "One-way: each driver varied alone. Interactions are not shown; see stress() for combined shocks." };
}
function stress(spec, ctx) {
  const { modelId, version, inputs, shocks, outputKeys } = spec; if (!shocks.length || shocks.length > 20) throw new SimError("BOUND_EXCEEDED", "1..20 shocks");
  const base = runModel(modelId, version, inputs, ctx); let c = clone(inputs); for (const s of shocks) { const bv = leafValue(c, s.path); const nv = s.pct !== undefined ? bv.mul(D(1).add(D(s.pct).pct())) : bv.add(D(s.abs)); setLeaf(c, s.path, nv.toString()); }
  const st = runModel(modelId, version, c, ctx); const keys = outputKeys || Object.keys(base.outputs).filter(k => typeof base.outputs[k] === "string" && /^-?\d+(\.\d+)?$/.test(base.outputs[k])); const rows = [];
  for (const k of keys) { const ex = (r) => (r.exact && r.exact[k] !== undefined ? r.exact[k] : r.outputs[k]); const a = ex(base), b = ex(st); if (a == null || b == null) { rows.push({ output: k, base: a, stressed: b, note: "unknown in one run" }); continue; } const A = D(a), B = D(b); const isPct = /_pct$/.test(k); rows.push({ output: k, base: A.toString(4), stressed: B.toString(4), absoluteChange: B.sub(A).toString(4), percentChange: !isPct && !A.isZero() ? B.sub(A).div(A.abs()).mul(100).toString(2) : null, percentagePointChange: isPct ? B.sub(A).toString(4) : null }); }
  return { kind: "stress", shocks, rows, baseFeasibility: base.feasibility, stressedFeasibility: st.feasibility, stressedWarnings: st.warnings, stressedInputHash: st.inputHash };
}
function reverseGoal(spec, ctx) {
  const { modelId, version, inputs, driver, outputKey, target } = spec; const lo0 = D(spec.lo), hi0 = D(spec.hi), T = D(target); if (lo0.gte(hi0)) throw new SimError("BAD_BOUNDS", "lo must be < hi");
  const f = x => { const r = safeRun(modelId, version, withDriver(inputs, driver, x), ctx); if (r.error) return { err: r.error.code }; const o = out(r, outputKey); return o === null ? { err: "UNKNOWN_OUTPUT" } : { o }; };
  const pts = []; for (let i = 0; i <= 10; i++) { const x = lo0.add(hi0.sub(lo0).mul(i).div(10)); pts.push({ x, r: f(x) }); } const okPts = pts.filter(p => !p.r.err);
  if (okPts.length < 2) return { kind: "reverse_goal", status: "NO_VALID_POINTS", detail: pts.map(p => p.r.err) };
  let inc = true, dec = true; for (let i = 1; i < okPts.length; i++) { if (okPts[i].r.o.lt(okPts[i - 1].r.o)) inc = false; if (okPts[i].r.o.gt(okPts[i - 1].r.o)) dec = false; }
  if (!inc && !dec) return { kind: "reverse_goal", status: "NON_MONOTONIC_REFUSED", message: "Output is not monotonic in this driver over the range; a unique answer cannot be promised.", samples: okPts.map(p => ({ driver: p.x.toString(4), output: p.r.o.toString(4) })) };
  const first = okPts[0], last = okPts[okPts.length - 1]; const minO = first.r.o.lt(last.r.o) ? first.r.o : last.r.o, maxO = first.r.o.gt(last.r.o) ? first.r.o : last.r.o;
  if (T.lt(minO) || T.gt(maxO)) return { kind: "reverse_goal", status: "INFEASIBLE_IN_BOUNDS", achievableRange: [minO.toString(4), maxO.toString(4)], message: "Target is outside what this driver can reach within the bounds." };
  let lo = first.x, hi = last.x, flo = first.r.o, iters = 0; const incr = last.r.o.gte(first.r.o); for (; iters < 100; iters++) { const mid = lo.add(hi).div(2), fm = f(mid); if (fm.err) return { kind: "reverse_goal", status: "SOLVER_HIT_INVALID_REGION", driverAt: mid.toString(6) }; if (fm.o.eq(T) || hi.sub(lo).abs().lt("0.0000001")) { lo = hi = mid; break; } if ((fm.o.lt(T)) === incr) lo = mid; else hi = mid; }
  const x = lo.add(hi).div(2), fin = f(x); return { kind: "reverse_goal", status: "SOLVED", driver, driverValue: x.toString(6), achievedOutput: fin.o ? fin.o.toString(4) : null, target: T.toString(4), iterations: iters, note: "Single-driver solution; all other inputs held. Advisory only." };
}
function optimize(spec, ctx) {
  const { modelId, version, inputs, variables, objective, constraints } = spec; if (!variables.length || variables.length > 3) throw new SimError("BOUND_EXCEEDED", "1..3 variables");
  const grids = variables.map(v => { const steps = v.steps || 11; if (steps < 2 || steps > 21) throw new SimError("BOUND_EXCEEDED", "steps 2..21"); const lo = D(v.lo), hi = D(v.hi); if (lo.gte(hi)) throw new SimError("BAD_BOUNDS", "lo<hi"); const g = []; for (let i = 0; i < steps; i++) g.push(lo.add(hi.sub(lo).mul(i).div(steps - 1))); return g; });
  const total = grids.reduce((a, g) => a * g.length, 1); if (total > MAX_RUNS) throw new SimError("BOUND_EXCEEDED", "grid " + total + " > " + MAX_RUNS);
  let best = null, runs = 0, feasible = 0, invalid = 0; const reasons = {}; const idx = new Array(variables.length).fill(0); const cmpOp = (v, c) => { const x = D(c.value); return c.op === ">=" ? v.gte(x) : c.op === "<=" ? v.lte(x) : v.eq(x); };
  for (let n = 0; n < total; n++) { let c = clone(inputs); const pt = {}; variables.forEach((v, i) => { const val = grids[i][idx[i]]; setLeaf(c, v.path, val.toString()); pt[v.path] = val.toString(6); });
    const r = safeRun(modelId, version, c, ctx); runs++; if (r.error || r.outputs === null) invalid++; else { let ok = true; for (const k of constraints || []) { const o = out(r, k.outputKey); if (o === null || !cmpOp(o, k)) { ok = false; const key = k.outputKey + k.op + k.value; reasons[key] = (reasons[key] || 0) + 1; } } if (ok) { feasible++; const o = out(r, objective.outputKey); if (o !== null && (best === null || (objective.sense === "min" ? o.lt(best.o) : o.gt(best.o)))) best = { o, pt, hash: r.inputHash }; } }
    for (let i = idx.length - 1; i >= 0; i--) { if (++idx[i] < grids[i].length) break; idx[i] = 0; } }
  return { kind: "bounded_grid_optimization", status: best ? "FEASIBLE_OPTIMUM_FOUND" : "INFEASIBLE", objective, constraints: constraints || [], best: best ? { objective: best.o.toString(4), at: best.pt, inputHash: best.hash } : null, runs, feasibleRuns: feasible, invalidRuns: invalid, violatedConstraintCounts: reasons, disclaimer: "Grid search over stated bounds and step sizes only. Not a global optimum, not a guarantee, not advice." };
}

/* ---------- feasibility graph (U06/U07) ---------- */
const DEPENDENCIES = [
  { from: "M06", to: "M04", kind: "purchase payment timing changes cash", source: "mock: A049 purchase flow NOT connected" },
  { from: "M07", to: "M08", kind: "batch hours consume machine/staff capacity", source: "mock: A049 production NOT connected" },
  { from: "M08", to: "M17", kind: "capacity caps sellable volume", source: "pure model link" },
  { from: "M13", to: "M04", kind: "principal & interest are cash, only interest is P&L", source: "pure model link" },
  { from: "M14", to: "M04", kind: "financing obligations vs profit", source: "A022 semantics (manual_unverified)" },
  { from: "M05", to: "M06", kind: "lead time vs stock cover", source: "mock: A048 inventory NOT connected" },
  { from: "M19", to: "M03", kind: "internal transfers eliminated before consolidated P&L", source: "pure model link" }];
function feasibility(bundle, limits) {
  const findings = []; const L = limits || {}; const push = (node, severity, code, message, src) => findings.push({ node, severity, code, message, source: src || null });
  const cashKeys = ["cashflow", "branch", "construction", "financing"];
  for (const k of Object.keys(bundle)) { const r = bundle[k]; if (!r || r.outputs === null) { push(k, "unknown", "NEEDS_INPUT", "Result unavailable: inputs missing; feasibility UNKNOWN, not assumed OK.", k); continue; } const f = r.feasibility;
    if (f && f !== "ok" && f !== "n/a") push(k, /INFEASIBLE|SHORTFALL|GAP|OVER_CAPACITY|STOCKOUT|LOSS|MISMATCH|NOT_RECOVERED/.test(f) ? "blocking" : "warning", f, (r.warnings && r.warnings[0]) || f, r.modelId + "@" + r.modelVersion);
    if (r.dataQuality && r.dataQuality.level === "ASSUMED_ONLY") push(k, "info", "ASSUMED_ONLY", "All inputs are assumptions; no actual source attached.", r.modelId); }
  if (L.minCashBuffer !== undefined) for (const k of cashKeys) { const r = bundle[k]; if (!r || !r.outputs) continue; const lo = r.outputs.lowest_cash !== undefined ? r.outputs.lowest_cash : r.outputs.minimum_closing_cash !== undefined ? r.outputs.minimum_closing_cash : null; if (lo !== null && D(lo).lt(L.minCashBuffer)) push(k, "blocking", "BELOW_REQUIRED_BUFFER", "Lowest cash " + lo + " is below required buffer " + L.minCashBuffer, r.modelId); }
  for (const f of L.financingFlags || []) if (f.principalInPnl) push("finance", "blocking", "PRINCIPAL_IN_PNL", "Loan/financing principal is counted as a P&L expense: double counting.", f.name);
  const deps = DEPENDENCIES.filter(d => Object.values(bundle).some(r => r && r.modelId === d.from) || Object.values(bundle).some(r => r && r.modelId === d.to));
  const blocking = findings.some(f => f.severity === "blocking"), unknown = findings.some(f => f.severity === "unknown"), warn = findings.some(f => f.severity === "warning");
  return { kind: "feasibility_graph", overall: blocking ? "INFEASIBLE" : unknown ? "UNKNOWN" : warn ? "AT_RISK" : "FEASIBLE_ON_STATED_ASSUMPTIONS", findings, dependencies: deps, sideEffects: [] };
}
/* ---------- deterministic insights ---------- */
function insights(res, opts) {
  const o = opts || {}, minMargin = D(o.minMarginPct == null ? 10 : o.minMarginPct); const rows = []; const add = (id, sev, en, bn) => rows.push({ ruleId: id, severity: sev, en, bn });
  if (!res || res.outputs === null) { add("INS-NEEDS-INPUT", "info", "Inputs are missing: no result yet. Unknown is not zero.", "ইনপুট অনুপস্থিত: ফলাফল নেই। অজানা মানে শূন্য নয়।"); return rows; }
  if (/LOSS/.test(res.feasibility || "")) add("INS-LOSS", "blocking", "Each unit/period loses money at these inputs.", "এই ইনপুটে প্রতি একক/সময়ে লোকসান।");
  const m = res.outputs.margin_on_revenue_pct; if (m != null && D(m).lt(minMargin) && D(m).gte(0)) add("INS-LOW-MARGIN", "warning", "Margin " + m + "% is below your " + minMargin.toString() + "% threshold.", "মার্জিন " + m + "% আপনার " + minMargin.toString() + "% সীমার নিচে।");
  if (/CASH|SHORTFALL|BUFFER/.test(res.feasibility || "")) add("INS-CASH", "blocking", "Cash is short or below buffer in at least one month: arrange funding or change timing.", "অন্তত এক মাসে নগদ ঘাটতি/বাফারের নিচে: অর্থায়ন বা সময়সূচি বদলান।");
  const pwn = res.outputs.profitable_months_with_negative_cash || res.outputs.profitable_months_with_negative_cash_change; if (pwn && D(pwn).isPos()) add("INS-PROFIT-NOT-CASH", "warning", pwn + " month(s) are profitable but cash-negative.", pwn + " মাস লাভজনক কিন্তু নগদ-নেগেটিভ।");
  if (res.feasibility === "INFEASIBLE_NONPOSITIVE_CONTRIBUTION") add("INS-NO-BREAKEVEN", "blocking", "Price does not cover variable cost: break-even is impossible.", "দাম পরিবর্তনশীল খরচ তোলে না: ব্রেক-ইভেন অসম্ভব।");
  if (res.dataQuality && res.dataQuality.level === "ASSUMED_ONLY") add("INS-ASSUMED", "info", "Every input is an assumption. Treat results as a what-if, not a forecast.", "সব ইনপুটই অনুমান। ফলাফল কী-হলে বিশ্লেষণ, পূর্বাভাস নয়।");
  if (res.warnings && res.warnings.some(w => /guarantee/i.test(w))) add("INS-NO-GUARANTEE", "info", "No return is guaranteed by this simulation.", "এই সিমুলেশন কোনো রিটার্নের নিশ্চয়তা দেয় না।");
  return rows;
}
/* ---------- U17/U19/U20: plan vs actual, accuracy, warnings ---------- */
function planSnapshot(result) { const snap = JSON.parse(JSON.stringify({ modelId: result.modelId, modelVersion: result.modelVersion, inputHash: result.inputHash, outputs: result.outputs, currency: result.currency })); snap.planHash = hashOf(snap); return Object.freeze(snap); }
function actualVsPlan(plan, actuals) {
  const copy = Object.assign({}, plan); delete copy.planHash; if (hashOf(copy) !== plan.planHash) throw new SimError("PLAN_TAMPERED", "Plan snapshot hash does not match: original assumptions are immutable");
  if (actuals.currency && actuals.currency !== plan.currency) throw new SimError("CURRENCY_MISMATCH", "actuals currency differs from plan");
  const rows = []; for (const k of Object.keys(actuals.values)) { const a = actuals.values[k]; if (a.kind !== "actual") { rows.push({ output: k, status: "SKIPPED_NOT_ACTUAL", kind: a.kind }); continue; } const pv = plan.outputs[k]; if (pv == null) { rows.push({ output: k, status: "NO_PLAN_VALUE" }); continue; } const P = D(pv), A = D(a.value); const isPct = /_pct$/.test(k); rows.push({ output: k, plan: P.toString(2), actual: A.toString(2), variance: A.sub(P).toString(2), variancePct: !isPct && !P.isZero() ? A.sub(P).div(P.abs()).mul(100).toString(2) : null, variancePercentagePoints: isPct ? A.sub(P).toString(4) : null, status: "MEASURED" }); }
  return { kind: "actual_vs_plan", planHash: plan.planHash, planImmutable: true, rows, note: "Variance is measured actual minus ORIGINAL plan; the plan is never rewritten." };
}
function forecastAccuracy(pairs) {
  const ok = pairs.filter(p => p.kind === "actual" && p.actual != null && p.forecast != null); if (ok.length < 3) return { kind: "forecast_accuracy", status: "INSUFFICIENT_COMPARABLE_ACTUALS", comparable: ok.length, needed: 3 };
  let abs = ZERO, bias = ZERO, ape = ZERO, apeN = 0; for (const p of ok) { const e = D(p.forecast).sub(D(p.actual)); bias = bias.add(e); abs = abs.add(e.abs()); if (!D(p.actual).isZero()) { ape = ape.add(e.abs().div(D(p.actual).abs())); apeN++; } }
  const n = ok.length; return { kind: "forecast_accuracy", status: "MEASURED", comparable: n, meanAbsoluteError: abs.div(n).toString(4), bias: bias.div(n).toString(4), biasDirection: bias.isPos() ? "over_forecast" : bias.isNeg() ? "under_forecast" : "none", mapePct: apeN ? ape.div(apeN).mul(100).toString(2) : null, zeroActualsExcluded: n - apeN };
}
function earlyWarnings(plan, actuals, rules) {
  const av = actualVsPlan(plan, actuals); const out = []; for (const r of rules) { const row = av.rows.find(x => x.output === r.output && x.status === "MEASURED"); if (!row) continue; const v = r.metric === "pp" ? row.variancePercentagePoints : row.variancePct; if (v === null) continue; const V = D(v); const bad = r.direction === "below" ? V.lt(D(r.threshold).neg()) : V.gt(r.threshold); if (bad) out.push({ output: r.output, ruleId: "EW-" + r.output, variance: v, threshold: r.threshold, message: "Actual deviates from plan beyond threshold: re-run the simulation with the actual baseline." , replanRecommended: true }); }
  return { kind: "early_warning", warnings: out, evidence: av.rows, replan: out.length ? "RECOMMENDED" : "NOT_TRIGGERED" };
}
module.exports = { sensitivity, stress, reverseGoal, optimize, feasibility, insights, planSnapshot, actualVsPlan, forecastAccuracy, earlyWarnings, DEPENDENCIES, getLeaf, setLeaf, clone };
