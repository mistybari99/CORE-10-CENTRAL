#!/usr/bin/env bash
# C10-A053/A054 disposable stack builder (PostgreSQL, NEVER Supabase). Usage: c10_a053_stack.sh full|reg|base
#  full: A018 + seed + A046 personas, rename, A020/A018-inv/A048/A049/A050 portfolio, A051 + seed  (db core10_a053_ci)
#  base: A018 + seed + A046 personas, A050 stack WITHOUT A051 (db core10_a053_ci_noa051) -> proves NOT CONNECTED path
#  reg : A018 + seed + A051 (+seed) only (db core10_a053_ci_reg) -> A051 baseline regression with A054 patches
# The A046/A048 gates insist on database-name prefixes; the script renames the disposable database between phases.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE=${1:-full}
P="psql -X -q -v ON_ERROR_STOP=1"
SQL=internal/enterprise-sql
admin(){ PGDATABASE=postgres $P "$@"; }
mk(){ admin -c "DROP DATABASE IF EXISTS $1" -c "CREATE DATABASE $1"; }
mv(){ admin -c "ALTER DATABASE $1 RENAME TO $2"; }
admin -c "DO \$\$BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF; IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF; END\$\$"
a051(){ for f in core attendance_leave payroll reads; do PGDATABASE=$1 $P -f $SQL/c10_a051_workforce_${f}_v1.sql; done; PGDATABASE=$1 $P -f tests/c10_a051_workforce_seed.sql; }
a018(){ PGDATABASE=$1 $P -f $SQL/c10_a018_demo_backend.sql; PGDATABASE=$1 $P -f tests/c10_a018_demo_seed.sql; }
a050chain(){ for f in c10_a020_business_setup_v1 c10_a018_inventory_v1 c10_a048_inventory_commands_v1 c10_a049_operation_workflow_v1 c10_a050_owner_portfolio_v1; do PGDATABASE=$1 $P -f $SQL/$f.sql; done; }
case "$MODE" in
 reg) mk core10_a053_ci_reg; a018 core10_a053_ci_reg; a051 core10_a053_ci_reg;;
 base|full)
  T=core10_a046_ci_a053_$MODE; N=core10_a048_ci_a053_$MODE
  F=core10_a053_ci; [ "$MODE" = base ] && F=core10_a053_ci_noa051
  mk $T; a018 $T
  PGDATABASE=$T $P -v c10_demo_ack=I_CONFIRM_DISPOSABLE_A046 -f $SQL/c10_a046_demo_personas_v1.sql
  mv $T $N; a050chain $N
  if [ "$MODE" = full ]; then a051 $N
   for f in c10_a054_workforce_policy_v1 c10_a054_workforce_bridge_v1; do PGDATABASE=$N $P -f $SQL/$f.sql; done; fi
  PGDATABASE=$N $P -f $SQL/c10_a053_workforce_integration_v1.sql
  admin -c "DROP DATABASE IF EXISTS $F"; mv $N $F;;
 *) echo "usage: $0 full|base|reg"; exit 2;;
esac
echo "stack $MODE ready"
