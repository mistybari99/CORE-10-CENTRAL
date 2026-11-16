#!/usr/bin/env bash
# NP06 / 0401: two independent PostgreSQL sessions reverse the same posted journal.
# Run AFTER np06-finance-race.sh in the disposable PG17 CI service only.
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
source_journal="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT id FROM core10.finance_journals_v1 WHERE business_id=9711 AND source_ref='np06-race-journal' AND status='posted'")"
[[ "$source_journal" =~ ^[0-9]+$ ]] || { echo "REVERSAL_RACE_POSTED_SOURCE_MISSING" >&2; exit 1; }

psql -X -q -v ON_ERROR_STOP=1 >"$tmp/setup" <<'SQL'
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SELECT core10.finance_set_period_v1(9711,'BDT','2026-12-01',true,'racerevperiod01');
SELECT core10.control_set_v1(9711,NULL,'finance.journal_reverse',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner enables synthetic reversal race','racerevcontrol1');
SQL

reverse_one() {
  local prefix="$1"
  psql -X -qAt -v ON_ERROR_STOP=1 >"$prefix.out" 2>"$prefix.err" <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SELECT core10.finance_reverse_posted_journal_v1($source_journal,'2026-12-01','correction','racereverse0001');
SQL
}
reverse_one "$tmp/one" & one=$!
reverse_one "$tmp/two" & two=$!
wait "$one" || { cat "$tmp/one.err" >&2; exit 1; }
wait "$two" || { cat "$tmp/two.err" >&2; exit 1; }
reversed="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT reversal_journal_id FROM core10.finance_reversals_v1 WHERE original_journal_id=$source_journal")"
[[ "$reversed" =~ ^[0-9]+$ ]] || { echo "REVERSAL_RACE_LINK_MISSING" >&2; exit 1; }
grep -Fxq "$reversed" "$tmp/one.out" || { echo "REVERSAL_RACE_FIRST_REPLAY_FAILED" >&2; exit 1; }
grep -Fxq "$reversed" "$tmp/two.out" || { echo "REVERSAL_RACE_SECOND_REPLAY_FAILED" >&2; exit 1; }
count="$(psql -X -At -c "SELECT count(*) FROM core10.finance_reversals_v1 WHERE original_journal_id=$source_journal")"
test "$count" = 1 || { echo "REVERSAL_RACE_LINK_DUPLICATED $count" >&2; exit 1; }
count="$(psql -X -At -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9711 AND action='finance.journal_reverse'")"
test "$count" = 1 || { echo "REVERSAL_RACE_AUDIT_DUPLICATED $count" >&2; exit 1; }
count="$(psql -X -At -c "SELECT count(*) FROM core10.finance_journals_v1 WHERE id=$reversed AND status='posted' AND source_domain='finance_reversal'")"
test "$count" = 1 || { echo "REVERSAL_RACE_POST_DUPLICATED $count" >&2; exit 1; }
echo "NP06_CONCURRENT_REVERSAL_ONCE_PASS original=$source_journal reversal=$reversed"
