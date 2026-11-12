#!/usr/bin/env bash
# Parallel sessions, canonical records and access changes after row-lock waits.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "${CORE10_BUILD01_DISPOSABLE_ACK:-}" == I_CONFIRM_BUILD01_DISPOSABLE ]] || exit 2
case "${PGHOST:-}" in localhost|127.0.0.1) ;; *) exit 2;; esac
[[ "${PGDATABASE:-}" =~ ^core10_build01_sql_[0-9]+$ ]] || exit 2
out=$(mktemp -d /tmp/core10-build01-races.XXXXXX)
q(){ psql -X -qAt -v ON_ERROR_STOP=1 -c "$1"; }
wait_all(){
  local failed=0 pid
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  if [[ "$failed" != 0 ]]; then
    echo "FAIL parallel request; inspect $out" >&2
    return 1
  fi
}
owner="SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);"
pids=()
for i in {1..8}; do
  q "$owner SELECT c10_demo.build01_setup_v1(11,'parallel-business','food_manufacturing','Parallel synthetic','quick',NULL,'build01-race-setup','#334155');" >"$out/setup-$i.log" 2>&1 &
  pids+=("$!")
done
wait_all
[[ "$(q "SELECT count(*) FROM c10_demo.businesses WHERE slug='parallel-business'")" == 1 ]]
[[ "$(q "SELECT count(*) FROM c10_demo.access_change_events_v1 WHERE request_key='build01-race-setup'")" == 1 ]]
pids=()
for i in {1..8}; do
  q "$owner SELECT c10_demo.build01_setup_v1(11,'parallel-industry','paint_hardware','Parallel synthetic industry','quick','[]','build01-race-industry','#334155');" >"$out/industry-$i.log" 2>&1 &
  pids+=("$!")
done
wait_all
[[ "$(q "SELECT count(*) FROM c10_demo.businesses WHERE slug='parallel-industry'")" == 1 ]]
[[ "$(q "SELECT count(*) FROM c10_demo.access_change_events_v1 WHERE request_key='build01-race-industry'")" == 1 ]]
pids=()
for i in {1..8}; do
  q "$owner SELECT c10_demo.build01_site_v1(101,'warehouse','Parallel site','build01-race-site');" >"$out/site-$i.log" 2>&1 &
  pids+=("$!")
done
wait_all
[[ "$(q "SELECT count(*) FROM c10_demo.sites WHERE business_id=101 AND request_key='build01-race-site'")" == 1 ]]
[[ "$(q "SELECT count(*) FROM c10_demo.access_change_events_v1 WHERE request_key='build01-race-site'")" == 1 ]]
pids=()
for i in {1..8}; do
  q "$owner SELECT c10_demo.build01_set_access_v1(101,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,1002,ARRAY['stock.read'],'{}',NULL,'build01-race-grant');" >"$out/grant-$i.log" 2>&1 &
  pids+=("$!")
done
wait_all
[[ "$(q "SELECT count(*) FROM c10_demo.access_change_events_v1 WHERE request_key='build01-race-grant'")" == 1 ]]
version=$(q "SELECT version FROM c10_demo.site_grants WHERE site_id=1002 AND user_id='44444444-4444-4444-8444-444444444444'")
pids=()
for i in {1..8}; do
  (if q "$owner SELECT c10_demo.build01_set_access_v1(101,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,1002,ARRAY['stock.read','stock.post'],'{}',NULL,'build01-race-stale-$i',$version);" >"$out/stale-$i.log" 2>&1; then
    printf 'applied\n' >"$out/stale-$i.result"
   else
    rg -q BUILD01_STALE_ACCESS_VERSION "$out/stale-$i.log"
    printf 'stale\n' >"$out/stale-$i.result"
   fi) &
  pids+=("$!")
done
wait_all
[[ "$(rg -l '^applied$' "$out"/stale-*.result | wc -l)" -eq 1 ]]
[[ "$(rg -l '^stale$' "$out"/stale-*.result | wc -l)" -eq 7 ]]
# The owner holds the business row, then revokes the waiting Business Owner.
# Initial authority is valid when the writer begins; post-wait authority is not.
lock_app="build01_owner_lock_${BASHPID}"
writer_app="build01_waiting_writer_${BASHPID}"
PGAPPNAME=$lock_app q "BEGIN; SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true); SELECT id FROM c10_demo.businesses WHERE id=101 FOR UPDATE; SELECT pg_sleep(3); SELECT c10_demo.change_access_v1(101,'22222222-2222-4222-8222-222222222222','business_member.revoke',NULL,NULL,NULL,'build01-race-revoke-owner'); COMMIT;" >"$out/locker.log" 2>&1 &
locker=$!
locked=false
for i in {1..30}; do
  if [[ "$(q "SELECT count(*) FROM pg_stat_activity WHERE application_name='$lock_app' AND wait_event='PgSleep'")" == 1 ]]; then locked=true; break; fi
  sleep 0.05
done
[[ "$locked" == true ]]
(if PGAPPNAME=$writer_app q "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false); SELECT c10_demo.build01_site_v1(101,'warehouse','Revoked waiting writer','build01-race-revoked-writer');" >"$out/writer.log" 2>&1; then
  printf 'unexpected-success\n' >"$out/writer.result"
 else
  rg -q BUILD01_SITE_DENIED "$out/writer.log"
  printf 'denied\n' >"$out/writer.result"
 fi) &
writer=$!
waiting=false
for i in {1..30}; do
  if [[ "$(q "SELECT count(*) FROM pg_stat_activity WHERE application_name='$writer_app' AND wait_event_type='Lock'")" == 1 ]]; then waiting=true; break; fi
  sleep 0.05
done
[[ "$waiting" == true ]]
wait "$locker"
wait "$writer"
[[ "$(<"$out/writer.result")" == denied ]]
[[ "$(q "SELECT count(*) FROM c10_demo.sites WHERE request_key='build01-race-revoked-writer'")" == 0 ]]
echo "PASS Build01 8-way legacy/industry setup/site/grant replay; 1applied/7stale race; revoked waiting writer denied; logs $out"
