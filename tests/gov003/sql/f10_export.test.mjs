// Feature 10 export-provenance: scoped CSV export, byte-hash receipt, audit receipt, idempotency, parity with the Node writer.
// Fresh disposable databases only (g3_f1011_*). Simulated request.jwt.claim.sub identities are NOT signed GoTrue evidence.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { freshDb, dropDb, rows, one, exec, execAsync, adminExec, lit, uuidLit } from '../lib/db.mjs';
import { T1, T2, B1, B2, B3, U } from '../lib/ids.mjs';
import {
  auditExportCsv, parseCsv, normalizeFilter, exportReceiptDigest, sha256Hex, csvCell, payloadText, looksSecret,
  PAYLOAD_ALLOWLIST, verifyExportBytes,
} from '../../../internal/gov003/server/csv-export.mjs';

const DB = 'g3_f1011_export';
const DB_TAMPER = 'g3_f1011_export_tamper';
const DB_LIMITS = 'g3_f1011_export_limits';
const DB_INJECT = 'g3_f1011_export_inject';
const ONLY = ['000', '010', '020', '030', '040', '100'];
const FIXTURE = new URL('../fixtures/f10_11_events.sql', import.meta.url).pathname;
const INJECT = new URL('../fixtures/f10_11_inject.sql', import.meta.url).pathname;

