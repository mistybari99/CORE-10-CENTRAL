"use strict";
/* U14 / R102 — calibrated uncertainty. A probability is produced ONLY from caller-supplied, structurally validated calibration evidence.
   No evidence (or weak evidence) => REFUSED. Output is always labelled conditional on that evidence; it is never a forecast, guarantee or advice.
   Sampling uses a seeded PRNG: identical inputs + seed => identical results. Sample values are converted to exact decimal strings before the model runs. */
const { Dec, D, SimError } = require("./decimal");
const { runModel } = require("./kernel"); const { hashOf } = require("./sha256"); const A = require("./analysis");
const LIMITS = { maxRuns: 2000, maxDrivers: 4, minSample: 30, minValidationObs: 20 };
function validateCalibration(c) {
  const p = []; if (!c || typeof c !== "object") return ["calibration evidence missing"]; const d = c.distribution || {};
  if (!["normal", "triangular", "uniform"].includes(d.type)) p.push("distribution.type must be normal|triangular|uniform");
  const num = x => typeof x === "string" && /^-?\d+(\.\d+)?$/.test(x);
  if (d.type === "normal" && !(num(d.mean) && num(d.sd) && D(d.sd).isPos())) p.push("normal needs decimal-string mean and sd>0");
  if (d.type === "triangular" && !(num(d.min) && num(d.mode) && num(d.max) && D(d.min).lt(d.max) && D(d.mode).gte(d.min) && D(d.mode).lte(d.max))) p.push("triangular needs min<=mode<=max, min<max");
  if (d.type === "uniform" && !(num(d.min) && num(d.max) && D(d.min).lt(d.max))) p.push("uniform needs min<max");
  if (!Number.isInteger(c.sampleSize) || c.sampleSize < LIMITS.minSample) p.push("sampleSize must be an integer >= " + LIMITS.minSample);
  if (typeof c.sourceRef !== "string" || c.sourceRef.length < 3) p.push("sourceRef (where the observations came from) required");
  const v = c.validation; if (!v || !["holdout", "backtest"].includes(v.method) || !Number.isInteger(v.observations) || v.observations < LIMITS.minValidationObs || typeof v.coverage80Pct !== "number" || v.coverage80Pct < 70 || v.coverage80Pct > 90) p.push("validation {method:holdout|backtest, observations>=" + LIMITS.minValidationObs + ", coverage80Pct in [70,90]} required: the 80% interval must actually contain ~80% of held-out observations");
  return p;
}
function prng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
function normalPair(u) { const a = Math.max(u(), 1e-12), b = u(); const r = Math.sqrt(-2 * Math.log(a)); return [r * Math.cos(2 * Math.PI * b), r * Math.sin(2 * Math.PI * b)]; }
function chol(m) { const n = m.length, L = Array.from({ length: n }, () => new Array(n).fill(0)); for (let i = 0; i < n; i++) for (let j = 0; j <= i; j++) { let s = m[i][j]; for (let k = 0; k < j; k++) s -= L[i][k] * L[j][k]; if (i === j) { if (s <= 1e-12) throw new SimError("BAD_CORRELATION", "correlation matrix is not positive definite"); L[i][i] = Math.sqrt(s); } else L[i][j] = s / L[j][j]; } return L; }
function monteCarlo(spec, ctx) {
  const { modelId, version, inputs, drivers, outputKey } = spec; if (!drivers || !drivers.length || drivers.length > LIMITS.maxDrivers) throw new SimError("BOUND_EXCEEDED", "1.." + LIMITS.maxDrivers + " drivers");
  const runs = spec.runs || 500; if (!Number.isInteger(runs) || runs < 50 || runs > LIMITS.maxRuns) throw new SimError("BOUND_EXCEEDED", "runs 50.." + LIMITS.maxRuns);
  const problems = []; drivers.forEach((d, i) => validateCalibration(d.calibration).forEach(x => problems.push("driver " + (d.path || i) + ": " + x)));
  if (problems.length) return { kind: "monte_carlo", status: "REFUSED_NOT_CALIBRATED", problems, message: "Probabilities require validated distribution evidence (U14/R102). Use scenario ranges instead.", probabilities: null };
  const corr = spec.correlations || []; let L = null; if (corr.length) { if (drivers.some(d => d.calibration.distribution.type !== "normal")) return { kind: "monte_carlo", status: "REFUSED_NOT_CALIBRATED", problems: ["correlations are supported only between normal drivers"], probabilities: null };
    const n = drivers.length, m = Array.from({ length: n }, (_, i) => Array.from({ length: n }, (_, j) => (i === j ? 1 : 0))); for (const c of corr) { const a = drivers.findIndex(d => d.path === c.a), b = drivers.findIndex(d => d.path === c.b); if (a < 0 || b < 0 || a === b || typeof c.rho !== "number" || Math.abs(c.rho) >= 1) throw new SimError("BAD_CORRELATION", "invalid correlation entry"); if (!c.evidence || !c.evidence.sourceRef) throw new SimError("BAD_CORRELATION", "each correlation needs evidence.sourceRef"); m[a][b] = m[b][a] = c.rho; } L = chol(m); }
  const u = prng(spec.seed == null ? 1 : spec.seed), outs = []; let invalid = 0; const spare = []; const stdNormal = () => { if (spare.length) return spare.pop(); const [x, y] = normalPair(u); spare.push(y); return x; };
  for (let r = 0; r < runs; r++) { const z = drivers.map(() => stdNormal()); const zc = L ? z.map((_, i) => z.slice(0, i + 1).reduce((s, v, k) => s + L[i][k] * v, 0)) : z; const c = A.clone(inputs);
    drivers.forEach((d, i) => { const dist = d.calibration.distribution; let x; if (dist.type === "normal") x = Number(dist.mean) + Number(dist.sd) * zc[i]; else if (dist.type === "uniform") x = Number(dist.min) + (Number(dist.max) - Number(dist.min)) * u(); else { const a = Number(dist.min), b = Number(dist.mode), cc = Number(dist.max), w = u(), f = (b - a) / (cc - a); x = w < f ? a + Math.sqrt(w * (cc - a) * (b - a)) : cc - Math.sqrt((1 - w) * (cc - a) * (cc - b)); } if (d.min != null) x = Math.max(x, Number(d.min)); if (d.max != null) x = Math.min(x, Number(d.max)); A.setLeaf(c, d.path, x.toFixed(6)); });
    let res; try { res = runModel(modelId, version, c, ctx); } catch (e) { if (e instanceof SimError) { invalid++; continue; } throw e; } if (res.outputs === null) { invalid++; continue; } const v = res.exact && res.exact[outputKey] !== undefined ? res.exact[outputKey] : res.outputs[outputKey]; if (v == null) { invalid++; continue; } outs.push(D(v)); }
  if (outs.length < runs * 0.8) return { kind: "monte_carlo", status: "TOO_MANY_INVALID_RUNS", invalid, runs, probabilities: null };
  const s = outs.slice().sort((a, b) => a.cmp(b)); const pct = p => s[Math.min(s.length - 1, Math.max(0, Math.ceil(p / 100 * s.length) - 1))].toString(4); const n = s.length, mean = s.reduce((a, b) => a.add(b), D(0)).div(n); const sd = s.reduce((a, b) => a.add(b.sub(mean).mul(b.sub(mean))), D(0)).div(n > 1 ? n - 1 : 1).sqrt();
  const probs = (spec.thresholds || []).map(t => ({ output: outputKey, op: ">=", threshold: String(t), probabilityPct: D(s.filter(x => x.gte(t)).length).div(n).mul(100).toString(2) }));
  return { kind: "monte_carlo", status: "CALIBRATED_CONDITIONAL", seed: spec.seed == null ? 1 : spec.seed, runs, validRuns: n, invalidRuns: invalid, outputKey, mean: mean.toString(4), sd: sd.toString(4), percentiles: { p5: pct(5), p10: pct(10), p25: pct(25), p50: pct(50), p75: pct(75), p90: pct(90), p95: pct(95) }, probabilities: probs, evidenceHash: hashOf(drivers.map(d => ({ p: d.path, c: d.calibration }))), disclaimer: "Conditional on the supplied calibration evidence and the model's assumptions. Not a forecast, guarantee, legal or investment advice. Uncalibrated or changed conditions invalidate it." };
}
module.exports = { monteCarlo, validateCalibration, LIMITS };
