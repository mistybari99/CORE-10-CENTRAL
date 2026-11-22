'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

// Source-order regression only; PG17 revocation-while-waiting is still required.
const file = path.join(__dirname, '..', '..', 'internal', 'migrations', '0201_np03a_inventory_commands.up.sql');
function verify(sql) {
  const start = sql.indexOf('SELECT * INTO c FROM core10.inventory_commands_v1 WHERE id=p_command FOR UPDATE;');
  assert.ok(start >= 0, 'command row must be locked');
  const tail = sql.slice(start);
  const auth = tail.indexOf('core10._inventory_may_act_v1(c.tenant_id,c.business_id,c.source_location,c.destination_location)');
  const scope = tail.indexOf('core10.can_see_business(c.tenant_id,c.business_id)');
  const effect = Math.min(...['core10.transfer_stock_v1(', 'core10.post_stock_event('].map(x => {
    const p = tail.indexOf(x); return p < 0 ? Infinity : p;
  }));
  assert.ok(scope >= 0 && scope < effect, 'post-lock business scope must precede stock effect');
  assert.ok(auth >= 0 && auth < effect, 'post-lock source AND destination authorization must precede stock effect');
}
const fixture = `SELECT * INTO c FROM core10.inventory_commands_v1 WHERE id=p_command FOR UPDATE;
IF NOT core10.can_see_business(c.tenant_id,c.business_id) THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
IF NOT core10._inventory_may_act_v1(c.tenant_id,c.business_id,c.source_location,c.destination_location) THEN RAISE EXCEPTION 'INV_PERMISSION_DENIED'; END IF;
v_ref := core10.transfer_stock_v1(...);`;
test('guard accepts post-lock scope and both location rights before posting', () => verify(fixture));
test('guard rejects missing post-lock location check', () => assert.throws(() => verify(fixture.replace(/IF NOT core10\._inventory_may_act_v1[^\n]+\n/, '')), /post-lock source/));
test('guard rejects location check after stock posting', () => assert.throws(() => verify(fixture.replace(/IF NOT core10\._inventory_may_act_v1[^\n]+\n/, '').concat('\nIF NOT core10._inventory_may_act_v1(c.tenant_id,c.business_id,c.source_location,c.destination_location) THEN RAISE EXCEPTION; END IF;')), /post-lock source/));
test('exact-checkout 0201 stock writer retains post-lock authorization', () => verify(fs.readFileSync(file, 'utf8')));