const be = (sub) => ({ role: 'c10g3_backend', sub });
const rd = (sub) => ({ role: 'c10g3_reader', sub });
const own = { role: 'c10g3_owner' };
let n = 0;
const key = (p = 'exp') => `${p}-${String(++n).padStart(6, '0')}`;
const code = (fn) => { try { fn(); } catch (e) { return e.code; } return null; };
const errOf = (fn) => { try { fn(); } catch (e) { return e; } return null; };
const ISO = (c) => `to_char(${c} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;
const hexText = (s) => `convert_from(decode('${Buffer.from(s, 'utf8').toString('hex')}', 'hex'), 'UTF8')`;
const ts = (v) => (v == null ? 'null::timestamptz' : `${lit(v)}::timestamptz`);

function runSqlFile(db, file) {
  const r = spawnSync('psql', ['-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', db, '-f', file], {
    env: { ...process.env, PGHOST: process.env.PGHOST || '127.0.0.1', PGPORT: process.env.PGPORT || '55432', PGUSER: process.env.PGUSER || 'postgres' },
    encoding: 'utf8',
  });
  if (r.status !== 0) throw new Error(`fixture failed: ${file}\n${r.stderr}`);
}
function seedFixture(db) { runSqlFile(db, FIXTURE); }
const exportSql = (o = {}) => `select * from c10_gov003_demo.export_audit_csv(
  p_tenant => ${uuidLit(o.t ?? T1)}, p_business => ${uuidLit(o.b ?? B1)}, p_idem => ${lit(o.idem)},
  p_from => ${ts(o.from)}, p_to => ${ts(o.to)}, p_action => ${lit(o.action)}, p_source_domain => ${lit(o.domain)},
  p_max_rows => ${o.max ?? 10000}, p_claimed_actor => ${uuidLit(o.claimed)})`;
const exp = (sub, o = {}, db = DB) => one(db, exportSql({ idem: key(), ...o }), be(sub));
const receiptRow = (db, id, sub = U.bizOwnerB1) =>
  one(db, `select r.*, ${ISO('r.issued_at')} as issued_iso from c10_gov003_demo.v_export_receipts r where export_receipt_id = ${uuidLit(id)}`, rd(sub));
const journal = (db, biz, maxSeq, sub) => rows(db, `select event_id, stream_seq, ${ISO('event_time')} as event_time, action, source_domain, source_id,
  source_version, receipt_id, event_digest, payload from c10_gov003_demo.v_audit_events
  where business_id = ${uuidLit(biz)} and stream_seq <= ${maxSeq} order by stream_seq`, rd(sub));
const countOwner = (db, table, where = 'true') => Number(one(db, `select count(*)::int as c from c10_gov003_demo.${table} where ${where}`, own).c);

before(() => {
  freshDb(DB, { only: ONLY }); seedFixture(DB);
});
after(() => { for (const d of [DB, DB_TAMPER, DB_LIMITS, DB_INJECT]) dropDb(d); });

// ------------------------------------------------------------------------------------------------ positive + receipt
test('f10 positive: owner export returns filtered rows, the byte hash, a durable export receipt and an audit receipt', () => {
  const r = exp(U.bizOwnerB1, { idem: key('first') });
  assert.equal(r.outcome, 'created'); assert.equal(r.replayed, false); assert.equal(r.row_count, 5);
  const recs = parseCsv(r.csv_text);
  assert.equal(recs.length, 6);
  assert.deepEqual(recs[0], ['event_id', 'stream_seq', 'event_time', 'action', 'source_domain', 'source_id', 'source_version', 'receipt_id', 'event_digest', 'payload_fields']);
  assert.ok(r.csv_text.endsWith('\r\n'));
  assert.equal(r.byte_sha256, sha256Hex(r.csv_text));
  assert.equal(r.byte_length, Buffer.byteLength(r.csv_text, 'utf8'));
  const rc = receiptRow(DB, r.export_receipt_id);
  assert.equal(rc.actor_id, U.bizOwnerB1); assert.equal(rc.tenant_id, T1); assert.equal(rc.business_id, B1);
  assert.equal(rc.row_count, 5); assert.equal(rc.byte_sha256, r.byte_sha256); assert.equal(rc.byte_length, r.byte_length);
  assert.equal(rc.csv_spec, 'g3csv1'); assert.equal(rc.report_id, 'audit_journal_v1'); assert.equal(rc.source_seq, 5);
  assert.match(rc.source_version, /^seq5\.[0-9a-f]{16}$/);
  const last = one(DB, `select event_digest from c10_gov003_demo.v_audit_events where business_id = '${B1}' and stream_seq = 5`, rd(U.bizOwnerB1));
  assert.equal(rc.source_version, `seq5.${last.event_digest.slice(0, 16)}`);
  const nf = normalizeFilter();
  assert.equal(rc.filter_sha256, nf.filterSha256); assert.deepEqual(rc.filter_params, nf.filter);
  assert.ok(Date.now() - Date.parse(rc.issued_at) < 60000);
  const ev = one(DB, `select *, ${ISO('event_time')} as time_iso from c10_gov003_demo.v_audit_events where event_id = '${rc.audit_event_id}'`, rd(U.bizOwnerB1));
  assert.equal(ev.action, 'export.csv'); assert.equal(ev.source_domain, 'gov003.export'); assert.equal(ev.reason_category, 'export');
  assert.equal(ev.actor_id, U.bizOwnerB1); assert.equal(ev.source_version, rc.source_version); assert.equal(ev.receipt_id, rc.audit_receipt_id);
  assert.deepEqual(Object.keys(ev.payload).sort(), ['artifact_sha256', 'filter_ref', 'receipt_ref', 'report_id', 'row_count']);
  assert.equal(ev.payload.artifact_sha256, r.byte_sha256); assert.equal(ev.payload.row_count, '5');
  assert.equal(ev.payload.filter_ref, rc.filter_sha256); assert.equal(ev.payload.receipt_ref, `g3x:${r.export_receipt_id}`);
  assert.equal(ev.payload.report_id, 'audit_journal_v1');
  // the receipt digest is reproducible outside the database
  assert.equal(rc.receipt_digest, exportReceiptDigest({
    exportReceiptId: rc.export_receipt_id, tenantId: T1, businessId: B1, actorId: U.bizOwnerB1, idempotencyKey: rc.idempotency_key,
    filterSha256: rc.filter_sha256, sourceSeq: rc.source_seq, sourceVersion: rc.source_version, rowCount: rc.row_count,
    byteSha256: rc.byte_sha256, byteLength: rc.byte_length, auditEventDigest: ev.event_digest, issuedAt: rc.issued_iso,
  }));
  assert.equal(one(DB, `select ok from c10_gov003_demo.verify_chain('${T1}', '${B1}')`, rd(U.bizOwnerB1)).ok, true);
});

test('f10 tenant owner may export a business of their tenant; the export is attributed to the tenant owner', () => {
  const r = exp(U.tenantOwnerT1, { action: 'sales.sale' });
  assert.equal(r.row_count, 1);
  assert.equal(receiptRow(DB, r.export_receipt_id).actor_id, U.tenantOwnerT1);
});

test('f10 exported audit event contains no PII, secrets or free text (allowlisted fields only)', () => {
  const r = exp(U.bizOwnerB1, { action: 'export.csv' });
  for (const rec of parseCsv(r.csv_text).slice(1)) {
    assert.ok(!looksSecret(rec[9]), rec[9]);
    for (const part of rec[9].split(';')) assert.ok(PAYLOAD_ALLOWLIST.includes(part.split('=')[0]), part);
  }
});

// ------------------------------------------------------------------------------------------------ Node/SQL parity
test('f10 parity: SQL CSV bytes are identical to the Node writer for the same journal rows', () => {
  const r = exp(U.bizOwnerB1);
  const rc = receiptRow(DB, r.export_receipt_id);
  const node = auditExportCsv(journal(DB, B1, rc.source_seq, U.bizOwnerB1));
  assert.equal(node.rowCount, r.row_count);
  assert.equal(node.text, r.csv_text);
  assert.equal(node.sha256, r.byte_sha256);
  assert.equal(node.byteLength, r.byte_length);
  assert.ok(Buffer.compare(node.bytes, Buffer.from(r.csv_text, 'utf8')) === 0);
  assert.equal(verifyExportBytes({ byte_sha256: rc.byte_sha256, byte_length: rc.byte_length }, node.bytes).ok, true);
});

const CELLS = [
  '', 'plain', 'a,b', 'say "hi"', 'l1\r\nl2', 'l1\rl2', 'l1\nl2', '=1+1', '+1', '-1', '@x', '\t=x', '\r=x', '\n+x', ' =x', "'=x",
  'a=b+c-d@e', 'e\u0301', '\u00E9', 'a\u202Eb\u2066c\u200Bd\uFEFFe\u00ADf', 'a\u0007b\u007Fc\u0085d\u2028e\u2029f', '\u202E=1+1',
  '\u0995\u09BE\u099C', '\u{1F600} smile', '\u{1F468}\u200D\u{1F469}', 'tab\there', '-5', '1+1', '=HYPERLINK("http://x","y")',
  'x'.repeat(2048), `=${'x'.repeat(100)}`, '"', ',', '""', '\u00C5\u212B', 'q\u0301\u0323',
];
test('f10 parity: g3_csv_cell (SQL) equals csvCell (Node) on a hostile corpus, including formula/CR/LF/Unicode cases', () => {
  const q = CELLS.map((s, i) => `select ${i} as i, encode(convert_to(c10_gov003_demo.g3_csv_cell(${hexText(s)}), 'UTF8'), 'hex') as h`).join(' union all ');
  const out = rows(DB, `${q} order by i`, be(U.bizOwnerB1));
  assert.equal(out.length, CELLS.length);
  for (const o of out) assert.equal(Buffer.from(o.h, 'hex').toString('utf8'), csvCell(CELLS[o.i]), JSON.stringify(CELLS[o.i]));
});
test('f10 parity: integer cells and oversize/invalid cells fail identically (G3A03)', () => {
  assert.equal(one(DB, `select c10_gov003_demo.g3_csv_cell('42', 'int') as v`, be(U.bizOwnerB1)).v, csvCell('42', 'int'));
  for (const bad of ['-1', '1.5', '', '=1']) {
    assert.equal(code(() => exec(DB, `select c10_gov003_demo.g3_csv_cell(${lit(bad)}, 'int')`, be(U.bizOwnerB1))), 'G3A03', bad);
  }
  assert.equal(code(() => exec(DB, `select c10_gov003_demo.g3_csv_cell(repeat('a', 2049))`, be(U.bizOwnerB1))), 'G3A03');
  assert.equal(one(DB, `select length(c10_gov003_demo.g3_csv_cell(repeat('a', 2048))) as l`, be(U.bizOwnerB1)).l, 2048);
});
const PAYLOADS = [
  { item_ref: 'sku-1', quantity_milli: '5000' }, { amount_minor: '-500', currency: 'bdt' }, { item_ref: '=cmd', entity_ref: '+1', source_ref: '@x', doc_ref: '-abc' },
  { item_ref: 'a;b=c' }, { entity_ref: 'a@b.com', note_code: 'ok' }, { password: 'x', item_ref: 'sku' }, { item_ref: '4111111111111111' },
  { status: 'ok', count: '-5', amount_minor: '12' }, { item_ref: null }, {}, { note_code: '\t=1', doc_ref: 'a\r\nb' },
];
test('f10 parity: g3_csv_payload_text (SQL) equals payloadText (Node) and the PII/secret allowlist matches payload_allowlist', () => {
  const q = PAYLOADS.map((p, i) => `select ${i} as i, encode(convert_to(c10_gov003_demo.g3_csv_payload_text(${lit(JSON.stringify(p))}::jsonb), 'UTF8'), 'hex') as h`).join(' union all ');
  for (const o of rows(DB, `${q} order by i`, be(U.bizOwnerB1))) {
    assert.equal(Buffer.from(o.h, 'hex').toString('utf8'), payloadText(PAYLOADS[o.i]), JSON.stringify(PAYLOADS[o.i]));
  }
  const sqlFields = rows(DB, 'select field_name from c10_gov003_demo.payload_allowlist order by field_name', own).map((r) => r.field_name);
  assert.deepEqual(sqlFields, [...PAYLOAD_ALLOWLIST].sort());
});
test('f10 parity: looksSecret (Node) equals looks_secret (SQL) on a corpus', () => {
  const corpus = ['eyJhbGciOiJIUzI1NiJ9', 'Bearer abc', 'my password', 'api-key', 'x@y.io', '4111111111111111', '123456789', 'a\n  at f (x)',
    'sku-1', 'abc123', '12345678', 'g3x:00000000-0000-4000-8000-0000000000aa', 'a'.repeat(64), 'service_role', 'TOKEN', 'private-key', '', 'Authorization'];
  const q = corpus.map((s, i) => `select ${i} as i, c10_gov003_demo.looks_secret(${hexText(s)}) as b`).join(' union all ');
  for (const o of rows(DB, `${q} order by i`, own)) assert.equal(looksSecret(corpus[o.i]), o.b, JSON.stringify(corpus[o.i]));
});

// ------------------------------------------------------------------------------------------------ filters
test('f10 filters: time window, action and source domain are applied and recorded exactly', () => {
  const w = exp(U.bizOwnerB1, { from: '2026-10-02T00:00:00Z', to: '2026-10-04T00:00:00Z' });
  assert.deepEqual(parseCsv(w.csv_text).slice(1).map((r) => r[5]), ['sku-2', 'sale-1001']);
  assert.deepEqual(receiptRow(DB, w.export_receipt_id).filter_params,
    normalizeFilter({ from: '2026-10-02T00:00:00Z', to: '2026-10-04T00:00:00Z' }).filter);
  const a = exp(U.bizOwnerB1, { action: 'sales.refund' });
  assert.equal(a.row_count, 1);
  assert.equal(parseCsv(a.csv_text)[1][5], "'-refund-7");           // real path: leading '-' neutralized
  assert.equal(parseCsv(a.csv_text)[1][9], 'amount_minor=-500;currency=bdt;reason_code=customer_return');
  const d = exp(U.bizOwnerB1, { domain: 'sales' });
  assert.equal(d.row_count, 2);
  const none = exp(U.bizOwnerB1, { action: 'nothing.here' });
  assert.equal(none.row_count, 0);
  assert.equal(none.csv_text, 'event_id,stream_seq,event_time,action,source_domain,source_id,source_version,receipt_id,event_digest,payload_fields\r\n');
  assert.equal(none.byte_sha256, sha256Hex(none.csv_text));
  assert.equal(receiptRow(DB, none.export_receipt_id).row_count, 0); // zero-row exports are still receipted
});

test('f10 filter normalization: SQL filter hash equals the Node normalizeFilter hash for several parameter sets', () => {
  for (const o of [{ action: 'stock.adjust' }, { domain: 'stock', max: 77 }, { from: '2026-10-01T00:00:00Z' }, { to: '2026-12-01T00:00:00Z', action: 'sales.sale' }]) {
    const r = exp(U.bizOwnerB1, o);
    const nf = normalizeFilter({ from: o.from ?? null, to: o.to ?? null, action: o.action ?? null, sourceDomain: o.domain ?? null, maxRows: o.max ?? 10000 });
    assert.equal(r.filter_sha256, nf.filterSha256, JSON.stringify(o));
  }
});

// ------------------------------------------------------------------------------------------------ idempotency
test('f10 idempotency: same key + same normalized filter returns the SAME receipt and bytes; changed filter is G3C01', () => {
  const k = key('idem');
  const a = exp(U.bizOwnerB1, { idem: k, action: 'stock.adjust' });
  const before = countOwner(DB, 'export_receipts');
  const evBefore = countOwner(DB, 'audit_events', `tenant_id = '${T1}' and business_id = '${B1}' and action = 'export.csv'`);
  // new journal rows after the first export must not change a replay (it is bound to its source snapshot)
  exp(U.bizOwnerB1, { action: 'stock.adjust' });
  const b = exp(U.bizOwnerB1, { idem: k, action: 'stock.adjust' });
  assert.equal(b.outcome, 'replayed'); assert.equal(b.replayed, true);
  assert.equal(b.export_receipt_id, a.export_receipt_id); assert.equal(b.audit_receipt_id, a.audit_receipt_id);
  assert.equal(b.csv_text, a.csv_text); assert.equal(b.byte_sha256, a.byte_sha256); assert.equal(b.receipt_digest, a.receipt_digest);
  assert.equal(b.issued_at, a.issued_at);
  assert.equal(countOwner(DB, 'export_receipts'), before + 1);                       // only the extra exp() above
  assert.equal(countOwner(DB, 'audit_events', `tenant_id = '${T1}' and business_id = '${B1}' and action = 'export.csv'`), evBefore + 1);
  // changed filters under the same key
  assert.equal(code(() => exp(U.bizOwnerB1, { idem: k, action: 'sales.sale' })), 'G3C01');
  assert.equal(code(() => exp(U.bizOwnerB1, { idem: k, action: 'stock.adjust', max: 99 })), 'G3C01');
  assert.equal(code(() => exp(U.bizOwnerB1, { idem: k, action: 'stock.adjust', from: '2026-01-01T00:00:00Z' })), 'G3C01');
  assert.equal(code(() => exp(U.bizOwnerB1, { idem: k })), 'G3C01');
  // key used by another actor cannot hijack the receipt
  assert.equal(code(() => exp(U.tenantOwnerT1, { idem: k, action: 'stock.adjust' })), 'G3C01');
  // a different key is a new export
  const c = exp(U.bizOwnerB1, { action: 'stock.adjust' });
  assert.notEqual(c.export_receipt_id, a.export_receipt_id);
});

test('f10 idempotency across businesses: the key space is per (tenant, business)', () => {
  const k = key('sep');
  const a = exp(U.bizOwnerB1, { idem: k });
  const b = exp(U.bizOwnerB2, { idem: k, b: B2 });
  assert.notEqual(a.export_receipt_id, b.export_receipt_id);
  assert.equal(b.row_count >= 2, true);
});

test('f10 REAL two-process concurrency: two independent PostgreSQL backends exporting with one key produce ONE receipt', async () => {
  const k = key('race');
  const sql = `select outcome || '|' || export_receipt_id || '|' || audit_receipt_id || '|' || byte_sha256 || '|' || row_count from c10_gov003_demo.export_audit_csv(
    p_tenant => '${T1}', p_business => '${B1}', p_idem => '${k}', p_action => 'stock.adjust')`;
  const pids = await Promise.all([execAsync(DB, 'select pg_backend_pid()', be(U.bizOwnerB1)), execAsync(DB, 'select pg_backend_pid()', be(U.bizOwnerB1))]);
  assert.ok(pids[0].ok && pids[1].ok);
  const [a, b] = await Promise.all([execAsync(DB, sql, be(U.bizOwnerB1)), execAsync(DB, sql, be(U.bizOwnerB1))]);
  assert.ok(a.ok && b.ok, JSON.stringify([a.error?.message, b.error?.message]));
  const pa = a.out.trim().split('|'); const pb = b.out.trim().split('|');
  assert.deepEqual([pa[0], pb[0]].sort(), ['created', 'replayed']);
  assert.equal(pa[1], pb[1]); assert.equal(pa[2], pb[2]); assert.equal(pa[3], pb[3]); assert.equal(pa[4], pb[4]);
  assert.equal(countOwner(DB, 'export_receipts', `idempotency_key = '${k}'`), 1);
  assert.equal(countOwner(DB, 'audit_events', `idempotency_key = 'export.${k}'`), 1);
});

test('f10 REAL concurrency with different filters under one key: exactly one wins, the other gets G3C01', async () => {
  const k = key('race2');
  const mk = (action) => `select export_receipt_id from c10_gov003_demo.export_audit_csv(p_tenant => '${T1}', p_business => '${B1}', p_idem => '${k}', p_action => '${action}')`;
  const [a, b] = await Promise.all([execAsync(DB, mk('stock.adjust'), be(U.bizOwnerB1)), execAsync(DB, mk('sales.sale'), be(U.bizOwnerB1))]);
  assert.equal([a, b].filter((x) => x.ok).length, 1);
  const loser = [a, b].find((x) => !x.ok);
  assert.equal(loser.error.code, 'G3C01');
  assert.equal(countOwner(DB, 'export_receipts', `idempotency_key = '${k}'`), 1);
});

// ------------------------------------------------------------------------------------------------ authorization / no leaks
test('f10 scope: T2, other business owner, site-only staff, investor, revoked, support, unknown and anonymous are denied with G3A02/G3A05', () => {
  const baseReceipts = countOwner(DB, 'export_receipts'); const baseEvents = countOwner(DB, 'audit_events');
  const denied = [U.t2Owner, U.bizOwnerB2, U.staffS1, U.investorB1, U.revokedB1, U.support];
  for (const sub of denied) assert.equal(code(() => exp(sub)), 'G3A02', sub);
  assert.equal(code(() => exp(U.t2Owner, { t: T2, b: B1 })), 'G3A02');             // own tenant id + foreign business
  assert.equal(code(() => exp(U.tenantOwnerT1, { t: T2, b: B3 })), 'G3A02');       // owner of T1 asking for T2/B3
  assert.equal(code(() => exp(U.tenantOwnerT1, { t: T1, b: B3 })), 'G3A02');       // business of another tenant under own tenant id
  assert.equal(code(() => exp(U.tenantOwnerT1, { b: '00000000-0000-4000-8000-000000000000' })), 'G3A02'); // nonexistent business
  assert.equal(code(() => exp(U.unknown)), 'G3A05');
  assert.equal(code(() => exec(DB, exportSql({ idem: key() }), { role: 'c10g3_backend' })), 'G3A05');
  assert.equal(countOwner(DB, 'export_receipts'), baseReceipts); assert.equal(countOwner(DB, 'audit_events'), baseEvents);
});

test('f10 scope: a denied caller learns nothing about foreign tenants (identical error for foreign and nonexistent business)', () => {
  const foreign = errOf(() => exp(U.t2Owner, { t: T1, b: B1 }));
  const ghost = errOf(() => exp(U.t2Owner, { t: T1, b: '00000000-0000-4000-8000-0000000000aa' }));
  assert.equal(foreign.code, 'G3A02'); assert.equal(foreign.detail, ghost.detail);
  assert.doesNotMatch(foreign.raw, /row_count|[0-9]+ rows|b1-only-marker/);
});

test('f10 scope: owner of T2 exports only their business; no T1 row, marker or count appears', () => {
  const r = exp(U.t2Owner, { t: T2, b: B3 });
  assert.equal(r.row_count, 2);
  assert.ok(!r.csv_text.includes('b1-only-marker') && !r.csv_text.includes('b2-sku') && !r.csv_text.includes('sale-1001'));
  assert.deepEqual(parseCsv(r.csv_text).slice(1).map((x) => x[5]), ['b3-marker-1', 'b3-sale-1']);
  const b2 = exp(U.bizOwnerB2, { b: B2, action: 'stock.adjust' });
  assert.deepEqual(parseCsv(b2.csv_text).slice(1).map((x) => x[5]), ['b2-sku-1', 'b2-sku-2']);
  assert.ok(!b2.csv_text.includes('b3-marker') && !b2.csv_text.includes('b1-only-marker'));
});

test('f10 scope: scoped receipt views show nobody else\'s receipts or counts', () => {
  exp(U.bizOwnerB1, { action: 'stock.adjust' });
  const mine = rows(DB, 'select export_receipt_id, business_id from c10_gov003_demo.v_export_receipts', rd(U.bizOwnerB1));
  assert.ok(mine.length > 0 && mine.every((x) => x.business_id === B1));
  for (const sub of [U.t2Owner, U.staffS1, U.investorB1, U.revokedB1, U.support, U.bizOwnerB2]) {
    assert.equal(rows(DB, `select 1 from c10_gov003_demo.v_export_receipts where business_id = '${B1}'`, rd(sub)).length, 0, sub);
    assert.equal(rows(DB, `select 1 from c10_gov003_demo.v_export_receipts where business_id = '${B1}'`, be(sub)).length, 0, sub);
  }
  for (const sub of [U.staffS1, U.investorB1, U.revokedB1, U.support, U.unknown]) {
    assert.equal(rows(DB, 'select 1 from c10_gov003_demo.v_export_receipts', rd(sub)).length, 0, sub);
  }
  assert.ok(rows(DB, 'select business_id from c10_gov003_demo.v_export_receipts', rd(U.t2Owner)).every((x) => x.business_id === B3));
  assert.ok(rows(DB, 'select business_id from c10_gov003_demo.v_export_receipts', rd(U.bizOwnerB2)).every((x) => x.business_id === B2));
});

test('f10 forged actor: caller-supplied actor that differs from the server-derived one is G3A01; a matching claim is harmless', () => {
  assert.equal(code(() => exp(U.bizOwnerB1, { claimed: U.tenantOwnerT1 })), 'G3A01');
  assert.equal(code(() => exp(U.staffS1, { claimed: U.bizOwnerB1 })), 'G3A01');   // forged claim is reported before scope
  const ok = exp(U.bizOwnerB1, { claimed: U.bizOwnerB1, action: 'sales.sale' });
  assert.equal(receiptRow(DB, ok.export_receipt_id).actor_id, U.bizOwnerB1);
});

test('f10 grants: app principal has no rights; reader cannot export; writers are SECURITY DEFINER owned by the owner role with a pinned search_path', () => {
  const app = { role: 'c10g3_app', sub: U.bizOwnerB1 };
  assert.equal(code(() => exec(DB, exportSql({ idem: key() }), app)), '42501');
  assert.equal(code(() => exec(DB, exportSql({ idem: key() }), rd(U.bizOwnerB1))), '42501');
  assert.equal(code(() => exec(DB, 'select * from c10_gov003_demo.export_receipts', app)), '42501');
  assert.equal(code(() => exec(DB, 'select * from c10_gov003_demo.v_export_receipts', app)), '42501');
  assert.equal(code(() => exec(DB, 'select * from c10_gov003_demo._exp_build_csv(null, null, null, 0)', be(U.bizOwnerB1))), '42501');
  assert.equal(code(() => exec(DB, 'select c10_gov003_demo._exp_gate(null, null, null)', be(U.bizOwnerB1))), '42501');
  const fns = rows(DB, `select p.proname, p.prosecdef, pg_get_userbyid(p.proowner) as owner, p.proconfig::text as cfg,
      has_function_privilege('public', p.oid, 'execute') as pub
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'c10_gov003_demo' and p.proname in ('export_audit_csv', 'verify_export', 'export_ledger_check', '_exp_build_csv', '_exp_gate')`, own);
  assert.equal(fns.length, 5);
  for (const f of fns) {
    assert.equal(f.prosecdef, true, f.proname); assert.equal(f.owner, 'c10g3_owner', f.proname); assert.equal(f.pub, false, f.proname);
    assert.match(f.cfg, /search_path=pg_catalog, c10_gov003_demo, pg_temp/, f.proname);
  }
});

test('f10 append-only: nobody can UPDATE/DELETE/TRUNCATE/INSERT export receipts directly, not even the owner role', () => {
  const id = exp(U.bizOwnerB1, { action: 'sales.sale' }).export_receipt_id;
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.export_receipts set row_count = 99 where export_receipt_id = '${id}'`, own)), 'G3H01');
  assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.export_receipts where export_receipt_id = '${id}'`, own)), 'G3H01');
  assert.equal(code(() => exec(DB, 'truncate c10_gov003_demo.export_receipts', own)), 'G3H01');
  assert.equal(code(() => exec(DB, `insert into c10_gov003_demo.export_receipts select * from c10_gov003_demo.export_receipts limit 1`, own)), 'G3H01');
  assert.equal(code(() => exec(DB, `update c10_gov003_demo.export_receipts set row_count = 99`, be(U.bizOwnerB1))), '42501');
  assert.equal(code(() => exec(DB, `delete from c10_gov003_demo.export_receipts`, be(U.bizOwnerB1))), '42501');
  assert.equal(code(() => exec(DB, `insert into c10_gov003_demo.export_receipts select * from c10_gov003_demo.export_receipts limit 1`, be(U.bizOwnerB1))), '42501');
  assert.equal(receiptRow(DB, id).row_count, 1);
});

// ------------------------------------------------------------------------------------------------ verify_export
test('f10 verify_export: exact bytes verify; any altered byte, dropped row, appended row or line-ending rewrite is G3A04', () => {
  const r = exp(U.bizOwnerB1, { action: 'stock.adjust' });
  const v = (csv, sub = U.bizOwnerB1, role = 'c10g3_backend') =>
    one(DB, `select * from c10_gov003_demo.verify_export(${uuidLit(r.export_receipt_id)}, ${hexText(csv)})`, { role, sub });
  assert.equal(v(r.csv_text).ok, true);
  assert.equal(v(r.csv_text, U.bizOwnerB1, 'c10g3_reader').byte_sha256, r.byte_sha256);
  assert.equal(v(r.csv_text, U.tenantOwnerT1).row_count, r.row_count);
  const lines = r.csv_text.split('\r\n');
  const tampered = [
    r.csv_text.replace('stock.adjust', 'stock.adjusT'),
    r.csv_text.replace(/,1,/, ',2,'),
    [lines[0], ...lines.slice(2)].join('\r\n'),                          // dropped row
    `${r.csv_text}${lines[1]}\r\n`,                                      // duplicated/appended row
    r.csv_text.replaceAll('\r\n', '\n'),                                 // line-ending rewrite
    r.csv_text.slice(0, -2), `${r.csv_text} `, `\uFEFF${r.csv_text}`, '',
  ];
  for (const t of tampered) assert.equal(code(() => v(t)), 'G3A04', JSON.stringify(t.slice(0, 60)));
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.verify_export(${uuidLit(r.export_receipt_id)}, null)`, be(U.bizOwnerB1))), 'G3A04');
});

