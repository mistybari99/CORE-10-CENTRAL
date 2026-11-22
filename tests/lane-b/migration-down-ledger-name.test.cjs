'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');

// Run the unmodified repository runner in an isolated directory with fake psql.
// A forged ledger name must not make down execute SQL outside migrations/.
const runner = path.resolve(__dirname, '../../internal/migrations/run.sh');
test('down refuses a ledger name that escapes the migration directory', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'core10-ledger-name-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const migrations = path.join(root, 'migrations');
  const bin = path.join(root, 'bin');
  fs.mkdirSync(migrations); fs.mkdirSync(bin);
  fs.copyFileSync(runner, path.join(migrations, 'run.sh'));
  fs.writeFileSync(path.join(root, 'outside.down.sql'), 'select 999;\n');
  const log = path.join(root, 'executed.log');
  fs.writeFileSync(path.join(bin, 'psql'), `#!/usr/bin/env bash
set -euo pipefail
args=" $* "
case "$args" in
  *" -1 "*) printf '%s\\n' "$args" >> "$MOCK_LOG" ;;
  *"select 1"*) echo 1 ;;
  *"to_regclass"*) echo t ;;
  *"select version from core10.schema_migrations"*) echo 206 ;;
  *"select name from core10.schema_migrations"*) echo '../outside' ;;
  *) echo "unexpected query: $args" >&2; exit 77 ;;
esac
`, {mode:0o755});
  const result = cp.spawnSync('bash', [path.join(migrations, 'run.sh'), 'down'], {
    encoding: 'utf8', env: {...process.env, PATH: `${bin}:${process.env.PATH}`, MOCK_LOG: log}
  });
  assert.notEqual(result.status, 0, `forged ledger name accepted: ${result.stdout}`);
  assert.equal(fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '', '',
    'rollback transaction must not start with a path-traversing ledger name');
});
