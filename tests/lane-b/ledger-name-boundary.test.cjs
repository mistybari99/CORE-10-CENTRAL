'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { validateRollbackTarget } = require('./ledger-name-boundary.cjs');
const checksum = 'a'.repeat(64);
function fixture(fn) {
  const parent = fs.mkdtempSync(path.join(os.tmpdir(), 'core10-laneb-'));
  const directory = path.join(parent, 'migrations'); fs.mkdirSync(directory);
  for (const suffix of ['up','down']) fs.writeFileSync(path.join(directory, `0206_stock.${suffix}.sql`), '-- synthetic\n');
  try { fn({ parent, directory, version: '206', name: '0206_stock', checksum }); }
  finally { fs.rmSync(parent, { recursive: true, force: true }); }
}
test('valid canonical ledger row resolves both local files', () => fixture(row => {
  const result = validateRollbackTarget(row);
  assert.equal(path.basename(result.down), '0206_stock.down.sql');
  assert.equal(result.version, 206);
}));
test('rejects traversal, absolute path, and SQL-like ledger names', () => fixture(row => {
  for (const name of ['../outside', '/tmp/outside', '0206_../outside', "0206_stock';drop table x;--", '0206_stock/../x'])
    assert.throws(() => validateRollbackTarget({ ...row, name }), /INVALID_LEDGER_NAME/);
}));
test('rejects ledger name/version mismatch and malformed version', () => fixture(row => {
  assert.throws(() => validateRollbackTarget({ ...row, version: '205' }), /LEDGER_VERSION_MISMATCH/);
  assert.throws(() => validateRollbackTarget({ ...row, version: '206;delete' }), /INVALID_LEDGER_VERSION/);
}));
test('rejects absent rollback companion and invalid SHA256', () => fixture(row => {
  assert.throws(() => validateRollbackTarget({ ...row, checksum: 'bad' }), /INVALID_LEDGER_CHECKSUM/);
  fs.unlinkSync(path.join(row.directory, '0206_stock.down.sql'));
  assert.throws(() => validateRollbackTarget(row), /ENOENT/);
}));
test('rejects symlinked rollback companion escaping migration directory', () => fixture(row => {
  const target = path.join(row.parent, 'outside.sql'); fs.writeFileSync(target, '-- synthetic\n');
  fs.unlinkSync(path.join(row.directory, '0206_stock.down.sql'));
  fs.symlinkSync(target, path.join(row.directory, '0206_stock.down.sql'));
  assert.throws(() => validateRollbackTarget(row), /MIGRATION_PATH_ESCAPE/);
}));
