"use strict";
/* C10-A025 exact decimal kernel. BigInt fixed-point, 18 fractional digits. No floating point in money math.
   Rounding for display is explicit: round(places, mode) where mode = "half_up" (away from zero, default) | "half_even" | "down" | "up". */
const SCALE_DIGITS = 18, SCALE = 10n ** 18n;
const RE = /^([+-]?)(\d+)(?:\.(\d{1,18}))?$/;
class SimError extends Error { constructor(code, message, detail) { super(message || code); this.code = code; this.detail = detail || null; } }
class Dec {
  constructor(v) { this.v = v; Object.freeze(this); }
  static parse(x) {
    if (x instanceof Dec) return x;
    if (typeof x === "number") {
      if (!Number.isSafeInteger(x)) throw new SimError("BAD_DECIMAL", "Non-integer JS numbers are refused; pass a decimal string", { value: String(x) });
      return new Dec(BigInt(x) * SCALE);
    }
    if (typeof x === "bigint") return new Dec(x * SCALE);
    if (typeof x !== "string") throw new SimError("BAD_DECIMAL", "Decimal must be a string", { value: String(x) });
    const m = RE.exec(x.trim());
    if (!m) throw new SimError("BAD_DECIMAL", "Malformed decimal: " + x, { value: x });
    const frac = (m[3] || "").padEnd(SCALE_DIGITS, "0");
    let v = BigInt(m[2]) * SCALE + BigInt(frac);
    if (m[1] === "-") v = -v;
    return new Dec(v);
  }
  static of(n) { return Dec.parse(n); }
  static get ZERO() { return ZERO; }
  static get ONE() { return ONE; }
  add(o) { return new Dec(this.v + Dec.parse(o).v); }
  sub(o) { return new Dec(this.v - Dec.parse(o).v); }
  neg() { return new Dec(-this.v); }
  abs() { return this.v < 0n ? this.neg() : this; }
  mul(o) { return new Dec(divRound(this.v * Dec.parse(o).v, SCALE)); }
  div(o) {
    const d = Dec.parse(o);
    if (d.v === 0n) throw new SimError("DIV_ZERO", "Division by zero");
    return new Dec(divRound(this.v * SCALE, d.v));
  }
  pow(n) {
    if (!Number.isInteger(n) || n < 0 || n > 1200) throw new SimError("BAD_EXPONENT", "Integer exponent 0..1200 required");
    let r = ONE, b = this, e = n;
    while (e > 0) { if (e & 1) r = r.mul(b); b = b.mul(b); e >>= 1; }
    return r;
  }
  sqrt() {
    if (this.v < 0n) throw new SimError("BAD_SQRT", "sqrt of negative");
    if (this.v === 0n) return ZERO;
    const n = this.v * SCALE; let x = BigInt(Math.ceil(Math.sqrt(Number(this.v) / 1e18)) * 1e9) || 1n; // seed
    x = x === 0n ? 1n : x; for (let i = 0; i < 200; i++) { const y = (x + n / x) >> 1n; if (y === x || y === x + 1n || y + 1n === x) { x = y; break; } x = y; }
    while (x * x > n) x -= 1n; while ((x + 1n) * (x + 1n) <= n) x += 1n;
    return new Dec(x);
  }
  cmp(o) { const b = Dec.parse(o).v; return this.v < b ? -1 : this.v > b ? 1 : 0; }
  eq(o) { return this.cmp(o) === 0; } lt(o) { return this.cmp(o) < 0; } lte(o) { return this.cmp(o) <= 0; }
  gt(o) { return this.cmp(o) > 0; } gte(o) { return this.cmp(o) >= 0; }
  isZero() { return this.v === 0n; } isNeg() { return this.v < 0n; } isPos() { return this.v > 0n; }
  min(o) { return this.lte(o) ? this : Dec.parse(o); } max(o) { return this.gte(o) ? this : Dec.parse(o); }
  pct() { return this.div(100); }                 // percent number -> fraction (12.5 -> 0.125)
  ceilInt() { let q = this.v / SCALE; if (this.v > 0n && this.v % SCALE !== 0n) q += 1n; return q; }
  floorInt() { let q = this.v / SCALE; if (this.v < 0n && this.v % SCALE !== 0n) q -= 1n; return q; }
  /* round to `places` decimals, returns Dec */
  round(places, mode) {
    places = places == null ? 2 : places;
    if (!Number.isInteger(places) || places < 0 || places > 18) throw new SimError("BAD_PLACES");
    const unit = 10n ** BigInt(SCALE_DIGITS - places);
    return new Dec(roundTo(this.v, unit, mode || "half_up"));
  }
  toString(places, mode) {
    const v = places == null ? this.v : this.round(places, mode).v;
    const neg = v < 0n, a = neg ? -v : v;
    const ip = a / SCALE, fp = (a % SCALE).toString().padStart(SCALE_DIGITS, "0");
    let frac = places == null ? fp.replace(/0+$/, "") : fp.slice(0, places);
    return (neg && (ip !== 0n || /[1-9]/.test(frac)) ? "-" : "") + ip.toString() + (frac ? "." + frac : "");
  }
  toJSON() { return this.toString(); }
  toNumberUnsafe() { return Number(this.toString()); } // display/charting ONLY, never money math
}
function divRound(n, d) { // round half away from zero
  const neg = (n < 0n) !== (d < 0n); n = n < 0n ? -n : n; d = d < 0n ? -d : d;
  let q = n / d; const r = n % d; if (r * 2n >= d) q += 1n; return neg ? -q : q;
}
function roundTo(v, unit, mode) {
  const neg = v < 0n, a = neg ? -v : v; let q = a / unit; const r = a % unit; const half = unit / 2n;
  if (mode === "down") { /* trunc */ } else if (mode === "up") { if (r > 0n) q += 1n; }
  else if (mode === "half_even") { if (r > half || (r === half && (q & 1n))) q += 1n; }
  else if (mode === "half_up") { if (r >= half && unit > 1n) q += 1n; }
  else throw new SimError("BAD_ROUNDING_MODE");
  const out = q * unit; return neg ? -out : out;
}
const ZERO = new Dec(0n), ONE = new Dec(SCALE);
const D = x => Dec.parse(x);
function sum(arr) { return arr.reduce((a, b) => a.add(b), ZERO); }
/* largest-remainder allocation: parts sum EXACTLY to total at `places` */
function allocate(total, weights, places) {
  places = places == null ? 2 : places; const t = D(total).round(places), w = weights.map(D);
  const W = sum(w); if (W.isZero()) throw new SimError("ALLOC_ZERO_WEIGHT");
  const unit = 10n ** BigInt(SCALE_DIGITS - places);
  const totalUnits = t.v / unit; const raw = w.map(x => (totalUnits * x.v * 1n) ); // scaled by W
  const Wv = W.v; const base = raw.map(r => r / Wv), rem = raw.map((r, i) => ({ i, r: r % Wv }));
  let left = totalUnits - base.reduce((a, b) => a + b, 0n);
  rem.sort((a, b) => (a.r === b.r ? a.i - b.i : (a.r > b.r ? -1 : 1)));
  for (let k = 0; left > 0n && k < rem.length; k++, left--) base[rem[k].i] += 1n;
  return base.map(u => new Dec(u * unit));
}
module.exports = { Dec, D, SimError, sum, allocate, ZERO, ONE, SCALE_DIGITS };
