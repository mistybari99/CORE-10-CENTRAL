#!/usr/bin/env bash
# GOV-002 PostgreSQL17 race test on a DISPOSABLE demo database only.
# Requires c10_a008_routing_delegation_withdrawal_e2e.sql to have run.
set -euo pipefail
D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
SQLCLIENT="psql"
owner='22222222-2222-4222-8222-222222222222'
maker='33333333-3333-4333-8333-333333333333'
delegate='99999999-9999-4999-8999-999999999999'

submit() {
  local doc="$1" key="$2"
  $SQLCLIENT -X -qAt -v ON_ERROR_STOP=1 -c \
   "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$maker',false); SELECT c10_demo.submit_typed_approval_v1(101,'demo_inventory','adjustment_review','$doc',1,'{\"amount\":1,\"unit\":\"kg\"}'::jsonb,'$key');" | tail -n1
}
vote() {
  local actor="$1" request="$2" action="$3" key="$4"
  $SQLCLIENT -X -qAt -v ON_ERROR_STOP=1 -c \
   "BEGIN; SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$actor',true); SELECT pg_sleep(0.3); SELECT c10_demo.decide_approval($request,'$action','$key'); COMMIT;"
}
check_one_success() {
  local first="$1" second="$2" label="$3"
  if [[ $(( (first==0) + (second==0) )) != 1 ]]; then
    echo "FAIL $label: expected one successful vote; status $first / $second"
    exit 1
  fi
}
rowcount() {
  $SQLCLIENT -X -qAt -v ON_ERROR_STOP=1 -c "$1" | tail -n1
}

# Two contradictory terminal commands race for ONE pending row lock.
rid="$(submit 'race-terminal-source' 'race_terminal_submit_01')"
vote "$owner" "$rid" reject 'race_reject_vote_01' >"$D/a" 2>&1 & p1=$!
vote "$owner" "$rid" defer 'race_defer_vote_01' >"$D/b" 2>&1 & p2=$!
set +e
wait "$p1"; s1=$?
wait "$p2"; s2=$?
set -e
check_one_success "$s1" "$s2" terminal
if [[ "$(rowcount "SELECT count(*) FROM c10_demo.approval_events WHERE request_id=$rid")" != 1 ]] ||
   [[ "$(rowcount "SELECT status FROM c10_demo.approval_requests WHERE id=$rid")" == pending ]]; then
  echo 'FAIL terminal: duplicate or missing transition'; exit 1
fi

# Business owner and granted manager race for same stage 1. Exactly one vote,
# one stage receipt, and NO premature approval.
rid2="$(submit 'race-staged-source' 'race_stage_submit_01')"
$SQLCLIENT -X -qAt -v ON_ERROR_STOP=1 -c \
 "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$owner',false); SELECT c10_demo.delegate_approval_stage_v1($rid2,'$delegate',20,'race_grant_stage_01');" >/dev/null
vote "$owner" "$rid2" approve 'race_owner_stage_01' >"$D/c" 2>&1 & p3=$!
vote "$delegate" "$rid2" approve 'race_delegate_stage_01' >"$D/d" 2>&1 & p4=$!
set +e
wait "$p3"; s3=$?
wait "$p4"; s4=$?
set -e
check_one_success "$s3" "$s4" stage
if [[ "$(rowcount "SELECT count(*) FROM c10_demo.approval_stage_receipts_v1 WHERE request_id=$rid2")" != 1 ]] ||
   [[ "$(rowcount "SELECT status FROM c10_demo.approval_requests WHERE id=$rid2")" != pending ]]; then
  echo 'FAIL stage: double vote or premature approved'; exit 1
fi
if [[ "$(rowcount "SELECT count(*) FROM c10_demo.stock_movements")" != 0 ]]; then
  echo 'FAIL: race posted stock'; exit 1
fi
echo 'PASS: two real concurrent psql sessions serialize terminal and stage-one decisions (one succeeds, one denied); no posting'
