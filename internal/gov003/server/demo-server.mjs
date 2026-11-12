// GOV-003 LOCAL-ONLY demo server: the JSON API (api.mjs) plus same-origin static files for the reviewer UI.
// DEMO / NOT LIVE - synthetic data. Refuses to start unless G3_DEMO=1. Binds 127.0.0.1 only.
//
// It builds its OWN disposable database (g3_demo, or g3_demo_test for tests) from the strict-ordered SQL migrations,
// the deterministic seed (2 tenants / 3 businesses / 4 sites / 9 inert identities) and a small deterministic demo
// fixture. No production URL, no secret, no service role, no deployment.
//
//   G3_DEMO=1 node internal/gov003/server/demo-server.mjs        (see internal/gov003/demo/README.md)
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { startApiServer, DEMO_MODE_HEADER } from './api.mjs';
import { securityHeaders } from './csp.mjs';
import { freshDb, dropDb, exec, lit, uuidLit } from '../../../tests/gov003/lib/db.mjs';
import { T1, T2, B1, B2, B3, S1, U } from '../../../tests/gov003/lib/ids.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const DEMO_DIR = join(here, '..', 'demo');
const CLIENT_DIR = join(here, '..', 'client');
export const DEMO_BANNER_LINE = 'DEMO / NOT LIVE — synthetic data';
export const ALLOWED_DATABASES = Object.freeze(['g3_demo', 'g3_demo_test']);
const S = 'c10_gov003_demo';

// ------------------------------------------------------------------------------------------------ static files
// Whitelist only: no directory listing, no path traversal, no query-driven file access.
const STATIC = Object.freeze({
  '/': [join(DEMO_DIR, 'index.html'), 'text/html; charset=utf-8'],
  '/index.html': [join(DEMO_DIR, 'index.html'), 'text/html; charset=utf-8'],
  '/app.js': [join(DEMO_DIR, 'app.js'), 'text/javascript; charset=utf-8'],
  '/app.css': [join(DEMO_DIR, 'app.css'), 'text/css; charset=utf-8'],
  '/favicon.svg': [join(DEMO_DIR, 'favicon.svg'), 'image/svg+xml'],
  '/client/api-client.js': [join(CLIENT_DIR, 'api-client.js'), 'text/javascript; charset=utf-8'],
});

export function createStaticHandler() {
  return async function serveStatic(req, res) {
    const base = { ...securityHeaders(), 'x-demo-mode': DEMO_MODE_HEADER };
    const host = String(req.headers.host || '').toLowerCase().replace(/:\d+$/, '');
    const pathname = new URL(req.url, 'http://127.0.0.1').pathname;
    const fail = (status, text) => { res.writeHead(status, { ...base, 'content-type': 'text/plain; charset=utf-8' }); res.end(text); };
    if (host !== '127.0.0.1' && host !== 'localhost') return fail(403, 'host not allowed');
    if (req.method !== 'GET' && req.method !== 'HEAD') return fail(405, 'method not allowed');
    const entry = Object.hasOwn(STATIC, pathname) ? STATIC[pathname] : null;
    if (!entry) return fail(404, 'not found');
    let data;
    try { data = await readFile(entry[0]); } catch { return fail(404, 'not found'); }
    res.writeHead(200, { ...base, 'content-type': entry[1], 'content-length': data.length });
    return res.end(req.method === 'HEAD' ? undefined : data);
  };
}

// ------------------------------------------------------------------------------------------------ demo fixture
const sha256 = (s) => createHash('sha256').update(s).digest('hex');
const SHA1 = '3d1c5a9e8b2f4a6c7d0e1f2a3b4c5d6e7f8a9b0c';
const SHA2 = '9f8e7d6c5b4a39281706f5e4d3c2b1a098765432';
const SHA3 = '5a5a5a5a6b6b6b6b7c7c7c7c8d8d8d8d9e9e9e9e';
const be = (sub) => ({ role: 'c10g3_backend', sub });

/**
 * Build (drop + create) a disposable demo database and load the deterministic demo fixture.
 * Event times are relative to `t0` so the stale-source rule behaves the same on every build.
 */
