'use strict';
// Lane B regression: an applied UP file must not be rolled back after checksum drift.
// This is an intentionally RED test on the current runner; do not merge until fixed.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../../internal/migrations/run.sh'),'utf8');

test('down checks applied UP checksum before rollback SQL and ledger deletion',()=>{
  const down=source.match(/\n down\)\s*([\s\S]*?)\n status\)/);
  assert.ok(down,'runner down case must exist');
  assert.match(down[1],/select\s+checksum\s+from\s+core10\.schema_migrations/i,
    'down must read the applied ledger checksum');
  assert.match(down[1],/sum\s+"?\$DIR\/\$n\.up\.sql"?/,
    'down must compare the applied checksum to the original UP file');
  const check=down[1].search(/select\s+checksum\s+from\s+core10\.schema_migrations/i);
  const execute=down[1].search(/\$\{PSQL\[@\]\}.*-1\s+-c/);
  assert.ok(check>=0 && execute>check,'checksum validation must precede rollback execution');
});
