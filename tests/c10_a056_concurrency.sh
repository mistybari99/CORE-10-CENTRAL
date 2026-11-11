#!/usr/bin/env bash
# C10-A056 concurrency proof on the disposable DB after tests/c10_a056_crm_lifecycle_e2e.sql: concurrent merge, quote revision, idempotent create.
set -uo pipefail
M=33333333-3333-4333-8333-333333333333
run() { # run <sleep> <sql>  (as manager, one transaction, holds locks for <sleep>s)
  psql -X -q -t -A -v ON_ERROR_STOP=1 -c "BEGIN; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$M',true); SELECT $2; SELECT pg_sleep($1); COMMIT;" 2>&1
}
one() { psql -X -q -t -A -v ON_ERROR_STOP=1 -c "BEGIN; SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','$M',true); SELECT $1; COMMIT;" 2>&1 | grep -v '^$' | grep -v "^$M" | tail -1; }
fail() { echo "FAIL: $*"; exit 1; }
cid() { one "(c10_demo.a056_create_customer_v1(101,1001,'person','$1',NULL,'$2',NULL,NULL,'$3')->>'customer_id')"; }
X1=$(cid "Race One" race1@example.test race-c1-000001); X2=$(cid "Race Two" race2@example.test race-c2-000001)
[ -n "$X1" ] && [ -n "$X2" ] || fail "setup customers"
run 2 "c10_demo.a056_merge_customers_v1($X1,$X2,1,1,'race-merge-a001','race a')" > /tmp/a056_m1.out 2>&1 &
sleep 0.7
run 0 "c10_demo.a056_merge_customers_v1($X2,$X1,1,1,'race-merge-b001','race b')" > /tmp/a056_m2.out 2>&1 &
wait
ok=$(grep -l '"survivor_id"' /tmp/a056_m1.out /tmp/a056_m2.out | wc -l); bad=$(grep -l 'A056_CUSTOMER_NOT_ACTIVE\|A056_STALE_CUSTOMER' /tmp/a056_m1.out /tmp/a056_m2.out | wc -l)
[ "$ok" = 1 ] && [ "$bad" = 1 ] || { cat /tmp/a056_m1.out /tmp/a056_m2.out; fail "concurrent merge expected exactly 1 success + 1 refusal (got $ok/$bad)"; }
n=$(psql -X -t -A -c "SELECT count(*) FROM c10_demo.a056_customers WHERE id IN ($X1,$X2) AND status='merged'"); [ "$n" = 1 ] || fail "exactly one loser expected, got $n"
echo "PASS concurrent merge: one winner, one refusal, one merged loser"
OPP=$(one "(c10_demo.a056_create_opportunity_v1(101,1001,$X1,NULL,NULL,'Race job',NULL,NULL,NULL,'race-opp-000001')->>'opportunity_id')")
Q=$(one "(c10_demo.a056_create_quotation_v1($OPP,'[{\"description\":\"A\",\"quantity\":1,\"unit_price\":10}]',NULL,NULL,'race-quote-00001')->>'quotation_id')")
[ -n "$Q" ] || fail "setup quote (opp=$OPP)"
run 2 "c10_demo.a056_revise_quotation_v1($Q,'[{\"description\":\"B\",\"quantity\":1,\"unit_price\":11}]',NULL,NULL,1,'race-rev-a00001')" > /tmp/a056_q1.out 2>&1 &
sleep 0.7
run 0 "c10_demo.a056_revise_quotation_v1($Q,'[{\"description\":\"C\",\"quantity\":1,\"unit_price\":12}]',NULL,NULL,1,'race-rev-b00001')" > /tmp/a056_q2.out 2>&1 &
wait
ok=$(grep -l '"version_no"' /tmp/a056_q1.out /tmp/a056_q2.out | wc -l); bad=$(grep -l 'A056_STALE_QUOTATION' /tmp/a056_q1.out /tmp/a056_q2.out | wc -l)
[ "$ok" = 1 ] && [ "$bad" = 1 ] || { cat /tmp/a056_q1.out /tmp/a056_q2.out; fail "concurrent quote revise expected 1 success + 1 stale"; }
n=$(psql -X -t -A -c "SELECT count(*) FROM c10_demo.a056_quote_versions WHERE quotation_id=$Q"); [ "$n" = 2 ] || fail "expected exactly 2 versions, got $n"
echo "PASS concurrent quote revision: one new immutable version, one STALE"
run 2 "c10_demo.a056_create_customer_v1(101,1001,'person','Same Key',NULL,NULL,NULL,NULL,'race-same-key-01')" > /tmp/a056_i1.out 2>&1 &
sleep 0.7
run 0 "c10_demo.a056_create_customer_v1(101,1001,'person','Same Key',NULL,NULL,NULL,NULL,'race-same-key-01')" > /tmp/a056_i2.out 2>&1 &
wait
n=$(psql -X -t -A -c "SELECT count(*) FROM c10_demo.a056_customers WHERE request_key='race-same-key-01'"); [ "$n" = 1 ] || { cat /tmp/a056_i*.out; fail "idempotent create produced $n rows"; }
grep -q '"replayed": true' /tmp/a056_i1.out /tmp/a056_i2.out || { cat /tmp/a056_i*.out; fail "second call not a replay"; }
echo "PASS concurrent idempotent create: one row, one replay"
