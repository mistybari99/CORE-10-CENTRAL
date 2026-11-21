#!/usr/bin/env bash
# NP06/0402 — two real PostgreSQL sessions prove same-key replay and budget caps.
# Disposable PG17 CI only. Uses a committed synthetic actor; no hosted credentials.
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
psql -X -q -v ON_ERROR_STOP=1 -f tests/migrations/np06-finance-arap-race-seed.sql >"$tmp/seed"
link="$(psql -X -At -c "SELECT l.id FROM core10.finance_arap_links_v1 l JOIN core10.finance_journals_v1 j ON j.id=l.journal_id WHERE l.business_id=9631 AND j.source_ref='arap-race-original'")"
payment="$(psql -X -At -c "SELECT id FROM core10.finance_journals_v1 WHERE business_id=9631 AND source_ref='arap-race-payment'")"
[[ "$link" =~ ^[0-9]+$ && "$payment" =~ ^[0-9]+$ ]] || { echo "ARAP_RACE_SEED_MISSING" >&2; exit 1; }

alloc() {
  local prefix="$1" amount="$2" key="$3"
  psql -X -qAt -v ON_ERROR_STOP=1 >"$prefix.out" 2>"$prefix.err" <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SELECT core10.finance_allocate_payment_v1($link,$payment,$amount,'$key');
SQL
}

# Same actor, same key/payload: concurrent replay yields one stored allocation.
alloc "$tmp/same1" 60 'arapRaceAlloc001' & a=$!
alloc "$tmp/same2" 60 'arapRaceAlloc001' & b=$!
wait "$a" || { cat "$tmp/same1.err"; exit 1; }
wait "$b" || { cat "$tmp/same2.err"; exit 1; }
allocation="$(psql -X -At -c "SELECT id FROM core10.finance_arap_allocations_v1 WHERE business_id=9631 AND request_key='arapRaceAlloc001'")"
[[ "$allocation" =~ ^[0-9]+$ ]] || { echo "ARAP_RACE_REPLAY_ID_MISSING"; exit 1; }
grep -Fxq "$allocation" "$tmp/same1.out" || { echo "ARAP_RACE_REPLAY_FIRST_FAILED"; exit 1; }
grep -Fxq "$allocation" "$tmp/same2.out" || { echo "ARAP_RACE_REPLAY_SECOND_FAILED"; exit 1; }
test "$(psql -X -At -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9631 AND action='finance.arap_allocate'")" = 1 || {
 echo "ARAP_RACE_DUPLICATE_AUDIT"; exit 1;
}

# Two distinct request keys try to spend 25 each from remaining 40.
# Exactly ONE can commit; the other is rejected without a money/audit side effect.
alloc "$tmp/cap1" 25 'arapRaceAlloc002' & a=$!
alloc "$tmp/cap2" 25 'arapRaceAlloc003' & b=$!
s1=0; s2=0
wait "$a" || s1=$?
wait "$b" || s2=$?
if [[ "$s1" == "$s2" ]]; then
 echo "ARAP_RACE_CAP_EXPECT_ONE_REJECTION rc1=$s1 rc2=$s2" >&2
 cat "$tmp/cap1.err" "$tmp/cap2.err" >&2
 exit 1
fi
if ((s1 != 0)); then grep -q 'FIN_ARAP_OVERALLOCATION' "$tmp/cap1.err" || { cat "$tmp/cap1.err"; exit 1; }; fi
if ((s2 != 0)); then grep -q 'FIN_ARAP_OVERALLOCATION' "$tmp/cap2.err" || { cat "$tmp/cap2.err"; exit 1; }; fi
test "$(psql -X -At -c "SELECT count(*) FROM core10.finance_arap_allocations_v1 WHERE business_id=9631")" = 2 || {
 echo "ARAP_RACE_UNEXPECTED_ALLOCATION_COUNT"; exit 1;
}
test "$(psql -X -At -c "SELECT sum(amount)::integer FROM core10.finance_arap_allocations_v1 WHERE business_id=9631")" = 85 || {
 echo "ARAP_RACE_BUDGET_BREACHED"; exit 1;
}
test "$(psql -X -At -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9631 AND action='finance.arap_allocate'")" = 2 || {
 echo "ARAP_RACE_UNEXPECTED_AUDIT_COUNT"; exit 1;
}
echo "NP06_ARAP_RACE_PASS replay_once=1 capped_commit=1 capped_reject=1 total=85"

# Third race: an unpaid AR source is reversed while its separate posted
# payment is being allocated. The 0401 journal lock + 0403 BEFORE INSERT guard
# must make exactly ONE outcome commit. Never permit paid-and-reversed.
rev_doc="$(psql -X -At -c "SELECT id FROM core10.finance_journals_v1 WHERE business_id=9631 AND source_ref='arap-race-reverse-original'")"
rev_pay="$(psql -X -At -c "SELECT id FROM core10.finance_journals_v1 WHERE business_id=9631 AND source_ref='arap-race-reverse-payment'")"
rev_link="$(psql -X -At -c "SELECT id FROM core10.finance_arap_links_v1 WHERE business_id=9631 AND journal_id=$rev_doc")"
[[ "$rev_doc" =~ ^[0-9]+$ && "$rev_pay" =~ ^[0-9]+$ && "$rev_link" =~ ^[0-9]+$ ]] || {
 echo "ARAP_REVERSE_RACE_FIXTURE_MISSING" >&2; exit 1;
}