test('f10 verify_export: unknown receipt (missing receipt for a claimed export) and foreign callers are G3A04, indistinguishable; no actor is G3A05', () => {
  const r = exp(U.bizOwnerB1, { action: 'sales.refund' });
  const call = (id, sub) => code(() => exec(DB, `select * from c10_gov003_demo.verify_export(${uuidLit(id)}, ${hexText(r.csv_text)})`, be(sub)));
  assert.equal(call('00000000-0000-4000-8000-0000000000ee', U.bizOwnerB1), 'G3A04');
  for (const sub of [U.t2Owner, U.staffS1, U.investorB1, U.revokedB1, U.support, U.bizOwnerB2]) assert.equal(call(r.export_receipt_id, sub), 'G3A04', sub);
  const e1 = errOf(() => exec(DB, `select * from c10_gov003_demo.verify_export('00000000-0000-4000-8000-0000000000ee', 'x')`, be(U.t2Owner)));
  const e2 = errOf(() => exec(DB, `select * from c10_gov003_demo.verify_export(${uuidLit(r.export_receipt_id)}, 'x')`, be(U.t2Owner)));
  assert.equal(e1.detail, e2.detail);
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.verify_export(${uuidLit(r.export_receipt_id)}, 'x')`, { role: 'c10g3_backend' })), 'G3A05');
  // a claimed file whose hash has no receipt at all is detectable through the scoped view
  const claimed = sha256Hex('some other file');
  assert.equal(rows(DB, `select 1 from c10_gov003_demo.v_export_receipts where byte_sha256 = '${claimed}'`, rd(U.bizOwnerB1)).length, 0);
  assert.ok(rows(DB, `select 1 from c10_gov003_demo.v_export_receipts where byte_sha256 = '${r.byte_sha256}'`, rd(U.bizOwnerB1)).length >= 1);
});

test('f10 export_ledger_check: receipts and export audit events are balanced; foreign callers are denied', () => {
  const l = one(DB, `select * from c10_gov003_demo.export_ledger_check('${T1}', '${B1}')`, rd(U.bizOwnerB1));
  assert.equal(l.ok, true); assert.equal(l.orphan_audit_events, 0); assert.equal(l.receipts, l.audit_events);
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.export_ledger_check('${T1}', '${B1}')`, rd(U.t2Owner))), 'G3A02');
  assert.equal(code(() => exec(DB, `select * from c10_gov003_demo.export_ledger_check('${T1}', '${B1}')`, rd(U.investorB1))), 'G3A02');
});

