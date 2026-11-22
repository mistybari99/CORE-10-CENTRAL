"use strict";
// TEST-ONLY loopback gateway. Serves the Owner Control Centre files and runs the allowlisted core10 RPCs
// in a disposable PostgreSQL database as the synthetic persona named by the browser test, through the
// real functions, RLS and grants (SET ROLE authenticated + JWT claims). Never deploy; never point at a hosted DB.
const http = require("node:http"), fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
const { spawnSync } = require("node:child_process");
const ROOT = path.resolve(__dirname, "../..");
const RPCS = new Set(require(path.join(ROOT, "core10-owner-control-client.js")).RPCS.concat(require(path.join(ROOT, "core10-master-data-client.js")).RPCS)
  .concat(require(path.join(ROOT, "core10-owner-dashboard-client.js")).RPCS));
require(path.join(ROOT, "core10-purchase-client.js")).RPCS.forEach((n) => RPCS.add(n));
// RLS-scoped table reads a client declares (exact column list); integer equality filters only.
const READS = require(path.join(ROOT, "core10-purchase-client.js")).READS;
const FILES = {
  "/harness.html": "tests/control-centre/harness.html", "/harness.js": "tests/control-centre/harness.js",
  "/core10-owner-control-client.js": "core10-owner-control-client.js",
  "/core10-owner-control-centre-ui.js": "core10-owner-control-centre-ui.js",
  "/core10-owner-control-centre.css": "core10-owner-control-centre.css",
  "/md-harness.html": "tests/control-centre/md-harness.html", "/md-harness.js": "tests/control-centre/md-harness.js",
  "/core10-master-data-client.js": "core10-master-data-client.js", "/core10-master-data-ui.js": "core10-master-data-ui.js",
  "/core10-master-data.css": "core10-master-data.css",
  "/od-harness.html": "tests/control-centre/od-harness.html", "/od-harness.js": "tests/control-centre/od-harness.js",
  "/core10-owner-dashboard-client.js": "core10-owner-dashboard-client.js", "/core10-owner-dashboard-ui.js": "core10-owner-dashboard-ui.js",
  "/core10-owner-dashboard.css": "core10-owner-dashboard.css"
};
Object.assign(FILES, {
  "/pu-harness.html": "tests/control-centre/pu-harness.html", "/pu-harness.js": "tests/control-centre/pu-harness.js",
  "/core10-purchase-client.js": "core10-purchase-client.js", "/core10-purchase-ui.js": "core10-purchase-ui.js",
  "/core10-purchase.css": "core10-purchase.css"
});
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "application/javascript; charset=utf-8", ".css": "text/css; charset=utf-8" };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

