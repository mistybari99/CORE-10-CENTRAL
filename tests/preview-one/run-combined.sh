#!/usr/bin/env bash
# Synthetic disposable PG17 integration only. No production connection or migration.
set -euo pipefail
cd "$(dirname "$0")/../.."
case "${PGHOST:-}" in localhost|127.0.0.1) ;; *) echo 'Loopback disposable PostgreSQL required'; exit 2;; esac
[[ "${CORE10_PREVIEW_DISPOSABLE_ACK:-}" == I_CONFIRM_DISPOSABLE_PREVIEW ]] || {
  echo 'Set CORE10_PREVIEW_DISPOSABLE_ACK=I_CONFIRM_DISPOSABLE_PREVIEW'; exit 2;
}
suite=${1:-cross-module}
case "$suite" in cross-module|operations|intent|crm|workforce|workforce-policy|assets|assets-policy|assets-registry|assets-planning|assets-workorders|assets-reports|assets-integrated|assets-http) ;; *) echo 'Unknown suite'; exit 2;; esac
if [[ "$suite" == assets ]]; then
  # Original A055 CI runs each area on a fresh database. Preserve that isolation,
  # but install ALL merged preview modules before every original area test.
  for area in policy registry planning workorders reports integrated; do
    bash tests/preview-one/run-combined.sh "assets-$area"
  done
  if [[ "${CORE10_PREVIEW_ASSETS_REST:-0}" == 1 ]]; then
    bash tests/preview-one/run-combined.sh assets-http
  fi
  echo 'PASS all A055 areas + integrated + concurrency + client on combined schemas'
  exit 0
fi
psql=(psql -X -q -v ON_ERROR_STOP=1)
seed_db="core10_a046_ci_preview_${BASHPID}"
work_db="core10_a048_ci_preview_${BASHPID}"
owned_db=''
cleanup() {
  # Only a database successfully created by this invocation is ever removed.
  if [[ -n "$owned_db" ]]; then
    PGDATABASE=postgres "${psql[@]}" -c "DROP DATABASE \"$owned_db\"" || true
  fi
}
trap cleanup EXIT
PGDATABASE=postgres "${psql[@]}" -c "CREATE DATABASE \"$seed_db\""
owned_db=$seed_db
export PGDATABASE=$seed_db
load() { printf 'LOAD %s\n' "$1"; "${psql[@]}" -f "$1"; }
"${psql[@]}" -c "DO \$\$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF; IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF; END \$\$"
load internal/enterprise-sql/c10_a018_demo_backend.sql
load tests/c10_a018_demo_seed.sql
"${psql[@]}" -v c10_demo_ack=I_CONFIRM_DISPOSABLE_A046 -f internal/enterprise-sql/c10_a046_demo_personas_v1.sql
# Preserve original A046/A048 database guards; rename the same disposable DB.
PGDATABASE=postgres "${psql[@]}" -c "ALTER DATABASE \"$seed_db\" RENAME TO \"$work_db\""
owned_db=$work_db
export PGDATABASE=$work_db
for file in \
 c10_a020_business_setup_v1 c10_a021_owner_controls_v1 \
 c10_a044_control_settings_v1 c10_a045_micro_engine_v1 \
 c10_a047_site_topology_v1 c10_a018_inventory_v1 \
 c10_a048_inventory_commands_v1 c10_a049_operation_workflow_v1 \
 c10_a050_owner_portfolio_v1 \
 c10_a051_workforce_core_v1 c10_a051_workforce_attendance_leave_v1 \
 c10_a051_workforce_payroll_v1 c10_a051_workforce_reads_v1 \
 c10_a052_intent_core_v1 c10_a052_intent_guidance_seed_v1 c10_a052_intent_rpc_v1 \
 c10_a054_workforce_policy_v1 c10_a054_workforce_bridge_v1 \
 c10_a053_workforce_integration_v1 \
 c10_a055_assets_core_v1 c10_a055_assets_policy_v1 c10_a055_assets_registry_v1 \
 c10_a055_assets_planning_v1 c10_a055_assets_workorders_v1 \
 c10_a055_assets_reports_v1 c10_a055_assets_lockdown_v1 \
 c10_a056_core_v1 c10_a056_pipeline_v1 c10_a056_growth_v1; do
  load "internal/enterprise-sql/$file.sql"
done
# Each matrix job runs the COMPLETE migration stack in one database before its
# unmodified module regression. Tests never borrow data from another job.
case "$suite" in
 cross-module) load tests/preview-one/cross-module.sql;;
 operations) load tests/c10_a049_operation_workflow_e2e.sql;;
 intent)
  load tests/c10_a052_intent_e2e.sql
  if [[ "${CORE10_PREVIEW_INTENT_BROWSER:-0}" == 1 ]]; then
    node tests/e2e/core10-a052-owner-intent-browser.js
  fi;;
 crm)
  load tests/c10_a056_crm_lifecycle_e2e.sql
  bash tests/c10_a056_concurrency.sh;;
 workforce)
  load tests/c10_a051_workforce_seed.sql
  load tests/c10_a051_workforce_e2e.sql
  bash tests/c10_a051_workforce_concurrency.sh;;
 workforce-policy)
  load tests/c10_a051_workforce_seed.sql
  load tests/c10_a054_policy_e2e.sql
  load tests/c10_a053_integration_e2e.sql
  bash tests/c10_a054_concurrency.sh;;
 assets-policy|assets-registry|assets-planning|assets-workorders|assets-reports)
  load tests/c10_a055_seed.sql
  load "tests/c10_a055_${suite#assets-}_e2e.sql";;
 assets-integrated)
  load tests/c10_a055_seed.sql
  load tests/c10_a055_integrated_e2e.sql
  # The original A055 race script's loader would destroy the combined stack.
  # Adapt ONLY its bootstrap to reuse this disposable database; every original
  # race, expected count, denial, and integrity assertion executes unchanged.
  grep -Fxq 'cd "$(dirname "$0")/.."' tests/c10_a055_concurrency.sh
  grep -Fxq 'tests/c10_a055_load.sh "$DB" >/dev/null' tests/c10_a055_concurrency.sh
  echo 'A055 concurrency: reuse combined DB; replace original loader only'
  A055_CONC_DB=$PGDATABASE bash <(sed \
    -e '/^cd "$(dirname "$0")\/\.\."$/d' \
    -e '/^tests\/c10_a055_load\.sh "\$DB" >\/dev\/null$/d' \
    tests/c10_a055_concurrency.sh)
  node tests/c10_a055_client.test.js;;
 assets-http)
  # The concurrency suite intentionally leaves an open breakdown. The original
  # HTTP suite asserts a clean open-downtime baseline, so it gets its own fresh
  # combined-schema DB rather than deleting or concealing race-test evidence.
  load tests/c10_a055_seed.sql
  bash tests/preview-one/assets-rest.sh;;
esac
printf 'PASS combined PostgreSQL17 preview stack: %s; synthetic claims, NOT GoTrue/staging/production\n' "$suite"