// ------------------------------------------------------------------------------------------------ tamper (privileged DBA is detectable, not preventable)
test('f10 tamper: receipt edits, deleted receipts, edited audit link and rewritten journal rows are all detected (DBA limitation stated)', () => {
  freshDb(DB_TAMPER, { only: ONLY }); seedFixture(DB_TAMPER);
  const e = (o) => exp(U.bizOwnerB1, o, DB_TAMPER);
  const r1 = e({ action: 'stock.adjust' }); const r2 = e({ action: 'sales.sale' }); const r3 = e({ action: 'sales.refund' }); const r4 = e({ domain: 'sales' });
  const verify = (r, sub = U.bizOwnerB1) => exec(DB_TAMPER, `select * from c10_gov003_demo.verify_export(${uuidLit(r.export_receipt_id)}, ${hexText(r.csv_text)})`, be(sub));
  for (const r of [r1, r2, r3, r4]) assert.ok(verify(r).includes('t'));
  const su = (sql) => adminExec(`set session_replication_role = replica; ${sql}`, DB_TAMPER);
  // 1. DBA edits a stored receipt
  su(`update c10_gov003_demo.export_receipts set row_count = row_count + 1 where export_receipt_id = '${r1.export_receipt_id}'`);
  assert.equal(code(() => verify(r1)), 'G3A04');
  assert.equal(e({ action: 'stock.adjust' }).outcome, 'created');                // unrelated exports keep working
  // 2. DBA deletes a receipt: the claimed export has no receipt and the ledger shows an orphan audit event
  su(`delete from c10_gov003_demo.export_receipts where export_receipt_id = '${r2.export_receipt_id}'`);
  assert.equal(code(() => verify(r2)), 'G3A04');
  const l = one(DB_TAMPER, `select * from c10_gov003_demo.export_ledger_check('${T1}', '${B1}')`, rd(U.bizOwnerB1));
  assert.equal(l.ok, false); assert.equal(l.orphan_audit_events, 1);
  // 3. DBA edits the audit event that backs a receipt
  su(`update c10_gov003_demo.audit_events set payload = jsonb_set(payload, '{artifact_sha256}', '"${'a'.repeat(64)}"') where event_id = (select audit_event_id from c10_gov003_demo.export_receipts where export_receipt_id = '${r3.export_receipt_id}')`);
  assert.equal(code(() => verify(r3)), 'G3A04');
  assert.equal(one(DB_TAMPER, `select ok, reason from c10_gov003_demo.verify_chain('${T1}', '${B1}')`, rd(U.bizOwnerB1)).ok, false);
  // 4. DBA rewrites a journal row that an export covered: replay regenerates different bytes and refuses
  const k = key('replay');
  const r5 = exp(U.bizOwnerB1, { idem: k, action: 'stock.adjust' }, DB_TAMPER);
  su(`update c10_gov003_demo.audit_events set source_id = 'rewritten-sku' where tenant_id = '${T1}' and business_id = '${B1}' and stream_seq = 1`);
  assert.equal(code(() => exp(U.bizOwnerB1, { idem: k, action: 'stock.adjust' }, DB_TAMPER)), 'G3A04');
  assert.equal(code(() => verify(r5)), null);                // bytes handed out earlier still match their receipt
  assert.equal(r5.row_count > 0, true);
});

