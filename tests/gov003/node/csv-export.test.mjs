// Feature 10 export-provenance: Node CSV writer (spec g3csv1). Pure unit tests, no database.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  CSV_SPEC, LIMITS, CsvExportError, csvCell, cleanText, writeCsv, auditExportCsv, payloadText, looksSecret,
  normalizeFilter, exportReceiptDigest, verifyExportBytes, parseCsv, canonicalFlat, toUtcIso, PAYLOAD_ALLOWLIST,
  AUDIT_COLUMNS, sha256Hex,
} from '../../../internal/gov003/server/csv-export.mjs';

const code = (fn) => { try { fn(); } catch (e) { return e.code ?? e.message; } return null; };
const FORMULA_START = /^[=+\-@\t\r\n]/;

const ev = (o = {}) => ({
  event_id: '00000000-0000-4000-8000-000000000001', stream_seq: 1, event_time: '2026-11-12T10:00:00.123456Z',
  action: 'stock.adjust', source_domain: 'stock', source_id: 'sku-1', source_version: 'v1',
  receipt_id: '00000000-0000-4000-8000-0000000000aa', event_digest: 'a'.repeat(64),
  payload: { item_ref: 'sku-1', quantity_milli: '5000' }, ...o,
});

test('spec constants and header/terminator: CRLF records, no BOM, header first', () => {
  assert.equal(CSV_SPEC, 'g3csv1');
  const r = auditExportCsv([ev()]);
  assert.ok(r.text.startsWith('event_id,stream_seq,event_time,action,source_domain,source_id,source_version,receipt_id,event_digest,payload_fields\r\n'));
  assert.ok(r.text.endsWith('\r\n'));
  assert.notEqual(r.bytes[0], 0xef); // no UTF-8 BOM
  assert.equal(r.rowCount, 1);
  assert.deepEqual(AUDIT_COLUMNS.map((c) => c.name).length, 10);
});

test('empty result is a header-only file with a valid hash (zero rows are still receipted)', () => {
  const r = auditExportCsv([]);
  assert.equal(r.rowCount, 0);
  assert.equal(r.text, 'event_id,stream_seq,event_time,action,source_domain,source_id,source_version,receipt_id,event_digest,payload_fields\r\n');
  assert.equal(r.sha256, createHash('sha256').update(r.text).digest('hex'));
});

test('SHA-256 covers the exact bytes (multi-byte text, CRLF) and byteLength is bytes not characters', () => {
  const r = writeCsv({ columns: [{ name: 'a' }], rows: [['\u09AC\u09BE\u0982\u09B2\u09BE'], ['\u00E9\u{1F600}']] });
  assert.equal(r.sha256, createHash('sha256').update(Buffer.from(r.text, 'utf8')).digest('hex'));
  assert.equal(r.byteLength, Buffer.byteLength(r.text, 'utf8'));
  assert.ok(r.byteLength > r.text.length);
});

test('formula guard: = + - @ TAB CR LF at cell start are neutralized with a single quote', () => {
  for (const lead of ['=', '+', '-', '@', '\t', '\r', '\n']) {
    const cell = csvCell(`${lead}SUM(1+1)`);
    const parsed = parseCsv(`${cell}\r\n`)[0][0];
    assert.ok(parsed.startsWith("'"), `lead ${JSON.stringify(lead)} -> ${JSON.stringify(parsed)}`);
    assert.ok(!FORMULA_START.test(parsed));
  }
  assert.equal(csvCell("=HYPERLINK(\"http://x\",\"y\")"), '"\'=HYPERLINK(""http://x"",""y"")"');
  assert.equal(csvCell('-5'), "'-5"); // text cells never trust a leading minus
});

test('formula guard leaves safe text alone (middle characters, leading space, quote already present)', () => {
  assert.equal(csvCell('a=b+c-d@e'), 'a=b+c-d@e');
  assert.equal(csvCell(' =x'), ' =x');
  assert.equal(csvCell("'=x"), "'=x");
  assert.equal(csvCell(''), '');
  assert.equal(csvCell(null), '');
});

test('integer cells are digits only and never guarded; anything else is G3A03', () => {
  assert.equal(csvCell('12345', 'int'), '12345');
  assert.equal(csvCell(7, 'int'), '7');
  for (const v of ['-1', '1.5', '', '=1', '1e3', ' 1', '1'.repeat(16), null, undefined]) assert.equal(code(() => csvCell(v, 'int')), 'G3A03', String(v));
  assert.equal(code(() => csvCell('x', 'blob')), 'G3A03');
});

