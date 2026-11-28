#!/usr/bin/env bash
set -euo pipefail
# Only in the disposable CI database after admission.test.sql.
q(){ psql -X -v ON_ERROR_STOP=1 -At -c "$1"; }
prefix="BEGIN; SELECT set_config('request.jwt.claims','{\"sub\":\"00000000-0000-4000-8000-000000099201\"}',true);"
account="(SELECT id FROM core10.integration_account_v1 WHERE business_id=99201 AND provider_code='email')"
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
q "$prefix SELECT core10._integration_enqueue_dry_run_candidate_v1($account,'race-a','synthetic-race','sample'); SELECT pg_sleep(1); COMMIT;" >"$d/a" & a=$!
q "$prefix SELECT core10._integration_enqueue_dry_run_candidate_v1($account,'race-b','synthetic-race','sample'); COMMIT;" >"$d/b" & b=$!
wait "$a"; wait "$b"
test "$(q "SELECT count(*) FROM core10.integration_outbox_v1 WHERE account_id=$account AND state='queued'")" = 1
test "$(q "SELECT count(*) FROM core10.integration_outbox_v1 WHERE account_id=$account AND state='blocked_cap'")" = 1
# Parallel same-key calls cannot duplicate a record, even if cap already exhausted.
q "$prefix SELECT core10._integration_enqueue_dry_run_candidate_v1($account,'race-replay','synthetic-race','sample'); SELECT pg_sleep(1); COMMIT;" >"$d/c" & c=$!
q "$prefix SELECT core10._integration_enqueue_dry_run_candidate_v1($account,'race-replay','synthetic-race','sample'); COMMIT;" >"$d/e" & e=$!
wait "$c"; wait "$e"
test "$(q "SELECT count(*) FROM core10.integration_outbox_v1 WHERE account_id=$account AND idempotency_key='race-replay'")" = 1
echo 'PASS concurrent cap and same-key enqueue'