function requireLoopbackDatabase() {
  if (!["127.0.0.1", "localhost"].includes(process.env.PGHOST || "")) throw Error("LOOPBACK_DATABASE_REQUIRED");
}
function psql(sql) {
  return spawnSync("psql", ["-X", "-q", "-At", "-v", "ON_ERROR_STOP=1"], { input: sql, encoding: "utf8", env: process.env });
}
function quote(text) {
  let tag; do tag = "$g" + crypto.randomBytes(6).toString("hex") + "$"; while (text.includes(tag));
  return tag + text + tag;
}
function signatures() {
  const names = Array.from(RPCS).map((n) => "'" + n + "'").join(",");
  const r = psql(`SELECT json_object_agg(proname, args) FROM (SELECT p.proname,
    coalesce(json_agg(json_build_object('n', a.n, 't', format_type(a.t, NULL)) ORDER BY a.o) FILTER (WHERE a.n IS NOT NULL), '[]') args
    FROM pg_proc p LEFT JOIN LATERAL unnest(p.proargnames, p.proargtypes::oid[]) WITH ORDINALITY a(n, t, o) ON true
    WHERE p.pronamespace = 'core10'::regnamespace AND p.proname IN (${names}) GROUP BY p.proname) s`);
  if (r.status !== 0) throw Error("SIGNATURES_UNAVAILABLE " + r.stderr);
  return JSON.parse(r.stdout.trim());
}
function call(sig, name, args, persona) {
  const params = (sig[name] || []).filter((a) => Object.prototype.hasOwnProperty.call(args, a.n)).map((a) => {
    const v = args[a.n];
    const lit = v === null || v === undefined ? "NULL" : quote(typeof v === "object" ? JSON.stringify(v) : String(v));
    return a.n + " => " + lit + "::" + a.t;
  });
  const claims = persona ? JSON.stringify({ sub: persona, role: "authenticated" }) : "{}";
  const sql = `SET ROLE authenticated;
DO $occ$ BEGIN PERFORM set_config('request.jwt.claims', ${quote(claims)}, false); PERFORM set_config('request.jwt.claim.sub', ${quote(persona || "")}, false); END $occ$;
SELECT to_jsonb(core10.${name}(${params.join(", ")}));`;
  const r = psql(sql);
  if (r.status !== 0) {
    const m = (r.stderr.match(/ERROR:\s+(.*)/) || [])[1] || "RPC_FAILED";
    return { status: 400, body: { message: m.trim() } };
  }
  const lines = r.stdout.trim().split("\n");
  return { status: 200, body: JSON.parse(lines[lines.length - 1]) };
}
function readTable(table, q, persona) {
  const cols = Object.prototype.hasOwnProperty.call(READS, table) ? READS[table] : null;
  if (!cols || q.get("select") !== cols) return { status: 404, body: { message: "READ_NOT_ALLOWED" } };
  const where = [];
  for (const [k, v] of q) {
    if (["select", "order", "limit"].includes(k)) continue;
    if (!/^[a-z_]+$/.test(k) || !/^[1-9][0-9]{0,17}$/.test(v)) return { status: 400, body: { message: "BAD_FILTER" } };
    where.push(k + " = " + v);
  }
  const order = q.get("order") || "id", lim = Number(q.get("limit") || 200);
  if (!cols.split(",").includes(order) || !Number.isInteger(lim) || lim < 1 || lim > 200) return { status: 400, body: { message: "BAD_FILTER" } };
  const claims = persona ? JSON.stringify({ sub: persona, role: "authenticated" }) : "{}";
  const r = psql(`SET ROLE authenticated;
DO $occ$ BEGIN PERFORM set_config('request.jwt.claims', ${quote(claims)}, false); PERFORM set_config('request.jwt.claim.sub', ${quote(persona || "")}, false); END $occ$;
SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.${order}), '[]'::jsonb) FROM (SELECT ${cols} FROM core10.${table}${where.length ? " WHERE " + where.join(" AND ") : ""} ORDER BY ${order} LIMIT ${lim}) x;`);
  if (r.status !== 0) return { status: 400, body: { message: ((r.stderr.match(/ERROR:\s+(.*)/) || [])[1] || "READ_FAILED").trim() } };
  const lines = r.stdout.trim().split("\n");
  return { status: 200, body: JSON.parse(lines[lines.length - 1]) };
}
function start(port) {
  requireLoopbackDatabase();
  const sig = signatures();
  const server = http.createServer((req, res) => {
    const send = (st, body, type) => { res.writeHead(st, { "content-type": type || "application/json", "cache-control": "no-store",
      "content-security-policy": "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; object-src 'none'" });
      res.end(typeof body === "string" ? body : JSON.stringify(body)); };
    const url = new URL(req.url, "http://127.0.0.1");
    if (req.method === "GET" && FILES[url.pathname]) {
      const f = path.join(ROOT, FILES[url.pathname]);
      return send(200, fs.readFileSync(f, "utf8"), TYPES[path.extname(f)]);
    }
    if (req.method === "POST" && url.pathname.startsWith("/rpc/")) {
      const name = url.pathname.slice(5), persona = String(req.headers["x-test-persona"] || "");
      if (!RPCS.has(name)) return send(404, { message: "RPC_NOT_ALLOWED" });
      if (persona && !UUID.test(persona)) return send(400, { message: "BAD_PERSONA" });
      let raw = ""; req.on("data", (c) => { raw += c; if (raw.length > 65536) req.destroy(); });
      req.on("end", () => { let args; try { args = raw ? JSON.parse(raw) : {}; } catch (_) { return send(400, { message: "BAD_JSON" }); }
        const out = call(sig, name, args, persona); send(out.status, out.body); });
      return;
    }
    if (req.method === "GET" && url.pathname.startsWith("/table/")) {
      const persona = String(req.headers["x-test-persona"] || "");
      if (persona && !UUID.test(persona)) return send(400, { message: "BAD_PERSONA" });
      const out = readTable(url.pathname.slice(7), url.searchParams, persona); return send(out.status, out.body);
    }
    send(404, { message: "NOT_FOUND" });
  });
  return new Promise((resolve) => server.listen(port || 0, "127.0.0.1", () => resolve(server)));
}
module.exports = { start };
if (require.main === module) start(Number(process.env.PORT || 58210)).then((s) => console.log("test gateway on", s.address().port));
