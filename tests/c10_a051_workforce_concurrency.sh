#!/usr/bin/env bash
# C10-A051 concurrency / idempotency under real parallel sessions. Disposable PostgreSQL ONLY.
# Requires the e2e fixture state (tests/c10_a051_workforce_e2e.sql already applied). Signed-claim simulation, not GoTrue.
set -u
OWNER=11111111-1111-4111-8111-111111111111; BO=22222222-2222-4222-8222-222222222222
MGR=33333333-3333-4333-8333-333333333333; E1=a2222222-2222-4222-8222-222222222222
OUT=$(mktemp -d); fail=0
run() { # uid sql outfile
 psql -X -q -tA -v ON_ERROR_STOP=1 -c "BEGIN; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$1',true); SELECT $2; COMMIT;" >"$3" 2>&1
}
as_superuser() { psql -X -q -tA -v ON_ERROR_STOP=1 -c "$1"; }
check() { if [ "$2" != "$3" ]; then echo "FAIL $1: got [$2] want [$3]"; fail=1; else echo "ok   $1"; fi; }
ok_count() { grep -L 'ERROR' "$OUT"/$1-* 2>/dev/null | wc -l | tr -d ' '; }

# 1) same punch batch retried by 8 parallel sessions -> identical receipt, exactly one stored punch
for i in $(seq 1 8); do run "$MGR" "c10_demo.wf_import_punches_v1(101,'conc-punch-0001',1001,'device','[{\"employee_no\":\"EMP-002\",\"at\":\"2026-11-03T09:00:00+06:00\",\"direction\":\"in\",\"ref\":\"conc-ref-1\"}]'::jsonb)" "$OUT/p-$i" & done; wait
check "parallel punch retry successes" "$(ok_count p)" 8
check "parallel punch identical receipts" "$(cat $OUT/p-* | grep -v '^\(BEGIN\|COMMIT\|SET\|t\|f\)$' | grep accepted | sort -u | wc -l | tr -d ' ')" 1
check "single stored punch" "$(as_superuser "SELECT count(*) FROM c10_demo.wf_punches WHERE source_ref='conc-ref-1'")" 1

# 2) five parallel draft creations (distinct keys) for one period -> exactly one wins
for i in $(seq 1 5); do run "$BO" "c10_demo.wf_create_payroll_draft_v1(101,'conc-draft-000$i','2026-09-01',NULL,NULL)" "$OUT/d-$i" & done; wait
check "exactly one draft created" "$(ok_count d)" 1
check "others rejected as in-progress" "$(grep -l 'wf_payroll_in_progress' $OUT/d-* | wc -l | tr -d ' ')" 4
check "one in-progress run in DB" "$(as_superuser "SELECT count(*) FROM c10_demo.wf_payroll_runs WHERE business_id=101 AND period_start='2026-09-01' AND status='draft'")" 1

# 3) approve vs reject of the same leave request by two reviewers -> exactly one decision wins
LV=$(psql -X -q -tA -c "BEGIN; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$E1',true); SELECT (c10_demo.wf_request_leave_v1(101,'conc-leave-req1',NULL,'SICK','2026-12-07','2026-12-07','concurrency test')->>'leave_id'); COMMIT;" | grep -E '^[0-9]+$')
run "$MGR"   "c10_demo.wf_decide_leave_v1(101,'conc-leave-dec1',$LV,'approve','manager says yes')" "$OUT/l-1" &
run "$OWNER" "c10_demo.wf_decide_leave_v1(101,'conc-leave-dec2',$LV,'reject','owner says no')" "$OUT/l-2" &
wait
check "exactly one leave decision succeeded" "$(ok_count l)" 1
check "loser got state error" "$(grep -l 'wf_leave_state_invalid' $OUT/l-* | wc -l | tr -d ' ')" 1

# 4) stale optimistic version on settings from two sessions
V=$(psql -X -q -tA -c "SELECT version FROM c10_demo.wf_business_settings WHERE business_id=101")
run "$BO"    "c10_demo.wf_save_settings_v1(101,'conc-cfg-00001',$V,'{\"duplicate_window_seconds\":90}'::jsonb,'parallel edit A')" "$OUT/s-1" &
run "$OWNER" "c10_demo.wf_save_settings_v1(101,'conc-cfg-00002',$V,'{\"duplicate_window_seconds\":100}'::jsonb,'parallel edit B')" "$OUT/s-2" &
wait
check "exactly one settings write wins" "$(ok_count s)" 1
check "loser stale" "$(grep -l 'wf_stale_version' $OUT/s-* | wc -l | tr -d ' ')" 1

# 5) same employee number created by 6 sessions with different keys -> one row
for i in $(seq 1 6); do run "$BO" "c10_demo.wf_save_employee_v1(101,'conc-emp-0000$i',NULL,NULL,'{\"employee_no\":\"EMP-CONC\",\"full_name\":\"Parallel Person\",\"joined_on\":\"2026-11-01\",\"contract_type\":\"contract\",\"site_id\":1001}'::jsonb,'parallel create')" "$OUT/e-$i" & done; wait
check "one employee created" "$(ok_count e)" 1
check "duplicates rejected" "$(grep -l 'wf_employee_no_duplicate' $OUT/e-* | wc -l | tr -d ' ')" 5
check "single employee row" "$(as_superuser "SELECT count(*) FROM c10_demo.wf_employees WHERE business_id=101 AND employee_no='EMP-CONC'")" 1

# 6) audit chain still valid after parallel load
check "audit chain intact" "$(psql -X -q -tA -c "BEGIN; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$OWNER',true); SELECT c10_demo.wf_integrity_report_v1(101)->>'ok'; COMMIT;" | grep -E '^(true|false)$')" true
rm -rf "$OUT"
[ $fail -eq 0 ] && echo A051_CONCURRENCY_PASS || { echo A051_CONCURRENCY_FAIL; exit 1; }
