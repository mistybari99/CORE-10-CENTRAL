// Node <-> SQL parity proofs (real PostgreSQL). Node canonical JSON/digests/redaction/scrub must agree with the
// SQL functions canonical_json, g3_sha256, event_digest_of, receipt_digest_of, looks_secret, validate_payload, scrub_text.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, dropDb, exec, lit } from '../lib/db.mjs';
import { T1, B1, S1, LE1, U } from '../lib/ids.mjs';
import { canonicalJson, sha256Hex, eventDigestOf, receiptDigestOf, utcIso } from '../../../internal/gov003/server/canonical.mjs';
import { validatePayload, looksSecret, scrubText, ALLOWLIST_FIELDS } from '../../../internal/gov003/server/redact.mjs';
import { buildEnvelope } from '../../../internal/gov003/server/envelope.mjs';
import { chainEvent, verifyChain } from '../../../internal/gov003/server/receipt.mjs';

const DB = 'g3_core_par';
before(() => { freshDb(DB, { only: ['000', '010', '020', '030', '040'] }); });
after(() => dropDb(DB));

// deterministic PRNG (mulberry32)
function prng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const jsonOut = (sql) => JSON.parse(exec(DB, sql).trim());
const sqlJson = (v) => lit(JSON.stringify(v));

// ------------------------------------------------------------------------------------------------ allowlist
test('payload_allowlist.json is an exact copy of the SQL payload_allowlist (names + kinds)', () => {
  const db = jsonOut(`select json_agg(json_build_object('field_name', field_name, 'kind', kind) order by field_name) from c10_gov003_demo.payload_allowlist;`);
  const js = [...ALLOWLIST_FIELDS].sort((a, b) => (a.field_name < b.field_name ? -1 : 1));
  assert.deepEqual(js, db);
});

