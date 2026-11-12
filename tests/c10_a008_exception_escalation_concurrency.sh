#!/usr/bin/env bash
# Independent authenticated PostgreSQL17 sessions; synthetic c10_demo only.
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
maker='33333333-3333-4333-8333-333333333333'
bo='22222222-2222-4222-8222-222222222222'
to='11111111-1111-4111-8111-111111111111'
db() { psql -X -qAt -v ON_ERROR_STOP=1 -c "$1"; }
as_actor() {
 local actor="$1" stmt="$2"
 db "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$actor',false);$stmt" | tail -n1
}
new_escalation() {
 local id="$1" req esc
 req="$(as_actor "$maker" "SELECT c10_demo.submit_typed_approval_v1(101,'demo_ops','exception_review','race-case-$id',1,'{\"case\":\"$id\"}'::jsonb,'exception_race_parent_${id}');")"
 esc="$(as_actor "$maker" "SELECT c10_demo.request_approval_exception_v1($req,'Parallel reviewer race at source','urgent',30,'exception_race_create_${id}');")"
 echo "$req:$esc"
}
vote() {
 local actor="$1" esc="$2" act="$3" key="$4"
 db "BEGIN; SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$actor',false);SELECT pg_sleep(0.3);SELECT c10_demo.decide_approval_exception_v1($esc,'$act','$key');COMMIT;"
}
approve_parent() {
 local actor="$1" req="$2" key="$3"
 db "BEGIN; SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$actor',false);SELECT pg_sleep(0.3);SELECT c10_demo.decide_approval($req,'approve','$key');COMMIT;"
}
IFS=: read -r r1 e1 <<< "$(new_escalation A_20261112)"
vote "$bo" "$e1" acknowledged race_ack_A01 >"$tmp/a" 2>&1 & p1=$!
vote "$to" "$e1" declined race_decline_A02 >"$tmp/b" 2>&1 & p2=$!
set +e
wait "$p1";a=$?
wait "$p2";b=$?
set -e
[[ $(( (a==0)+(b==0) )) -eq 1 ]] || {
 echo "FAIL: two independent escalation terminals must have exactly one winner ($a/$b)"
 tail -n 12 "$tmp/a" "$tmp/b";exit 1;
}
[[ "$(db "SELECT count(*) FROM c10_demo.approval_exception_events_v1 WHERE escalation_id=$e1;")" == 2 ]] ||
 { echo "FAIL: duplicate terminal audit event";exit 1; }
[[ "$(db "SELECT status FROM c10_demo.approval_requests WHERE id=$r1;")" == pending ]] ||
 { echo "FAIL: escalation must not approve main request";exit 1; }

# Parent approve vs escalation race under independent actor sessions.
IFS=: read -r r2 e2 <<< "$(new_escalation B_20261112)"
approve_parent "$bo" "$r2" race_normal_vote_B01 >"$tmp/c" 2>&1 & p3=$!
vote "$to" "$e2" acknowledged race_ack_B02 >"$tmp/d" 2>&1 & p4=$!
set +e
wait "$p3";c=$?
wait "$p4";d=$?
set -e
[[ "$c" -eq 0 ]] || {
 echo "FAIL: ordinary approval blocked by escalation"; tail -n 12 "$tmp/c" "$tmp/d";exit 1;
}
[[ "$(db "SELECT status FROM c10_demo.approval_requests WHERE id=$r2;")" == approved ]] ||
 { echo "FAIL: main approval not finalized";exit 1; }
[[ "$(db "SELECT count(*) FROM c10_demo.approval_exception_events_v1 WHERE escalation_id=$e2 AND action='acknowledged';")" -le 1 ]] ||
 { echo "FAIL: duplicate escalation race receipt";exit 1; }
[[ "$(db "SELECT count(*) FROM c10_demo.stock_movements;")" == 6 ]] ||
 { echo "FAIL: escalation touched stock";exit 1; }
echo 'PASS: independent escalation terminal races, parent approval serialization, no non-authorizing stock effect'
