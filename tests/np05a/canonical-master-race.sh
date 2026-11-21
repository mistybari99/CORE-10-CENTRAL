#!/usr/bin/env bash
# Real canonical Master + two sessions, no production hook replacements.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d);holder= waiter=
cleanup(){
 psql -X -q -At -c "select pg_cancel_backend(pid) from pg_stat_activity where application_name in('mfg_master_holder','mfg_master_waiter') and pid<>pg_backend_pid()" >/dev/null || true
 exec 3>&- || true
 [ -z "$holder" ] || wait "$holder" 2>/dev/null || true
 [ -z "$waiter" ] || wait "$waiter" 2>/dev/null || true
 rm -rf "$work"
}
trap cleanup EXIT
owner="select set_config('request.jwt.claims','{\"sub\":\"95111111-1111-4111-8111-111111111111\"}',false); SET ROLE authenticated;"
checker="select set_config('request.jwt.claims','{\"sub\":\"95222222-2222-4222-8222-222222222222\"}',false); SET ROLE authenticated;"
recipe=$(psql -X -At -c "select id from core10.bom_recipes_v1 where recipe_code='MASTER-LIVE' and business_id=9511")
item=$(psql -X -At -c "select id from core10.items where business_id=9511 and sku='MFG-FLOUR'")
conv=$(psql -X -At -c "select c.id from core10.master_uom_conversions_v1 c join core10.master_uoms_v1 u on u.id=c.from_uom_id where c.business_id=9511 and u.code='MFG_G'")
# Clone through production recipe RPC, keeping immutable original quantity/UOM references.
for code in MASTER-WAIT-ITEM MASTER-WAIT-UOM MASTER-WAIT-REVOKE MASTER-WAIT-CONTROL; do
 psql -X -q -v ON_ERROR_STOP=1 -c "select set_config('request.jwt.claims','{\"sub\":\"95111111-1111-4111-8111-111111111111\"}',false); select core10.mfg_create_recipe_v1(9511,9521,finished_item_id,'$code',yield_quantity,yield_uom_ref,ingredients_payload,overhead_estimate,'mfg_clone_$code') from core10.bom_recipes_v1 where id=$recipe" >/dev/null
done
# Same-key approvals return one state transition, one receipt and one canonical Audit event.
psql -X -q -v ON_ERROR_STOP=1 -c "$checker select core10.mfg_approve_recipe_v1(9511,9521,$recipe,'2026-01-01 UTC','master_concurrent_approve')" >"$work/a" 2>&1 & a=$!
psql -X -q -v ON_ERROR_STOP=1 -c "$checker select core10.mfg_approve_recipe_v1(9511,9521,$recipe,'2026-01-01 UTC','master_concurrent_approve')" >"$work/b" 2>&1 & b=$!
wait "$a";wait "$b"
[ "$(psql -X -At -c "select count(*) from core10.mfg_command_receipts_v1 where request_key='master_concurrent_approve'")" = 1 ]
[ "$(psql -X -At -c "select count(*) from core10.canonical_audit_events_v1 a join core10.mfg_command_receipts_v1 r on r.audit_event_id=a.id where r.request_key='master_concurrent_approve'")" = 1 ]
# FIFO allows explicit COMMIT only AFTER pg_stat_activity proves the waiter is blocked.
for kind in ITEM UOM REVOKE CONTROL;do
 r=$(psql -X -At -c "select id from core10.bom_recipes_v1 where recipe_code='MASTER-WAIT-$kind' and business_id=9511")
 mkfifo "$work/fifo"
 PGAPPNAME=mfg_master_holder psql -X -q -v ON_ERROR_STOP=1 <"$work/fifo" >"$work/holder" 2>&1 & holder=$!
 exec 3>"$work/fifo"
 case "$kind" in
 ITEM) sql="UPDATE core10.items SET status='inactive',version=version+1 WHERE id=$item"; expected=MFG_MASTER_ITEM_UNUSABLE;;
 UOM) sql="UPDATE core10.master_uom_conversions_v1 SET active=false,version=version+1 WHERE id=$conv"; expected=MASTER_UOM_NO_CONVERSION;;
 *) sql="SELECT id FROM core10.items WHERE id=$item FOR UPDATE"; expected=MFG_SCOPE_DENIED;;
 esac
 printf 'BEGIN; %s;\n' "$sql" >&3
 ready=false
 for _ in $(seq 1 200);do
  if [ "$(psql -X -At -c "select count(*) from pg_stat_activity where application_name='mfg_master_holder' and state='idle in transaction'")" = 1 ];then ready=true;break;fi
  sleep .02
 done
 [ "$ready" = true ] || { cat "$work/holder";echo MASTER_HOLDER_NOT_READY;exit 1; }
 PGAPPNAME=mfg_master_waiter psql -X -q -v ON_ERROR_STOP=1 -c "$checker select core10.mfg_approve_recipe_v1(9511,9521,$r,'2026-01-01 UTC','master_wait_$kind')" >"$work/waiter" 2>&1 & waiter=$!
 blocked=false
 for _ in $(seq 1 200);do
  if [ "$(psql -X -At -c "select count(*) from pg_stat_activity where application_name='mfg_master_waiter' and wait_event_type='Lock'")" = 1 ];then blocked=true;break;fi
  sleep .02
 done
 [ "$blocked" = true ] || { cat "$work/waiter";echo MASTER_WAIT_NOT_OBSERVED;exit 1; }
 case "$kind" in
 REVOKE) psql -X -q -v ON_ERROR_STOP=1 -c "update core10.business_members set active=false where business_id=9511 and user_id='95222222-2222-4222-8222-222222222222'" >/dev/null;;
 CONTROL)
 expected=MFG_CONTROL_CHANGED_RETRY
 ver=$(psql -X -At -c "select coalesce(max(version),0) from core10.control_setting_versions_v1 where business_id=9511 and feature_key='mfg.recipe_approve' and site_id is null")
 psql -X -q -v ON_ERROR_STOP=1 -c "$owner select core10.control_set_v1(9511,NULL,'mfg.recipe_approve',false,0::smallint,'{}',NULL,false,$ver,'Synthetic waiting master gate','master_wait_control_off')" >/dev/null;;
 esac
 printf 'COMMIT;\n' >&3;exec 3>&-;wait "$holder";holder=;rm "$work/fifo"
 if wait "$waiter";then echo MASTER_WAIT_UNSAFE_SUCCESS;exit 1;fi;waiter=
 grep -q "$expected" "$work/waiter" || { cat "$work/waiter";exit 1; }
 case "$kind" in
 ITEM) psql -X -q -c "update core10.items set status='active',version=version+1 where id=$item" >/dev/null;;
 UOM) psql -X -q -c "update core10.master_uom_conversions_v1 set active=true,version=version+1 where id=$conv" >/dev/null;;
 REVOKE) psql -X -q -c "update core10.business_members set active=true where business_id=9511 and user_id='95222222-2222-4222-8222-222222222222'" >/dev/null;;
 CONTROL)
 psql -X -q -v ON_ERROR_STOP=1 -c "$owner select core10.control_set_v1(9511,NULL,'mfg.recipe_approve',true,0::smallint,'{}',NULL,false,$((ver+1)),'Synthetic resume','master_wait_control_on')" >/dev/null;;
 esac
 [ "$(psql -X -At -c "select count(*) from core10.mfg_command_receipts_v1 where request_key='master_wait_$kind'")" = 0 ]
 echo "NP05A_CANONICAL_MASTER_WAIT_${kind}_OK"
done
echo NP05A_CANONICAL_MASTER_CONCURRENT_APPROVAL_ONCE_OK