// ------------------------------------------------------------------------------------------------ limits
test('f10 limits: row cap raises an explicit truncation error (never a silent cut); invalid parameters are G3A03; nothing is written on failure', () => {
  freshDb(DB_LIMITS, { only: ONLY }); seedFixture(DB_LIMITS);
  const x = (o, sub = U.bizOwnerB1) => exp(sub, o, DB_LIMITS);
  const rBefore = countOwner(DB_LIMITS, 'export_receipts'); const eBefore = countOwner(DB_LIMITS, 'audit_events');
  const trunc = errOf(() => x({ max: 4 }));
  assert.equal(trunc.code, 'G3A03'); assert.match(trunc.detail, /export_truncated/);
  assert.equal(x({ max: 5 }).row_count, 5);
  assert.equal(x({ max: 1, action: 'sales.refund' }).row_count, 1);
  assert.equal(code(() => x({ max: 1, action: 'stock.adjust' })), 'G3A03');
  for (const bad of [{ max: 0 }, { max: -3 }, { max: 10001 }, { idem: 'short' }, { idem: 'bad key with spaces' }, { idem: 'x'.repeat(101) },
    { action: 'Bad Action' }, { domain: '1x' }, { from: '2026-10-05T00:00:00Z', to: '2026-10-01T00:00:00Z' }, { from: '2026-10-05T00:00:00Z', to: '2026-10-05T00:00:00Z' }]) {
    assert.equal(code(() => x(bad)), 'G3A03', JSON.stringify(bad));
  }
  assert.equal(countOwner(DB_LIMITS, 'export_receipts'), rBefore + 2 /* the two successful exports */);
  assert.equal(countOwner(DB_LIMITS, 'audit_events'), eBefore + 2);
});