export function buildDemoDatabase(name, { t0 = new Date() } = {}) {
  if (!ALLOWED_DATABASES.includes(name)) throw new Error(`GOV-003 demo may only use ${ALLOWED_DATABASES.join(' / ')}`);
  freshDb(name); // strict-ordered migrations 000..120 + deterministic seed
  const at = (minutesAgo) => new Date(t0.getTime() - minutesAgo * 60000).toISOString();
  const ev = (o) => `select 1 from ${S}.append_event_logged(${uuidLit(o.tenant ?? T1)}, ${uuidLit(o.business ?? B1)}, ${uuidLit(o.site ?? null)}, null::uuid,
    ${lit(o.domain)}, ${lit(o.sid)}, 'v1', ${lit(o.action)}, ${lit(o.time)}::timestamptz, ${lit(o.idem)}, ${lit(o.idem)},
    ${lit(JSON.stringify(o.payload))}::jsonb, null::text, ${lit(o.reason ?? 'operational')}, null::uuid, null::uuid);`;

  // Business A: owner activity -----------------------------------------------------------------------------------
  const ownerEvents = [180, 120, 60, 30].map((m, i) => ev({
    domain: 'erp.orders', sid: `ORD-${1001 + i}`, action: 'order.created', time: at(m), idem: `demo-seed-order-00${i + 1}`,
    payload: { status: 'new', amount_minor: String(125000 + i * 15000), currency: 'bdt', channel: 'showroom', entity_ref: `ORD-${1001 + i}` } }));
  exec(name, ownerEvents.join('\n'), be(U.bizOwnerB1));

  // Business A: site staff activity that triggers advisory signals (duplicates, stale feed, sensitive command, retries)
  const dup = { amount_minor: '45000', currency: 'bdt', item_ref: 'ITEM-CAKE-01', quantity_milli: '1000' };
  const staffEvents = [
    ...[25, 24, 23].map((m, i) => ev({ site: S1, domain: 'pos.sales', sid: 'SALE-77', action: 'sale.recorded', time: at(m), idem: `demo-seed-dup-00${i + 1}`, payload: dup })),
    ev({ site: S1, domain: 'stock.feed', sid: 'FEED-1', action: 'stock.count', time: at(31 * 60), idem: 'demo-seed-feed-001', reason: 'inventory',
      payload: { item_ref: 'ITEM-CAKE-01', quantity_milli: '12000', unit: 'pcs' } }),
    ev({ site: S1, domain: 'stock.feed', sid: 'FEED-1', action: 'stock.count', time: at(30 * 60), idem: 'demo-seed-feed-002', reason: 'inventory',
      payload: { item_ref: 'ITEM-CAKE-01', quantity_milli: '11000', unit: 'pcs' } }),
    ev({ site: S1, domain: 'erp.approvals', sid: 'APR-9', action: 'approval.granted', time: at(20), idem: 'demo-seed-approval-001', reason: 'access',
      payload: { status: 'approved', entity_ref: 'APR-9' } }),
    // one retry loop: the same key, same payload, submitted four times (one create + three exact replays)
    ...[0, 1, 2, 3].map(() => ev({ site: S1, domain: 'pos.sales', sid: 'SALE-78', action: 'sale.recorded', time: at(40), idem: 'demo-seed-retry-001',
      payload: { amount_minor: '8000', currency: 'bdt', item_ref: 'ITEM-TEA-02', quantity_milli: '2000' } })),
  ];
  exec(name, staffEvents.join('\n'), be(U.staffS1));

  // Other scopes (foreign to a Business A owner): used to prove no cross-scope counts or rows ----------------------
  exec(name, ev({ business: B2, domain: 'erp.orders', sid: 'ORD-2001', action: 'order.created', time: at(50), idem: 'demo-seed-b2-001',
    payload: { status: 'new', amount_minor: '5000', currency: 'bdt' } }), be(U.bizOwnerB2));
  exec(name, [51, 52].map((m, i) => ev({ tenant: T2, business: B3, domain: 'erp.orders', sid: `ORD-300${i + 1}`, action: 'order.created', time: at(m),
    idem: `demo-seed-b3-00${i + 1}`, payload: { status: 'new', amount_minor: '7000', currency: 'bdt' } })).join('\n'), be(U.t2Owner));

  // Readiness (Story C): green CI on SHA1, source HEAD moved to SHA2; plus a feature with only simulated green on its head
  const prf = (feature, level, sha, run, idem) => `select 1 from ${S}.record_readiness_proof(${uuidLit(T1)}, ${uuidLit(B1)}, ${lit(feature)}, ${lit(level)},
    ${lit(sha)}, 'ci_isolated', ${lit(run)}, true, ${lit(sha256(`${feature}|${level}|${sha}`))}, 'pass', ${lit(idem)});`;
  const head = (feature, sha, idem) => `select 1 from ${S}.record_readiness_head(${uuidLit(T1)}, ${uuidLit(B1)}, ${lit(feature)}, ${lit(sha)}, ${lit(idem)});`;
  const reg = (feature, title, idem) => `select 1 from ${S}.register_readiness_feature(${uuidLit(T1)}, ${uuidLit(B1)}, ${lit(feature)}, ${lit(title)}, ${lit(idem)});`;
  exec(name, [
    reg('storyc.export-provenance', 'Export provenance (Story C: stale CI)', 'demo-seed-reg-001'),
    head('storyc.export-provenance', SHA1, 'demo-seed-head-001'),
    prf('storyc.export-provenance', 'code_built', SHA1, 'sim-ci-run-001', 'demo-seed-proof-001'),
    prf('storyc.export-provenance', 'isolated_test_pass', SHA1, 'sim-ci-run-001', 'demo-seed-proof-002'),
    head('storyc.export-provenance', SHA2, 'demo-seed-head-002'),
    reg('storyc.simulated-green', 'Canonical audit event (simulated isolated green only)', 'demo-seed-reg-002'),
    head('storyc.simulated-green', SHA3, 'demo-seed-head-003'),
    prf('storyc.simulated-green', 'code_built', SHA3, 'sim-ci-run-002', 'demo-seed-proof-003'),
    prf('storyc.simulated-green', 'isolated_test_pass', SHA3, 'sim-ci-run-002', 'demo-seed-proof-004'),
  ].join('\n'), be(U.bizOwnerB1));

  // Incident with an active hold (second owner reviews it: the placer cannot) -------------------------------------
  const retention = new Date(t0.getTime() + 30 * 86400000).toISOString();
  exec(name, `
    select 1 from ${S}.open_incident(${uuidLit(T1)}, ${uuidLit(B1)}, null::uuid, 'INC-DEMO-0001', 'high', 'security', 'demo-seed-inc-001');
    select 1 from ${S}.add_evidence(${uuidLit(T1)}, ${uuidLit(B1)}, 'INC-DEMO-0001', 'EV-LOG-0001', 'log_extract', ${lit(sha256('synthetic log extract 1'))}, 2048::bigint, 'src:demo-log', null::timestamptz, 'demo-seed-inc-002');
    select 1 from ${S}.add_evidence(${uuidLit(T1)}, ${uuidLit(B1)}, 'INC-DEMO-0001', 'EV-CSV-0001', 'export_csv', ${lit(sha256('synthetic export csv 1'))}, 4096::bigint, 'src:demo-export', null::timestamptz, 'demo-seed-inc-003');
    select 1 from ${S}.set_hold(${uuidLit(T1)}, ${uuidLit(B1)}, 'INC-DEMO-0001', null::text, 'HOLD-DEMO-0001', 'security_incident', ${lit(retention)}::timestamptz, 'demo-seed-inc-004');
  `, be(U.bizOwnerB1));
  exec(name, `select 1 from ${S}.review_hold(${uuidLit(T1)}, ${uuidLit(B1)}, 'INC-DEMO-0001', 'HOLD-DEMO-0001', 'approved', 'reviewed_ok', 'demo-seed-inc-005');`, be(U.bizOwnerB1Second));

  // Requirement trace snapshots (one valid, one deliberately invalid to show violations) --------------------------
  const goodTrace = { expected_requirement_count: 3, declared_requirement_ids: ['R1', 'R2', 'R3'],
    requirements: [{ id: 'R1', status: 'built', hard: true }, { id: 'R2', status: 'built', hard: true },
      { id: 'R3', status: 'deferred', hard: false, deferral_reason: 'needs signed GoTrue (blocked)' }],
    features: [{ id: 'F1', requirement_ids: ['R1'], head_sha: SHA1 }, { id: 'F2', requirement_ids: ['R2'], head_sha: SHA1 }],
    source_files: [{ path: 'internal/gov003/sql/030_append_event.sql', feature_id: 'F1' }, { path: 'internal/gov003/sql/100_export.sql', feature_id: 'F2' }],
    tests: [{ id: 'T1', feature_id: 'F1', passed: true, commit_sha: SHA1 }, { id: 'T2', feature_id: 'F2', passed: true, commit_sha: SHA1 }],
    releases: [] };
  const badTrace = { ...goodTrace, tests: [{ id: 'T1', feature_id: 'F1', passed: true }, { id: 'T2', feature_id: 'F2', passed: true, commit_sha: SHA1 }] };
  const imp = (snap, label, idem) => `select 1 from ${S}.import_trace_snapshot(${uuidLit(T1)}, ${uuidLit(B1)}, ${lit(JSON.stringify(snap))}::jsonb, ${lit(label)}, ${lit(idem)});`;
  exec(name, [imp(goodTrace, 'demo snapshot valid', 'demo-seed-trace-001'), imp(badTrace, 'demo snapshot invalid - test without exact sha', 'demo-seed-trace-002')].join('\n'), be(U.bizOwnerB1));

  // Grant review: owner approves the current catalog as the baseline, THEN a simulated drift is applied by the DB
  // owner role so that the diff has an advisory finding to show. (Only in this disposable database.)
  exec(name, `select 1 from ${S}.record_baseline(${uuidLit(T1)}, ${uuidLit(B1)}, 'demo-seed-baseline-001');`, be(U.bizOwnerB1));
  exec(name, `grant select on ${S}.v_audit_events to c10g3_app;`, { role: 'c10g3_owner' });
  return name;
}

