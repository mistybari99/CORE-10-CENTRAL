'use strict';
// Lane B regression: invoke the REAL migration runner against a disposable fake psql.
// No database credentials, hosted writes or migration SQL execution.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');

test('down refuses a symlinked rollback companion escaping the migration directory', () => {
  const root = path.resolve(__dirname, '../..');
  const source = fs.readFileSync(path.join(root, 'internal/migrations/run.sh'), 'utf8');
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'core10-laneb-symlink-'));
  try {
    const dir = path.join(tmp, 'internal/migrations');
    const bin = path.join(tmp, 'bin');
    fs.mkdirSync(dir, { recursive: true });
    fs.mkdirSync(bin);
    const runner = path.join(dir, 'run.sh');
    fs.writeFileSync(runner, source, { mode: 0o755 });
    const name = '0206_safe';
    fs.writeFileSync(path.join(dir, name + '.up.sql'), '-- synthetic UP only\n');
    const outside = path.join(tmp, 'outside.down.sql');
    fs.writeFileSync(outside, '-- synthetic OUTSIDE marker; never execute\n');
    fs.symlinkSync(outside, path.join(dir, name + '.down.sql'));
    const marker = path.join(tmp, 'rollback-invoked');
    const fake = path.join(bin, 'psql');
    fs.writeFileSync(fake, `#!/usr/bin/env bash
args="$*"
case "$args" in
  *"select 1"*) echo 1 ;;
  *"to_regclass"*) echo t ;;
  *"select version from core10.schema_migrations"*) echo 206 ;;
  *"select name from core10.schema_migrations"*) echo 0206_safe ;;
  *"-f "*) printf '%s\\n' "$args" > "$CORE10_TEST_MARKER" ;;
esac
`, { mode: 0o755 });
    const run = cp.spawnSync('bash', [runner, 'down'], {
      encoding: 'utf8',
      timeout: 5000,
      env: { ...process.env, PATH: bin + path.delimiter + process.env.PATH,
        CORE10_TEST_MARKER: marker, DATABASE_URL: '' },
    });
    assert.equal(run.error, undefined, String(run.error));
    assert.notEqual(run.status, 0, 'symlink escape must fail closed before rollback');
    assert.equal(fs.existsSync(marker), false, 'rollback transaction must not be invoked');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