// ------------------------------------------------------------------------------------------------ canonical json + sha256
const rnd = prng(20261112);
const STR_ALPHA = ['a', 'Z', '0', ' ', '"', '\\', '/', '\u0001', '\u001f', '\b', '\f', '\n', '\r', '\t', '\u007f', 'é', 'ß', '日', ' ', ' ', '￿', '�', '\u{1F600}', '\u{10FFFF}', '́', '|', '$', "'", '%', '_'];
const randStr = (max = 6) => { let s = ''; const n = Math.floor(rnd() * (max + 1)); for (let i = 0; i < n; i++) s += STR_ALPHA[Math.floor(rnd() * STR_ALPHA.length)]; return s; };
function gen(depth = 0) {
  const r = rnd();
  if (depth > 3 || r < 0.35) {
    const k = Math.floor(rnd() * 6);
    if (k === 0) return { text: 'null', value: null };
    if (k === 1) { const b = rnd() < 0.5; return { text: String(b), value: b }; }
    if (k === 2) { const n = Math.floor((rnd() - 0.5) * 2 ** 40); return { text: String(n), value: n }; }
    if (k === 3) { const big = BigInt(Math.floor(rnd() * 1e15)) * 1000000007n * (rnd() < 0.5 ? -1n : 1n); return { text: big.toString(), value: big }; }
    const s = randStr(); return { text: JSON.stringify(s), value: s };
  }
  if (r < 0.65) { const n = Math.floor(rnd() * 4); const items = Array.from({ length: n }, () => gen(depth + 1)); return { text: `[${items.map((i) => i.text).join(',')}]`, value: items.map((i) => i.value) }; }
  const n = Math.floor(rnd() * 5); const seen = new Set(); const pairs = [];
  for (let i = 0; i < n; i++) { const k = randStr(4); if (seen.has(k) || k === '__proto__') continue; seen.add(k); pairs.push([k, gen(depth + 1)]); }
  const text = `{${pairs.map(([k, v]) => `${JSON.stringify(k)}:${v.text}`).join(',')}}`;
  const value = {}; for (const [k, v] of pairs) value[k] = v.value;
  return { text, value };
}
const fixed = [
  ['null', null], ['true', true], ['false', false], ['0', 0], ['-0', 0], ['1.0', 1], ['1e3', 1000], ['-12.000', -12], ['""', ''], ['[]', []], ['{}', {}],
  ['{"b":1,"a":{"d":[],"c":{}},"":2}', { b: 1, a: { d: [], c: {} }, '': 2 }],
  ['[12345678901234567890,-9223372036854775808,9007199254740993]', [12345678901234567890n, -9223372036854775808n, 9007199254740993n]],
  ['{"é":1,"z":2,"Z":3,"a":4,"日":5,"\\ud83d\\ude00":6,"\\uffff":7}', { é: 1, z: 2, Z: 3, a: 4, 日: 5, '\u{1F600}': 6, '￿': 7 }],
  ['{"__proto__":1,"a":2}', JSON.parse('{"__proto__":1,"a":2}')],
  ['"\\u0001\\u0002\\u0003\\u0004\\u0005\\u0006\\u0007\\u0008\\u0009\\u000a\\u000b\\u000c\\u000d\\u000e\\u000f"', '\u0001\u0002\u0003\u0004\u0005\u0006\u0007\b\t\n\u000b\f\r\u000e\u000f'],
  ['"\\u0010\\u0011\\u0012\\u0013\\u0014\\u0015\\u0016\\u0017\\u0018\\u0019\\u001a\\u001b\\u001c\\u001d\\u001e\\u001f\\u007f \\"\\\\\\/"', '\u0010\u0011\u0012\u0013\u0014\u0015\u0016\u0017\u0018\u0019\u001a\u001b\u001c\u001d\u001e\u001f\u007f "\\/'],
  ['"\\u2028\\u2029\\u00e9\\u65e5\\ud83d\\ude00"', '  é日\u{1F600}'],
  ['[[[[[[[[[[1]]]]]]]]]],{"a":[{"b":[{}]}]}'.replace(/^(.*),(.*)$/, '[$1,$2]'), [[[[[[[[[[1]]]]]]]]]].length ? [[[[[[[[[[[1]]]]]]]]]], { a: [{ b: [{}] }] }] : null],
];
for (let c = 1; c < 32; c++) fixed.push([JSON.stringify(String.fromCharCode(c)), String.fromCharCode(c)]);
for (let i = 0; i < 400; i++) { const g = gen(); fixed.push([g.text, g.value]); }

test('canonical JSON + sha256 are byte-identical to SQL canonical_json/g3_sha256 on a corpus', () => {
  const texts = fixed.map(([t]) => t);
  const rows = jsonOut(`select json_agg(json_build_object('i', i, 'c', encode(convert_to(c10_gov003_demo.canonical_json(x::jsonb), 'UTF8'), 'hex'), 'h', c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(x::jsonb))) order by i)
    from jsonb_array_elements_text(${sqlJson(texts)}::jsonb) with ordinality as t(x, i);`);
  assert.equal(rows.length, fixed.length);
  let nested = 0;
  fixed.forEach(([text, value], idx) => {
    const js = canonicalJson(value);
    assert.equal(Buffer.from(js, 'utf8').toString('hex'), rows[idx].c, `canonical mismatch for ${text.slice(0, 80)}`);
    assert.equal(sha256Hex(js), rows[idx].h, `sha mismatch for ${text.slice(0, 80)}`);
    if (value && typeof value === 'object') nested++;
  });
  assert.ok(nested > 100 && fixed.length > 400);
});

test('both implementations reject the same unsupported values (non-integers)', () => {
  for (const text of ['1.5', '{"a":0.1}', '[1e-3]']) {
    assert.throws(() => exec(DB, `select c10_gov003_demo.canonical_json(${lit(text)}::jsonb);`), (e) => e.code === 'G3A03');
    assert.throws(() => canonicalJson(JSON.parse(text)), (e) => /CANON_FLOAT/.test(e.code));
  }
  assert.throws(() => exec(DB, `select ${lit('"\\u0000"')}::jsonb;`), (e) => /unsupported Unicode escape/i.test(e.detail || e.message));
  assert.throws(() => canonicalJson('\u0000'), (e) => e.code === 'CANON_NUL');
});

