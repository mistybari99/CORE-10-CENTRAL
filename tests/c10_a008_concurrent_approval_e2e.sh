#!/usr/bin/env bash
# Disposable PostgreSQL only: two independent sessions race the same approval/key.
set -euo pipefail
export PGOPTIONS="-c statement_timeout=15000"
psql -v ON_ERROR_STOP=1 -Atc "INSERT INTO c10_demo.approval_requests(tenant_id,business_id,created_by) VALUES (1,101,'33333333-3333-4333-8333-333333333333') RETURNING id" > /tmp/c10-a008-request-id
id="$(tail -n1 /tmp/c10-a008-request-id)"
[[ "$id" =~ ^[0-9]+$ ]]
rm -f /tmp/c10-a008-lock-ready
# Lock the request in a separate transaction; ensure both callers must wait.
psql -v ON_ERROR_STOP=1 > /tmp/c10-a008-lock.log 2>&1 <<SQL &
BEGIN;
SELECT id FROM c10_demo.approval_requests WHERE id=$id FOR UPDATE;
\! touch /tmp/c10-a008-lock-ready
SELECT pg_sleep(3);
COMMIT;
SQL
locker=$!
for i in {1..100}; do
  [[ -f /tmp/c10-a008-lock-ready ]] && break
  kill -0 "$locker" 2>/dev/null || { cat /tmp/c10-a008-lock.log; exit 1; }
  sleep 0.05
done
[[ -f /tmp/c10-a008-lock-ready ]] || { echo 'FAIL: lock not acquired'; exit 1; }
# Separate authenticated connections with identical actor, action and key.
for n in 1 2; do
  psql -v ON_ERROR_STOP=1 -At > "/tmp/c10-a008-race-$n" 2>&1 <<SQL &
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
SELECT c10_demo.decide_approval($id,'approve','concurrent_same_key_01');
SQL
  pids[$n]=$!
done
wait "${pids[1]}"
wait "${pids[2]}"
wait "$locker"
a="$(tail -n1 /tmp/c10-a008-race-1)"
b="$(tail -n1 /tmp/c10-a008-race-2)"
[[ "$a" =~ ^[0-9]+$ && "$a" == "$b" ]] || { echo 'FAIL: concurrent replay differs'; cat /tmp/c10-a008-race-{1,2}; exit 1; }
count="$(psql -v ON_ERROR_STOP=1 -Atc "SELECT count(*) FROM c10_demo.approval_events WHERE request_id=$id")"
state="$(psql -v ON_ERROR_STOP=1 -Atc "SELECT status FROM c10_demo.approval_requests WHERE id=$id")"
[[ "$count" == 1 && "$state" == approved ]] || { echo "FAIL: events=$count status=$state"; exit 1; }
echo "PASS: concurrent same-key approval produced one event and identical event IDs"
