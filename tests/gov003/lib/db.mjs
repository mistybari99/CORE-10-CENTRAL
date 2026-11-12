// Zero-dependency PostgreSQL helper for the GOV-003 isolated suites. Uses the `psql` binary only.
// Disposable resources only: every suite creates and drops its own database. No secrets are used.
import { spawn, spawnSync } from 'node:child_process';
import { readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const SQL_DIR = join(here, '..', '..', '..', 'internal', 'gov003', 'sql');
export const SEED = join(here, '..', 'fixtures', 'seed.sql');

const base = () => ({
  ...process.env,
  PGHOST: process.env.PGHOST || '127.0.0.1',
  PGPORT: process.env.PGPORT || '55432',
  PGUSER: process.env.PGUSER || 'postgres',
});

export class PgError extends Error {
  constructor(code, message, raw) { super(`${code}: ${message}`); this.code = code; this.detail = message; this.raw = raw; }
}
export const lit = (s) => (s === null || s === undefined) ? 'null' : `'${String(s).replace(/'/g, "''")}'`;
export const uuidLit = (s) => (s === null || s === undefined) ? 'null::uuid' : `${lit(s)}::uuid`;

function parseError(stderr) {
  const m = /ERROR:\s+([0-9A-Z]{5}):\s*([^\n]*)/.exec(stderr);
  return m ? new PgError(m[1], m[2], stderr) : new PgError('XXXXX', stderr.trim().split('\n')[0] || 'psql failure', stderr);
}
function args(db, extra = []) {
  return ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-d', db, ...extra];
}
function prelude({ role, sub } = {}) {
  let s = '';
  if (role) s += `set role ${role};\n`;
  if (sub) s += `set request.jwt.claim.sub = ${lit(sub)};\n`;
  return s;
}

/** Run SQL text as a session; returns stdout. Throws PgError with SQLSTATE on failure. */
export function exec(db, sql, ctx = {}) {
  const r = spawnSync('psql', args(db), { input: prelude(ctx) + sql, env: base(), encoding: 'utf8' });
  if (r.status !== 0) throw parseError(r.stderr || '');
  return r.stdout;
}
/** Run a SELECT-able query and return rows as objects (via json_agg). */
export function rows(db, query, ctx = {}) {
  const out = exec(db, `select coalesce(json_agg(t), '[]'::json) from (${query}) t;`, ctx).trim();
  return JSON.parse(out.split('\n').filter(Boolean).pop());
}
export const one = (db, query, ctx) => rows(db, query, ctx)[0];

/** Async independent connection (true separate PostgreSQL backend) for genuine concurrency races. */
export function execAsync(db, sql, ctx = {}) {
  return new Promise((resolve) => {
    const p = spawn('psql', args(db), { env: base() });
    let out = ''; let err = '';
    p.stdout.on('data', (d) => (out += d));
    p.stderr.on('data', (d) => (err += d));
    p.on('close', (code) => resolve(code === 0 ? { ok: true, out } : { ok: false, error: parseError(err), out }));
    p.stdin.end(prelude(ctx) + sql);
  });
}

export function adminExec(sql, dbName = 'postgres') {
  const r = spawnSync('psql', ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', dbName, '-c', sql], { env: base(), encoding: 'utf8' });
  if (r.status !== 0) throw parseError(r.stderr || '');
  return r.stdout;
}
export function serverVersion() { return adminExec('show server_version').trim(); }

export function migrationFiles() {
  return readdirSync(SQL_DIR).filter((f) => /^\d{3}_.*\.sql$/.test(f)).sort();
}
function runFile(db, file) {
  const r = spawnSync('psql', ['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-d', db, '-f', file],
    { env: base(), encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`migration failed: ${file}\n${r.stderr}`);
}
/** Fresh lifecycle: drop/create database, strict ordered migrations, deterministic seed. */
export function freshDb(name, { seed = true, only = null } = {}) {
  adminExec(`drop database if exists ${name} with (force)`);
  adminExec(`create database ${name}`);
  // `only` (e.g. ['000','010','020','030','040','050']) lets a feature owner test its own migration
  // against the core without depending on sibling migrations. Final CI always runs every file in order.
  for (const f of migrationFiles()) {
    if (only && !only.includes(f.slice(0, 3))) continue;
    runFile(name, join(SQL_DIR, f));
  }
  if (seed) runFile(name, SEED);
  return name;
}
export function dropDb(name) { try { adminExec(`drop database if exists ${name} with (force)`); } catch { /* ignore */ } }
