"use strict";
const { D, SimError } = require("./decimal");
/* Dimensioned conversions. Only same-dimension conversion allowed; unknown units rejected. Factors are exact decimals to the dimension base. */
const DIM = {
  kg: ["mass", "1000"], g: ["mass", "1"], mg: ["mass", "0.001"], lb: ["mass", "453.59237"], ton: ["mass", "1000000"],
  l: ["volume", "1000"], litre: ["volume", "1000"], ml: ["volume", "1"],
  piece: ["count", "1"], pcs: ["count", "1"], dozen: ["count", "12"], carton12: ["count", "12"], carton24: ["count", "24"],
  hour: ["time", "60"], staff_hour: ["staff_time", "60"], machine_hour: ["machine_time", "60"], minute: ["time", "1"],
  m: ["length", "1000"], km: ["length", "1000000"], sqm: ["area", "1"], bag50kg: ["mass", "50000"]
};
function dimOf(u) { const x = DIM[u]; if (!x) throw new SimError("UNKNOWN_UNIT", "Unknown unit: " + u, { unit: u }); return x[0]; }
function convert(qty, from, to) {
  if (from === to) return D(qty);
  const a = DIM[from], b = DIM[to];
  if (!a || !b) throw new SimError("UNKNOWN_UNIT", "Unknown unit " + (!a ? from : to), { from, to });
  if (a[0] !== b[0]) throw new SimError("UNIT_DIMENSION_MISMATCH", "Cannot convert " + from + " to " + to, { from, to });
  return D(qty).mul(a[1]).div(b[1]);
}
module.exports = { convert, dimOf, UNITS: Object.keys(DIM) };