reverse_concurrent() {
 psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/reverse.out" 2>"$tmp/reverse.err" <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SELECT core10.finance_reverse_posted_journal_v1($rev_doc,'2026-12-01','correction','arapRaceRevPost01');
SQL
}
allocate_concurrent() {
 psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/allocate.out" 2>"$tmp/allocate.err" <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SELECT core10.finance_allocate_payment_v1($rev_link,$rev_pay,60,'arapRaceRevAlloc01');
SQL
}
reverse_concurrent & r1=$!
allocate_concurrent & r2=$!
rc1=0; rc2=0
wait "$r1" || rc1=$?
wait "$r2" || rc2=$?
if [[ "$rc1" == "$rc2" ]]; then
 echo "ARAP_REVERSAL_ALLOCATION_RACE_MUST_HAVE_ONE_WINNER rc_reverse=$rc1 rc_allocate=$rc2" >&2
 cat "$tmp/reverse.err" "$tmp/allocate.err" >&2
 exit 1
fi
if ((rc1 != 0)); then
 grep -q "FIN_ARAP_ALLOCATED_REVERSAL_NOT_CONNECTED" "$tmp/reverse.err" || {
  cat "$tmp/reverse.err" >&2; exit 1;
 }
fi
if ((rc2 != 0)); then
 grep -q "FIN_ARAP_PAYMENT_SCOPE_OR_STATUS" "$tmp/allocate.err" || {
  cat "$tmp/allocate.err" >&2; exit 1;
 }
fi
rev_done="$(psql -X -At -c "SELECT count(*) FROM core10.finance_reversals_v1 WHERE original_journal_id=$rev_doc")"
alloc_done="$(psql -X -At -c "SELECT count(*) FROM core10.finance_arap_allocations_v1 WHERE link_id=$rev_link")"
if [[ "$rev_done:$alloc_done" != "1:0" && "$rev_done:$alloc_done" != "0:1" ]]; then
 echo "ARAP_REVERSAL_ALLOCATION_RACE_BAD_STATE reverse=$rev_done allocation=$alloc_done" >&2; exit 1
fi
audit_rev="$(psql -X -At -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9631 AND action='finance.journal_reverse'")"
if [[ "$audit_rev" != "$rev_done" ]]; then
 echo "ARAP_REVERSAL_ALLOCATION_AUDIT_INCONSISTENT" >&2; exit 1
fi
echo "ARAP_REVERSAL_ALLOCATION_RACE_PASS reverse=$rev_done allocation=$alloc_done"
# A locked journal belonging to another tenant must not hold up our caller.
# Real independent PG17 sessions: one holds FOR UPDATE, two attempt F3 RPCs.
foreign_journal="$(psql -X -At -c "SELECT id FROM core10.finance_journals_v1 WHERE business_id=9641 AND source_ref='arap-race-foreign-lock'")"
[[ "$foreign_journal" =~ ^[0-9]+$ ]] || { echo 'ARAP_FOREIGN_JOURNAL_MISSING'; exit 1; }
(
 PGAPPNAME=core10_arap_foreign_lock psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/foreign-locker.out" 2>"$tmp/foreign-locker.err" <<SQL
BEGIN;
SELECT id FROM core10.finance_journals_v1 WHERE id=$foreign_journal FOR UPDATE;
SELECT pg_sleep(5);
ROLLBACK;
SQL
) & foreign_locker=$!
lock_ready=0
for _ in $(seq 1 80); do
 if [[ "$(psql -X -At -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='core10_arap_foreign_lock' AND state='active' AND query LIKE 'SELECT pg_sleep(5)%'")" == 1 ]]; then
   lock_ready=1; break
 fi
 sleep 0.05
done
if [[ "$lock_ready" != 1 ]]; then
 echo ARAP_FOREIGN_LOCK_NOT_ACQUIRED >&2
 cat "$tmp/foreign-locker.err" >&2
 wait "$foreign_locker" || true
 exit 1
fi
if psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/foreign-link.out" 2>"$tmp/foreign-link.err" <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SET statement_timeout='1500ms';
SELECT core10.finance_link_open_item_v1($foreign_journal,1,1,'ar',
 '2026-11-30','arapForeignLockLink1');
SQL
then
 echo ARAP_FOREIGN_LINK_UNEXPECTEDLY_ALLOWED >&2; exit 1
fi
grep -q 'FIN_ARAP_AUTH_DENIED' "$tmp/foreign-link.err" || {
 echo ARAP_FOREIGN_LINK_WAITED_FOR_ROW_LOCK >&2
 cat "$tmp/foreign-link.err" >&2; exit 1
}
if psql -X -qAt -v ON_ERROR_STOP=1 >"$tmp/foreign-alloc.out" 2>"$tmp/foreign-alloc.err" <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SET statement_timeout='1500ms';
SELECT core10.finance_allocate_payment_v1($link,$foreign_journal,1,
 'arapForeignLockAlloc1');
SQL
then
 echo ARAP_FOREIGN_PAYMENT_UNEXPECTEDLY_ALLOWED >&2; exit 1
fi
grep -q 'FIN_ARAP_PAYMENT_SCOPE_OR_STATUS' "$tmp/foreign-alloc.err" || {
 echo ARAP_FOREIGN_PAYMENT_WAITED_FOR_ROW_LOCK >&2
 cat "$tmp/foreign-alloc.err" >&2; exit 1
}
wait "$foreign_locker" || { cat "$tmp/foreign-locker.err" >&2; exit 1; }
echo NP06_ARAP_FOREIGN_LOCK_GUARD_PASS
