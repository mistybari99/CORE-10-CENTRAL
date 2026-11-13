"use strict";
/* Minimal DB executor over the psql CLI (no npm dependency). DRAFT: one short-lived psql per call. Production swaps this for a pooled driver
   behind the same interface: exec({ role, sub, sql }) -> { ok, out, err }. Role is whitelisted; `sub` comes ONLY from the authenticated session. */
const { spawnSync } = require("child_process");
const ROLES = new Set(["sim_authenticated", "sim_gateway"]);
const esc = s => { const t = String(s); if (t.includes("\0")) throw new Error("NUL byte refused"); return "'" + t.replace(/'/g, "''") + "'"; };
const json = o => { const t = JSON.stringify(o); let tag = "j"; while (t.includes("$" + tag + "$")) tag += "x"; return "$" + tag + "$" + t + "$" + tag + "$::jsonb"; };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, ID = /^[A-Za-z0-9_-]{1,64}$/;
function makeExecutor(opts) {
  opts = opts || {}; const db = opts.db || process.env.C10_SIM_DB || "c10_a025_persist";
  return { exec({ role, sub, sql }) {
    if (!ROLES.has(role)) throw new Error("role not allowed: " + role); if (typeof sub !== "string" || !ID.test(sub)) throw new Error("bad actor");
    const script = "set role " + role + ";\ndo $c$ begin perform set_config('request.jwt.claims', " + esc(JSON.stringify({ sub, synthetic: true, notSignedAuth: true })) + ", false); end $c$;\n" + sql;
    const r = spawnSync("psql", ["-X", "-q", "-A", "-t", "-d", db, "-v", "ON_ERROR_STOP=1"], { input: script, encoding: "utf8", env: process.env, timeout: 20000 });
    return { ok: r.status === 0, out: (r.stdout || "").trim(), err: (r.stderr || "").trim() };
  } };
}
module.exports = { makeExecutor, esc, json, UUID, ID };
