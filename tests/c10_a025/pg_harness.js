"use strict";
/* Disposable PostgreSQL harness. Uses PGHOST/PGPORT/PGUSER if provided (CI: postgres:17 service), else starts a throwaway local cluster. NEVER connects anywhere else. */
const { spawnSync, spawn } = require("child_process"); const fs = require("fs"), path = require("path"), os = require("os");
let started = null; const DB = "c10_a025_persist"; const SQL = path.join(__dirname, "../../modules/simulation/sql");
function bins() { const base = fs.readdirSync("/usr/lib/postgresql").sort().pop(); return "/usr/lib/postgresql/" + base + "/bin"; }
function ensureServer() {
  if (process.env.PGHOST || process.env.C10_PG_EXTERNAL) { return { external: true }; }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "c10pg-")); const isRoot = process.getuid && process.getuid() === 0; const run = (cmd, args) => isRoot ? spawnSync("runuser", ["-u", "postgres", "--", cmd].concat(args), { encoding: "utf8" }) : spawnSync(cmd, args, { encoding: "utf8" });
  if (isRoot) fs.chownSync(dir, Number(spawnSync("id", ["-u", "postgres"], { encoding: "utf8" }).stdout), 0);
  let r = run(path.join(bins(), "initdb"), ["-D", dir + "/data", "-A", "trust"]); if (r.status !== 0) throw new Error("initdb failed: " + r.stderr);
  r = run(path.join(bins(), "pg_ctl"), ["-D", dir + "/data", "-o", "-p 54399 -k " + dir + " -c listen_addresses=''", "-l", dir + "/log", "-w", "start"]); if (r.status !== 0) throw new Error("pg_ctl failed: " + r.stderr);
  process.env.PGHOST = dir; process.env.PGPORT = "54399"; process.env.PGUSER = "postgres"; started = { dir, run }; return { external: false };
}
function stopServer() { if (started) started.run(path.join(bins(), "pg_ctl"), ["-D", started.dir + "/data", "-m", "immediate", "stop"]); started = null; }
function psql(sql, opts) { opts = opts || {}; const r = spawnSync("psql", ["-X", "-q", "-A", "-t", "-d", opts.db || DB, "-v", "ON_ERROR_STOP=1"], { input: sql, encoding: "utf8", env: process.env }); return { ok: r.status === 0, out: (r.stdout || "").trim(), err: (r.stderr || "").trim() }; }
function psqlAsync(sql) { return new Promise(res => { const p = spawn("psql", ["-X", "-q", "-A", "-t", "-d", DB, "-v", "ON_ERROR_STOP=1"], { env: process.env }); let out = "", err = ""; p.stdout.on("data", d => (out += d)); p.stderr.on("data", d => (err += d)); p.on("close", c => res({ ok: c === 0, out: out.trim(), err: err.trim() })); p.stdin.end(sql); }); }
const claims = u => u === null ? "" : "do $c$ begin perform set_config('request.jwt.claims', '" + JSON.stringify({ sub: u, synthetic: true, notSignedAuth: true }) + "', false); end $c$;\n";
const pre = (role, u) => "set role " + role + ";\n" + (u === undefined ? "" : claims(u));
function as(user, sql, role) { return psql(pre(role || "sim_authenticated", user) + sql); }
function asAsync(user, sql) { return psqlAsync(pre("sim_authenticated", user) + sql); }
function setup() { psql("drop database if exists " + DB, { db: "postgres" }); const c = psql("create database " + DB, { db: "postgres" }); if (!c.ok) throw new Error(c.err);
  for (const f of ["c10_a025_fixture_v1.sql", "c10_a025_scenarios_v1.sql"]) { const r = psql(fs.readFileSync(path.join(SQL, f), "utf8")); if (!r.ok) throw new Error(f + ": " + r.err); }
  const reg = spawnSync("node", [path.join(__dirname, "../../modules/simulation/tools/registry-sql.js")], { encoding: "utf8" }); const r2 = psql(reg.stdout); if (!r2.ok) throw new Error("registry: " + r2.err); }
const lit = o => "$j$" + JSON.stringify(o) + "$j$::jsonb";
module.exports = { ensureServer, stopServer, psql, as, asAsync, setup, lit, DB, SQL };
