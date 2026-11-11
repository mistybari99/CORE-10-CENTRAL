#!/usr/bin/env bash
# C10-A054 concurrency under REAL parallel sessions. Disposable PostgreSQL ONLY. Run AFTER tests/c10_a054_policy_e2e.sql
# (needs the e2e fixture state in business 102). Signed-claim simulation, not GoTrue.
set -u
BOB=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa; MGRB=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb; MGRB2=b1111111-1111-4111-8111-111111111111
OUT=$(mktemp -d); fail=0
run(){ psql -X -q -tA -v ON_ERROR_STOP=1 -c "BEGIN; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$1',true); SELECT $2; COMMIT;" >"$3" 2>&1; }
su(){ psql -X -q -tA -v ON_ERROR_STOP=1 -c "$1"; }
check(){ if [ "$2" != "$3" ]; then echo "FAIL $1: got [$2] want [$3]"; fail=1; else echo "ok   $1"; fi; }
nok(){ grep -L 'ERROR' "$OUT"/$1-* 2>/dev/null | wc -l | tr -d ' '; }
B2=$(su "SELECT id FROM c10_demo.wf_employees WHERE business_id=102 AND employee_no='B2'")

# 1) revocation racing an in-flight delegated action: the action must NOT slip through after the revoke commits
run "$BOB" "c10_demo.a054_grant_delegation_v1(102,'conc-grant-0001','$MGRB','payroll_preparer','allow',NULL,'2026-09-01','2026-09-01',NULL,'Sep preparer')" "$OUT/g-1"
DID=$(su "SELECT id FROM c10_demo.a054_delegations WHERE request_key='conc-grant-0001'")
( psql -X -q -tA -v ON_ERROR_STOP=1 -c "BEGIN; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$BOB',true); SELECT c10_demo.a054_revoke_delegation_v1(102,'conc-revoke-0001',$DID,1,'revoked during race'); SELECT pg_sleep(2); COMMIT;" >"$OUT/r-1" 2>&1 ) &
sleep 0.7
run "$MGRB" "c10_demo.wf_create_payroll_draft_v1(102,'conc-draft-0001','2026-09-01',NULL,NULL)" "$OUT/d-1"; wait
check "revoke committed" "$(su "SELECT revoked_at IS NOT NULL FROM c10_demo.a054_delegations WHERE id=$DID")" t
check "racing action denied after revoke" "$(grep -c 'a054_delegation_denied' "$OUT/d-1")" 1
check "no September draft created" "$(su "SELECT count(*) FROM c10_demo.wf_payroll_runs WHERE business_id=102 AND period_start='2026-09-01'")" 0

# 2) four parallel payment records of 10000 against ~25072 outstanding: at most two fit
OUTSTAND=$(su "SELECT outstanding FROM c10_demo.a054i_liability_lines(102,'2026-10-01') WHERE employee_id=$B2")
for i in 1 2 3 4; do run "$BOB" "c10_demo.a054_record_external_payment_v1(102,'conc-pay-000$i','2026-10-01',$B2,10000,'cash','EXT-CONC-$i',current_date,NULL)" "$OUT/p-$i" & done; wait
check "payments never exceed outstanding (successes)" "$(nok p)" 2
check "overflow rejected" "$(grep -l 'a054_payment_exceeds_outstanding' $OUT/p-* | wc -l | tr -d ' ')" 2
check "outstanding never negative" "$(su "SELECT outstanding>=0 FROM c10_demo.a054i_liability_lines(102,'2026-10-01') WHERE employee_id=$B2")" t
check "outstanding dropped by exactly two records" "$(su "SELECT outstanding FROM c10_demo.a054i_liability_lines(102,'2026-10-01') WHERE employee_id=$B2")" "$(su "SELECT $OUTSTAND-20000")"

# 3) same request key from 6 sessions -> one record, identical receipts
for i in $(seq 1 6); do run "$BOB" "c10_demo.a054_record_external_payment_v1(102,'conc-pay-same1','2026-10-01',$B2,100,'cash','EXT-SAME-1',current_date,NULL)" "$OUT/s-$i" & done; wait
check "same-key retries all succeed" "$(nok s)" 6
check "exactly one stored record" "$(su "SELECT count(*) FROM c10_demo.a054_payment_records WHERE request_key='conc-pay-same1'")" 1

# 4) quota race: two non-overlapping requests (9 + 10 days) against a 14-day quota -> exactly one wins
run "$MGRB2" "c10_demo.wf_request_leave_v1(102,'conc-lv-000001',$B2,'SICK','2026-12-01','2026-12-10','quota race a')" "$OUT/l-1" &
run "$MGRB2" "c10_demo.wf_request_leave_v1(102,'conc-lv-000002',$B2,'SICK','2026-12-14','2026-12-24','quota race b')" "$OUT/l-2" &
wait
check "exactly one leave accepted" "$(nok l)" 1
check "other rejected on quota" "$(grep -l 'wf_leave_quota_exceeded' $OUT/l-* | wc -l | tr -d ' ')" 1

# 5) audit chain still intact after all concurrent writes
check "audit chain intact" "$(su "SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$BOB',false); SELECT c10_demo.wf_integrity_report_v1(102)->>'ok'" | tail -1)" true
[ "$fail" = 0 ] && echo A054_CONCURRENCY_PASS || { echo A054_CONCURRENCY_FAIL; exit 1; }
