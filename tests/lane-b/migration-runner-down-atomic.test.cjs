'use strict';
// Down-path transactional regression: only local fake psql, never a hosted database.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const runner = path.resolve(__dirname, '../../internal/migrations/run.sh');
function runDown({ fail = false, missing = false } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'core10-down-atomic-'));
  try {
    const dir = path.join(root, 'migrations'), bin = path.join(root, 'bin');
    fs.mkdirSync(dir); fs.mkdirSync(bin);
    fs.copyFileSync(runner, path.join(dir, 'run.sh'));
    if (!missing) fs.writeFileSync(path.join(dir, '0206_fixture.down.sql'), 'SELECT 1;\n');
    const log = path.join(root, 'calls.log');
    const psql = path.join(bin, 'psql');
    fs.writeFileSync(psql, `#!/bin/sh
printf '%s\\n' "$*" >> "$CORE10_PSQL_LOG"
prev=""
sql=""
for arg do
  if [ "$prev" = "-c" ]; then sql="$arg"; break; fi
  prev="$arg"
done
case "$sql" in
  "select 1") echo 1 ;;
  *"to_regclass"*) echo t ;;
  *"select version from core10.schema_migrations"*) echo 206 ;;
  *"select name from core10.schema_migrations where version=206"*) echo 0206_fixture ;;
  *"delete from core10.schema_migrations where version=206"*)
    if [ "$CORE10_FAIL_DOWN" = "1" ]; then exit 42; fi ;;
  *) echo "UNEXPECTED_SQL:$sql" >&2; exit 93 ;;
esac
`);
    fs.chmodSync(psql, 0o755);
    const result = spawnSync('bash', [path.join(dir, 'run.sh'), 'down'], {
      encoding: 'utf8', timeout: 10000,
      env: { ...process.env, PATH: bin + path.delimiter + process.env.PATH,
        DATABASE_URL: '', CORE10_PSQL_LOG: log, CORE10_FAIL_DOWN: fail ? '1' : '0' }
    });
    const calls = fs.existsSync(log) ? fs.readFileSync(log, 'utf8').split('\n').filter(Boolean) : [];
    assert.equal(result.error, undefined, String(result.error));
    assert.doesNotMatch(result.stderr, /UNEXPECTED_SQL/);
    return { result, calls };
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
}

test('down executes ledger deletion and rollback SQL in a single transaction', () => {
  const { result, calls } = runDown();
  assert.equal(result.status, 0, result.stderr);
  const writes = calls.filter(c => /delete from core10\.schema_migrations|-f .*\.down\.sql/.test(c));
  assert.equal(writes.length, 1, 'ledger and down SQL must use the same psql invocation');
  assert.match(writes[0], /-1 /);
  assert.match(writes[0], /delete from core10\.schema_migrations where version=206/);
  assert.match(writes[0], /-f .*0206_fixture\.down\.sql/);
  assert.match(result.stdout, /rolled back 0206_fixture/);
});

test('failed down does not report successful rollback', () => {
  const { result, calls } = runDown({ fail: true });
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /rolled back 0206_fixture/);
  assert.equal(calls.filter(c => /delete from core10\.schema_migrations/.test(c)).length, 1);
});

test('missing down script does not report rollback', () => {
  const { result } = runDown({ missing: true });
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /rolled back 0206_fixture/);
});
