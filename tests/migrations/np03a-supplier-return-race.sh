#!/usr/bin/env bash
# B-012 / 0207: real concurrent sessions on supplier returns and GRN cancel (disposable PG17 only;
# harness of np03a-procurement-race.sh).
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
Q() { psql -X -qAt -v ON_ERROR_STOP=1 "$@"; }
OWNER=17030000-0000-4000-8000-000000000001
Q -f tests/migrations/np03a-supplier-return-race-seed.sql >/dev/null
fail() { echo "SUPPLIER_RETURN_RACE_FAIL: $*" >&2; exit 1; }
# run_round name n sql [sql_for_session_1]: n sessions start together behind one advisory lock.
run_round() {
  local name=$1 n=$2 sql=$3 first=${4:-} i body
  Q -c "SELECT pg_advisory_lock(17030)" -c "SELECT pg_sleep(1.2)" -c "SELECT pg_advisory_unlock(17030)" >/dev/null &
  sleep 0.4
  for i in $(seq 1 "$n"); do
    body=$sql; if [ "$i" = 1 ] && [ -n "$first" ]; then body=$first; fi
    ( psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/$name.$i.out" 2>"$tmp/$name.$i.err" <<SQL
SELECT pg_advisory_lock_shared(17030); SELECT pg_advisory_unlock_shared(17030);
SET ROLE authenticated; SELECT set_config('request.jwt.claims','{"sub":"$OWNER"}',false);
${body//\{i\}/$i}
SQL
      echo $? >"$tmp/$name.$i.rc" ) &
  done
  wait
}
ok_count() { local c=0 f; for f in "$tmp/$1".*.rc; do [ "$(cat "$f")" = 0 ] && c=$((c+1)); done; echo $c; }
only_errors() { local f; for f in "$tmp/$1".*.err; do [ -s "$f" ] || continue; grep -qE "$2" "$f" || { cat "$f" >&2; fail "$1: unexpected error"; }; done; }
GRNA=$(Q -c "SELECT id FROM core10.goods_receipts_v1 WHERE request_key='rrace-grn-0001'")
GRNB=$(Q -c "SELECT id FROM core10.goods_receipts_v1 WHERE request_key='rrace-grn-0002'")
PO2=$(Q -c "SELECT id FROM core10.purchase_orders_v1 WHERE request_key='rrace-po-0002'")

# 1. Four preparers draft 30 each against 50 accepted: exactly one draft (the reservation is serialized).
run_round draft 4 "SELECT core10.procurement_save_return_v1($GRNA,'[{\"line_no\":1,\"quantity\":30}]','race return','rrace-ret-000{i}')->>'return_id';"
[ "$(ok_count draft)" = 1 ] || { cat "$tmp"/draft.*.err >&2; fail "over-return drafts=$(ok_count draft)"; }
only_errors draft "PROC_RETURN_EXCEEDS_ACCEPTED"
RET=$(Q -c "SELECT id FROM core10.supplier_returns_v1 WHERE business_id=17031 AND status='draft'")

# 2. Four posters of that draft with different keys: one posts, stock falls once.
run_round post 4 "SELECT core10.procurement_advance_return_v1($RET,'post',1,'rrace-rpost-000{i}')->>'status';"
[ "$(ok_count post)" = 1 ] || { cat "$tmp"/post.*.err >&2; fail "return posted $(ok_count post) times"; }
only_errors post "PROC_STALE_VERSION|PROC_INVALID_TRANSITION"
[ "$(Q -c "SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=1703111 AND item_id=17301")" = "20.000" ] || fail "stock not exactly 50-30"
[ "$(Q -c "SELECT returned_qty FROM core10.goods_receipt_lines_v1 WHERE grn_id=$GRNA AND line_no=1")" = "30.000" ] || fail "GRN returned not 30"

# 3. Cancel GRN B while three receivers try to take its 10 open units: the cancel commits, and at most one
#    receiver gets the freed quantity (never more than ordered).
run_round cx 4 "SELECT core10.procurement_receive_v1($PO2,1703111,'[{\"line_no\":1,\"quantity\":10}]',NULL,'rrace-recv-000{i}')->>'grn_id';" \
 "SELECT core10.procurement_cancel_grn_v1($GRNB,1,'race cancel','rrace-cx-0001')->>'status';"
[ "$(cat "$tmp/cx.1.rc")" = 0 ] || { cat "$tmp/cx.1.err" >&2; fail "cancel failed"; }
only_errors cx "CONTROL_LIMIT:over_receipt_pct"
[ "$(Q -c "SELECT coalesce(sum(l.received_qty),0) FROM core10.goods_receipt_lines_v1 l JOIN core10.goods_receipts_v1 g ON g.id=l.grn_id WHERE l.po_id=$PO2 AND g.status<>'cancelled'")" \
  = "$(( ($(ok_count cx)-1)*10 )).000" ] || fail "live receipts do not match winners"
[ "$(ok_count cx)" -le 2 ] || fail "freed quantity received twice"
[ "$(Q -c "SELECT count(*) FROM core10.inventory_reconciliation_v1 WHERE business_id=17031 AND NOT reconciled")" = 0 ] || fail "not reconciled"
echo "PASS np03a supplier-return races: concurrent over-return drafts, concurrent return posting, cancel vs receive"
