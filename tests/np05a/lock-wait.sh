#!/usr/bin/env bash
# Requires concurrency.sh's disposable fictional fixture. Three real session lock waits.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
holder= waiter=
cleanup(){
 for app in np05a_holder np05a_waiter; do
  psql -X -q -At -c "select pg_cancel_backend(pid) from pg_stat_activity where application_name='$app' and pid<>pg_backend_pid()" >/dev/null || true
 done
 [ -z "$holder" ] || wait "$holder" 2>/dev/null || true
 [ -z "$waiter" ] || wait "$waiter" 2>/dev/null || true
 rm -rf "$work"
}
trap cleanup EXIT
batch=$(psql -X -At -c "select id from core10.production_batches_v1 where business_id=9511")
claim="select set_config('request.jwt.claims','{\"sub\":\"95222222-2222-4222-8222-222222222222\"}',false); SET ROLE authenticated;"
owner="select set_config('request.jwt.claims','{\"sub\":\"95111111-1111-4111-8111-111111111111\"}',false); SET ROLE authenticated;"
await_lock(){
 local app=$1 found=false
 for _ in $(seq 1 200); do
  if [ "$(psql -X -At -c "select count(*) from pg_stat_activity where application_name='$app' and wait_event_type='Lock'")" = 1 ]; then found=true; break; fi
  sleep .02
 done
 [ "$found" = true ] || { echo "DID_NOT_OBSERVE_LOCK_WAIT $app"; exit 1; }
}
hold(){
 PGAPPNAME=np05a_holder psql -X -q -v ON_ERROR_STOP=1 -c "BEGIN; $1 SELECT pg_sleep(30); COMMIT;" >"$work/holder" 2>&1 & holder=$!
 # Ready means the holder has acquired its target lock and reached the deliberate test sleep.
 local found=false
 for _ in $(seq 1 200); do
  if [ "$(psql -X -At -c "select count(*) from pg_stat_activity where application_name='np05a_holder' and wait_event='PgSleep'")" = 1 ]; then found=true; break; fi
  sleep .02
 done
 [ "$found" = true ] || { echo HOLDER_NOT_READY; exit 1; }
}
unhold(){
 psql -X -q -At -c "select pg_cancel_backend(pid) from pg_stat_activity where application_name='np05a_holder'" >/dev/null
 wait "$holder" 2>/dev/null || true; holder=
}
# 1. Wait on command advisory lock; a new immediately-effective Control version must force retry.
hold "SELECT pg_advisory_xact_lock(hashtextextended('mfg:9511:wait_handoff_01',0));"
PGAPPNAME=np05a_waiter psql -X -q -v ON_ERROR_STOP=1 -c "$claim SELECT core10.mfg_request_handoff_v1(9511,9521,$batch,'finance','wait_handoff_01');" >"$work/waiter" 2>&1 & waiter=$!
await_lock np05a_waiter
psql -X -q -v ON_ERROR_STOP=1 -c "$owner SELECT core10.control_set_v1(9511,NULL,'mfg.handoff',false,0::smallint,'{}',NULL,false,0,'Owner disables while waiting','wait_control_off');" >/dev/null
unhold
if wait "$waiter"; then echo DISABLED_WAITING_COMMAND_ACCEPTED; exit 1; fi; waiter=
grep -q MFG_CONTROL_CHANGED_RETRY "$work/waiter"
if psql -X -q -v ON_ERROR_STOP=1 -c "$claim SELECT core10.mfg_request_handoff_v1(9511,9521,$batch,'finance','wait_handoff_01');" >"$work/disabled" 2>&1; then echo DISABLED_RETRY_ACCEPTED; exit 1; fi
grep -q CONTROL_DISABLED "$work/disabled"
psql -X -q -v ON_ERROR_STOP=1 -c "$owner SELECT core10.control_set_v1(9511,NULL,'mfg.handoff',true,0::smallint,'{}',NULL,false,1,'Owner re-enables handoff','wait_control_on');" >/dev/null
# 2. Wait on batch row lock; revoke the caller before releasing it. No receipt may be created.
hold "SELECT id FROM core10.production_batches_v1 WHERE id=$batch FOR UPDATE;"
PGAPPNAME=np05a_waiter psql -X -q -v ON_ERROR_STOP=1 -c "$claim SELECT core10.mfg_request_handoff_v1(9511,9521,$batch,'finance','wait_revoke_01');" >"$work/revoked" 2>&1 & waiter=$!
await_lock np05a_waiter
# Fixture-only admin mutation of canonical membership, never a production bypass or shadow grant.
psql -X -q -v ON_ERROR_STOP=1 -c "UPDATE core10.business_members SET active=false WHERE business_id=9511 AND user_id='95222222-2222-4222-8222-222222222222'" >/dev/null
unhold
if wait "$waiter"; then echo REVOKED_WAITING_COMMAND_ACCEPTED; exit 1; fi; waiter=
grep -q MFG_SCOPE_DENIED "$work/revoked"
psql -X -q -v ON_ERROR_STOP=1 -c "UPDATE core10.business_members SET active=true WHERE business_id=9511 AND user_id='95222222-2222-4222-8222-222222222222'" >/dev/null
# 3. Wait on recipe-version allocation; this extra lock must also precede the fresh Control check.
hold "SELECT pg_advisory_xact_lock(hashtextextended('mfg-recipe:9511:9521:WAIT-RECIPE',0));"
PGAPPNAME=np05a_waiter psql -X -q -v ON_ERROR_STOP=1 -c "$claim SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'WAIT-RECIPE',100,'fixture:piece','[{\"item\":9542,\"qty\":1,\"uom_ref\":\"fixture:kg\",\"kind\":\"ingredient\",\"waste_pct\":0,\"estimated_unit_cost\":80}]',0,'wait_recipe_01');" >"$work/recipe" 2>&1 & waiter=$!
await_lock np05a_waiter
psql -X -q -v ON_ERROR_STOP=1 -c "$owner SELECT core10.control_set_v1(9511,NULL,'mfg.recipe',false,0::smallint,'{}',NULL,false,0,'Owner pauses recipe allocation','wait_recipe_off');" >/dev/null
unhold
if wait "$waiter"; then echo DISABLED_RECIPE_WAIT_ACCEPTED; exit 1; fi; waiter=
grep -q MFG_CONTROL_CHANGED_RETRY "$work/recipe"
psql -X -q -v ON_ERROR_STOP=1 -c "$owner SELECT core10.control_set_v1(9511,NULL,'mfg.recipe',true,0::smallint,'{}',NULL,false,1,'Owner resumes recipe allocation','wait_recipe_on');" >/dev/null
[ "$(psql -X -At -c "select count(*) from core10.mfg_command_receipts_v1 where request_key in('wait_handoff_01','wait_revoke_01','wait_recipe_01')")" = 0 ]
[ "$(psql -X -At -c "select count(*) from core10.stock_movements where business_id=9511")" = 0 ]
# A successful source request now creates the exact history that 0501 must preserve.
psql -X -q -v ON_ERROR_STOP=1 -c "$claim SELECT core10.mfg_request_handoff_v1(9511,9521,$batch,'finance','wait_final_source');" >/dev/null
if psql -X -q -v ON_ERROR_STOP=1 -1 -f internal/migrations/0501_np05a_material_handoff.down.sql >"$work/down0501" 2>&1; then echo SOURCE_HISTORY_ROLLBACK_ACCEPTED; exit 1; fi
grep -q MFG_ROLLBACK_HAS_HISTORY "$work/down0501"
echo NP05A_LOCK_WAIT_CONTROL_AND_REVOCATION_OK