// ------------------------------------------------------------------------------------------------ digests of real appended events
const append = (n, { site = S1, entity = null, payload, actor = U.bizOwnerB1 } = {}) => exec(DB,
  `select event_id from c10_gov003_demo.append_event(${lit(T1)}::uuid, ${lit(B1)}::uuid, ${site ? lit(site) + '::uuid' : 'null::uuid'}, ${entity ? lit(entity) + '::uuid' : 'null::uuid'},
    'pos', ${lit('sale-' + n)}, 'v1', 'sale.created', ${lit('2026-11-12T10:00:00.' + String(100000 + n * 7) + '+06:00')}::timestamptz, ${lit('corr-' + n)}, ${lit('idem-par-' + n + '-0000')},
    ${lit(JSON.stringify(payload ?? { status: 'open', count: String(n) }))}::jsonb, null, 'operational');`, { role: 'c10g3_backend', sub: actor });

const readRows = (tz) => {
  const q = (t) => JSON.parse(exec(DB, `${tz ? `set timezone = ${lit(tz)};` : ''}\nselect coalesce(json_agg(x order by ${t === 'audit_events' ? 'stream_seq' : 'issued_at'}), '[]') from (select * from c10_gov003_demo.${t} where business_id = ${lit(B1)}::uuid) x;`).trim());
  return { events: q('audit_events'), receipts: q('audit_receipts') };
};

test('Node eventDigestOf/receiptDigestOf equal the stored digests of REAL appended events (any session time zone)', () => {
  for (let n = 1; n <= 6; n++) append(n, { site: n % 2 ? S1 : null, entity: n === 3 ? LE1 : null });
  append(7, { payload: { status: 'open', item_ref: 'a/b#c:1.2' }, actor: U.tenantOwnerT1 });
  for (const tz of [undefined, 'UTC', 'Asia/Kolkata', 'America/Los_Angeles', 'Pacific/Auckland']) {
    const { events, receipts } = readRows(tz);
    assert.equal(events.length, 7);
    const byEvent = new Map(receipts.map((r) => [r.event_id, r]));
    for (const e of events) {
      assert.equal(eventDigestOf(e), e.event_digest, `event seq ${e.stream_seq} tz ${tz}`);
      assert.equal(receiptDigestOf(byEvent.get(e.event_id)), byEvent.get(e.event_id).receipt_digest, `receipt seq ${e.stream_seq} tz ${tz}`);
    }
    // whole chain verifies in Node
    assert.deepEqual(verifyChain(events, receipts), { ok: true, checked: 7, first_bad_seq: null, reason: null });
  }
});

test('Node envelope + offline chainEvent reproduce the database digests exactly', () => {
  const { events, receipts } = readRows();
  let head = null;
  for (const e of events) {
    const env = buildEnvelope({ event_id: e.event_id, tenant_id: e.tenant_id, business_id: e.business_id, site_id: e.site_id, legal_entity_id: e.legal_entity_id,
      source_domain: e.source_domain, source_id: e.source_id, source_version: e.source_version, action: e.action, event_time: e.event_time,
      correlation_id: e.correlation_id, idempotency_key: e.idempotency_key, payload: e.payload, reason_category: e.reason_category });
    assert.equal(env.payload_sha256, e.payload_sha256);
    const r = receipts.find((x) => x.event_id === e.event_id);
    const sim = chainEvent(env, { actorId: e.actor_id, head, ingestTime: e.ingest_time, receiptId: r.receipt_id, issuedAt: r.issued_at });
    assert.equal(sim.event.event_digest, e.event_digest);
    assert.equal(sim.event.prior_digest, e.prior_digest);
    assert.equal(sim.receipt.receipt_digest, r.receipt_digest);
    head = sim.head;
  }
  assert.equal(head.last_seq, events.length);
});