test('quoting: comma, quote, CR and LF force RFC 4180 quoting; embedded CRLF/CR normalize to LF', () => {
  assert.equal(csvCell('a,b'), '"a,b"');
  assert.equal(csvCell('say "hi"'), '"say ""hi"""');
  assert.equal(csvCell('l1\r\nl2'), '"l1\nl2"');
  assert.equal(csvCell('l1\rl2'), '"l1\nl2"');
  assert.equal(csvCell('l1\nl2'), '"l1\nl2"');
  const r = writeCsv({ columns: [{ name: 'a' }, { name: 'b' }], rows: [['x\r\ny', 'p,q'], ['"', 'z']] });
  assert.deepEqual(parseCsv(r.text), [['a', 'b'], ['x\ny', 'p,q'], ['"', 'z']]);
});

test('Unicode: NFC, bidi/zero-width/control stripping, Bangla and emoji survive, lone surrogates repaired', () => {
  assert.equal(csvCell('e\u0301'), '\u00E9'); // NFD -> NFC
  assert.equal(csvCell('a\u202Eb\u2066c\u200Bd\uFEFFe\u00ADf'), 'abcdef');
  assert.equal(csvCell('a\u0007b\u0000c\u007Fd\u0085e\u2028f\u2029g'), 'abcdefg');
  assert.equal(csvCell('\u099F\u09BE\u0995\u09BE \u{1F600}'), '\u099F\u09BE\u0995\u09BE \u{1F600}');
  assert.equal(csvCell('x\uD800y'), 'x\uFFFDy');
  // stripping must not let a bidi/control character hide a formula start
  assert.equal(csvCell('\u202E=1+1'), "'=1+1");
  assert.equal(csvCell('\u0007+1'), "'+1");
  assert.equal(cleanText('\u200F\u200Ex'), 'x');
});

test('cell limit: 2048 code points ok, 2049 is an explicit G3A03 (no silent truncation); emoji count as one', () => {
  assert.equal(csvCell('a'.repeat(2048)).length, 2048);
  assert.equal(code(() => csvCell('a'.repeat(2049))), 'G3A03');
  assert.equal([...csvCell('\u{1F600}'.repeat(2048))].length, 2048);
  assert.equal(code(() => csvCell('\u{1F600}'.repeat(2049))), 'G3A03');
  assert.equal(code(() => csvCell(`=${'a'.repeat(2048)}`)), 'G3A03'); // guard quote counts toward the cap
});

test('row limit: a record over 8192 bytes is G3A03 even when every cell is under the cell cap', () => {
  const big = '\u{1F600}'.repeat(1100); // 4400 bytes per cell
  assert.equal(code(() => writeCsv({ columns: [{ name: 'a' }, { name: 'b' }], rows: [[big, big]] })), 'G3A03');
  assert.equal(writeCsv({ columns: [{ name: 'a' }], rows: [[big]] }).rowCount, 1);
});

test('row count cap: more rows than max_rows is an explicit export_truncated error; hard cap 10000', () => {
  const rows = [['1'], ['2'], ['3']];
  assert.equal(writeCsv({ columns: [{ name: 'a', kind: 'int' }], rows, maxRows: 3 }).rowCount, 3);
  const e = (() => { try { writeCsv({ columns: [{ name: 'a', kind: 'int' }], rows, maxRows: 2 }); } catch (x) { return x; } })();
  assert.ok(e instanceof CsvExportError); assert.equal(e.code, 'G3A03'); assert.match(e.message, /export_truncated/);
  for (const bad of [0, -1, 10001, 1.5, NaN]) assert.equal(code(() => writeCsv({ columns: [{ name: 'a' }], rows: [], maxRows: bad })), 'G3A03');
  assert.equal(LIMITS.maxRows, 10000);
});

test('file size cap: 8 MiB total is an explicit error', () => {
  const line = 'x'.repeat(900);
  const rows = Array.from({ length: 10000 }, () => [line]);
  assert.equal(code(() => writeCsv({ columns: [{ name: 'a' }], rows })), 'G3A03');
});

test('column names are validated and row width must match the header', () => {
  assert.equal(code(() => writeCsv({ columns: [{ name: 'A b' }], rows: [] })), 'G3A03');
  assert.equal(code(() => writeCsv({ columns: [{ name: 'a' }, { name: 'b' }], rows: [['1']] })), 'G3A03');
});

test('PII/secret allowlist: unknown fields never reach the file, secret-looking values are withheld', () => {
  const t = payloadText({ item_ref: 'sku-1', password: 'hunter2', email: 'a@b.com', phone: '01712345678', jwt: 'eyJhbGciOi.x.y' });
  assert.equal(t, 'item_ref=sku-1');
  assert.equal(payloadText({ entity_ref: 'a@b.com' }), 'entity_ref=[withheld]');
  assert.equal(payloadText({ source_ref: 'service_role' }), 'source_ref=[withheld]');
  assert.equal(payloadText({ item_ref: '4111111111111111' }), 'item_ref=[withheld]');
  assert.equal(payloadText({ doc_ref: 'Bearer abc' }), 'doc_ref=[withheld]');
  assert.equal(payloadText({ note_code: 'x\n   at Object.<anonymous> (file.js:1:1)' }), 'note_code=[withheld]');
  assert.ok(!PAYLOAD_ALLOWLIST.some((f) => /pass|secret|token|email|phone|jwt|card|health|salary|payroll/i.test(f)));
});

