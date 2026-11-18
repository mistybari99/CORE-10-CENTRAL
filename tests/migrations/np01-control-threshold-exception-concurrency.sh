#!/usr/bin/env bash
# NP01 / B-020 / 0114 — disposable PG17 concurrency, authorization-before-lock
# and revoked member proof. No hosted or staging access is permitted.
set -euo pipefail
cd "$(dirname "$0")/../.."
case "$PGHOST" in localhost|127.0.0.1) ;; *) echo 'NP01_0114_LOCAL_ONLY' >&2; exit 2;; esac
DB="core10_0114_gov002_$$"
tmp=$(mktemp -d)
cleanup(){ PGDATABASE=postgres psql -X -q -c "DROP DATABASE IF EXISTS $DB WITH (FORCE)" >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT
PGDATABASE=postgres psql -X -q -c "CREATE DATABASE $DB"
export PGDATABASE="$DB"
psql -X -q -v ON_ERROR_STOP=1 -c "DO \$\$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated')
 THEN CREATE ROLE authenticated NOLOGIN; END IF;
END \$\$;"
internal/migrations/run.sh up >/dev/null
owner=99981111-1111-4111-8111-111111111111
maker=99983333-3333-4333-8333-333333333333
foreign=99982222-2222-4222-8222-222222222222
psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO core10.tenants(id,slug) VALUES
 (99981,'np01-0114-race-a'),(99982,'np01-0114-race-b');
INSERT INTO core10.legal_entities(id,tenant_id,label)
 VALUES(99983,99981,'NP01 0114 Race A'),(99984,99982,'NP01 0114 Race B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(99985,99981,99983,'np01-0114-race-a','sweets_bakery','np01_0114_race_biza'),
       (99986,99982,99984,'np01-0114-race-b','sweets_bakery','np01_0114_race_bizb');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(99981,'99981111-1111-4111-8111-111111111111','tenant_owner'),
       (99982,'99982222-2222-4222-8222-222222222222','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role)
 VALUES(99981,99985,'99983333-3333-4333-8333-333333333333','manager');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','99981111-1111-4111-8111-111111111111',false);
SELECT core10.publish_approval_policy_v1(99985,'stock','adjust',60,'np01_0114_race_policy_01');
SQL
pol=$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT id FROM core10.approval_policy_versions_v1 WHERE business_id=99985 AND domain='stock' AND action_code='adjust' ORDER BY id DESC LIMIT 1")
run_rpc(){
 local uid="$1" expression="$2" outfile="$3"
 psql -X -q -At -v ON_ERROR_STOP=1 >"$outfile" 2>&1 <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$uid',false);
SELECT 'RPC_RESULT '||$expression;
SQL
}
race_same(){
 local label="$1" uid="$2" expression="$3"
 run_rpc "$uid" "$expression" "$tmp/$label-a" & local a=$!
 run_rpc "$uid" "$expression" "$tmp/$label-b" & local b=$!
 wait "$a";wait "$b"
 local va vb
 va=$(grep '^RPC_RESULT ' "$tmp/$label-a" | tail -1)
 vb=$(grep '^RPC_RESULT ' "$tmp/$label-b" | tail -1)
 [[ -n "$va" && "$va" = "$vb" ]] || {
 echo "NP01_0114_REPLAY_RACE:$label";cat "$tmp/$label-a" "$tmp/$label-b";exit 1;
 }
 echo "$va" | sed 's/^RPC_RESULT //'
}
race_same threshold "$owner" "core10.configure_approval_threshold_v1($pol,'quantity','KG',4.125,3,'np01_0114_race_threshold_01')" >/dev/null
run_rpc "$maker" "core10.submit_typed_approval_v1(99985,'stock','adjust','np01-0114-race-source',1,'{\"amount\":4.125,\"unit\":\"KG\"}'::jsonb,'np01_0114_race_submit_01')" "$tmp/submit"
req=$(grep '^RPC_RESULT ' "$tmp/submit"|tail -1|cut -d' ' -f2-)
e=$(race_same exception "$maker" "core10.request_approval_exception_v1($req,'Two independent exception request writers','urgent',30,'np01_0114_race_exception_01')")
[ "$(psql -X -At -c "SELECT count(*) FROM core10.approval_exception_escalations_v1 WHERE request_id=$req")" = 1 ] || { echo 'NP01_0114_DUPLICATE_EXCEPTION';exit 1; }
# Owner decision versus maker withdrawal; exactly one is permitted to commit.
do_transition(){
 local uid="$1" expression="$2" output="$3"
 psql -X -q -At -v ON_ERROR_STOP=0 >"$output" 2>&1 <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$uid',false);
SELECT 'TRANSITION '||$expression;
SQL
}
do_transition "$owner" "core10.decide_approval_exception_v1($e,'acknowledged','np01_0114_race_ack_01')" "$tmp/ack" & a=$!
do_transition "$maker" "core10.withdraw_approval_exception_v1($e,'np01_0114_race_withdraw_01')" "$tmp/withdraw" & b=$!
wait "$a";wait "$b"
ok=$(grep -h -c '^TRANSITION [0-9]' "$tmp/ack" "$tmp/withdraw" | awk '{s+=$1} END{print s+0}')
stale=$(grep -h -c 'exception_stale_or_final' "$tmp/ack" "$tmp/withdraw" | awk '{s+=$1} END{print s+0}')
[ "$ok" = 1 ] && [ "$stale" = 1 ] || { echo "NP01_0114_FINAL_STATE_RACE_FAIL:$ok:$stale";cat "$tmp/ack" "$tmp/withdraw";exit 1; }
[ "$(psql -X -At -c "SELECT count(*) FROM core10.approval_exception_events_v1 WHERE escalation_id=$e AND action<>'submitted'")" = 1 ] || {
 echo 'NP01_0114_DUPLICATE_TERMINAL_EVENT';exit 1;
}
# Hold actual protected rows in a separate transaction. A foreign Owner's
# requests must fail authorization before waiting on those exclusive locks.
hold(){
 local q="$1" target="$2"
 psql -X -q -At -v ON_ERROR_STOP=1 >"$target" 2>&1 <<SQL
BEGIN;
$q
SELECT 'LOCK_HELD';
SELECT pg_sleep(2);
COMMIT;
SQL
}
assert_fast_denied(){
 local label="$1" heldsql="$2" uid="$3" rpc="$4" expected="$5"
 hold "$heldsql" "$tmp/lock-$label" & local locker=$!
 local ready=0
 for _ in {1..100}; do
  if grep -q LOCK_HELD "$tmp/lock-$label" 2>/dev/null; then ready=1;break;fi
  sleep 0.02
 done
 [ "$ready" = 1 ] || { echo "NP01_0114_LOCK_HOLDER_MISSING:$label";kill "$locker" 2>/dev/null||true;exit 1; }
 psql -X -q -At -v ON_ERROR_STOP=0 >"$tmp/deny-$label" 2>&1 <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$uid',false);
SET statement_timeout='700ms';
SELECT $rpc;
SQL
 if ! grep -q "$expected" "$tmp/deny-$label" || grep -qi 'statement timeout' "$tmp/deny-$label"; then
  echo "NP01_0114_AUTH_BEFORE_LOCK_FAILED:$label";cat "$tmp/deny-$label";exit 1;
 fi
 wait "$locker"
}
assert_fast_denied policy "SELECT id FROM core10.approval_policy_versions_v1 WHERE id=$pol FOR UPDATE;" "$foreign" "core10.configure_approval_threshold_v1($pol,'quantity','KG',4.125,3,'np01_0114_race_foreign_01')" threshold_not_authorized
assert_fast_denied request "SELECT id FROM core10.approval_requests WHERE id=$req FOR UPDATE;" "$foreign" "core10.request_approval_exception_v1($req,'Foreign maker forged an exception','urgent',30,'np01_0114_race_foreign_02')" exception_request_denied
assert_fast_denied decide "SELECT id FROM core10.approval_requests WHERE id=$req FOR UPDATE;" "$foreign" "core10.decide_approval_exception_v1($e,'acknowledged','np01_0114_race_foreign_03')" exception_decision_denied
assert_fast_denied withdraw "SELECT id FROM core10.approval_requests WHERE id=$req FOR UPDATE;" "$foreign" "core10.withdraw_approval_exception_v1($e,'np01_0114_race_foreign_04')" exception_withdraw_denied
psql -X -q -v ON_ERROR_STOP=1 -c "UPDATE core10.business_members SET valid_until=now()-interval '1 day' WHERE business_id=99985 AND user_id='$maker'::uuid"
psql -X -q -At -v ON_ERROR_STOP=0 >"$tmp/revoked" 2>&1 <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','$maker',false);
SELECT core10.request_approval_exception_v1($req,'Previously authorized maker is revoked','urgent',30,'np01_0114_race_revoked_01');
SQL
grep -q exception_request_denied "$tmp/revoked" || { echo 'NP01_0114_REVOKED_MAKER_NOT_DENIED';cat "$tmp/revoked";exit 1; }
[ "$(psql -X -At -c "SELECT (core10.verify_canonical_audit_v1(99985)->>'ok')::boolean")" = t ] || { echo 'NP01_0114_AUDIT_CHAIN_FAIL';exit 1; }
echo "PASS NP01 0114: two-session threshold/exception replay, competing finals, four unauthorized lock probes, revoked maker, canonical Audit"
