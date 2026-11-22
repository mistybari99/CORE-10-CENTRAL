#!/usr/bin/env bash
# B-012 / 0201: real concurrent PostgreSQL sessions against the stock command RPCs (disposable PG17 only).
# A coordinator session holds an advisory lock; every worker blocks on it, so all workers of a round are
# released at the same instant and genuinely overlap (same harness as np02-master-race.sh).
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
Q() { psql -X -qAt -v ON_ERROR_STOP=1 "$@"; }
OWNER=c1111111-1111-4111-8111-111111111111; OTHER=c5555555-5555-4555-8555-555555555555
Q -f tests/migrations/np03a-inventory-race-seed.sql >/dev/null
fail() { echo "INVENTORY_RACE_FAIL: $*" >&2; exit 1; }
run_round() {
  local name=$1 n=$2 sql=$3 i
  Q -c "SELECT pg_advisory_lock(73100)" -c "SELECT pg_sleep(1.2)" -c "SELECT pg_advisory_unlock(73100)" >/dev/null &
  sleep 0.4
  for i in $(seq 1 "$n"); do
    ( psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/$name.$i.out" 2>"$tmp/$name.$i.err" <<SQL
SELECT pg_advisory_lock_shared(73100); SELECT pg_advisory_unlock_shared(73100);
SET ROLE authenticated;
${sql//\{i\}/$i}
SQL
      echo $? >"$tmp/$name.$i.rc" ) &
  done
  wait
}
ok_count() { local c=0 f; for f in "$tmp/$1".*.rc; do [ "$(cat "$f")" = 0 ] && c=$((c+1)); done; echo $c; }
as() { echo "SELECT set_config('request.jwt.claims','{\"sub\":\"$1\"}',false);"; }
cid() { Q -c "SELECT id FROM core10.inventory_commands_v1 WHERE business_id=7311 AND request_key='$1'"; }
bal() { Q -c "SELECT coalesce((SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=$1 AND item_id=73101),0)"; }
only_errors() { local f; for f in "$tmp/$1".*.err; do [ -s "$f" ] || continue; grep -qE "$2" "$f" || { cat "$f" >&2; fail "$1: unexpected error"; }; done; }

# 1. Same create key, same actor, 4 sessions: one command, one request row, one audit event, same id everywhere.
run_round samekey 4 "$(as $OWNER) SELECT core10.create_inventory_command_v1(7311,'receive',NULL,731111,73101,7,NULL,'race-same-key-0001')->>'command_id';"
[ "$(ok_count samekey)" = 4 ] || { cat "$tmp"/samekey.*.err >&2; fail "same-key sessions did not all replay"; }
[ "$(cat "$tmp"/samekey.*.out | grep -E '^[0-9]+$' | sort -u | wc -l)" = 1 ] || fail "same key returned different ids"
[ "$(Q -c "SELECT count(*) FROM core10.inventory_commands_v1 WHERE business_id=7311 AND request_key='race-same-key-0001'")" = 1 ] || fail "duplicate command"
[ "$(Q -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=7311 AND request_key='inventory:7311:race-same-key-0001'")" = 1 ] || fail "audit not exactly once"

# 2. Oversell: six confirmed issues of 3 from a balance of 10 post at once -> exactly three post, balance 1.
run_round oversell 6 "$(as $OWNER) SELECT core10.advance_inventory_command_v1($(cid race-iss-0001)-1+{i},'post',2,'race-iss-post-000{i}')->>'status';"
ids_ok=$(Q -c "SELECT count(*) FROM core10.inventory_commands_v1 WHERE business_id=7311 AND request_key LIKE 'race-iss-000_' AND id-$(cid race-iss-0001) BETWEEN 0 AND 5")
[ "$ids_ok" = 6 ] || fail "issue commands are not contiguous ids"
[ "$(ok_count oversell)" = 3 ] || { cat "$tmp"/oversell.*.err >&2; fail "oversell winners=$(ok_count oversell)"; }
only_errors oversell "INV_INSUFFICIENT_STOCK"
[ "$(bal 731111)" = "1.000" ] || fail "factory balance $(bal 731111) not 1"
[ "$(Q -c "SELECT count(*) FROM core10.inventory_commands_v1 WHERE business_id=7311 AND request_key LIKE 'race-iss-000_' AND status='posted'")" = 3 ] || fail "posted count"

# 3. One command, four posters with different keys at the same version: one posts, the rest are stale.
ONE=$(cid race-one-0001); G0=$(bal 731131)
run_round one 4 "$(as $OWNER) SELECT core10.advance_inventory_command_v1($ONE,'post',2,'race-one-post-000{i}')->>'status';"
[ "$(ok_count one)" = 1 ] || fail "single command posted $(ok_count one) times"
only_errors one "INV_STALE_VERSION|INV_INVALID_TRANSITION|INV_CONFIRM_FIRST"
[ "$(Q -c "SELECT count(*) FROM core10.stock_movements WHERE request_key='c10-inv-cmd-$ONE'")" = 1 ] || fail "double movement"
[ "$(Q -c "SELECT ($(bal 731131)-$G0)")" = "1.000" ] || fail "godown did not grow by exactly 1"

# 4. Crossing transfers branch <-> godown in eight sessions (deadlock bait): no deadlock, stock conserved.
T0=$(Q -c "SELECT $(bal 731121)+$(bal 731131)")
run_round cross 8 "$(as $OWNER) SELECT core10.advance_inventory_command_v1(c.cid,'post',2,'race-x-post-000{i}')->>'status' FROM (SELECT
 ((SELECT core10.advance_inventory_command_v1((core10.create_inventory_command_v1(7311,'transfer',
   CASE WHEN {i}%2=0 THEN 731121 ELSE 731131 END, CASE WHEN {i}%2=0 THEN 731131 ELSE 731121 END,73101,5,NULL,'race-x-000{i}')->>'command_id')::bigint,
   'confirm',1,'race-x-conf-000{i}'))->>'command_id')::bigint AS cid) c;"
