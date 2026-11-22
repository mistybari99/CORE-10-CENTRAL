'use strict';
// Executes the repository runner against a local fake psql. No hosted database access.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const runner = path.resolve(__dirname, '../../internal/migrations/run.sh');
function fixture({ down = true, failApply = false } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'core10-atomic-'));
  const migrations = path.join(root, 'migrations');
  const bin = path.join(root, 'bin');
  fs.mkdirSync(migrations);
  fs.mkdirSync(bin);
  fs.copyFileSync(runner, path.join(migrations, 'run.sh'));
  fs.writeFileSync(path.join(migrations, '0207_fixture.up.sql'), 'SELECT 1;\n');
  if (down) fs.writeFileSync(path.join(migrations, '0207_fixture.down.sql'), 'SELECT 1;\n');
  const psql = path.join(bin, 'psql');
  fs.writeFileSync(psql, `#!/bin/sh
printf '%s\\n' "$*" >> "$CORE10_PSQL_LOG"
for arg do
  if [ "$prev" = "-c" ]; then sql="$arg"; break; fi
  prev="$arg"
done
case "$sql" in
  "select 1") echo 1 ;;
  *"to_regclass"*) echo t ;;
  *"select version from core10.schema_migrations"*) echo 206 ;;
  *"insert into core10.schema_migrations"*)
    if [ "$CORE10_FAIL_APPLY" = "1" ]; then exit 42; fi ;;
  *) echo "UNEXPECTED_SQL:$sql" >&2; exit 93 ;;
esac
`);
  fs.chmodSync(psql, 0o755);
  const log = path.join(root, 'psql.log');
  const result = spawnSync('bash', [path.join(migrations, 'run.sh'), 'up'], {
    encoding: 'utf8', timeout: 10000,
    env: { ...process.env, PATH: bin + path.delimiter + process.env.PATH,
      DATABASE_URL: '', CORE10_PSQL_LOG: log, CORE10_FAIL_APPLY: failApply ? '1' : '0' }
  });
  const calls = fs.existsSync(log) ? fs.readFileSync(log, 'utf8').split('\n').filter(Boolean) : [];
  fs.rmSync(root, { recursive: true, force: true });
  assert.equal(result.error, undefined, String(result.error));
  assert.doesNotMatch(result.stderr, /UNEXPECTED_SQL/);
  return { result, calls };
}

test('missing rollback companion fails before any migration SQL executes', () => {
  const { result, calls } = fixture({ down: false });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /MISSING_DOWN 0207_fixture/);
  assert.equal(calls.some(c => /-f |insert into core10\.schema_migrations/.test(c)), false);
});

test('successful migration uses one transaction for SQL and checksum ledger insert', () => {
  const { result, calls } = fixture();
  assert.equal(result.status, 0, result.stderr);
  const apply = calls.filter(c => /-f |insert into core10\.schema_migrations/.test(c));
  assert.equal(apply.length, 1, 'SQL and ledger insert must share one psql invocation');
  assert.match(apply[0], /-1 /);
  assert.match(apply[0], /-f .*0207_fixture\.up\.sql/);
  assert.match(apply[0], /insert into core10\.schema_migrations/);
  assert.match(apply[0], /[a-f0-9]{64}/);
});

test('failed transactional apply is not reported as applied', () => {
  const { result, calls } = fixture({ failApply: true });
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /applied 0207_fixture/);
  assert.equal(calls.filter(c => /-f .*0207_fixture\.up\.sql/.test(c)).length, 1);
});
