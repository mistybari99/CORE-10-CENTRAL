#!/usr/bin/env bash
# PACK-02 disposable SQL runner. Loopback PostgreSQL only; creates and drops
# its own database. Never point this at a hosted or production project.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "${CORE10_PACK02_DISPOSABLE_ACK:-}" == I_CONFIRM_PACK02_DISPOSABLE ]] || { echo 'ACK required'; exit 2; }
case "${PGHOST:-}" in localhost|127.0.0.1) ;; *) echo 'Loopback database required'; exit 2;; esac
suite=${1:-all}
if [[ "$suite" == all ]]; then
  for area in workspace regression controls scale portfolio agreement; do bash tests/pack02/run-sql.sh "$area"; done
  exit 0
fi
case "$suite" in workspace) tests=(tests/pack02/workspace-e2e.sql);;
 # Unchanged Build01 integration must still pass with PACK-02 loaded.
 regression) tests=(tests/build01/access-integration.sql);;
 controls) tests=(tests/pack02/controls-e2e.sql);;
 scale) tests=(tests/pack02/scale-e2e.sql);;
 portfolio) tests=(tests/pack02/portfolio-e2e.sql);;
 agreement) tests=(tests/pack02/agreement-e2e.sql);;
 app) tests=(tests/pack02/app-browser.cjs);;
 *) exit 2;; esac
database="core10_preview_pack02_${BASHPID}"
extra=()
if [[ "$suite" == portfolio || "$suite" == agreement ]]; then
  # A050 gates on its own disposable database prefix and the A048/A049 stack.
  database="core10_a048_local_pack02_${BASHPID}"
  extra=(internal/enterprise-sql/c10_a048_inventory_commands_v1.sql
   internal/enterprise-sql/c10_a049_operation_workflow_v1.sql
   internal/enterprise-sql/c10_a050_owner_portfolio_v1.sql)
fi
owned=''
cleanup(){ if [[ -n "$owned" ]]; then PGDATABASE=postgres psql -X -q -c "DROP DATABASE IF EXISTS \"$owned\"" || true; fi; }
trap cleanup EXIT
PGDATABASE=postgres psql -X -q -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$database\""
owned=$database
export PGDATABASE=$database
psql=(psql -X -q -v ON_ERROR_STOP=1)
"${psql[@]}" -c "DO \$\$ BEGIN IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF; IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF; END \$\$"
# Same canonical order as tests/build01/run-load.sh, then the additive PACK-02 file.
for file in \
 internal/enterprise-sql/c10_a018_demo_backend.sql \
 tests/c10_a018_demo_seed.sql \
 internal/enterprise-sql/c10_a018_inventory_v1.sql \
 internal/enterprise-sql/c10_a020_business_setup_v1.sql \
 internal/enterprise-sql/c10_a020_industry_draft_v2.sql \
 internal/enterprise-sql/c10_a021_owner_controls_v1.sql \
 internal/enterprise-sql/c10_a034_access_governance_v1.sql \
 internal/enterprise-sql/c10_build01_access_integration_v1.sql \
 internal/enterprise-sql/c10_pack02_workspace_v1.sql \
 internal/enterprise-sql/c10_a044_control_settings_v1.sql \
 internal/enterprise-sql/c10_pack02_controls_v1.sql \
 "${extra[@]}"; do
  printf 'LOAD %s\n' "$file"
  "${psql[@]}" -f "$file"
done
for test in "${tests[@]}"; do
  printf 'TEST %s\n' "$test"
  if [[ "$test" == *.cjs ]]; then node "$test"; else "${psql[@]}" -f "$test"; fi
done
echo "PASS PACK-02 $suite; synthetic claim fixtures only"
