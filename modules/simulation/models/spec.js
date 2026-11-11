"use strict";
/* tiny spec helpers: l = [English, Bangla] label */
const f = (t, k, l, o) => Object.assign({ t, k, l, req: true }, o || {});
module.exports = {
  money: (k, l, o) => f("money", k, l, Object.assign({ min: "0", unit: "currency" }, o || {})),
  signed: (k, l, o) => f("money", k, l, Object.assign({ unit: "currency" }, o || {})),
  pct: (k, l, o) => f("percent", k, l, Object.assign({ min: "0", max: "100", unit: "percent" }, o || {})),
  dec: (k, l, o) => f("decimal", k, l, o), int: (k, l, o) => f("int", k, l, o),
  qty: (k, l, unit, o) => f("qty", k, l, Object.assign({ unit, min: "0" }, o || {})),
  series: (k, l, o) => f("series", k, l, Object.assign({ unit: "currency" }, o || {})),
  list: (k, l, item, o) => f("list", k, l, Object.assign({ item }, o || {})),
  enumT: (k, l, values, o) => f("enum", k, l, Object.assign({ values }, o || {})),
  bool: (k, l, o) => f("bool", k, l, o), text: (k, l, o) => f("text", k, l, o),
  opt: o => Object.assign({}, o, { req: false })
};
