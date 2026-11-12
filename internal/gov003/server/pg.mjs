// GOV-003 zero-dependency PostgreSQL access through the `psql` binary. DEMO / NOT LIVE contract core.
//
// Safety model
//  * Parameters are NEVER string-interpolated into SQL by this module. Each value is delivered on psql's STDIN as
//    `\set <name> '<escaped>'` (so it never appears in argv or the process environment) and the SQL text refers to it
//    with psql's quoting operator :'name' (literal) - psql itself escapes the value. Values may be any size.
//  * SQL text must be a trusted constant. It is linted: no backslash (psql meta-commands such as \! are shell
//    escapes), no unquoted :name interpolation, no E'' strings, and every :'name' must be a supplied parameter.
//  * Per request: BEGIN; SET LOCAL statement_timeout/lock_timeout/idle timeouts; SET LOCAL ROLE <allow-listed role>;
//    set_config('request.jwt.claim.sub', <actor uuid>, true); then the query. A hard process timeout kills psql.
//  * Errors are projected to { code, detail }: detail is kept only for codes raised by the GOV-003 SQL core (G3xxx)
//    and scrubbed; for every other SQLSTATE a static message is used because PostgreSQL messages can echo parameter
//    values. Raw stderr, SQL text and parameter values are never exposed, logged or attached to errors.
//  * Connection comes from standard PG* environment variables (host/port default to the local test bed like
//    tests/gov003/lib/db.mjs: 127.0.0.1:55432). PGPASSWORD etc. are forwarded to the child only.
//  * null parameters are sent as '' (psql variables cannot be NULL): write nullif(:'name', '') in SQL.
//  * A simulated request.jwt.claim.sub is NOT signed GoTrue evidence. It is a trusted-boundary input for isolated tests.
import { spawn, spawnSync } from 'node:child_process';
import { scrubText } from './redact.mjs';

export class PgError extends Error {
  constructor(code, detail) {
    super(`${code}: ${detail}`);
    this.name = 'PgError';
    this.code = code;
    this.detail = detail;
  }
}

const ROLE_RE = /^[a-z_][a-z0-9_]{0,62}$/;
const PARAM_RE = /^[a-z][a-z0-9_]{0,40}$/;
const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
const DEFAULT_ROLES = Object.freeze(['c10g3_backend', 'c10g3_reader', 'c10g3_app']);

const STATIC_MESSAGES = {
  '57014': 'statement timeout',
  '42501': 'insufficient privilege',
  '23505': 'unique violation',
  '23503': 'foreign key violation',
  '23502': 'not-null violation',
  '23514': 'check violation',
  '22P02': 'invalid text representation',
  '22007': 'invalid datetime format',
  '22023': 'invalid parameter value',
  '40001': 'serialization failure',
  '40P01': 'deadlock detected',
  '55P03': 'lock not available',
  '42P01': 'undefined table',
  '42883': 'undefined function',
  '42601': 'syntax error',
  '25006': 'read-only transaction',
};

/** psql backslash-argument single-quote encoding: ' -> '', \ -> \\, control chars -> 3-digit octal. */
export function psqlQuote(value) {
  let out = "'";
  for (const ch of value) {
    const c = ch.codePointAt(0);
    if (ch === "'") out += "''";
    else if (ch === '\\') out += '\\\\';
    else if (c < 0x20 || c === 0x7f) out += '\\' + c.toString(8).padStart(3, '0');
    else out += ch;
  }
  return out + "'";
}

function hasLoneSurrogate(s) {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff) { const n = s.charCodeAt(i + 1); if (n >= 0xdc00 && n <= 0xdfff) { i++; continue; } return true; }
    if (c >= 0xdc00 && c <= 0xdfff) return true;
  }
  return false;
}

