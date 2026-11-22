'use strict';
// Real repository runner, disposable fake psql only. No database connections.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const source = path.resolve(__dirname, '../../internal/migrations/run.sh');
function attempt(name, checksum) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'core10-down-boundary-'));
  try {
    const migrationDir = path.join(root, 'internal', 'migrations');
    const binDir = path.join(root, 'bin');
    fs.mkdirSync(migrationDir, { recursive: true });
    fs.mkdirSync(binDir);
    fs.copyFileSync(source, path.join(migrationDir, 'run.sh'));
    fs.writeFileSync(path.join(migrationDir, '0206_safe.up.sql'), 'select 1;\n');
    fs.writeFileSync(path.join(migrationDir, '0206_safe.down.sql'), 'select 2;\n');
    fs.writeFileSync(path.join(root, 'outside.down.sql'), 'select 3;\n');
    const fake = `#!/usr/bin/env node
const fs=require('node:fs');
const a=process.argv.slice(2); const sql=a[a.indexOf('-c')+1]||'';
if(a.includes('-1')) { fs.appendFileSync(process.env.TRACE_FILE, 'TRANSACTION\\n'); process.exit(0); }
if(sql.includes('to_regclass')) console.log('t');
else if(sql.includes('select version')) console.log('206');
else if(sql.includes('select name')) console.log(process.env.LEDGER_NAME);
else if(sql.includes('select checksum')) console.log(process.env.LEDGER_CHECKSUM);
else if(sql.includes('select 1')) console.log('1');
`;
    fs.writeFileSync(path.join(binDir, 'psql'), fake, { mode: 0o755 });
    const trace = path.join(root, 'trace');
    const result = spawnSync('bash', [path.join(migrationDir, 'run.sh'), 'down'], {
      encoding: 'utf8', timeout: 5000,
      env: { ...process.env, PATH: `${binDir}:${process.env.PATH}`, LEDGER_NAME: name,
        LEDGER_CHECKSUM: checksum, TRACE_FILE: trace },
    });
    return { status: result.status, stderr: result.stderr, stdout: result.stdout,
      transaction: fs.existsSync(trace) && fs.readFileSync(trace, 'utf8').includes('TRANSACTION') };
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
}

test('rollback rejects ledger name traversal before any SQL transaction', () => {
  const r = attempt('../outside', '0'.repeat(64));
  assert.notEqual(r.status, 0, `unsafe rollback succeeded: ${r.stdout}`);
  assert.equal(r.transaction, false, 'rollback SQL was invoked for untrusted ledger name');
});

test('rollback rejects applied UP checksum drift before any SQL transaction', () => {
  const r = attempt('0206_safe', 'f'.repeat(64));
  assert.notEqual(r.status, 0, `checksum drift accepted: ${r.stdout}`);
  assert.equal(r.transaction, false, 'rollback SQL was invoked despite checksum drift');
});
