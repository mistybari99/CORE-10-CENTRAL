'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const crypto = require('node:crypto');

// Runs a copy of the actual repository runner in a disposable directory.
// Fake psql has no database connectivity and records transaction attempts.
const runner = path.resolve(__dirname, '../../internal/migrations/run.sh');
function scenario(t, ledgerChecksum) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'core10-down-integrity-'));
  t.after(() => fs.rmSync(dir, {recursive:true, force:true}));
  const migrations = path.join(dir, 'migrations');
  const bin = path.join(dir, 'bin');
  fs.mkdirSync(migrations); fs.mkdirSync(bin);
  fs.copyFileSync(runner, path.join(migrations, 'run.sh'));
  const name = '0206_integrity_fixture';
  const up = 'select 1;\n';
  fs.writeFileSync(path.join(migrations, `${name}.up.sql`), up);
  fs.writeFileSync(path.join(migrations, `${name}.down.sql`), 'select 2;\n');
  const actual = crypto.createHash('sha256').update(up).digest('hex');
  const fakePsql = `#!/usr/bin/env bash
set -euo pipefail
args=" $* "
if [[ "$args" == *" -1 "* ]]; then
  printf 'TRANSACTION %s\\n' "$args" >> "$MOCK_LOG"
  exit 0
fi
case "$args" in
  *"select 1"*) echo 1 ;;
  *"to_regclass"*) echo t ;;
  *"select version from core10.schema_migrations"*) echo 206 ;;
  *"select name from core10.schema_migrations"*) echo 0206_integrity_fixture ;;
  *"select checksum from core10.schema_migrations"*) echo "$MOCK_LEDGER_CHECKSUM" ;;
  *) echo "unexpected mock SQL: $args" >&2; exit 77 ;;
esac
`;
  fs.writeFileSync(path.join(bin, 'psql'), fakePsql, {mode:0o755});
  const log = path.join(dir, 'transaction.log');
  const result = cp.spawnSync('bash', [path.join(migrations, 'run.sh'), 'down'], {
    encoding:'utf8', env:{...process.env, PATH:`${bin}:${process.env.PATH}`, MOCK_LEDGER_CHECKSUM:ledgerChecksum === 'valid' ? actual : ledgerChecksum, MOCK_LOG:log}
  });
  return {result, transactions:fs.existsSync(log)?fs.readFileSync(log,'utf8'):''};
}

test('down rejects altered applied UP checksum before executing rollback transaction', t => {
  const {result,transactions} = scenario(t, '0'.repeat(64));
  assert.notEqual(result.status, 0, `rollback unexpectedly succeeded: ${result.stdout}`);
  assert.match(result.stderr, /CHECKSUM_DRIFT/);
  assert.equal(transactions, '', 'rollback SQL must never execute on checksum drift');
});

test('down permits exactly one atomic rollback for matching ledger checksum', t => {
  const {result,transactions} = scenario(t, 'valid');
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /rolled back 0206_integrity_fixture/);
  const lines = transactions.trim().split('\n');
  assert.equal(lines.length, 1, transactions);
  assert.ok(lines[0].includes('delete from core10.schema_migrations'));
  assert.ok(lines[0].includes('0206_integrity_fixture.down.sql'));
});
