// Static safety checks: no secrets, no production URLs, no service role in client/demo, fence on forbidden paths.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(fileURLToPath(import.meta.url), '..', '..', '..');
const roots = ['internal/gov003', 'tests/gov003'].map((p) => join(root, p));
const files = [];
const walk = (d) => { for (const f of readdirSync(d)) { const p = join(d, f); statSync(p).isDirectory() ? walk(p) : files.push(p); } };
roots.forEach(walk);
// Intentional synthetic negative-test vectors (fake JWT-shaped strings used to prove redaction rejects them).
const VECTOR_FILES = new Set(['tests/gov003/node/redact.test.mjs', 'tests/gov003/sql/parity_canonical_redact.test.mjs']);
const failures = [];
const rel = (p) => relative(root, p);
for (const f of files) {
  if (f.endsWith('static-checks.mjs')) continue;
  const text = readFileSync(f, 'utf8');
  const isBrowser = rel(f).startsWith('internal/gov003/client/') || rel(f).startsWith('internal/gov003/demo/');
  if (!VECTOR_FILES.has(rel(f)) && /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\./.test(text)) failures.push(`${rel(f)}: JWT-like literal`);
  if (/sk_(live|test)_[A-Za-z0-9]{8,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}/.test(text)) failures.push(`${rel(f)}: credential-like literal`);
  if (/supabase\.co|\.supabase\.|IMG-ERP-SG/i.test(text) && !/fence|forbidden|never|not /i.test(text)) failures.push(`${rel(f)}: production reference`);
  if (isBrowser && /service[_-]?role/i.test(text) && !/no service[_-]?role|never.*service[_-]?role|without service[_-]?role/i.test(text)) failures.push(`${rel(f)}: service role reference in browser code`);
  if (isBrowser && /\bhttps?:\/\/(?!localhost|127\.0\.0\.1)/.test(text) && !/w3\.org/.test(text)) failures.push(`${rel(f)}: external URL in browser code`);
}
if (failures.length) { console.error(failures.join('\n')); process.exit(1); }
console.log(`static checks OK (${files.length} files scanned)`);
