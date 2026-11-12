#!/usr/bin/env bash
# Actual two-session PG17 races against disposable c10_demo source+approval.
# Must run after c10_a008_demo_source_post_reverse_e2e.sql; no live data.
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
maker='33333333-3333-4333-8333-333333333333'
owner='22222222-2222-4222-8222-222222222222'
db() { psql -X -qAt -v ON_ERROR_STOP=1 -c "$1"; }
maker_sql() {
  db "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$maker',false); $1" | tail -n1
}
owner_sql() {
  db "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$owner',false); $1" | tail -n1
}
create_approved_post() {
  local key="$1" delta="$2" cmd req
  cmd="$(maker_sql "SELECT c10_demo.prepare_demo_stock_v1(5001,8001,$delta,'${key}_prepare');")"
  req="$(maker_sql "SELECT c10_demo.submit_typed_approval_v1(101,'demo_stock','post_adjustment','demo-adjustment:'||$cmd,1,c10_demo.demo_stock_payload_v1($cmd),'${key}_submit');")"
  owner_sql "SELECT c10_demo.decide_approval($req,'approve','${key}_decision');" >/dev/null
  echo "$cmd:$req"
}
run_post() {
  local cmd="$1" req="$2" exec_key="$3"
  db "BEGIN; SET ROLE service_role; SELECT pg_sleep(0.25); SELECT c10_demo.execute_approved_demo_stock_v1($cmd,$req,'$exec_key'); COMMIT;"
}
run_reverse() {
  local rid="$1" req="$2" exec_key="$3"
  db "BEGIN; SET ROLE service_role; SELECT pg_sleep(0.25); SELECT c10_demo.execute_approved_demo_reversal_v1($rid,$req,'$exec_key'); COMMIT;"
}
check_single_post() {
  local cmd="$1"
  local count
  count="$(db "SELECT count(*) FROM c10_demo.stock_movements WHERE request_key='gov002-post-$cmd';")"
  [[ "$count" == "1" ]] || { echo "FAIL: double source post $cmd count=$count"; exit 1; }
}
check_one_winner() {
  local s1="$1" s2="$2" label="$3"
  [[ $(( (s1==0)+(s2==0) )) == 1 ]] || {
    echo "FAIL: $label expected exactly one distinct-key winner ($s1,$s2)";exit 1;
  }
}
# Same key from two independent service-role sessions => both see SAME id,
# but only ONE physical movement + ONE append-only approval receipt.
IFS=: read -r a ar <<< "$(create_approved_post race_post_a_01 3)"
run_post "$a" "$ar" 'same_execute_race_a' >"$tmp/a1" 2>&1 & p1=$!
run_post "$a" "$ar" 'same_execute_race_a' >"$tmp/a2" 2>&1 & p2=$!
wait "$p1"; wait "$p2"
id1="$(grep -E '^[0-9]+$' "$tmp/a1" | tail -1)"
id2="$(grep -E '^[0-9]+$' "$tmp/a2" | tail -1)"
[[ -n "$id1" && "$id1" == "$id2" ]] || { echo "FAIL: concurrent identical keys returned different movement IDs";exit 1; }
check_single_post "$a"

# Different keys racing the SAME command cannot both produce effects.
IFS=: read -r b br <<< "$(create_approved_post race_post_b_01 6)"
run_post "$b" "$br" 'first_execution_race_b' >"$tmp/b1" 2>&1 & p3=$!
run_post "$b" "$br" 'second_execute_race_b' >"$tmp/b2" 2>&1 & p4=$!
set +e
wait "$p3";s3=$?
wait "$p4";s4=$?
set -e
check_one_winner "$s3" "$s4" distinct_key
check_single_post "$b"

# Maker requests a second independent, approved reversal of command A.
rid="$(maker_sql "SELECT c10_demo.prepare_demo_reversal_v1($a,'Concurrent compensation race','race_reversal_prep_01');")"
rr="$(maker_sql "SELECT c10_demo.submit_typed_approval_v1(101,'demo_stock','reverse_adjustment','demo-reversal:'||$rid,1,c10_demo.demo_reversal_payload_v1($rid),'race_reversal_submit_01');")"
owner_sql "SELECT c10_demo.decide_approval($rr,'approve','race_reversal_owner_vote_01');" >/dev/null
run_reverse "$rid" "$rr" 'same_reverse_execute_a' >"$tmp/r1" 2>&1 & p5=$!
run_reverse "$rid" "$rr" 'same_reverse_execute_a' >"$tmp/r2" 2>&1 & p6=$!
wait "$p5";wait "$p6"
r1="$(grep -E '^[0-9]+$' "$tmp/r1" | tail -1)"
r2="$(grep -E '^[0-9]+$' "$tmp/r2" | tail -1)"
[[ -n "$r1" && "$r1" == "$r2" ]] || { echo "FAIL: double reverse produced different IDs";exit 1; }
[[ "$(db "SELECT count(*) FROM c10_demo.stock_movements WHERE request_key='gov002-rev-$rid';")" == 1 ]] ||
 { echo "FAIL: duplicate compensating reversal";exit 1; }
[[ "$(db "SELECT sum(delta) FROM c10_demo.stock_movements WHERE location_id=5001;")" == 10.000 ]] ||
 { echo "FAIL: net reconciliation after races (expected 4+3+6-3 = 10 KG)";exit 1; }
[[ "$(db "SELECT count(*) FROM c10_demo.approval_demo_execution_receipts_v1;")" == 6 ]] ||
 { echo "FAIL: expected 3 base + 3 concurrent-source receipts";exit 1; }
echo 'PASS: real concurrent source posts (same-key replay, different-key conflict), compensating reversal and exact 10 KG ledger reconciliation'