test('f10 limits: an oversized cell is an explicit error in SQL and in Node, and is contained to its own business', () => {
  const big = 'x'.repeat(128);
  const fields = ['item_ref', 'entity_ref', 'source_ref', 'grant_ref', 'policy_ref', 'signal_ref', 'evidence_ref', 'artifact_sha256', 'commit_sha',
    'report_id', 'filter_ref', 'hold_ref', 'case_ref', 'feature_id', 'requirement_id', 'receipt_ref', 'batch_ref', 'doc_ref'];
  const payload = Object.fromEntries(fields.map((f) => [f, big]));
  exec(DB_LIMITS, `select c10_gov003_demo.append_event('${T1}', '${B2}', null, null, 'stock', 'huge-1', 'v1', 'stock.huge', now(), 'corr-huge', 'idem-huge-0001', ${lit(JSON.stringify(payload))}::jsonb, null, 'inventory')`, be(U.bizOwnerB2));
  const e = errOf(() => exp(U.bizOwnerB2, { b: B2 }, DB_LIMITS));
  assert.equal(e.code, 'G3A03'); assert.match(e.detail, /export_cell_too_long/);
  assert.equal(exp(U.bizOwnerB2, { b: B2, action: 'stock.adjust' }, DB_LIMITS).row_count, 2);   // a filter that excludes the huge row works
  assert.equal(exp(U.bizOwnerB1, {}, DB_LIMITS).row_count >= 5, true);                          // other business unaffected
  const ev = { event_id: '00000000-0000-4000-8000-000000000001', stream_seq: 1, event_time: '2026-10-01T00:00:00.000000Z', action: 'stock.huge', source_domain: 'stock',
    source_id: 'huge-1', source_version: 'v1', receipt_id: '00000000-0000-4000-8000-0000000000aa', event_digest: 'a'.repeat(64), payload };
  assert.equal(code(() => auditExportCsv([ev])), 'G3A03');
});

