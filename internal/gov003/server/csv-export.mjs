// GOV-003 feature 10 export-provenance: pure, zero-dependency CSV writer. DEMO / NOT LIVE contract code.
//
// Spec "g3csv1" -- the byte-for-byte mirror of internal/gov003/sql/100_export.sql (g3_csv_cell, g3_csv_payload_text,
// _exp_build_csv). The parity test (tests/gov003/sql/f10_export.test.mjs) proves SQL bytes === Node bytes.
//
//   * UTF-8 bytes, no BOM; header row; records separated and terminated by CRLF (RFC 4180).
//   * Text cell: toWellFormed -> NFC -> strip C0/C1 controls (except TAB/LF/CR), soft hyphen, bidi marks/embeddings/
//     isolates, zero-width and other format characters, U+2028/2029, BOM -> NFC -> CRLF/CR become LF ->
//     spreadsheet formula guard: a cell starting with = + - @ TAB CR LF gets a single leading quote ->
//     reject > 2048 code points -> quote the cell when it contains , " CR LF (quotes doubled).
//   * Integer cells are 1-15 ASCII digits and are never guarded (they cannot start with = + - @).
//   * A record over 8192 bytes, more than 10000 rows, or a file over 8 MiB is an explicit error (never a silent cut).
//   * Payload cell: allowlisted field names only, sorted, "key=value;key=value", values that look like secrets/PII
//     become [withheld], ';' in values becomes %3B, each value formula-guarded (pure integers exempt).
//
// A SHA-256 over the exact bytes is a provenance aid. It is not WORM storage and not a legal certification.
import { createHash } from 'node:crypto';

export const CSV_SPEC = 'g3csv1';
export const LIMITS = Object.freeze({ maxCellChars: 2048, maxRowBytes: 8192, maxRows: 10000, maxBytes: 8 * 1024 * 1024 });
export const REPORT_ID = 'audit_journal_v1';

export class CsvExportError extends Error {
  constructor(code, message) { super(`${code}: ${message}`); this.code = code; this.detail = message; }
}
const bad = (message) => new CsvExportError('G3A03', message);

export const sha256Hex = (input) =>
  createHash('sha256').update(typeof input === 'string' ? Buffer.from(input, 'utf8') : input).digest('hex');

// ------------------------------------------------------------------------------------------------ cell handling
const STRIP = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u00AD\u061C\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]/gu;
const GUARD = /^[=+@\t\r\n-]/;
const NEEDS_QUOTE = /[",\r\n]/;

export function cleanText(value) {
  let s = String(value ?? '').toWellFormed().normalize('NFC');
  s = s.replace(STRIP, '').normalize('NFC');
  return s.replace(/\r\n?/g, '\n');
}

/** One CSV cell. kind: 'text' (cleaned + formula-guarded) or 'int' (digits only). */
export function csvCell(value, kind = 'text') {
  if (kind === 'int') {
    const t = typeof value === 'number' ? String(value) : value;
    if (typeof t !== 'string' || !/^[0-9]{1,15}$/.test(t)) throw bad('export_cell_invalid: integer cell must be 1-15 digits');
    return t;
  }
  if (kind !== 'text') throw bad('export_cell_invalid: unknown cell kind');
  let s = cleanText(value);
  if (GUARD.test(s)) s = `'${s}`;
  if ([...s].length > LIMITS.maxCellChars) throw bad(`export_cell_too_long: a cell exceeds ${LIMITS.maxCellChars} characters`);
  if (NEEDS_QUOTE.test(s)) s = `"${s.replaceAll('"', '""')}"`;
  return s;
}

// ------------------------------------------------------------------------------------------------ secrets / PII
// Mirrors c10_gov003_demo.looks_secret (020_audit_core.sql). Drift is checked by the parity test.
const SECRET_RES = [
  /eyJ[A-Za-z0-9_-]{8,}/,
  /(bearer\s|service[_-]?role|passw(or)?d|secret|api[_-]?key|token|private[_-]?key|authorization)/i,
  /[^\s@]+@[^\s@]+\.[A-Za-z]{2,}/,
  /(^|[^0-9A-Za-z-])[0-9]{13,19}($|[^0-9A-Za-z-])/,
  /^[0-9]{9,}$/,
  /\n\s+at /,
];
export const looksSecret = (s) => SECRET_RES.some((re) => re.test(String(s ?? '')));

// Mirrors c10_gov003_demo.payload_allowlist (020). Only these field names may reach an export.
export const PAYLOAD_ALLOWLIST = Object.freeze([
  'amount_minor', 'currency', 'item_ref', 'quantity_milli', 'unit', 'status', 'old_status', 'new_status',
  'reason_code', 'entity_ref', 'entity_kind', 'source_ref', 'channel', 'window_start', 'window_end', 'count',
  'expected_count', 'row_count', 'grant_ref', 'policy_ref', 'severity', 'note_code', 'signal_ref', 'review_decision',
  'evidence_ref', 'artifact_sha256', 'commit_sha', 'report_id', 'filter_ref', 'hold_ref', 'case_ref', 'feature_id',
  'requirement_id', 'receipt_ref', 'batch_ref', 'doc_ref', 'method', 'detail_code', 'observed_at', 'last_seen_at',
]);

export function payloadText(payload, allowlist = PAYLOAD_ALLOWLIST) {
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) return '';
  const allowed = new Set(allowlist);
  const parts = [];
  for (const key of Object.keys(payload).filter((k) => allowed.has(k)).sort()) {
    const raw = payload[key];
    let sv = typeof raw === 'string' ? raw : raw === null ? '' : JSON.stringify(raw);
    if (looksSecret(sv)) sv = '[withheld]';
    else {
      sv = cleanText(sv).replaceAll(';', '%3B');
      if (GUARD.test(sv) && !/^-?[0-9]+$/.test(sv)) sv = `'${sv}`;
    }
    parts.push(`${key}=${sv}`);
  }
  return parts.join(';');
}