test('SQL accepts the Node-computed payload_sha256 and rejects a wrong one (G3A04)', () => {
  const env = buildEnvelope({ tenant_id: T1, business_id: B1, source_domain: 'pos', source_id: 'sale-sha', source_version: 'v1', action: 'sale.created',
    event_time: '2026-11-12T10:00:00Z', correlation_id: 'corr-sha', idempotency_key: 'idem-sha-000001', payload: { status: 'open', amount_minor: '1250' }, reason_category: 'operational' });
  const call = (sha) => exec(DB, `select outcome from c10_gov003_demo.append_event(${lit(T1)}::uuid, ${lit(B1)}::uuid, null, null, 'pos', 'sale-sha', 'v1', 'sale.created',
    ${lit(env.event_time)}::timestamptz, 'corr-sha', 'idem-sha-000001', ${lit(canonicalJsonText(env.payload))}::jsonb, ${lit(sha)}, 'operational');`, { role: 'c10g3_backend', sub: U.bizOwnerB1 }).trim();
  assert.throws(() => call('f'.repeat(64)), (e) => e.code === 'G3A04');
  assert.equal(call(env.payload_sha256), 'created');
  assert.equal(call(env.payload_sha256), 'replayed');
});
const canonicalJsonText = (p) => JSON.stringify(p);

test('tampered rows (triggers disabled by superuser): Node verifyChain and SQL verify_chain agree on reason and position', () => {
  const cases = [
    ['update c10_gov003_demo.audit_events set action = $$sale.deleted$$ where stream_seq = 3 and business_id = ' + lit(B1) + '::uuid', 'event_digest_mismatch', 3],
    ['update c10_gov003_demo.audit_events set payload = jsonb_set(payload, $${status}$$, $$"closed"$$) where stream_seq = 2 and business_id = ' + lit(B1) + '::uuid', 'payload_hash_mismatch', 2],
    ['update c10_gov003_demo.audit_receipts set receipt_digest = repeat($$0$$, 64) where event_id = (select event_id from c10_gov003_demo.audit_events where stream_seq = 5 and business_id = ' + lit(B1) + '::uuid)', 'receipt_digest_mismatch', 5],
  ];
  // the mutation helper disables ONLY the guard triggers (superuser capability = documented DBA/WORM limitation)
  const run = (sqlMut) => exec(DB, `alter table c10_gov003_demo.audit_events disable trigger g3_no_update_delete; alter table c10_gov003_demo.audit_receipts disable trigger g3_no_update_delete;
    ${sqlMut};
    alter table c10_gov003_demo.audit_events enable trigger g3_no_update_delete; alter table c10_gov003_demo.audit_receipts enable trigger g3_no_update_delete;`);
  for (const [mut, reason, seq] of cases) {
    const before = readRows();
    run(mut);
    const { events, receipts } = readRows();
    const nodeV = verifyChain(events, receipts);
    const sqlV = JSON.parse(exec(DB, `select row_to_json(v) from c10_gov003_demo.verify_chain(${lit(T1)}::uuid, ${lit(B1)}::uuid) v;`, { role: 'c10g3_reader', sub: U.bizOwnerB1 }).trim());
    assert.equal(nodeV.ok, false); assert.equal(nodeV.reason, reason); assert.equal(nodeV.first_bad_seq, seq);
    assert.equal(sqlV.ok, false); assert.equal(sqlV.reason, reason); assert.equal(Number(sqlV.first_bad_seq), seq);
    // restore original rows exactly so the next case starts clean
    for (const e of before.events) exec(DB, `alter table c10_gov003_demo.audit_events disable trigger g3_no_update_delete;
      update c10_gov003_demo.audit_events set action = ${lit(e.action)}, payload = ${lit(JSON.stringify(e.payload))}::jsonb where event_id = ${lit(e.event_id)}::uuid;
      alter table c10_gov003_demo.audit_events enable trigger g3_no_update_delete;`);
    for (const r of before.receipts) exec(DB, `alter table c10_gov003_demo.audit_receipts disable trigger g3_no_update_delete;
      update c10_gov003_demo.audit_receipts set receipt_digest = ${lit(r.receipt_digest)} where receipt_id = ${lit(r.receipt_id)}::uuid;
      alter table c10_gov003_demo.audit_receipts enable trigger g3_no_update_delete;`);
    assert.equal(verifyChain(readRows().events, readRows().receipts).ok, true);
  }
});

