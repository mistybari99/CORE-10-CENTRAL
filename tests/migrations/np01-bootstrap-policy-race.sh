#!/usr/bin/env bash
# D063: an OFF write started after the decision statement must still win when
# the decision was waiting on the shared tenant lock.
set -euo pipefail
[[ "${PGHOST:-}" == 127.0.0.1 || "${PGHOST:-}" == localhost ]] || {
  echo DISPOSABLE_PGHOST_REQUIRED >&2
  exit 1
}
root="$(cd "$(dirname "$0")/../.." && pwd)"
scratch="$(mktemp -d)"
db="core10_bootstrap_$$"
createdb "$db"
trap 'dropdb --if-exists "$db"; rm -rf "$scratch"' EXIT
export PGDATABASE="$db"
"$root/internal/migrations/run.sh" up >"$scratch/migration.log" 2>&1 || {
  cat "$scratch/migration.log" >&2
  exit 1
}
psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO core10.tenants (id, slug) VALUES (9615, 'bootstrap-race');
INSERT INTO core10.legal_entities (id, tenant_id, label) VALUES (9615, 9615, 'Bootstrap race fixture');
INSERT INTO core10.tenant_members (tenant_id, user_id, role)
 VALUES (9615, '00009615-0000-4000-8000-000000000001', 'tenant_owner');
SELECT set_config('request.jwt.claims', '{"sub":"00009615-0000-4000-8000-000000000001"}', false);
SELECT core10._set_bootstrap_policy_v1(9615, true, NULL, 0, 'Enable race fixture', 'fixture-bootstrap-on');
SQL

psql -X -q -v ON_ERROR_STOP=1 >"$scratch/writer.log" 2>&1 <<SQL &
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"00009615-0000-4000-8000-000000000001"}', false);
SELECT core10._lock_bootstrap_policy_v1(9615);
\\! touch "$scratch/held"
\\! timeout 15 sh -c 'until test -f "$scratch/waiter-ready"; do sleep .05; done'
SELECT core10._set_bootstrap_policy_v1(9615, false, NULL, 1, 'Disable race fixture', 'fixture-bootstrap-off');
COMMIT;
SQL
writer=$!
for _ in $(seq 1 100); do
  [[ -e "$scratch/held" ]] && break
  sleep .05
done
test -e "$scratch/held" || { cat "$scratch/writer.log" >&2; exit 1; }

PGAPPNAME=core10-bootstrap-waiter psql -X -qAt -v ON_ERROR_STOP=1 >"$scratch/decision.log" 2>&1 <<'SQL' &
SELECT set_config('request.jwt.claims', '{"sub":"00009615-0000-4000-8000-000000000001"}', false);
SET statement_timeout = '20s';
SELECT result->>'enabled' = 'false' AND result->>'version' = '2'
       AND (result->>'decision_at')::timestamptz > statement_timestamp()
FROM core10._bootstrap_policy_decision_v1(9615) AS result;
SQL
waiter=$!
PGAPPNAME=core10-bootstrap-setup-waiter psql -X -qAt -v ON_ERROR_STOP=1 >"$scratch/setup.log" 2>&1 <<'SQL' &
SET ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"00009615-0000-4000-8000-000000000001"}', false);
SET statement_timeout = '20s';
SELECT core10.build01_setup_v1(9615,'waited-setup','sweets_bakery','Waited setup','quick',NULL,'waited-setup-01','#112233');
SQL
setup_waiter=$!
blocked=""
for _ in $(seq 1 100); do
  blocked="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM pg_stat_activity
    WHERE datname = current_database()
      AND application_name IN ('core10-bootstrap-waiter','core10-bootstrap-setup-waiter')
      AND wait_event_type = 'Lock' AND wait_event = 'advisory'")"
  [[ "$blocked" == 2 ]] && break
  sleep .05
done
touch "$scratch/waiter-ready"
wait "$writer" || { cat "$scratch/writer.log" >&2; exit 1; }
wait "$waiter" || { cat "$scratch/decision.log" >&2; exit 1; }
test "$blocked" = 2
grep -Fxq t "$scratch/decision.log"
if wait "$setup_waiter"; then
  echo 'Business setup ignored an OFF write committed during the wait' >&2
  exit 1
fi
grep -q 'CONTROL_DISABLED:setup001.provision' "$scratch/setup.log"
test "$(psql -X -At -v ON_ERROR_STOP=1 -c 'SELECT count(*) FROM core10.businesses WHERE tenant_id = 9615')" = 0
if psql -X -1 -v ON_ERROR_STOP=1 -f "$root/internal/migrations/0116_np01_bootstrap_provisioning.down.sql" >"$scratch/cutover-down.log" 2>&1; then
  echo 'Rollback removed the active Business setup gate' >&2
  exit 1
fi
grep -q BOOTSTRAP_PROVISIONING_HISTORY_ROLLBACK_REFUSED "$scratch/cutover-down.log"

if psql -X -1 -v ON_ERROR_STOP=1 -f "$root/internal/migrations/0115_np01_bootstrap_policy_provider.down.sql" >"$scratch/down.log" 2>&1; then
  echo 'Rollback erased committed bootstrap policy history' >&2
  exit 1
fi
grep -q BOOTSTRAP_POLICY_HISTORY_ROLLBACK_REFUSED "$scratch/down.log"
test "$(psql -X -At -v ON_ERROR_STOP=1 -c 'SELECT count(*) FROM core10.control_setting_versions_v1 WHERE tenant_id = 9615 AND business_id IS NULL')" = 2
echo NP01_BOOTSTRAP_POLICY_POST_WAIT_OFF_AND_ROLLBACK_GUARD_PASS