test('payload cell: sorted keys, ; escaped, values formula-guarded, pure integers exempt, non-object is empty', () => {
  assert.equal(payloadText({ status: 'ok', count: '-5', amount_minor: '12' }), 'amount_minor=12;count=-5;status=ok');
  assert.equal(payloadText({ item_ref: '=cmd', entity_ref: '+1+1', source_ref: '@x', doc_ref: '-abc' }),
    "doc_ref='-abc;entity_ref='+1+1;item_ref='=cmd;source_ref='@x");
  assert.equal(payloadText({ item_ref: 'a;b=c' }), 'item_ref=a%3Bb=c');
  assert.equal(payloadText(null), ''); assert.equal(payloadText([]), ''); assert.equal(payloadText('x'), '');
  assert.equal(payloadText({ item_ref: null }), 'item_ref=');
});

test('looksSecret mirrors the SQL rule set on a corpus', () => {
  for (const s of ['eyJhbGciOiJIUzI1NiJ9', 'Bearer abc', 'my password', 'api-key', 'x@y.io', '4111111111111111', '123456789', 'a\n  at f (x)']) {
    assert.equal(looksSecret(s), true, s);
  }
  for (const s of ['sku-1', 'abc123', '12345678', 'g3x:00000000-0000-4000-8000-0000000000aa', 'a'.repeat(64)]) assert.equal(looksSecret(s), false, s);
});

test('adversarial rows: formula-looking source ids/payload values are neutralized; reparse finds no formula cell start', () => {
  const rows = [
    ev({ stream_seq: 2, source_id: '=HYPERLINK("http://evil","x")', payload: { item_ref: '=1+1', note_code: '@SUM(A1)' } }),
    ev({ stream_seq: 3, source_id: '+cmd|\' /C calc\'!A0', action: 'x.y' }),
    ev({ stream_seq: 4, source_id: '-2+3', payload: { count: '-2' } }),
    ev({ stream_seq: 5, source_id: '@A1', source_version: '\t=1' }),
    ev({ stream_seq: 1, source_id: 'ok' }),
  ];
  const parsed = parseCsv(auditExportCsv(rows).text);
  assert.equal(parsed.length, 6);
  assert.equal(parsed[1][0], '00000000-0000-4000-8000-000000000001'); // sorted by stream_seq: seq 1 first
  for (const rec of parsed.slice(1)) for (const cell of rec) assert.ok(!FORMULA_START.test(cell), JSON.stringify(cell));
  assert.ok(parsed.some((r) => r[5] === "'-2+3"));
  assert.ok(parsed.some((r) => r[9].includes("item_ref='=1+1")));
});

test('fuzz: no generated cell survives csvCell+parse with a formula start, bidi, CR or control characters', () => {
  const alphabet = ['=', '+', '-', '@', '\t', '\r', '\n', ' ', '"', ',', 'a', '1', '\u202E', '\u200B', '\u0007', '\u00E9', 'e\u0301', '\u{1F600}', '\u0995'];
  let seed = 12345; const rnd = (n) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n; };
  for (let i = 0; i < 2000; i += 1) {
    const s = Array.from({ length: rnd(12) }, () => alphabet[rnd(alphabet.length)]).join('');
    const cell = parseCsv(`${csvCell(s)}\r\n`)[0][0];
    assert.ok(!FORMULA_START.test(cell), JSON.stringify([s, cell]));
    assert.ok(!/[\r\u202E\u200B\u0007]/.test(cell), JSON.stringify([s, cell]));
    assert.equal(cell, cell.normalize('NFC'));
  }
});

test('normalizeFilter: deterministic, order independent, UTC micro ISO, changed filter changes the hash', () => {
  const a = normalizeFilter({ from: '2026-11-01T00:00:00.000Z', action: 'stock.adjust', maxRows: 50 });
  const b = normalizeFilter({ maxRows: 50, action: 'stock.adjust', from: new Date('2026-11-01T00:00:00Z') });
  assert.equal(a.filterSha256, b.filterSha256);
  assert.equal(a.canonical, '{"action":"stock.adjust","from":"2026-11-01T00:00:00.000000Z","max_rows":"50","report_id":"audit_journal_v1"}');
  assert.equal(a.filterSha256, sha256Hex(a.canonical));
  assert.notEqual(a.filterSha256, normalizeFilter({ from: '2026-11-01T00:00:00Z', action: 'stock.adjust', maxRows: 51 }).filterSha256);
  assert.notEqual(a.filterSha256, normalizeFilter({ from: '2026-11-02T00:00:00Z', action: 'stock.adjust', maxRows: 50 }).filterSha256);
  assert.equal(normalizeFilter().canonical, '{"max_rows":"10000","report_id":"audit_journal_v1"}');
  assert.equal(toUtcIso('2026-11-12T10:00:00.123456Z'), '2026-11-12T10:00:00.123456Z');
});