// ------------------------------------------------------------------------------------------------ looks_secret / validate_payload / scrub
const JWT = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
const FRAGS = [JWT, 'eyJabcdefgh', 'eyJabc', 'Bearer abc.def-ghi', 'bearer\tTOKEN123', 'BEARER  x', 'bearerx', 'service_role', 'service-role', 'serviceRole', 'password', 'passwd', 'Passw0rd', 'SECRET', 'secret=1',
  'api_key=abc', 'API-KEY: zzz', 'apikey', 'token', 'Token: abc', 'private_key', 'private-key', 'Authorization: x', 'authorization', 'a@b.co', 'x.y@z.example.com', 'a@b', '@b.com', 'a@@b.com', 'a@b.c',
  'user@host.org,next', '4111111111111111', '4111 1111 1111 1111', '123456789', '12345678', '1234567890123', '12345678901234567890', '+8801712345678', '01712-345-678', '+1 555 123 4567', '123 456 7',
  'postgres://u:p@h:5432/db', 'postgresql://x', 'https://example.com/a?b=c', 'HTTP://X.Y', 'mysql://a', 'redis://h', 'mongodb://h', 'ftp://h', 'at Object.run (/srv/a.js:1:2)', 'at fn (x)', ' at foo (a.js)',
  'Eat x (y)', 'é at x (y)', '1at x (y)', '_at x (y)', 'AT x.y (z)', '    at async x (y)', ' ', '\t', ' ', '　', ' ', ' ', ' ', '\u0085', ' ', 'é', '日本', 'ok', 'open', 'sale-1', 'a.b', '-', '_', ':', '=', ';', ',', '/', '#'];
const SEPS = ['', ' ', '  ', '\n', '\n   ', '\n\t', '\r\n', ' ', ',', ';', '=', ':', '-', '.', '|', ' ', '　', ' ', ' ', ' ', '\u0085'];
function fuzzString() { const n = 1 + Math.floor(rnd() * 4); let s = ''; for (let i = 0; i < n; i++) s += SEPS[Math.floor(rnd() * SEPS.length)] + FRAGS[Math.floor(rnd() * FRAGS.length)]; return s + SEPS[Math.floor(rnd() * SEPS.length)]; }
const strCorpus = [...FRAGS, ...FRAGS.map((f) => `x ${f} y`), ...FRAGS.map((f) => `${f}\n   at a (b)`), ...FRAGS.map((f) => `\n${f}`), ...FRAGS.map((f) => `${f}\n`), '', 'x'.repeat(400), 'é'.repeat(400), ...Array.from({ length: 600 }, fuzzString)];
const strs = strCorpus.map((s) => s.replace(/\u0000/g, ''));

test('looks_secret parity on a corpus (fragments, boundaries, Unicode whitespace, 600 fuzz strings)', () => {
  const rows = jsonOut(`select json_agg(c10_gov003_demo.looks_secret(x) order by i) from jsonb_array_elements_text(${sqlJson(strs)}::jsonb) with ordinality as t(x, i);`);
  assert.equal(rows.length, strs.length);
  const diffs = []; let trues = 0;
  strs.forEach((s, i) => { if (looksSecret(s) !== rows[i]) diffs.push(JSON.stringify(s).slice(0, 80)); if (rows[i]) trues++; });
  assert.deepEqual(diffs, []);
  assert.ok(trues > 100 && trues < strs.length - 100, `corpus is not discriminating: ${trues}/${strs.length}`);
});