// ------------------------------------------------------------------------------------------------ writer
/**
 * @param {{columns: {name: string, kind?: 'text'|'int'}[], rows: any[][], maxRows?: number}} spec
 * @returns {{text: string, bytes: Buffer, sha256: string, byteLength: number, rowCount: number, spec: string}}
 */
export function writeCsv({ columns, rows, maxRows = LIMITS.maxRows }) {
  if (!Number.isInteger(maxRows) || maxRows < 1 || maxRows > LIMITS.maxRows) throw bad('export_param_invalid: max_rows must be 1..10000');
  for (const c of columns) if (!/^[a-z][a-z0-9_]*$/.test(c.name)) throw bad('export_param_invalid: column name');
  if (rows.length > maxRows) {
    throw bad(`export_truncated: matching rows exceed the cap of ${maxRows} rows; narrow the filter (no silent cut)`);
  }
  const lines = [columns.map((c) => c.name).join(',')];
  for (const row of rows) {
    if (row.length !== columns.length) throw bad('export_cell_invalid: row width differs from header');
    const line = row.map((v, i) => csvCell(v, columns[i].kind ?? 'text')).join(',');
    if (Buffer.byteLength(line, 'utf8') > LIMITS.maxRowBytes) throw bad(`export_row_too_long: a CSV record exceeds ${LIMITS.maxRowBytes} bytes`);
    lines.push(line);
  }
  const text = `${lines.join('\r\n')}\r\n`;
  const bytes = Buffer.from(text, 'utf8');
  if (bytes.length > LIMITS.maxBytes) throw bad('export_too_large: CSV exceeds 8 MiB');
  return { text, bytes, sha256: sha256Hex(bytes), byteLength: bytes.length, rowCount: rows.length, spec: CSV_SPEC };
}

export const AUDIT_COLUMNS = Object.freeze([
  { name: 'event_id' }, { name: 'stream_seq', kind: 'int' }, { name: 'event_time' }, { name: 'action' },
  { name: 'source_domain' }, { name: 'source_id' }, { name: 'source_version' }, { name: 'receipt_id' },
  { name: 'event_digest' }, { name: 'payload_fields' },
]);

const MICRO_ISO = /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$/;
export function toUtcIso(value) {
  if (typeof value === 'string' && MICRO_ISO.test(value)) return value;
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) throw bad('export_param_invalid: not a timestamp');
  return d.toISOString().replace('Z', '000Z');
}

/**
 * Audit-journal rows (as the scoped view returns them, event_time already UTC ISO or Date) -> g3csv1 file.
 * @param {{event_id: string, stream_seq: number|string, event_time: string|Date, action: string, source_domain: string,
 *   source_id: string, source_version: string, receipt_id: string, event_digest: string, payload: object}[]} events
 */
export function auditExportCsv(events, { maxRows = LIMITS.maxRows } = {}) {
  const sorted = [...events].sort((a, b) => Number(a.stream_seq) - Number(b.stream_seq));
  const rows = sorted.map((e) => [
    e.event_id, String(e.stream_seq), toUtcIso(e.event_time), e.action, e.source_domain, e.source_id,
    e.source_version, e.receipt_id, e.event_digest, payloadText(e.payload),
  ]);
  return writeCsv({ columns: AUDIT_COLUMNS, rows, maxRows });
}