[ "$(ok_count cross)" = 8 ] || { cat "$tmp"/cross.*.err >&2; fail "crossing transfers failed (deadlock?)"; }
[ "$(Q -c "SELECT $(bal 731121)+$(bal 731131)")" = "$T0" ] || fail "transfer did not conserve stock"

# 5. Owner switches stock off while posters race: each post either committed first or got CONTROL_DISABLED;
#    afterwards every post is refused.
run_round ctl 4 "$(as $OWNER) SELECT CASE WHEN {i}=1 THEN (core10.control_set_v1(7311,NULL,'inventory.stock_event',false,0::smallint,'{}'::jsonb,NULL,false,0,'Owner pauses stock during race','race-ctl-off-0001'))::text
 ELSE (core10.advance_inventory_command_v1($(cid race-ctl-0002)-2+{i},'post',2,'race-ctl-post-000{i}'))::text END;"
[ "$(cat "$tmp/ctl.1.rc")" = 0 ] || { cat "$tmp/ctl.1.err" >&2; fail "control switch failed"; }
only_errors ctl "CONTROL_DISABLED:inventory.stock_event"
posted=$(Q -c "SELECT count(*) FROM core10.inventory_commands_v1 WHERE business_id=7311 AND request_key LIKE 'race-ctl-000_' AND status='posted'")
moved=$(Q -c "SELECT count(*) FROM core10.stock_movements m JOIN core10.inventory_commands_v1 c ON m.request_key='c10-inv-cmd-'||c.id WHERE c.request_key LIKE 'race-ctl-000_'")
[ "$posted" = "$moved" ] || fail "posted commands ($posted) != ledger movements ($moved)"
LEFT=$(Q -c "SELECT id FROM core10.inventory_commands_v1 WHERE business_id=7311 AND request_key LIKE 'race-ctl-000_' AND status='confirmed' LIMIT 1")
if [ -n "$LEFT" ]; then
  if psql -X -qAt -v ON_ERROR_STOP=1 >/dev/null 2>"$tmp/after.err" <<SQL
SET ROLE authenticated; $(as $OWNER)
SELECT core10.advance_inventory_command_v1($LEFT,'post',2,'race-ctl-after-0001');
SQL
  then fail "post after switch-off succeeded"; fi
  grep -q "CONTROL_DISABLED:inventory.stock_event" "$tmp/after.err" || fail "post after switch-off not refused by Control"
fi

# 6. Other tenant and unsigned sessions racing the owner on the same command: only the owner's action lands.
Q -c "SELECT set_config('request.jwt.claims','{\"sub\":\"$OWNER\"}',false); SELECT core10.control_set_v1(7311,NULL,'inventory.stock_event',true,0::smallint,'{}'::jsonb,NULL,false,1,'Owner resumes stock','race-ctl-on-0001')" >/dev/null
XT=$(Q -c "SELECT set_config('request.jwt.claims','{\"sub\":\"$OWNER\"}',false)" -c "SELECT core10.create_inventory_command_v1(7311,'receive',NULL,731121,73101,2,NULL,'race-xt-0001')->>'command_id'" | tail -1)
run_round xt 3 "SELECT CASE {i} WHEN 1 THEN set_config('request.jwt.claims','{\"sub\":\"$OWNER\"}',false)
 WHEN 2 THEN set_config('request.jwt.claims','{\"sub\":\"$OTHER\"}',false) ELSE set_config('request.jwt.claims','{}',false) END;
 SELECT core10.advance_inventory_command_v1($XT,'confirm',1,'race-xt-conf-000{i}')->>'status';"