// ------------------------------------------------------------------------------------------------ start
export async function startDemoServer({ env = process.env, database = 'g3_demo', port = 0, log, rebuild = true } = {}) {
  if (env.G3_DEMO !== '1') throw new Error('refusing to start: set G3_DEMO=1 (this is a DEMO / NOT LIVE local server)');
  if (!ALLOWED_DATABASES.includes(database)) throw new Error(`database must be one of ${ALLOWED_DATABASES.join(', ')}`);
  if (rebuild) buildDemoDatabase(database);
  const srv = await startApiServer({ env, database, port, log, fallback: createStaticHandler() });
  return { ...srv, database, drop: () => dropDb(database) };
}

async function main() {
  if (process.env.G3_DEMO !== '1') {
    process.stderr.write('Refusing to start: G3_DEMO=1 is required. This is a DEMO / NOT LIVE local server (synthetic data, 127.0.0.1 only).\n');
    process.exit(2);
  }
  const database = process.env.G3_DEMO_DB || 'g3_demo';
  const port = Number(process.env.G3_DEMO_PORT || 8787);
  process.stdout.write(`${DEMO_BANNER_LINE}\nBuilding disposable database ${database} (migrations + seed + demo fixture) ...\n`);
  const srv = await startDemoServer({ env: process.env, database, port, log: (m) => process.stderr.write(`[g3-demo] ${m}\n`) });
  process.stdout.write(`${DEMO_BANNER_LINE}\nListening on ${srv.url}  (127.0.0.1 only, Ctrl+C to stop)\nDatabase: ${database} (disposable; rebuilt on every start)\n`);
  const stop = async () => { await srv.close(); process.exit(0); };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => { process.stderr.write(`demo server failed: ${String(e && e.message).split('\n')[0]}\n`); process.exit(1); });
}
