import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { writeFileSync, chmodSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPool, lintSql, psqlQuote, PgError } from '../../../internal/gov003/server/pg.mjs';
import { buildEnvelope, toSqlParams, APPEND_EVENT_SQL } from '../../../internal/gov003/server/envelope.mjs';
import { verifyChain } from '../../../internal/gov003/server/receipt.mjs';
import { projectSafeError } from '../../../internal/gov003/server/redact.mjs';
import { freshDb, dropDb } from '../lib/db.mjs';
import { T1, T2, B1, S1, U } from '../lib/ids.mjs';

const DB = 'g3_core_pg';
process.env.PGHOST ||= '127.0.0.1'; process.env.PGPORT ||= '55432'; process.env.PGUSER ||= 'postgres';
let pool;
const backend = (actor) => ({ role: 'c10g3_backend', actor });
const code = (c) => (e) => e instanceof PgError && e.code === c;

before(() => {
  freshDb(DB, { only: ['000', '010', '020', '030', '040'] });
  pool = createPool({ database: DB });
});
after(() => dropDb(DB));

const env = (i, extra = {}) => buildEnvelope({ tenant_id: T1, business_id: B1, site_id: S1, source_domain: 'pos', source_id: `sale-${i}`,
  source_version: 'v1', action: 'sale.created', event_time: '2026-11-12T10:00:00Z', correlation_id: `corr-${i}`, idempotency_key: `idem-pg-key-${i}`,
  payload: { status: 'open', count: String(i) }, reason_category: 'operational', ...extra });

test('lintSql: accepts parameterised SQL and skips quoted regions', () => {
  assert.deepEqual([...lintSql(`select :'a'::uuid, :"b", '12:30', $$ \\x :y $$, "c:d" -- :zz \\q\n /* :ww \\ */ from t where x::int = 1`)].sort(), ['a', 'b']);
});

test('lintSql: rejects backslash meta-commands, unquoted :name, E-strings, empty text', () => {
  for (const bad of ['select 1 \\! id', 'select 1\n\\q', 'select :x', 'select :{?x}', "select E'a'", '', '   ', 'select $$ open']) {
    assert.throws(() => lintSql(bad), code('PGLINT'), bad);
  }
  assert.doesNotThrow(() => lintSql("select 'it''s \\' ::text"));
});

test('psqlQuote encodes quotes, backslashes and control characters', () => {
  assert.equal(psqlQuote("a'b\\c\n"), "'a''b\\\\c\\012'");
});

test('hostile parameter values round-trip byte-exactly and cannot inject SQL or meta-commands', () => {
  const hostile = ["'; drop schema c10_gov003_demo cascade; --", '\\! touch /tmp/g3_pwned', 'a\nb\r\nc\td\u0001\u007f', ":foo :'bar' :\"baz\" $$ $x$",
    'é😀日本語', '\\', "''", '', ' lead and trail ', 'x'.repeat(300000), '\\g /dev/null\n\\q'];
  for (const v of hostile) {
    const r = pool.query("select :'v' as v, length(:'v') as len", { v }, { role: 'c10g3_reader' });
    assert.equal(r[0].v, v);
    assert.equal(r[0].len, [...v].length);
  }
  assert.equal(pool.query("select count(*)::int as n from pg_namespace where nspname = 'c10_gov003_demo'", {}, { role: 'c10g3_reader' })[0].n, 1);
});

test('null and typed parameters', () => {
  const r = pool.query(`select nullif(:'n', '') as n, :'i'::int + 1 as i, :'b'::boolean as b, (:'j'::jsonb)->>'k' as k, :'d'::timestamptz as d, :'big'::numeric as big`,
    { n: null, i: 41, b: true, j: { k: 'v' }, d: new Date(Date.UTC(2026, 0, 1)), big: 12345678901234567890n }, { role: 'c10g3_reader' });
  assert.equal(r[0].n, null); assert.equal(r[0].i, 42); assert.equal(r[0].b, true); assert.equal(r[0].k, 'v');
  assert.equal(r[0].big, 12345678901234567890);
  assert.throws(() => pool.query("select :'a'", { a: '\u0000' }, { role: 'c10g3_reader' }), code('PGPARAM'));
  assert.throws(() => pool.query("select :'a'", { a: '\ud800' }, { role: 'c10g3_reader' }), code('PGPARAM'));
  assert.throws(() => pool.query("select :'a'", { a: NaN }, { role: 'c10g3_reader' }), code('PGPARAM'));
  assert.throws(() => pool.query("select :'a'", { a: () => 1 }, { role: 'c10g3_reader' }), code('PGPARAM'));
});