test('normalizeFilter rejects malformed input with G3A03', () => {
  for (const bad of [{ maxRows: 0 }, { maxRows: 10001 }, { action: 'Bad Action' }, { sourceDomain: '1x' }, { from: 'not-a-date' },
    { from: '2026-11-02T00:00:00Z', to: '2026-11-01T00:00:00Z' }, { from: '2026-11-02T00:00:00Z', to: '2026-11-02T00:00:00Z' }]) {
    assert.equal(code(() => normalizeFilter(bad)), 'G3A03', JSON.stringify(bad));
  }
  assert.equal(code(() => canonicalFlat({ a: 1 })), 'G3A03');
});

test('verifyExportBytes: exact bytes pass; any change, truncation, append, missing receipt or content is G3A04', () => {
  const r = auditExportCsv([ev(), ev({ stream_seq: 2 })]);
  const receipt = { byte_sha256: r.sha256, byte_length: r.byteLength };
  assert.equal(verifyExportBytes(receipt, r.text).ok, true);
  assert.equal(verifyExportBytes(receipt, r.bytes).ok, true);
  assert.equal(code(() => verifyExportBytes(receipt, r.text.replace('stock', 'stocK'))), 'G3A04');
  assert.equal(code(() => verifyExportBytes(receipt, r.text.slice(0, -2))), 'G3A04');
  assert.equal(code(() => verifyExportBytes(receipt, `${r.text}x`)), 'G3A04');
  assert.equal(code(() => verifyExportBytes(receipt, r.text.replaceAll('\r\n', '\n'))), 'G3A04'); // line-ending rewrite
  assert.equal(code(() => verifyExportBytes(null, r.text)), 'G3A04');
  assert.equal(code(() => verifyExportBytes({}, r.text)), 'G3A04');
  assert.equal(code(() => verifyExportBytes(receipt, null)), 'G3A04');
});

test('exportReceiptDigest is deterministic and binds every recorded field', () => {
  const base = {
    exportReceiptId: '00000000-0000-4000-8000-0000000000e1', tenantId: '11111111-1111-4111-8111-111111111111',
    businessId: 'b1000000-0000-4000-8000-000000000001', actorId: '1d000000-0000-4000-8000-000000000002',
    idempotencyKey: 'exp-key-0001', filterSha256: 'f'.repeat(64), sourceSeq: 7, sourceVersion: 'seq7.abcdef0123456789',
    rowCount: 3, byteSha256: 'b'.repeat(64), byteLength: 321, auditEventDigest: 'd'.repeat(64), issuedAt: '2026-11-12T10:00:00.000001Z',
  };
  const d = exportReceiptDigest(base);
  assert.match(d, /^[0-9a-f]{64}$/); assert.equal(d, exportReceiptDigest({ ...base }));
  const variants = {
    exportReceiptId: 'x1', tenantId: 'x2', businessId: 'x3', actorId: 'x4', idempotencyKey: 'x5', filterSha256: 'x6', sourceSeq: 8,
    sourceVersion: 'x7', rowCount: 4, byteSha256: 'x8', byteLength: 322, auditEventDigest: 'x9', issuedAt: '2026-11-12T10:00:00.000002Z',
  };
  for (const [k, v] of Object.entries(variants)) assert.notEqual(exportReceiptDigest({ ...base, [k]: v }), d, k);
});

test('parseCsv rejects malformed CSV (bare newline, stray quote, unterminated quote)', () => {
  assert.equal(code(() => parseCsv('a\nb\r\n')), 'G3A03');
  assert.equal(code(() => parseCsv('a"b\r\n')), 'G3A03');
  assert.equal(code(() => parseCsv('"abc\r\n')), 'G3A03');
  assert.deepEqual(parseCsv('a,b\r\n"c,d",e\r\n'), [['a', 'b'], ['c,d', 'e']]);
});

test('the module claims no legal compliance and no network/dependency imports', async () => {
  const { readFileSync } = await import('node:fs');
  const src = readFileSync(new URL('../../../internal/gov003/server/csv-export.mjs', import.meta.url), 'utf8');
  assert.ok(/not WORM storage and not a legal certification/.test(src));
  const imports = [...src.matchAll(/^import .* from '([^']+)'/gm)].map((m) => m[1]);
  assert.deepEqual(imports, ['node:crypto']);
});