function paramText(name, v) {
  if (v === null || v === undefined) return '';
  let s;
  if (typeof v === 'string') s = v;
  else if (typeof v === 'number') { if (!Number.isFinite(v)) throw new PgError('PGPARAM', `parameter ${name} is not finite`); s = String(v); }
  else if (typeof v === 'bigint') s = v.toString();
  else if (typeof v === 'boolean') s = v ? 'true' : 'false';
  else if (v instanceof Date) { if (!Number.isFinite(v.getTime())) throw new PgError('PGPARAM', `parameter ${name} invalid date`); s = v.toISOString(); }
  else if (typeof v === 'object') s = JSON.stringify(v);
  else throw new PgError('PGPARAM', `parameter ${name} has unsupported type`);
  if (s.includes('\u0000') || hasLoneSurrogate(s)) throw new PgError('PGPARAM', `parameter ${name} is not valid text`);
  return s;
}

/**
 * Lint trusted SQL text. Returns the set of referenced parameter names. Throws PgError('PGLINT').
 * Quoted regions ('...', "...", $tag$...$tag$, comments) are skipped; psql variable refs :'x' and :"x" are collected.
 */
export function lintSql(sql) {
  if (typeof sql !== 'string' || sql.trim() === '') throw new PgError('PGLINT', 'sql must be a non-empty string');
  if (sql.includes('\u0000')) throw new PgError('PGLINT', 'sql contains NUL');
  const refs = new Set();
  const n = sql.length;
  let i = 0;
  while (i < n) {
    const c = sql[i];
    if (c === '\\') throw new PgError('PGLINT', 'backslash is not allowed in SQL text (psql meta-commands are shell escapes)');
    if (c === ':') {
      if (sql[i + 1] === ':') { i += 2; continue; }
      const m = /^:(['"])([a-z][a-z0-9_]*)\1/.exec(sql.slice(i, i + 64));
      if (m) { refs.add(m[2]); i += m[0].length; continue; }
      if (/[A-Za-z_{]/.test(sql[i + 1] || '')) throw new PgError('PGLINT', 'unquoted :name interpolation is not allowed; use :\'name\'');
      i++; continue;
    }
    if (c === "'") {
      if (i > 0 && /[eE]/.test(sql[i - 1]) && !/[A-Za-z0-9_]/.test(sql[i - 2] || ' ')) {
        throw new PgError('PGLINT', "E'' strings are not allowed");
      }
      i++;
      while (i < n) { if (sql[i] === "'") { if (sql[i + 1] === "'") { i += 2; continue; } break; } i++; }
      i++; continue;
    }
    if (c === '"') {
      i++;
      while (i < n) { if (sql[i] === '"') { if (sql[i + 1] === '"') { i += 2; continue; } break; } i++; }
      i++; continue;
    }
    if (c === '$') {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i, i + 80));
      if (m) {
        const end = sql.indexOf(m[0], i + m[0].length);
        if (end === -1) throw new PgError('PGLINT', 'unterminated dollar quote');
        i = end + m[0].length; continue;
      }
      i++; continue;
    }
    if (c === '-' && sql[i + 1] === '-') { const e = sql.indexOf('\n', i); i = e === -1 ? n : e + 1; continue; }
    if (c === '/' && sql[i + 1] === '*') { const e = sql.indexOf('*/', i + 2); if (e === -1) throw new PgError('PGLINT', 'unterminated comment'); i = e + 2; continue; }
    i++;
  }
  return refs;
}

function projectPgError(stderr, status, signal, timedOut) {
  if (timedOut) return new PgError('PGTIMEOUT', 'hard process timeout');
  const m = /(?:ERROR|FATAL):\s+([0-9A-Z]{5}):\s*([^\n]*)/.exec(stderr || '');
  if (m) {
    const code = m[1];
    if (code.startsWith('G3')) return new PgError(code, scrubText(m[2]).slice(0, 200));
    return new PgError(code, STATIC_MESSAGES[code] || 'database error');
  }
  if (/could not connect|connection to server|Connection refused|timeout expired|no such file or directory/i.test(stderr || '')) {
    return new PgError('PGCONN', 'could not connect to the database');
  }
  if (signal) return new PgError('PGKILLED', `psql terminated by ${signal}`);
  return new PgError('PGFAIL', `psql failed with status ${status}`);
}

/**
 * createPool({ database, host, port, user, allowedRoles, statementTimeoutMs, hardTimeoutGraceMs, maxConcurrent, maxOutputBytes, psqlPath, env })
 * Returns { query, queryAsync, config } - no persistent connections (one psql process per call, one transaction).
 */
export function createPool(options = {}) {
  const baseEnv = options.env || process.env;
  const cfg = Object.freeze({
    database: options.database || baseEnv.PGDATABASE,
    host: options.host || baseEnv.PGHOST || '127.0.0.1',
    port: String(options.port || baseEnv.PGPORT || '55432'),
    user: options.user || baseEnv.PGUSER || 'postgres',
    allowedRoles: Object.freeze([...(options.allowedRoles || DEFAULT_ROLES)]),
    statementTimeoutMs: Math.min(Math.max(Number(options.statementTimeoutMs ?? 5000), 100), 60000),
    hardTimeoutGraceMs: Math.max(0, Number(options.hardTimeoutGraceMs ?? 8000)),
    maxConcurrent: Math.max(1, Number(options.maxConcurrent ?? 8)),
    maxOutputBytes: Number(options.maxOutputBytes ?? 16 * 1024 * 1024),
    psqlPath: options.psqlPath || 'psql',
    requireRole: options.requireRole !== false,
  });
  if (!cfg.database || !/^[A-Za-z0-9_.-]{1,63}$/.test(cfg.database)) throw new PgError('PGCONFIG', 'a valid database name is required');
  for (const r of cfg.allowedRoles) if (!ROLE_RE.test(r)) throw new PgError('PGCONFIG', 'invalid role in allowedRoles');

  const childEnv = () => {
    const e = {};
    for (const [k, v] of Object.entries(baseEnv)) if (k.startsWith('PG') && typeof v === 'string') e[k] = v;
    if (baseEnv.PATH) e.PATH = baseEnv.PATH;
    Object.assign(e, { PGHOST: cfg.host, PGPORT: cfg.port, PGUSER: cfg.user, PGDATABASE: cfg.database,
      PGCLIENTENCODING: 'UTF8', PGCONNECT_TIMEOUT: '5', PGAPPNAME: 'c10-gov003' });
    delete e.PGOPTIONS; // never let ambient env widen role/timeouts
    return e;
  };

  function build(sqlText, params = {}, { role, actor, raw = false } = {}) {
    const refs = lintSql(sqlText);
    const names = Object.keys(params || {});
    for (const nme of names) {
      if (!PARAM_RE.test(nme) || nme.startsWith('g3_')) throw new PgError('PGPARAM', 'invalid parameter name');
    }
    for (const r of refs) if (!names.includes(r)) throw new PgError('PGLINT', `SQL references unsupplied parameter "${r}"`);
    if (role === undefined || role === null) {
      if (cfg.requireRole) throw new PgError('PGROLE', 'a role is required');
    } else if (!ROLE_RE.test(role) || !cfg.allowedRoles.includes(role)) {
      throw new PgError('PGROLE', 'role is not allow-listed');
    }
    if (actor !== undefined && actor !== null && (typeof actor !== 'string' || !UUID_RE.test(actor))) {
      throw new PgError('PGACTOR', 'actor must be a UUID');
    }
    const t = cfg.statementTimeoutMs;
    let s = '\\set ON_ERROR_STOP on\n';
    for (const nme of names) s += `\\set ${nme} ${psqlQuote(paramText(nme, params[nme]))}\n`;
    if (role) s += `\\set g3_role ${psqlQuote(role)}\n`;
    s += `\\set g3_actor ${psqlQuote(actor ? actor.toLowerCase() : '')}\n`;
    s += 'begin;\n';
    s += `set local statement_timeout = ${t};\nset local lock_timeout = ${Math.min(t, 3000)};\n`;
    s += `set local idle_in_transaction_session_timeout = ${t + 5000};\n`;
    if (role) s += 'set local role :"g3_role";\n';
    s += "select set_config('request.jwt.claim.sub', :'g3_actor', true) \\g /dev/null\n";
    const body = sqlText.trim().replace(/;+\s*$/, '');
    s += raw ? `${body};\n` : `select coalesce(json_agg(g3_rows), '[]'::json) from (${body}) g3_rows;\n`;
    s += 'commit;\n';
    return s;
  }
  const args = () => ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'];
  const parseOut = (out, raw) => {
    if (raw) return out;
    const text = out.trim();
    try { return JSON.parse(text); } catch { throw new PgError('PGRESULT', 'result was not valid JSON'); }
  };

  /** Synchronous: returns rows (array of objects). Throws PgError. */
  function query(sqlText, params, ctx = {}) {
    const script = build(sqlText, params, ctx);
    const r = spawnSync(cfg.psqlPath, args(), {
      input: script, env: childEnv(), encoding: 'utf8', timeout: cfg.statementTimeoutMs + cfg.hardTimeoutGraceMs,
      killSignal: 'SIGKILL', maxBuffer: cfg.maxOutputBytes,
    });
    if (r.error && r.error.code === 'ETIMEDOUT') throw projectPgError('', null, null, true);
    if (r.error && r.error.code === 'ENOBUFS') throw new PgError('PGOUTPUT', 'result too large');
    if (r.error) throw new PgError('PGSPAWN', 'could not start psql');
    if (r.status !== 0) throw projectPgError(r.stderr, r.status, r.signal, false);
    return parseOut(r.stdout, !!ctx.raw);
  }

  let active = 0; const waiters = [];
  const acquire = () => (active < cfg.maxConcurrent ? (active++, Promise.resolve()) : new Promise((res) => waiters.push(res)));
  const release = () => { const w = waiters.shift(); if (w) w(); else active--; };

  /** Asynchronous independent connection (a separate PostgreSQL backend per call): use for true concurrency. */
  async function queryAsync(sqlText, params, ctx = {}) {
    const script = build(sqlText, params, ctx);
    await acquire();
    try {
      return await new Promise((resolve, reject) => {
        const p = spawn(cfg.psqlPath, args(), { env: childEnv(), stdio: ['pipe', 'pipe', 'pipe'] });
        let out = ''; let err = ''; let timedOut = false; let tooBig = false;
        const timer = setTimeout(() => { timedOut = true; p.kill('SIGKILL'); }, cfg.statementTimeoutMs + cfg.hardTimeoutGraceMs);
        p.stdout.setEncoding('utf8'); p.stderr.setEncoding('utf8');
        p.stdout.on('data', (d) => { out += d; if (out.length > cfg.maxOutputBytes) { tooBig = true; p.kill('SIGKILL'); } });
        p.stderr.on('data', (d) => { if (err.length < 65536) err += d; });
        p.on('error', () => { clearTimeout(timer); reject(new PgError('PGSPAWN', 'could not start psql')); });
        p.on('close', (code, signal) => {
          clearTimeout(timer);
          if (tooBig) return reject(new PgError('PGOUTPUT', 'result too large'));
          if (code !== 0) return reject(projectPgError(err, code, signal, timedOut));
          try { resolve(parseOut(out, !!ctx.raw)); } catch (e) { reject(e); }
        });
        p.stdin.on('error', () => { /* psql exited early; close handler reports */ });
        p.stdin.end(script);
      });
    } finally { release(); }
  }

  return Object.freeze({ query, queryAsync, config: cfg });
}