test('parameter name, unsupplied reference and role allow-list rules', () => {
  assert.throws(() => pool.query("select :'a'", {}, { role: 'c10g3_reader' }), code('PGLINT'));
  for (const name of ['A', '1a', 'a-b', 'g3_role', 'g3_actor', 'x'.repeat(42)]) assert.throws(() => pool.query('select 1', { [name]: 'x' }, { role: 'c10g3_reader' }), code('PGPARAM'), name);
  assert.throws(() => pool.query('select 1', {}, {}), code('PGROLE'));
  assert.throws(() => pool.query('select 1', {}, { role: 'c10g3_owner' }), code('PGROLE'));
  assert.throws(() => pool.query('select 1', {}, { role: 'postgres' }), code('PGROLE'));
  assert.throws(() => pool.query('select 1', {}, { role: 'c10g3_reader"; reset role; --' }), code('PGROLE'));
  assert.throws(() => pool.query('select 1', {}, { role: 'c10g3_reader', actor: "x'; --" }), code('PGACTOR'));
  assert.throws(() => createPool({}), code('PGCONFIG'));
  assert.throws(() => createPool({ database: DB, allowedRoles: ['bad role'] }), code('PGCONFIG'));
  // role opt-in for owner/test fixtures is explicit
  const owner = createPool({ database: DB, allowedRoles: ['c10g3_owner'] });
  assert.equal(owner.query('select current_user as u', {}, { role: 'c10g3_owner' })[0].u, 'c10g3_owner');
});

test('per-request role and actor are applied per call and never leak between calls', () => {
  const q = "select current_user as u, c10_gov003_demo.actor_id() as a, current_setting('statement_timeout') as t";
  const a = pool.query(q, {}, { role: 'c10g3_reader', actor: U.bizOwnerB1.toUpperCase() });
  assert.equal(a[0].u, 'c10g3_reader'); assert.equal(a[0].a, U.bizOwnerB1); assert.equal(a[0].t, '5s');
  const b = pool.query(q, {}, { role: 'c10g3_reader' });
  assert.equal(b[0].a, null);
  const c = pool.query(q, {}, { role: 'c10g3_app', actor: U.unknown });
  assert.equal(c[0].a, null, 'unknown identity is not an actor');
});

test('app role has no table rights: static, value-free error', () => {
  assert.throws(() => pool.query('select * from c10_gov003_demo.audit_events', {}, { role: 'c10g3_app' }), (e) => e.code === '42501' && e.detail === 'insufficient privilege');
});

test('errors never expose parameter values, stderr, SQL text or stack-like data', () => {
  const secret = 'SuperSecretValue-9f8e7d6c';
  let err;
  try { pool.query("select :'v'::uuid", { v: secret }, { role: 'c10g3_reader' }); } catch (e) { err = e; }
  assert.ok(err instanceof PgError); assert.equal(err.code, '22P02'); assert.equal(err.detail, 'invalid text representation');
  assert.equal(JSON.stringify(err, Object.getOwnPropertyNames(err)).includes(secret), false);
  assert.equal(err.message.includes(secret), false);
  assert.deepEqual(Object.keys(err).sort(), ['code', 'detail', 'name']);
});

test('GOV-003 core codes keep a scrubbed detail: forged actor, scope denial, unauthenticated, payload not allowed', () => {
  const e = env(1);
  const p = toSqlParams(e);
  const forged = `select * from c10_gov003_demo.append_event(:'tenant_id'::uuid, :'business_id'::uuid, null, null, :'source_domain', :'source_id', :'source_version', :'action',
    :'event_time'::timestamptz, :'correlation_id', :'idempotency_key', :'payload'::jsonb, null, :'reason_category', :'forged'::uuid)`;
  assert.throws(() => pool.query(forged, { ...p, forged: U.tenantOwnerT1 }, backend(U.bizOwnerB1)), (x) => x.code === 'G3A01' && /forged_actor/.test(x.detail));
  assert.throws(() => pool.query(APPEND_EVENT_SQL, p, backend(U.unknown)), code('G3A05'));
  assert.throws(() => pool.query(APPEND_EVENT_SQL, p, backend(null)), code('G3A05'));
});

test('SAFE ERROR PROJECTION of a real database refusal', () => {
  const e = env(2, { tenant_id: T2 }); // business B1 does not belong to tenant T2 -> scope denied
  let err; try { pool.query(APPEND_EVENT_SQL, toSqlParams(e), backend(U.bizOwnerB1)); } catch (x) { err = x; }
  assert.equal(err.code, 'G3A02');
  const safe = projectSafeError(err, { correlationId: 'corr-2' });
  assert.equal(safe.error_code, 'SCOPE_DENIED'); assert.equal(safe.http_status, 403);
});