// ------------------------------------------------------------------------------------------------ filter + receipt
export function canonicalFlat(obj) {
  return `{${Object.keys(obj).sort().map((k) => {
    if (typeof obj[k] !== 'string') throw bad('canonical: only string values are supported');
    return `${JSON.stringify(k)}:${JSON.stringify(obj[k])}`;
  }).join(',')}}`;
}

/** Same normalized filter as export_audit_csv(): UTC micro ISO times, string max_rows, null keys dropped. */
export function normalizeFilter({ from = null, to = null, action = null, sourceDomain = null, maxRows = LIMITS.maxRows } = {}) {
  if (!Number.isInteger(maxRows) || maxRows < 1 || maxRows > LIMITS.maxRows) throw bad('export_param_invalid: max_rows must be 1..10000');
  const token = /^[a-z][a-z0-9_.-]{1,63}$/;
  if (action !== null && !token.test(action)) throw bad('export_param_invalid: action filter');
  if (sourceDomain !== null && !token.test(sourceDomain)) throw bad('export_param_invalid: source_domain filter');
  const f = from === null ? null : toUtcIso(from);
  const t = to === null ? null : toUtcIso(to);
  if (f !== null && t !== null && f >= t) throw bad('export_param_invalid: from must be before to');
  const filter = { max_rows: String(maxRows), report_id: REPORT_ID };
  if (action !== null) filter.action = action;
  if (f !== null) filter.from = f;
  if (sourceDomain !== null) filter.source_domain = sourceDomain;
  if (t !== null) filter.to = t;
  const canonical = canonicalFlat(filter);
  return { filter, canonical, filterSha256: sha256Hex(canonical) };
}

/** Mirrors export_receipt_digest_of() in SQL. `issuedAt` must be the UTC micro ISO string. */
export function exportReceiptDigest(r) {
  return sha256Hex(['g3x1', r.exportReceiptId, r.tenantId, r.businessId, r.actorId, r.idempotencyKey, r.filterSha256,
    String(r.sourceSeq), r.sourceVersion, String(r.rowCount), r.byteSha256, String(r.byteLength), r.auditEventDigest,
    toUtcIso(r.issuedAt)].join('|'));
}

/** Content check against a receipt-like object: any difference or a missing receipt is G3A04 (matches verify_export). */
export function verifyExportBytes(receipt, content) {
  if (!receipt || typeof receipt.byte_sha256 !== 'string') throw new CsvExportError('G3A04', 'export_receipt_missing: no receipt for this claim');
  const bytes = typeof content === 'string' ? Buffer.from(content, 'utf8') : content;
  if (!Buffer.isBuffer(bytes) && !(bytes instanceof Uint8Array)) throw new CsvExportError('G3A04', 'export_content_hash_mismatch: no content supplied');
  const sha = sha256Hex(bytes);
  if (sha !== receipt.byte_sha256 || bytes.length !== Number(receipt.byte_length)) {
    throw new CsvExportError('G3A04', 'export_content_hash_mismatch: supplied bytes do not match the recorded SHA-256');
  }
  return { ok: true, sha256: sha, byteLength: bytes.length };
}

// ------------------------------------------------------------------------------------------------ RFC 4180 reader
/** Minimal strict RFC 4180 parser for verification/tests. Returns string[][]; throws on malformed quoting. */
export function parseCsv(text) {
  const out = []; let row = []; let cell = ''; let i = 0; let quoted = false; let atCellStart = true;
  while (i < text.length) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { cell += '"'; i += 2; continue; }
        quoted = false; i += 1; continue;
      }
      cell += c; i += 1; continue;
    }
    if (c === '"' && atCellStart) { quoted = true; atCellStart = false; i += 1; continue; }
    if (c === '"') throw new CsvExportError('G3A03', 'csv_malformed: quote inside an unquoted cell');
    if (c === ',') { row.push(cell); cell = ''; atCellStart = true; i += 1; continue; }
    if (c === '\r' && text[i + 1] === '\n') { row.push(cell); out.push(row); row = []; cell = ''; atCellStart = true; i += 2; continue; }
    if (c === '\r' || c === '\n') throw new CsvExportError('G3A03', 'csv_malformed: bare CR/LF outside quotes');
    cell += c; atCellStart = false; i += 1;
  }
  if (quoted) throw new CsvExportError('G3A03', 'csv_malformed: unterminated quote');
  if (cell !== '' || row.length) { row.push(cell); out.push(row); }
  return out;
}
