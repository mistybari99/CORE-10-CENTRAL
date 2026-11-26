#!/usr/bin/env bash
# Extend the preserved Stock regression in memory without changing its pinned blob.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY' | psql -X -q -v ON_ERROR_STOP=1
from pathlib import Path
source = Path("tests/migrations/np03a-lots-e2e.sql").read_text()
# Insert only at unique known boundaries; fail closed on source drift.
anchor1 = "SELECT pg_temp.cmd(2,2,'transfer',1901111,1901121,19102,2,:g_2,NULL,'lotk-xe3')"
anchor2 = "SELECT pg_temp.ok(pg_temp.lb(1901111,'G-2')=3"
for anchor, addition in [
    (anchor1, """SELECT pg_temp.ok((core10.advance_inventory_command_v1(
  (:'e2'::jsonb->>'command_id')::bigint,'post',2,'lotk-xe2-p')->>'stock_ref')=(:'e2'::jsonb->>'stock_ref'),
 'showroom transfer retry resolves to the original transfer');
"""),
    (anchor2, """SELECT pg_temp.ok((SELECT count(*)=2 AND sum(delta)=0
 FROM core10.stock_movements WHERE transfer_id=(:'e2'::jsonb->>'stock_ref')::bigint),
 'showroom transfer retry leaves exactly two balanced movement legs');
"""),
]:
    if source.count(anchor) != 1:
        raise SystemExit("Bakery lot regression source changed: " + anchor)
    source = source.replace(anchor, addition + anchor)
print(source)
PY