test('statement timeout is enforced by the server (57014) and the hard timeout kills a hung psql', () => {
  const fast = createPool({ database: DB, statementTimeoutMs: 100 });
  assert.throws(() => fast.query('select pg_sleep(3)', {}, { role: 'c10g3_reader' }), (e) => e.code === '57014' && e.detail === 'statement timeout');
  const dir = mkdtempSync(join(tmpdir(), 'g3pg-')); const fake = join(dir, 'psql');
  writeFileSync(fake, '#!/bin/sh\nsleep 30\n'); chmodSync(fake, 0o755);
  const hung = createPool({ database: DB, psqlPath: fake, statementTimeoutMs: 100, hardTimeoutGraceMs: 300 });
  const t0 = Date.now();
  assert.throws(() => hung.query('select 1', {}, { role: 'c10g3_reader' }), code('PGTIMEOUT'));
  assert.ok(Date.now() - t0 < 5000);
});

test('connection failure and missing binary map to static codes', () => {
  assert.throws(() => createPool({ database: DB, port: 1 }).query('select 1', {}, { role: 'c10g3_reader' }), code('PGCONN'));
  assert.throws(() => createPool({ database: DB, psqlPath: '/nonexistent/psql' }).query('select 1', {}, { role: 'c10g3_reader' }), code('PGSPAWN'));
});

test('raw mode returns stdout of an unwrapped statement', () => {
  const out = pool.query("select 'x' || :'a'", { a: 'y' }, { role: 'c10g3_reader', raw: true });
  assert.equal(out.trim(), 'xy');
});

test('queryAsync: genuine concurrency - 8 simultaneous identical appends store ONE event; same receipt for all', async () => {
  const e = env(10); const p = toSqlParams(e);
  const res = await Promise.all(Array.from({ length: 8 }, () => pool.queryAsync(APPEND_EVENT_SQL, p, backend(U.bizOwnerB1))));
  const created = res.filter((r) => r[0].outcome === 'created');
  assert.equal(created.length, 1);
  assert.equal(new Set(res.map((r) => r[0].receipt_id)).size, 1);
  assert.equal(res.filter((r) => r[0].replayed === true).length, 7);
  assert.equal(pool.query(`select count(*)::int n from c10_gov003_demo.audit_events where idempotency_key = :'k'`, { k: e.idempotency_key }, { role: 'c10g3_backend', actor: U.bizOwnerB1 })[0].n, 1);
  // same key, changed payload -> conflict
  const changed = env(10, { payload: { status: 'open', count: '999' } });
  await assert.rejects(pool.queryAsync(APPEND_EVENT_SQL, toSqlParams(changed), backend(U.bizOwnerB1)), (x) => x.code === 'G3C01');
});

test('end to end: appended chain read back through RLS verifies in Node (and agrees with SQL verify_chain)', async () => {
  for (let i = 20; i < 24; i++) pool.query(APPEND_EVENT_SQL, toSqlParams(env(i)), backend(U.bizOwnerB1));
  const ctx = { role: 'c10g3_reader', actor: U.bizOwnerB1 };
  const events = pool.query(`select * from c10_gov003_demo.audit_events where tenant_id = :'t'::uuid and business_id = :'b'::uuid order by stream_seq`, { t: T1, b: B1 }, ctx);
  assert.ok(events.length >= 5);
  const owner = createPool({ database: DB, allowedRoles: ['c10g3_owner'] });
  const receipts = owner.query(`select * from c10_gov003_demo.audit_receipts where tenant_id = :'t'::uuid and business_id = :'b'::uuid`, { t: T1, b: B1 }, { role: 'c10g3_owner' });
  const v = verifyChain(events, receipts);
  assert.deepEqual(v, { ok: true, checked: events.length, first_bad_seq: null, reason: null });
  const sqlV = pool.query(`select * from c10_gov003_demo.verify_chain(:'t'::uuid, :'b'::uuid)`, { t: T1, b: B1 }, ctx)[0];
  assert.equal(sqlV.ok, true); assert.equal(Number(sqlV.checked), events.length);
  // foreign principals read nothing
  assert.deepEqual(pool.query('select event_id from c10_gov003_demo.audit_events', {}, { role: 'c10g3_reader', actor: U.t2Owner }), []);
  assert.deepEqual(pool.query('select event_id from c10_gov003_demo.audit_events', {}, { role: 'c10g3_reader' }), []);
});

test('maxConcurrent bounds simultaneous psql processes', async () => {
  const small = createPool({ database: DB, maxConcurrent: 2 });
  const t0 = Date.now();
  await Promise.all(Array.from({ length: 6 }, () => small.queryAsync('select pg_sleep(0.4)', {}, { role: 'c10g3_reader' })));
  assert.ok(Date.now() - t0 >= 1150, `elapsed ${Date.now() - t0}`);
});
