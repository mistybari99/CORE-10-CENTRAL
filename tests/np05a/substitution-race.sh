#!/usr/bin/env bash
# After existing concurrency/lock-wait/waste tests and substitution-browser-seed.sql.
# Draft operations use real production code; no substitution-check fixture is installed here.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d); holder= waiter=
cleanup(){
 psql -X -q -At -c "select pg_cancel_backend(pid) from pg_stat_activity where application_name in('np05a_sub_holder','np05a_sub_waiter') and pid<>pg_backend_pid()" >/dev/null || true
 [ -z "$holder" ] || wait "$holder" 2>/dev/null || true
 [ -z "$waiter" ] || wait "$waiter" 2>/dev/null || true
 rm -rf "$work"
}
trap cleanup EXIT
claim="select set_config('request.jwt.claims','{\"sub\":\"95222222-2222-4222-8222-222222222222\"}',false); SET ROLE authenticated;"
owner="select set_config('request.jwt.claims','{\"sub\":\"95111111-1111-4111-8111-111111111111\"}',false); SET ROLE authenticated;"
for code in SUB-RACE SUB-WAIT; do
 psql -X -q -v ON_ERROR_STOP=1 -c "$claim SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'$code',100,'fixture:piece','[{\"item\":9542,\"qty\":10,\"uom_ref\":\"fixture:kg\",\"kind\":\"ingredient\",\"waste_pct\":2,\"estimated_unit_cost\":80}]',0,'sub_race_create_$code');" >/dev/null
done
recipe=$(psql -X -At -c "select id from core10.bom_recipes_v1 where business_id=9511 and recipe_code='SUB-RACE'")
waiting_recipe=$(psql -X -At -c "select id from core10.bom_recipes_v1 where business_id=9511 and recipe_code='SUB-WAIT'")
call(){ printf "SELECT core10.mfg_define_substitution_v1(9511,9521,%s,1,9546,2.5,'fixture:kg',200,1,50,'Fictional concurrent alternative','%s');" "$1" "$2"; }
psql -X -q -v ON_ERROR_STOP=1 -c "$claim $(call "$recipe" sub_race_same)" >"$work/a" 2>&1 & a=$!
psql -X -q -v ON_ERROR_STOP=1 -c "$claim $(call "$recipe" sub_race_same)" >"$work/b" 2>&1 & b=$!
wait "$a";wait "$b"
[ "$(psql -X -At -c "select count(*) from core10.bom_substitution_rules_v1 where bom_id=$recipe")" = 1 ]
hold(){
 PGAPPNAME=np05a_sub_holder psql -X -q -v ON_ERROR_STOP=1 -c "BEGIN; SELECT id FROM core10.bom_recipes_v1 WHERE id=$waiting_recipe FOR UPDATE; SELECT pg_sleep(30); COMMIT;" >"$work/holder" 2>&1 & holder=$!
 local ready=false
 for _ in $(seq 1 200);do
  if [ "$(psql -X -At -c "select count(*) from pg_stat_activity where application_name='np05a_sub_holder' and wait_event='PgSleep'")" = 1 ];then ready=true;break;fi
  sleep .02
 done
 [ "$ready" = true ] || { echo SUB_HOLDER_NOT_READY;exit 1; }
 PGAPPNAME=np05a_sub_waiter psql -X -q -v ON_ERROR_STOP=1 -c "$claim $(call "$waiting_recipe" "$1")" >"$work/waiter" 2>&1 & waiter=$!
 local blocked=false
 for _ in $(seq 1 200);do
  if [ "$(psql -X -At -c "select count(*) from pg_stat_activity where application_name='np05a_sub_waiter' and wait_event_type='Lock'")" = 1 ];then blocked=true;break;fi
  sleep .02
 done
 [ "$blocked" = true ] || { echo SUB_WAITER_NOT_BLOCKED;exit 1; }
}
release(){
 psql -X -q -At -c "select pg_cancel_backend(pid) from pg_stat_activity where application_name='np05a_sub_holder'" >/dev/null
 wait "$holder" 2>/dev/null || true;holder=
 if wait "$waiter";then echo SUB_WAITING_REQUEST_ACCEPTED;exit 1;fi;waiter=
}
hold sub_wait_disabled
psql -X -q -v ON_ERROR_STOP=1 -c "$owner SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_substitution',false,0::smallint,'{}',NULL,false,0,'Owner pauses waiting proposals','sub_wait_off');" >/dev/null
release
grep -q MFG_CONTROL_CHANGED_RETRY "$work/waiter"
psql -X -q -v ON_ERROR_STOP=1 -c "$owner SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_substitution',true,0::smallint,'{}',NULL,false,1,'Owner resumes draft proposals','sub_wait_on');" >/dev/null
hold sub_wait_revoked
psql -X -q -v ON_ERROR_STOP=1 -c "UPDATE core10.business_members SET active=false WHERE business_id=9511 AND user_id='95222222-2222-4222-8222-222222222222'" >/dev/null
release
grep -q MFG_SCOPE_DENIED "$work/waiter"
psql -X -q -v ON_ERROR_STOP=1 -c "UPDATE core10.business_members SET active=true WHERE business_id=9511 AND user_id='95222222-2222-4222-8222-222222222222'" >/dev/null
# Distinct keys for the same recipe/line/alternative also cannot create duplicate definitions.
psql -X -q -v ON_ERROR_STOP=1 -c "$claim $(call "$waiting_recipe" sub_race_left)" >"$work/left" 2>&1 & a=$!
psql -X -q -v ON_ERROR_STOP=1 -c "$claim $(call "$waiting_recipe" sub_race_right)" >"$work/right" 2>&1 & b=$!
left=0;right=0;wait "$a" || left=$?;wait "$b" || right=$?
[ "$(( (left==0)+(right==0) ))" = 1 ] || { echo SUB_DUPLICATE_PAIR_ACCEPTED;exit 1; }
if [ "$left" != 0 ];then grep -q MFG_SUBSTITUTION_EXISTS "$work/left";else grep -q MFG_SUBSTITUTION_EXISTS "$work/right";fi
[ "$(psql -X -At -c 'select count(*) from core10.bom_substitution_rules_v1')" = 2 ]
[ "$(psql -X -At -c "select count(*) from core10.canonical_audit_events_v1 where action='mfg.substitution_define'")" = 2 ]
[ "$(psql -X -At -c "select count(*) from core10.mfg_command_receipts_v1 where request_key in('sub_wait_disabled','sub_wait_revoked')")" = 0 ]
[ "$(psql -X -At -c 'select count(*) from core10.stock_movements where business_id=9511')" = 0 ]
if psql -X -q -v ON_ERROR_STOP=1 -1 -f internal/migrations/0503_np05a_recipe_substitution.down.sql >"$work/down" 2>&1;then echo SUB_HISTORY_ROLLBACK_ACCEPTED;exit 1;fi
grep -q MFG_ROLLBACK_HAS_HISTORY "$work/down"
echo NP05A_SUBSTITUTION_RACE_SCOPE_AND_ROLLBACK_OK
