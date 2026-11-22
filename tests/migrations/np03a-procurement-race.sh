#!/usr/bin/env bash
# B-012 / 0203: real concurrent sessions on purchase receipts (disposable PG17 only; harness of np02-master-race.sh).
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
Q() { psql -X -qAt -v ON_ERROR_STOP=1 "$@"; }
OWNER=a7411111-1111-4111-8111-111111111111
Q -f tests/migrations/np03a-procurement-race-seed.sql >/dev/null
fail() { echo "PROCUREMENT_RACE_FAIL: $*" >&2; exit 1; }
run_round() {
  local name=$1 n=$2 sql=$3 i
  Q -c "SELECT pg_advisory_lock(74100)" -c "SELECT pg_sleep(1.2)" -c "SELECT pg_advisory_unlock(74100)" >/dev/null &
  sleep 0.4
  for i in $(seq 1 "$n"); do
    ( psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/$name.$i.out" 2>"$tmp/$name.$i.err" <<SQL
SELECT pg_advisory_lock_shared(74100); SELECT pg_advisory_unlock_shared(74100);
SET ROLE authenticated; SELECT set_config('request.jwt.claims','{"sub":"$OWNER"}',false);
${sql//\{i\}/$i}
SQL
      echo $? >"$tmp/$name.$i.rc" ) &
  done
  wait
}
ok_count() { local c=0 f; for f in "$tmp/$1".*.rc; do [ "$(cat "$f")" = 0 ] && c=$((c+1)); done; echo $c; }
only_errors() { local f; for f in "$tmp/$1".*.err; do [ -s "$f" ] || continue; grep -qE "$2" "$f" || { cat "$f" >&2; fail "$1: unexpected error"; }; done; }
PO1=$(Q -c "SELECT id FROM core10.purchase_orders_v1 WHERE request_key='prace-po-0001'")
GRN=$(Q -c "SELECT id FROM core10.goods_receipts_v1 WHERE request_key='prace-grn-0001'")

# 1. Four receivers race for the same 10 open units with 6 each: exactly one receipt is accepted.
run_round recv 4 "SELECT core10.procurement_receive_v1($PO1,741111,'[{\"line_no\":1,\"quantity\":6}]',NULL,'prace-recv-000{i}')->>'grn_id';"
[ "$(ok_count recv)" = 1 ] || { cat "$tmp"/recv.*.err >&2; fail "over-receipt winners=$(ok_count recv)"; }
only_errors recv "CONTROL_LIMIT:over_receipt_pct"
[ "$(Q -c "SELECT sum(l.received_qty) FROM core10.goods_receipt_lines_v1 l WHERE l.po_id=$PO1")" = "6.000" ] || fail "received total not 6"

# 2. Four posters of one inspected receipt with different keys: one posts, stock grows once.
run_round post 4 "SELECT core10.procurement_post_grn_v1($GRN,2,'prace-post-000{i}')->>'status';"
[ "$(ok_count post)" = 1 ] || { cat "$tmp"/post.*.err >&2; fail "receipt posted $(ok_count post) times"; }
only_errors post "PROC_STALE_VERSION|PROC_INVALID_TRANSITION"
[ "$(Q -c "SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=741111 AND item_id=74101")" = "10.000" ] || fail "stock not exactly 10"
[ "$(Q -c "SELECT count(*) FROM core10.inventory_reconciliation_v1 WHERE business_id=7411 AND NOT reconciled")" = 0 ] || fail "not reconciled"
echo "PASS np03a procurement races: concurrent over-receipt, concurrent GRN posting"
