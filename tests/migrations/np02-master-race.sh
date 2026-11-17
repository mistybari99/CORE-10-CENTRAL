#!/usr/bin/env bash
# B-011: real concurrent PostgreSQL sessions against the Master Data RPCs (disposable PG17 only).
# A coordinator session holds an advisory lock; every worker blocks on it, so all workers of a round
# are released at the same instant and genuinely overlap. Nothing here is sequential replay.
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
Q() { psql -X -qAt -v ON_ERROR_STOP=1 "$@"; }
OWNER=b1111111-1111-4111-8111-111111111111; OTHER=b5555555-5555-4555-8555-555555555555
Q -f tests/migrations/np02-master-race-seed.sql >/dev/null
fail() { echo "MASTER_RACE_FAIL: $*" >&2; exit 1; }

# run_round NAME N SQL-for-worker-i (use {i}); outputs $tmp/NAME.i.out / .err; exit codes in $tmp/NAME.i.rc
run_round() {
  local name=$1 n=$2 sql=$3 i
  Q -c "SELECT pg_advisory_lock(98100)" -c "SELECT pg_sleep(1.2)" -c "SELECT pg_advisory_unlock(98100)" >/dev/null &
  local coord=$!; sleep 0.4
  for i in $(seq 1 "$n"); do
    ( psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/$name.$i.out" 2>"$tmp/$name.$i.err" <<SQL
SELECT pg_advisory_lock_shared(98100); SELECT pg_advisory_unlock_shared(98100);
SET ROLE authenticated;
${sql//\{i\}/$i}
SQL
      echo $? >"$tmp/$name.$i.rc" ) &
  done
  wait
}
ok_count() { local c=0 f; for f in "$tmp/$1".*.rc; do [ "$(cat "$f")" = 0 ] && c=$((c+1)); done; echo $c; }
as() { echo "SELECT set_config('request.jwt.claims','{\"sub\":\"$1\"}',false);"; }

# 1. Same request key, same actor, 4 sessions: all succeed with the SAME id, one row, one audit event.
run_round samekey 4 "$(as $OWNER) SELECT core10.master_save_item_v1(9811,'RACE-1','Race item',NULL,NULL,NULL,NULL,NULL,0,'race-same-key-0001');"
[ "$(ok_count samekey)" = 4 ] || { cat "$tmp"/samekey.*.err >&2; fail "same-key sessions did not all replay"; }
[ "$(cat "$tmp"/samekey.*.out | grep -E '^[0-9]+$' | sort -u | wc -l)" = 1 ] || fail "same key returned different ids"
[ "$(Q -c "SELECT count(*) FROM core10.items WHERE business_id=9811 AND sku='RACE-1'")" = 1 ] || fail "duplicate item"
[ "$(Q -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9811 AND request_key='master:9811:race-same-key-0001'")" = 1 ] || fail "audit not exactly once"

# 2. Different keys, same SKU, 4 sessions: exactly one item; losers fail with a unique violation, no partial rows.
run_round sku 4 "$(as $OWNER) SELECT core10.master_save_item_v1(9811,'RACE-2','Race two',NULL,NULL,NULL,NULL,NULL,0,'race-sku-key-000{i}');"
[ "$(ok_count sku)" = 1 ] || fail "SKU race winners=$(ok_count sku)"
grep -lq "duplicate key" "$tmp"/sku.*.err || fail "SKU losers did not fail on the unique key"
[ "$(Q -c "SELECT count(*) FROM core10.items WHERE business_id=9811 AND sku='RACE-2'")" = 1 ] || fail "duplicate SKU"
[ "$(Q -c "SELECT count(*) FROM core10.master_requests_v1 WHERE business_id=9811 AND request_key LIKE 'race-sku-key-%'")" = 1 ] || fail "loser left a request row"
[ "$(Q -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9811 AND request_key LIKE 'master:9811:race-sku-key-%'")" = 1 ] || fail "loser left an audit row"

# 3. Same barcode, different keys: exactly one barcode row.
ITEM=$(Q -c "SELECT id FROM core10.items WHERE business_id=9811 AND sku='RACE-1'")
run_round bc 4 "$(as $OWNER) SELECT core10.master_save_barcode_v1(9811,'4006381333931',$ITEM,NULL,NULL,true,0,'race-bc-key-000{i}');"
[ "$(ok_count bc)" = 1 ] || fail "barcode winners=$(ok_count bc)"
[ "$(Q -c "SELECT count(*) FROM core10.master_item_barcodes_v1 WHERE business_id=9811 AND barcode='4006381333931'")" = 1 ] || fail "duplicate barcode"

# 4. Optimistic version: 4 sessions update the same item at version 1 with different keys -> one wins (version 2).
run_round ver 4 "$(as $OWNER) SELECT core10.master_save_item_v1(9811,'RACE-1','Edit {i}',NULL,NULL,NULL,NULL,NULL,1,'race-ver-key-000{i}');"
[ "$(ok_count ver)" = 1 ] || fail "version winners=$(ok_count ver)"
grep -lq "MASTER_STALE_OR_MISSING" "$tmp"/ver.*.err || fail "losers not refused as stale"
[ "$(Q -c "SELECT version FROM core10.items WHERE business_id=9811 AND sku='RACE-1'")" = 2 ] || fail "version not exactly 2"

# 5. Cross-tenant owner and unsigned sessions racing the real owner: only the owner's write lands.
run_round xt 3 "SELECT CASE {i} WHEN 1 THEN set_config('request.jwt.claims','{\"sub\":\"$OWNER\"}',false)
 WHEN 2 THEN set_config('request.jwt.claims','{\"sub\":\"$OTHER\"}',false) ELSE set_config('request.jwt.claims','{}',false) END;
 SELECT core10.master_save_party_v1(9811,'XT-{i}','customer','Party {i}',NULL,NULL,NULL,NULL,0,'race-xt-key-000{i}');"
[ "$(cat "$tmp/xt.1.rc")" = 0 ] || fail "owner write failed"
grep -q MASTER_AUTH_DENIED "$tmp/xt.2.err" && grep -q MASTER_AUTH_DENIED "$tmp/xt.3.err" || fail "foreign/unsigned not denied"
[ "$(Q -c "SELECT count(*) FROM core10.master_parties_v1 WHERE business_id=9811 AND code LIKE 'XT-%'")" = 1 ] || fail "foreign party landed"

# 6. Owner Control flipped off while writers race: every write either committed before the switch or was
#    refused CONTROL_DISABLED; after the switch commits, a new write is always refused.
run_round ctl 4 "$(as $OWNER) SELECT CASE WHEN {i}=1 THEN (core10.control_set_v1(9811,NULL,'master.party',false,0::smallint,'{}'::jsonb,NULL,false,0,'Owner pauses during race','race-ctl-off-0001'))::text
 ELSE (core10.master_save_party_v1(9811,'CT-{i}','customer','Party {i}',NULL,NULL,NULL,NULL,0,'race-ctl-key-000{i}'))::text END;"
[ "$(cat "$tmp/ctl.1.rc")" = 0 ] || { cat "$tmp/ctl.1.err" >&2; fail "control switch failed"; }
for i in 2 3 4; do
  if [ "$(cat "$tmp/ctl.$i.rc")" != 0 ]; then grep -q "CONTROL_DISABLED:master.party" "$tmp/ctl.$i.err" || { cat "$tmp/ctl.$i.err" >&2; fail "unexpected error in ctl.$i"; }; fi
done
landed=$(Q -c "SELECT count(*) FROM core10.master_parties_v1 WHERE business_id=9811 AND code LIKE 'CT-%'")
reqs=$(Q -c "SELECT count(*) FROM core10.master_requests_v1 WHERE business_id=9811 AND request_key LIKE 'race-ctl-key-%'")
[ "$landed" = "$reqs" ] || fail "party rows ($landed) != recorded requests ($reqs)"
if psql -X -qAt -v ON_ERROR_STOP=1 >/dev/null 2>"$tmp/after.err" <<SQL
SET ROLE authenticated; $(as $OWNER)
SELECT core10.master_save_party_v1(9811,'CT-9','customer','After',NULL,NULL,NULL,NULL,0,'race-ctl-after-0001');
SQL
then fail "write accepted after Owner disabled master.party"; fi
grep -q "CONTROL_DISABLED:master.party" "$tmp/after.err" || fail "post-switch refusal was not CONTROL_DISABLED"

# Audit integrity for the whole run: one master audit event per recorded request, none for refusals.
[ "$(Q -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9811 AND source_domain='master'")" = \
  "$(Q -c "SELECT count(*) FROM core10.master_requests_v1 WHERE business_id=9811")" ] || fail "audit/request mismatch"
echo "NP02_MASTER_RACE_PASS (same-key replay x4, SKU, barcode, version, cross-tenant, Owner Control switch; ctl writes landed=$landed)"
