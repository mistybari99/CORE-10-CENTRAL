#!/usr/bin/env bash
# NP06 / 0401: independently executable against a migrated disposable PostgreSQL 17 DB.
# Self-seeds a posted source when the posting-race fixture has not run; combined CI
# still runs its original posting-race then reversal-race order without duplicate seed.
# Also proves a foreign tenant cannot wait on a locked journal via SECURITY DEFINER.
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
source_journal="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT id FROM core10.finance_journals_v1 WHERE business_id=9711 AND source_ref='np06-race-journal' AND status='posted'")"
if [[ -z "$source_journal" ]]; then
  # No dependency on np06-finance-race.sh: seed + post in this script itself.
  # Refuse partially prepared/colliding fixtures rather than masking defects.
  conflict="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM core10.businesses WHERE id=9711")"
  [[ "$conflict" == "0" ]] || { echo "REVERSAL_RACE_INCOMPLETE_SOURCE_FIXTURE" >&2; exit 1; }
  psql -X -q -v ON_ERROR_STOP=1 -c "INSERT INTO core10.templates(code,source_status,demo_allowed)
     VALUES('sweets_bakery','available',true) ON CONFLICT(code) DO NOTHING" >"$tmp/template"
  psql -X -q -v ON_ERROR_STOP=1 -f tests/migrations/np06-finance-race-seed.sql >"$tmp/self-seed"
  source_journal="$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT id FROM core10.finance_journals_v1 WHERE business_id=9711 AND source_ref='np06-race-journal'")"
  [[ "$source_journal" =~ ^[0-9]+$ ]] || { echo "REVERSAL_RACE_SELF_SEED_JOURNAL_MISSING" >&2; exit 1; }
  psql -X -q -v ON_ERROR_STOP=1 >"$tmp/self-post" <<'SQL'
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SELECT core10.finance_post_journal_v1(
  (SELECT id FROM core10.finance_journals_v1
   WHERE business_id=9711 AND source_ref='np06-race-journal'), 'racepost0001');
SQL
  echo "REVERSAL_RACE_SELF_SEEDED_POSTED_SOURCE"
fi
[[ "$source_journal" =~ ^[0-9]+$ ]] || { echo "REVERSAL_RACE_POSTED_SOURCE_MISSING" >&2; exit 1; }

psql -X -q -v ON_ERROR_STOP=1 >"$tmp/setup" <<'SQL'
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SELECT core10.finance_set_period_v1(9711,'BDT','2026-12-01',true,'racerevperiod01');
SELECT core10.control_set_v1(9711,NULL,'finance.journal_reverse',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner enables synthetic reversal race','racerevcontrol1');
SQL

# Separate valid tenant owner, not a member of the source tenant. Even when
# source journal is row-locked by another session, this caller must fail with
# FIN_AUTH_DENIED *before* lock_timeout (authorization-before-lock regression).
psql -X -q -v ON_ERROR_STOP=1 >"$tmp/foreign-tenant" <<'SQL'
INSERT INTO core10.tenants(id,slug) VALUES(973,'np06-reversal-foreign');
INSERT INTO core10.legal_entities(id,tenant_id,label)
 VALUES(9730,973,'Reversal Foreign Legal');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(9731,973,9730,'np06-reversal-foreign-business','sweets_bakery','np06-rev-foreign-01');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(973,'95555555-5555-4555-8555-555555555555','tenant_owner');
SQL

# Create a lock held by a REAL independent PostgreSQL connection. The psql
# metacommand touches the file only after SELECT ... FOR UPDATE has succeeded.
psql -X -q -v ON_ERROR_STOP=1 >"$tmp/holder.out" 2>"$tmp/holder.err" <<SQL &
BEGIN;
SELECT id FROM core10.finance_journals_v1 WHERE id=$source_journal FOR UPDATE;
\\! touch "$tmp/lock-held"
SELECT pg_sleep(5);
ROLLBACK;
SQL
holder=$!
for attempt in $(seq 1 120); do
  [[ -f "$tmp/lock-held" ]] && break
  kill -0 "$holder" 2>/dev/null || break
  sleep 0.05
done
[[ -f "$tmp/lock-held" ]] || { cat "$tmp/holder.err" >&2; echo "REVERSAL_LOCK_HOLDER_NOT_READY" >&2; exit 1; }
if psql -X -q -v ON_ERROR_STOP=1 >"$tmp/foreign-call.out" 2>"$tmp/foreign-call.err" <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"95555555-5555-4555-8555-555555555555"}',false);
SET lock_timeout='350ms';
SET statement_timeout='1500ms';
SELECT core10.finance_reverse_posted_journal_v1(
  $source_journal,'2026-12-01','correction','racereverseforeign01');
SQL
then
  echo "REVERSAL_FOREIGN_AUTH_UNEXPECTEDLY_ALLOWED" >&2
  exit 1
fi
grep -q 'FIN_AUTH_DENIED' "$tmp/foreign-call.err" || {
  cat "$tmp/foreign-call.err" >&2
  echo "REVERSAL_FOREIGN_LOCKED_BEFORE_AUTH" >&2
  exit 1
}
wait "$holder" || { cat "$tmp/holder.err" >&2; exit 1; }
echo "REVERSAL_FOREIGN_LOCK_BYPASS_DENIED_BEFORE_LOCK_PASS"

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