test('scrub_text parity on the same corpus (exact output equality)', () => {
  const rows = jsonOut(`select json_agg(c10_gov003_demo.scrub_text(x) order by i) from jsonb_array_elements_text(${sqlJson(strs)}::jsonb) with ordinality as t(x, i);`);
  const diffs = [];
  strs.forEach((s, i) => { if (scrubText(s) !== rows[i]) diffs.push({ in: JSON.stringify(s).slice(0, 60), js: scrubText(s).slice(0, 60), sql: String(rows[i]).slice(0, 60) }); });
  assert.deepEqual(diffs, []);
  assert.ok(rows.some((r) => r.includes('[redacted-jwt]')) && rows.some((r) => r.includes('[frame]')) && rows.some((r) => r.includes('[redacted-email]')) && rows.some((r) => r.includes('[redacted-number]')));
});

const TRY_VALIDATE = `create function pg_temp.try_validate(j jsonb) returns text language plpgsql as $$ begin perform c10_gov003_demo.validate_payload(j); return 'ok'; exception when others then return sqlerrm; end $$;\n`;
// validate_payload corpus --------------------------------------------------------------------------------------
const BAD_BY_KIND = {
  money: ['12.5', '1e3', '', '-', '1234567890123456789', 'abc', ' 1', '1\n', '--1', '+1'],
  count: ['1.0', '1e3', '', '1234567890123456', 'x', '1 ', '1\n'],
  ts: ['2026-11-12', '2026-11-12 10:00:00Z', '2026-11-12T10:00:00', '2026-11-12T10:00:00+00:00', 'T10:00Z', '2026-11-12T10:00:00z', '2026-11-12T10:00:00Z\n'],
  enum: ['Open', 'has space', '', 'x'.repeat(65), 'a/b', 'a@b', 'open\n', 'ÿ', 'a#b'],
  ref: ['has space', '', 'x'.repeat(129), 'a@b.com', JWT, 'token-1', 'password1', 'secret', '123456789', '4111111111111111', 'a\nb', 'é', 'a|b', 'service_role', 'Bearer'],
  text: [],
};
const GOOD_BY_KIND = {
  money: ['0', '-0', '12', '-1250', '123456789012345678'],
  count: ['0', '7', '-7', '123456789012345'],
  ts: ['2026-11-12T10:00:00Z', '2026-11-12T10:00:00.123456Z', '2026-11-12T10:0:0Z', '2026-99-99T99:99Z'],
  enum: ['open', 'a_b-c.d:e', 'x'.repeat(64), '0', 'bdt'],
  ref: ['a', 'sku:1/a#2', 'x'.repeat(128), '1234', '12345678', 'A-b_c.d', 'commit/abc123'],
  text: ['hello', 'free text allowed', ''],
};
const GENERIC_BAD = [1, 1.5, -3, 2 ** 40, true, false, null, [], ['a'], {}, { a: 'b' }, 'x'.repeat(257), 'e\nf', 'a@b.com', '4111111111111111', JWT, 'x\n   at foo (bar)', '\u0000'.slice(1)];
function buildPayloads() {
  const out = [];
  for (const { field_name: f, kind } of ALLOWLIST_FIELDS) {
    for (const v of GOOD_BY_KIND[kind]) out.push({ [f]: v });
    for (const v of BAD_BY_KIND[kind]) out.push({ [f]: v });
    for (const v of GENERIC_BAD) out.push({ [f]: v });
  }
  out.push({}, { unknown_field: 'x' }, { password: 'x' }, { Status: 'open' }, { '': 'x' }, { status: 'open', extra: 'x' }, { 'a b': 'x' }, { email: 'a@b.com', status: 'open' }, { 'ü': 'x' });
  const fields = ALLOWLIST_FIELDS.map((f) => f.field_name);
  for (let i = 0; i < 500; i++) {
    const p = {}; const n = 1 + Math.floor(rnd() * 5);
    for (let j = 0; j < n; j++) {
      const { field_name: f, kind } = ALLOWLIST_FIELDS[Math.floor(rnd() * fields.length)];
      const r = rnd();
      p[f] = r < 0.55 ? GOOD_BY_KIND[kind][Math.floor(rnd() * GOOD_BY_KIND[kind].length)]
        : r < 0.8 ? (BAD_BY_KIND[kind].length ? BAD_BY_KIND[kind][Math.floor(rnd() * BAD_BY_KIND[kind].length)] : GENERIC_BAD[Math.floor(rnd() * GENERIC_BAD.length)])
          : GENERIC_BAD[Math.floor(rnd() * GENERIC_BAD.length)];
    }
    if (rnd() < 0.1) p['junk_' + i] = 'x';
    out.push(p);
  }
  return out;
}

