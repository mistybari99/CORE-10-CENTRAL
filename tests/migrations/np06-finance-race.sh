#!/usr/bin/env bash
# NP06: two independent database sessions compete to post one journal.
# Disposable PostgreSQL 17 job only; SQL fixture uses synthetic identities.
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
psql -X -q -v ON_ERROR_STOP=1 -f tests/migrations/np06-finance-race-seed.sql >"$tmp/seed"
journal="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT id FROM core10.finance_journals_v1 WHERE business_id=9711 AND source_ref='np06-race-journal'")"
[[ "$journal" =~ ^[0-9]+$ ]] || { echo "RACE_SEED_MISSING" >&2; exit 1; }

post() {
  local prefix="$1"
  psql -X -qAt -v ON_ERROR_STOP=1 >"$prefix.out" 2>"$prefix.err" <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SELECT core10.finance_post_journal_v1($journal,'racepost0001');
SQL
}
post "$tmp/one" & one=$!
post "$tmp/two" & two=$!
wait "$one" || { cat "$tmp/one.err" >&2; exit 1; }
wait "$two" || { cat "$tmp/two.err" >&2; exit 1; }
grep -Fxq "$journal" "$tmp/one.out" || { echo "RACE_FIRST_POST_FAILED" >&2; exit 1; }
grep -Fxq "$journal" "$tmp/two.out" || { echo "RACE_SECOND_REPLAY_FAILED" >&2; exit 1; }
audit_count="$(psql -X -At -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9711 AND action='finance.journal_post'")"
test "$audit_count" = "1" || { echo "RACE_DUPLICATE_AUDIT $audit_count" >&2; exit 1; }
posted_count="$(psql -X -At -c "SELECT count(*) FROM core10.finance_journals_v1 WHERE id=$journal AND status='posted'")"
test "$posted_count" = "1" || { echo "RACE_POST_STATE_FAILED" >&2; exit 1; }
echo "NP06_CONCURRENT_POST_ONCE_PASS journal=$journal"
