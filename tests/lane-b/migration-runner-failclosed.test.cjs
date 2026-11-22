'use strict';
// Execute the real migration runner against a disposable fake psql transport.
// No database connection, hosted writes, or historical migration edits.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const sourceRunner = path.resolve(__dirname, '../../internal/migrations/run.sh');

function runScenario(mode, expectedError) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'core10-runner-negative-'));
  try {
    const migrations = path.join(tmp, 'migrations');
    const bin = path.join(tmp, 'bin');
    fs.mkdirSync(migrations);
    fs.mkdirSync(bin);
    fs.copyFileSync(sourceRunner, path.join(migrations, 'run.sh'));
    fs.writeFileSync(path.join(migrations, '0205_lane_b_fixture.up.sql'), 'SELECT 1;\n');
    fs.writeFileSync(path.join(migrations, '0205_lane_b_fixture.down.sql'), 'SELECT 1;\n');
    const psql = path.join(bin, 'psql');
    fs.writeFileSync(psql, `#!/bin/sh
for arg do
  if [ "$prev" = "-c" ]; then sql="$arg"; break; fi
  prev="$arg"
done
case "$sql" in
  "select 1") echo 1 ;;
  *"to_regclass"*) echo t ;;
  *"select version from core10.schema_migrations"*)
    if [ "$CORE10_MOCK_MODE" = "out_of_order" ]; then echo 206; else echo 205; fi ;;
  *"select checksum from core10.schema_migrations"*) echo intentionally-wrong-sha256 ;;
  *) echo "UNEXPECTED_SQL:$sql" >&2; exit 93 ;;
esac
`);
    fs.chmodSync(psql, 0o755);
    const result = spawnSync('bash', [path.join(migrations, 'run.sh'), 'up'], {
      encoding: 'utf8',
      env: { ...process.env, PATH: bin + path.delimiter + process.env.PATH,
        CORE10_MOCK_MODE: mode, DATABASE_URL: '' },
      timeout: 10000
    });
    assert.equal(result.error, undefined, String(result.error));
    assert.notEqual(result.status, 0, 'runner must fail closed');
    assert.match(result.stderr, expectedError);
    assert.doesNotMatch(result.stderr, /UNEXPECTED_SQL/);
    assert.doesNotMatch(result.stdout, /applied 0205/);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

test('unapplied lower version is rejected before executing SQL', () => {
  runScenario('out_of_order', /OUT_OF_ORDER 0205_lane_b_fixture/);
});

test('applied migration with mismatched checksum is rejected before executing SQL', () => {
  runScenario('checksum_drift', /CHECKSUM_DRIFT 0205_lane_b_fixture/);
});