test('Node validatePayload accepts/rejects EXACTLY like SQL validate_payload (generated corpus incl. messages for single-field payloads)', () => {
  const payloads = buildPayloads();
  const texts = payloads.map((p) => JSON.stringify(p));
  const rows = jsonOut(TRY_VALIDATE + `select json_agg(pg_temp.try_validate(x::jsonb) order by i) from jsonb_array_elements_text(${sqlJson(texts)}::jsonb) with ordinality as t(x, i);`);
  assert.equal(rows.length, payloads.length);
  let accepted = 0; let rejected = 0; const diffs = []; const msgDiffs = [];
  payloads.forEach((p, i) => {
    let js = 'ok'; try { validatePayload(JSON.parse(texts[i])); } catch (e) { js = e.message; }
    if ((js === 'ok') !== (rows[i] === 'ok')) diffs.push({ payload: texts[i].slice(0, 100), js, sql: rows[i] });
    else if (js === 'ok') accepted++; else rejected++;
    if (Object.keys(p).length === 1 && js !== rows[i]) msgDiffs.push({ payload: texts[i].slice(0, 80), js, sql: rows[i] });
  });
  assert.deepEqual(diffs, [], 'accept/reject must be identical');
  assert.deepEqual(msgDiffs, [], 'single-field error messages must be identical');
  assert.ok(accepted > 150 && rejected > 500, `corpus balance accepted=${accepted} rejected=${rejected}`);
});

test('required rejection classes are rejected by BOTH (allowed vs unknown field, JWT, email, 16-digit card, stack trace, over-length, wrong kind)', () => {
  const must = [
    [{ status: 'open', count: '2' }, true], [{ role: 'owner' }, false], [{ item_ref: JWT }, false], [{ item_ref: 'a@b.com' }, false],
    [{ item_ref: '4111111111111111' }, false], [{ item_ref: 'x\n   at foo (bar)' }, false], [{ item_ref: 'x'.repeat(300) }, false], [{ amount_minor: 'twelve' }, false],
    [{ count: 3 }, false],
  ];
  const texts = must.map(([p]) => JSON.stringify(p));
  const rows = jsonOut(TRY_VALIDATE + `select json_agg(pg_temp.try_validate(x::jsonb) order by i) from jsonb_array_elements_text(${sqlJson(texts)}::jsonb) with ordinality as t(x, i);`);
  must.forEach(([p, ok], i) => {
    assert.equal(rows[i] === 'ok', ok, `sql ${texts[i].slice(0, 60)}`);
    assert.equal((() => { try { validatePayload(p); return true; } catch { return false; } })(), ok, `node ${texts[i].slice(0, 60)}`);
  });
});

test('utcIso equals SQL utc_iso for microsecond timestamps in many zones', () => {
  const samples = ['2026-11-12T10:00:00.123456+05:30', '1999-12-31T23:59:59.999999Z', '2024-02-29T12:00:00.5-08:00', '0099-03-04T00:00:00+00', '9999-12-31T23:59:59.999999Z'];
  const rows = jsonOut(`select json_agg(c10_gov003_demo.utc_iso(x::timestamptz) order by i) from jsonb_array_elements_text(${sqlJson(samples)}::jsonb) with ordinality as t(x, i);`);
  samples.forEach((s, i) => assert.equal(utcIso(s), rows[i], s));
});
