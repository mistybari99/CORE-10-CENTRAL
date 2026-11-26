#!/usr/bin/env bash
# Two independent concurrent PostgreSQL sessions per operation.
# Disposable synthetic fixtures are created by np01-governance-e2e.sql.
# This proves row-lock + idempotency, NOT signed hosted GoTrue behavior.
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
owner="11111111-1111-4111-8111-111111111111"
manager="22222222-2222-4222-8222-222222222222"
run_rpc() {
 local uid="$1" expr="$2" outfile="$3"
 psql -X -v ON_ERROR_STOP=1 -At -c "BEGIN;
  SELECT set_config('request.jwt.claim.sub','$uid',true);
  SELECT $expr;
  COMMIT;" >"$outfile"
}
first_id() { grep -E '^[0-9]+$' "$1" | head -1; }
race() {
 local label="$1" user="$2" sql="$3"
 run_rpc "$user" "$sql" "$tmp/$label-A" &
 local a=$!
 run_rpc "$user" "$sql" "$tmp/$label-B" &
 local b=$!
 wait "$a"; wait "$b"
 local va vb
 va="$(first_id "$tmp/$label-A")"
 vb="$(first_id "$tmp/$label-B")"
 if [ -z "$va" ] || [ "$va" != "$vb" ]; then
  echo "NP01 concurrency failure: $label $va != $vb" >&2; exit 1
 fi
 echo "$va"
}
p_id="$(race policy "$owner" "core10.publish_approval_policy_v1(99121,'stock','receipt',30,'np01_race_policy_0001')")"
r_id="$(race request "$manager" "core10.submit_typed_approval_v1(99121,'stock','receipt','np01_race_source',1,'{\"amount\":1,\"unit\":\"KG\"}'::jsonb,'np01_race_req_00001')")"
e_id="$(race exception "$manager" "core10.request_approval_exception_v1($r_id,'Concurrent exception review','normal',10,'np01_race_exception_0001')")"
count_policy="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM core10.approval_policy_versions_v1 WHERE business_id=99121 AND request_key='np01_race_policy_0001';")"
count_req="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM core10.approval_requests WHERE business_id=99121 AND submit_key_v1='np01_race_req_00001';")"
count_esc="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM core10.approval_exception_escalations_v1 WHERE business_id=99121 AND request_key='np01_race_exception_0001';")"
if [[ "$count_policy" != 1 || "$count_req" != 1 || "$count_esc" != 1 ]]; then
 echo "NP01 concurrency duplicates policy=$count_policy request=$count_req exception=$count_esc" >&2
 exit 1
fi
echo "NP01_CONCURRENT_SESSIONS_OK policy=$p_id request=$r_id exception=$e_id"
