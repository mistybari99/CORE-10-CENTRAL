#!/usr/bin/env bash
# B-012 / 0209: real concurrent sessions on lot hold and lot-aware issue (disposable PG17 only;
# harness of np03a-supplier-return-race.sh).
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
Q() { psql -X -qAt -v ON_ERROR_STOP=1 "$@"; }
OWNER=19030000-0000-4000-8000-000000000001
Q -f tests/migrations/np03a-lots-race-seed.sql >/dev/null
fail() { echo "LOTS_RACE_FAIL: $*" >&2; exit 1; }
run_round() {
  local name=$1 n=$2 sql=$3 first=${4:-} i body
  Q -c "SELECT pg_advisory_lock(19030)" -c "SELECT pg_sleep(1.2)" -c "SELECT pg_advisory_unlock(19030)" >/dev/null &
  sleep 0.4
  for i in $(seq 1 "$n"); do
    body=$sql; if [ "$i" = 1 ] && [ -n "$first" ]; then body=$first; fi
    ( psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/$name.$i.out" 2>"$tmp/$name.$i.err" <<SQL
SELECT pg_advisory_lock_shared(19030); SELECT pg_advisory_unlock_shared(19030);
SET ROLE authenticated; SELECT set_config('request.jwt.claims','{"sub":"$OWNER"}',false);
${body//\{i\}/$i}
SQL
      echo $? >"$tmp/$name.$i.rc" ) &
  done
  wait
}
ok_count() { local c=0 f; for f in "$tmp/$1".*.rc; do [ "$(cat "$f")" = 0 ] && c=$((c+1)); done; echo $c; }
only_errors() { local f; for f in "$tmp/$1".*.err; do [ -s "$f" ] || continue; grep -qE "$2" "$f" || { cat "$f" >&2; fail "$1: unexpected error"; }; done; }
LRB=$(Q -c "SELECT id FROM core10.inventory_lots_v1 WHERE business_id=19031 AND lot_code='LR-B'")
# one stock command: create (named lot or lot-less) -> confirm -> post, in one session
cmd() { # $1 = lot id or NULL, $2 = qty, $3 = key
  echo "SELECT core10.advance_inventory_command_v1(x.c,'post',2,'$3-p')->>'status' FROM (SELECT (core10.advance_inventory_command_v1(
   (CASE WHEN $1::bigint IS NULL THEN core10.create_inventory_command_v1(19031,'issue',1903111,NULL,19301,$2,NULL,'$3')
    ELSE core10.inventory_create_lot_command_v1(19031,'issue',1903111,NULL,19301,$2,$1,NULL,'$3') END->>'command_id')::bigint,
   'confirm',1,'$3-c')->>'command_id')::bigint AS c) x;"
}

# 1. One session holds LR-B while three issue 5 of LR-B by name: the hold commits; every issue either posted before
#    it (lot share lock) or is refused INV_LOT_HELD; the lot balance falls exactly once per winner.
run_round hold 4 "$(cmd "$LRB" 5 'lrace-hiss-000{i}')" "SELECT core10.inventory_lot_hold_v1($LRB,'hold',NULL,'lrace-hold-0001')->>'status';"
[ "$(cat "$tmp/hold.1.rc")" = 0 ] || { cat "$tmp/hold.1.err" >&2; fail "hold failed"; }
only_errors hold "INV_LOT_HELD"
W1=$(( $(ok_count hold) - 1 ))
[ "$(Q -c "SELECT on_hand FROM core10.stock_lot_balances_v1 WHERE location_id=1903111 AND lot_id=$LRB")" = "$(printf '%d.000' $((30-5*W1)))" ] || fail "LR-B not 30-5x$W1"
[ "$(Q -c "SELECT count(*) FROM core10.inventory_commands_v1 WHERE business_id=19031 AND lot_id=$LRB AND status='posted'")" = "$W1" ] \
  || fail "posted LR-B commands do not match the winners"
Q -c "SELECT set_config('request.jwt.claims','{\"sub\":\"$OWNER\"}',false)" -c "SELECT core10.inventory_lot_hold_v1($LRB,'release',NULL,'lrace-rel-0001')" >/dev/null

# 2. Five lot-less issues of 15 race for what is left: winners = floor(left/15); lots drained FEFO, never below zero,
#    breakdown always equals the location balance (all stock here is lot stock).
LEFT=$((60-5*W1))
run_round fefo 5 "$(cmd NULL 15 'lrace-fiss-000{i}')"
WANT=$(( LEFT/15 < 5 ? LEFT/15 : 5 ))
[ "$(ok_count fefo)" = "$WANT" ] || { cat "$tmp"/fefo.*.err >&2; fail "lot-less winners $(ok_count fefo) <> $WANT"; }
only_errors fefo "INV_INSUFFICIENT_STOCK"
[ "$(Q -c "SELECT count(*) FROM core10.stock_lot_balances_v1 WHERE business_id=19031 AND on_hand<0")" = 0 ] || fail "negative lot balance"
[ "$(Q -c "SELECT count(*) FROM core10.inventory_lot_reconciliation_v1 WHERE business_id=19031 AND (NOT reconciled OR untracked<>0)")" = 0 ] || fail "lot breakdown not reconciled"
[ "$(Q -c "SELECT count(*) FROM core10.inventory_reconciliation_v1 WHERE business_id=19031 AND NOT reconciled")" = 0 ] || fail "ledger not reconciled"
LRA=$(Q -c "SELECT on_hand FROM core10.stock_lot_balances_v1 b JOIN core10.inventory_lots_v1 l ON l.id=b.lot_id WHERE b.business_id=19031 AND l.lot_code='LR-A'")
[ "$LRA" = "0.000" ] || fail "FEFO did not drain the earlier-expiring LR-A first (LR-A=$LRA)"
echo "PASS np03a lots races: hold vs named-lot issue, concurrent lot-less FEFO issue"
