'use strict';
const fs = require('node:fs');
const path = require('node:path');

/** Read-only preflight for a migration runner's latest applied ledger row.
 * Never execute SQL using ledger-controlled names before this succeeds.
 */
function validateRollbackTarget({ directory, version, name, checksum }) {
  const v = String(version);
  if (!/^[0-9]{1,4}$/.test(v) || !Number.isSafeInteger(Number(v))) throw new Error('INVALID_LEDGER_VERSION');
  if (typeof name !== 'string' || !/^[0-9]{4}_[a-z0-9][a-z0-9_-]*$/.test(name)) throw new Error('INVALID_LEDGER_NAME');
  if (Number(name.slice(0, 4)) !== Number(v)) throw new Error('LEDGER_VERSION_MISMATCH');
  if (typeof checksum !== 'string' || !/^[0-9a-f]{64}$/.test(checksum)) throw new Error('INVALID_LEDGER_CHECKSUM');
  const root = fs.realpathSync(directory);
  const up = path.join(root, `${name}.up.sql`);
  const down = path.join(root, `${name}.down.sql`);
  for (const candidate of [up, down]) {
    if (!fs.statSync(candidate).isFile() || path.dirname(fs.realpathSync(candidate)) !== root) throw new Error('MIGRATION_PATH_ESCAPE');
  }
  return Object.freeze({ up, down, version: Number(v), name, checksum });
}
module.exports = { validateRollbackTarget };