// ------------------------------------------------------------------------------------------------ formula injection
test('f10 formula injection: =,+,-,@,TAB,CR,LF at the start of source ids and payload values are neutralized; SQL bytes equal Node bytes', () => {
  freshDb(DB_INJECT, { only: ONLY }); seedFixture(DB_INJECT);
  runSqlFile(DB_INJECT, INJECT);                      // disposable DB only: lets hostile values reach the journal
  const hostile = [
    '=HYPERLINK("http://evil.example/x","click")', '+1+1', '@SUM(A1)', '-2+3', '\t=1+1', '\r=cmd', '\n+x', '\u202E=1+1',
    'a,b"c', 'line1\r\nline2', "=cmd|' /C calc'!A0", 'safe-id',
  ];
  hostile.forEach((sid, i) => exec(DB_INJECT, `select c10_gov003_demo.append_event('${T1}', '${B1}', null, null, 'stock', ${hexText(sid)}, 'v1', 'stock.adjust', now(), 'corr-inj-${i}', 'idem-inj-${String(i).padStart(4, '0')}',
    ${lit(JSON.stringify({ item_ref: sid, entity_ref: '+1', source_ref: '@x', doc_ref: '-abc', note_code: '\t=1', password: 'hunter2', channel: 'a;b', last_seen_at: '=NOW()', status: 'password=hunter2' }))}::jsonb,
    null, 'inventory')`, be(U.bizOwnerB1)));
  const r = exp(U.bizOwnerB1, {}, DB_INJECT);
  const recs = parseCsv(r.csv_text);
  assert.equal(recs.length - 1, r.row_count);
  for (const rec of recs.slice(1)) for (const cell of rec) assert.ok(!/^[=+\-@\t\r\n]/.test(cell), JSON.stringify(cell));
  const sources = recs.slice(1).map((x) => x[5]);
  for (const [raw, exp_] of [['=HYPERLINK("http://evil.example/x","click")', '\'=HYPERLINK("http://evil.example/x","click")'], ['+1+1', "'+1+1"], ['@SUM(A1)', "'@SUM(A1)"], ['-2+3', "'-2+3"],
    ['\t=1+1', "'\t=1+1"], ['\r=cmd', "'\n=cmd"], ['\n+x', "'\n+x"], ['\u202E=1+1', "'=1+1"], ['line1\r\nline2', 'line1\nline2'], ['safe-id', "'safe-id".slice(1)]]) {
    if (raw === 'safe-id') continue;
    assert.ok(sources.includes(exp_), JSON.stringify([raw, exp_]));
  }
  assert.ok(sources.includes('a,b"c') && sources.includes('safe-id') && sources.includes('line1\nline2'));
  const pay = recs.slice(1).map((x) => x[9]).filter((p) => p.includes('doc_ref'));
  for (const p of pay) {
    assert.ok(!p.includes('password') && !p.includes('hunter2'), p);                // non-allowlisted key dropped and secret value withheld
    assert.match(p, /doc_ref='-abc/); assert.match(p, /entity_ref='\+1/); assert.match(p, /source_ref='@x/); assert.match(p, /note_code='\t=1|note_code='\n=1/);
    assert.match(p, /last_seen_at='=NOW\(\)/); assert.match(p, /status=\[withheld\]/); assert.match(p, /channel=a%3Bb/);
  }
  const rc = receiptRow(DB_INJECT, r.export_receipt_id);
  const node = auditExportCsv(journal(DB_INJECT, B1, rc.source_seq, U.bizOwnerB1));
  assert.equal(node.text, r.csv_text);                                                // byte parity under attack
  assert.equal(node.sha256, r.byte_sha256);
  assert.equal(one(DB_INJECT, `select ok from c10_gov003_demo.verify_export(${uuidLit(r.export_receipt_id)}, ${hexText(r.csv_text)})`, be(U.bizOwnerB1)).ok, true);
});
