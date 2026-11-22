#!/usr/bin/env bash
# Runs after concurrency.sh and lock-wait.sh, using only their disposable fictional fixture.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d); holder= waiter=
cleanup(){
 psql -X -q -At -c "select pg_cancel_backend(pid) from pg_stat_activity where application_name in('np05a_waste_holder','np05a_waste_waiter') and pid<>pg_backend_pid()" >/dev/null || true
 [ -z "$holder" ] || wait "$holder" 2>/dev/null || true
 [ -z "$waiter" ] || wait "$waiter" 2>/dev/null || true
 rm -rf "$work"
}
trap cleanup EXIT
batch=$(psql -X -At -c 'select id from core10.production_batches_v1 where business_id=9511')
claim="select set_config('request.jwt.claims','{\"sub\":\"95222222-2222-4222-8222-222222222222\"}',false); SET ROLE authenticated;"
owner="select set_config('request.jwt.claims','{\"sub\":\"95111111-1111-4111-8111-111111111111\"}',false); SET ROLE authenticated;"
call(){ printf "SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,%s,'SPILLAGE','FICTIONAL-MILK','Fictional concurrency spill','%s');" "$batch" "$1" "$2"; }
psql -X -q -v ON_ERROR_STOP=1 -c "$claim $(call 1 waste_race_same) SELECT pg_sleep(.3);" >"$work/a" 2>&1 & a=$!
psql -X -q -v ON_ERROR_STOP=1 -c "$claim $(call 1 waste_race_same)" >"$work/b" 2>&1 & b=$!
wait "$a";wait "$b"
[ "$(psql -X -At -c 'select count(*) from core10.mfg_material_waste_v1')" = 1 ]
# Different keys contend on the same batch row: of two 1.5 kg requests only one fits the 3 kg cap.
psql -X -q -v ON_ERROR_STOP=1 -c "$claim $(call 1.5 waste_race_left)" >"$work/left" 2>&1 & a=$!
psql -X -q -v ON_ERROR_STOP=1 -c "$claim $(call 1.5 waste_race_right)" >"$work/right" 2>&1 & b=$!
left=0;right=0
wait "$a" || left=$?;wait "$b" || right=$?
[ "$(( (left==0)+(right==0) ))" = 1 ] || { echo CONCURRENT_CAP_NOT_ENFORCED; exit 1; }
if [ "$left" != 0 ];then grep -q CONTROL_LIMIT:max_waste_pct "$work/left";else grep -q CONTROL_LIMIT:max_waste_pct "$work/right";fi
[ "$(psql -X -At -c 'select sum(quantity) from core10.mfg_material_waste_v1')" = '2.5' ]
[ "$(psql -X -At -c "select count(*) from core10.canonical_audit_events_v1 where action='mfg.material_waste_record'")" = 2 ]
hold(){
 PGAPPNAME=np05a_waste_holder psql -X -q -v ON_ERROR_STOP=1 -c "BEGIN; SELECT id FROM core10.production_batches_v1 WHERE id=$batch FOR UPDATE; SELECT pg_sleep(30); COMMIT;" >"$work/holder" 2>&1 & holder=$!
 local ready=false
 for _ in $(seq 1 200);do
  if [ "$(psql -X -At -c "select count(*) from pg_stat_activity where application_name='np05a_waste_holder' and wait_event='PgSleep'")" = 1 ];then ready=true;break;fi
  sleep .02
 done
 [ "$ready" = true ] || { echo WASTE_HOLDER_NOT_READY;exit 1; }
 PGAPPNAME=np05a_waste_waiter psql -X -q -v ON_ERROR_STOP=1 -c "$claim $(call .1 "$1")" >"$work/waiter" 2>&1 & waiter=$!
 local blocked=false
 for _ in $(seq 1 200);do
  if [ "$(psql -X -At -c "select count(*) from pg_stat_activity where application_name='np05a_waste_waiter' and wait_event_type='Lock'")" = 1 ];then blocked=true;break;fi
  sleep .02
 done
 [ "$blocked" = true ] || { echo WASTE_WAITER_NOT_BLOCKED;exit 1; }
}
release(){
 psql -X -q -At -c "select pg_cancel_backend(pid) from pg_stat_activity where application_name='np05a_waste_holder'" >/dev/null
 wait "$holder" 2>/dev/null || true;holder=
 if wait "$waiter";then echo WASTE_WAITING_COMMAND_UNEXPECTEDLY_ACCEPTED;exit 1;fi;waiter=
}
hold waste_wait_disabled
psql -X -q -v ON_ERROR_STOP=1 -c "$owner SELECT core10.control_set_v1(9511,NULL,'mfg.material_waste',false,0::smallint,'{}',NULL,false,0,'Owner pauses blocked waste observation','waste_wait_off');" >/dev/null
release
grep -q MFG_CONTROL_CHANGED_RETRY "$work/waiter"
psql -X -q -v ON_ERROR_STOP=1 -c "$owner SELECT core10.control_set_v1(9511,NULL,'mfg.material_waste',true,0::smallint,'{}',NULL,false,1,'Owner resumes waste observations','waste_wait_on');" >/dev/null
hold waste_wait_revoked
psql -X -q -v ON_ERROR_STOP=1 -c "UPDATE core10.business_members SET active=false WHERE business_id=9511 AND user_id='95222222-2222-4222-8222-222222222222'" >/dev/null
release
grep -q MFG_SCOPE_DENIED "$work/waiter"
psql -X -q -v ON_ERROR_STOP=1 -c "UPDATE core10.business_members SET active=true WHERE business_id=9511 AND user_id='95222222-2222-4222-8222-222222222222'" >/dev/null
[ "$(psql -X -At -c "select count(*) from core10.mfg_command_receipts_v1 where request_key in('waste_wait_disabled','waste_wait_revoked')")" = 0 ]
[ "$(psql -X -At -c 'select count(*) from core10.stock_movements where business_id=9511')" = 0 ]
if psql -X -q -v ON_ERROR_STOP=1 -1 -f internal/migrations/0502_np05a_material_waste.down.sql >"$work/down" 2>&1;then echo WASTE_HISTORY_ROLLBACK_ACCEPTED;exit 1;fi
grep -q MFG_ROLLBACK_HAS_HISTORY "$work/down"
echo NP05A_WASTE_RACE_LIMIT_REVOCATION_AND_ROLLBACK_OK