[ "$(cat "$tmp/xt.1.rc")" = 0 ] || { cat "$tmp/xt.1.err" >&2; fail "owner confirm failed"; }
grep -q "INV_SCOPE" "$tmp/xt.2.err" || fail "foreign tenant not refused"
grep -qE "INV_INVALID_ACTION|INV_SCOPE" "$tmp/xt.3.err" || fail "unsigned not refused"
[ "$(Q -c "SELECT confirmed_by FROM core10.inventory_commands_v1 WHERE id=$XT")" = "$OWNER" ] || fail "wrong confirmer"

[ "$(Q -c "SELECT count(*) FROM core10.inventory_reconciliation_v1 WHERE business_id=7311 AND NOT reconciled")" = 0 ] || fail "ledger not reconciled"
# 7. Real membership revocation while the command row is locked: an already-admitted caller
#    must re-authorize AFTER the wait, not post on a stale pre-lock membership snapshot.
#    The lock waiter is observed in pg_stat_activity BEFORE the owner is revoked (no timing-only guess).
RVC=$(Q -c "SELECT set_config('request.jwt.claims','{\"sub\":\"$OWNER\"}',false)" \
  -c "SELECT core10.create_inventory_command_v1(7311,'receive',NULL,731111,73101,4,NULL,'race-revoke-0001')->>'command_id'" | tail -1)
Q -c "SELECT set_config('request.jwt.claims','{\"sub\":\"$OWNER\"}',false)" \
  -c "SELECT core10.advance_inventory_command_v1($RVC,'confirm',1,'race-revoke-confirm-0001')" >/dev/null
before_revoke=$(bal 731111)
(
  if psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/revoke.holder.out" 2>"$tmp/revoke.holder.err" <<SQL
BEGIN;
SELECT id FROM core10.inventory_commands_v1 WHERE id=$RVC FOR UPDATE;
SELECT pg_sleep(5);
UPDATE core10.tenant_members SET active=false WHERE tenant_id=731 AND user_id='$OWNER';
COMMIT;
SQL
  then echo 0 > "$tmp/revoke.holder.rc"; else echo 1 > "$tmp/revoke.holder.rc"; fi
) &
holder_pid=$!
sleep 0.3
(
  if psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/revoke.worker.out" 2>"$tmp/revoke.worker.err" <<SQL
SET application_name = 'core10_stock_revocation_waiter';
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"$OWNER"}',false);
SELECT core10.advance_inventory_command_v1($RVC,'post',2,'race-revoke-post-0001');
SQL
  then echo 0 > "$tmp/revoke.worker.rc"; else echo 1 > "$tmp/revoke.worker.rc"; fi
) &
worker_pid=$!
saw_wait=0
for attempt in $(seq 1 35); do
  waiting=$(Q -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='core10_stock_revocation_waiter' AND wait_event_type='Lock'")
  if [ "$waiting" = 1 ]; then saw_wait=1; break; fi
  sleep 0.12
done
wait "$holder_pid" || true
wait "$worker_pid" || true
[ "$saw_wait" = 1 ] || fail "revoke race never observed blocked worker before revocation"
[ "$(cat "$tmp/revoke.holder.rc")" = 0 ] || { cat "$tmp/revoke.holder.err" >&2; fail "revocation transaction failed"; }
[ "$(cat "$tmp/revoke.worker.rc")" != 0 ] || fail "revoked owner posted stock after row-lock wait"
grep -qE 'INV_SCOPE|INV_PERMISSION_DENIED' "$tmp/revoke.worker.err" || { cat "$tmp/revoke.worker.err" >&2; fail "revoked writer returned wrong denial"; }
[ "$(Q -c "SELECT status FROM core10.inventory_commands_v1 WHERE id=$RVC")" = confirmed ] || fail "revoked command transitioned"
[ "$(bal 731111)" = "$before_revoke" ] || fail "revoked command altered the ledger"
Q -c "UPDATE core10.tenant_members SET active=true WHERE tenant_id=731 AND user_id='$OWNER'" >/dev/null

echo "PASS np03a inventory races: same key, oversell, single post, crossing transfers, Control switch, cross-tenant, revoked mid-lock"
