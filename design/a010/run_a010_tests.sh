#!/usr/bin/env bash
# Usage: sudo bash run_a010_tests.sh [negctl]  -- throwaway PG16 cluster; never touches Supabase.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"; NEG=0; [ "${1:-}" = negctl ] && NEG=1
BIN=/usr/lib/postgresql/16/bin; T=$(mktemp -d); chown postgres "$T"; chmod 755 "$D"; PORT=$((54000 + RANDOM % 900))
sudo -u postgres $BIN/initdb -D "$T/d" -A trust >/dev/null
sudo -u postgres $BIN/pg_ctl -D "$T/d" -o "-p $PORT -k $T -c listen_addresses=''" -w -l "$T/log" start >/dev/null
trap 'sudo -u postgres $BIN/pg_ctl -D "$T/d" -m immediate stop >/dev/null; rm -rf "$T"' EXIT
P(){ sudo -u postgres env PGHOST="$T" PGPORT=$PORT $BIN/psql -X -q -v ON_ERROR_STOP=1 -d postgres "$@"; }
SNAP="select md5(string_agg(x,'|' order by x)) from (
 select table_name||'.'||column_name||':'||data_type||':'||is_nullable x from information_schema.columns where table_schema='public'
 union all select 'con:'||conrelid::regclass||':'||pg_get_constraintdef(oid) from pg_constraint where connamespace='public'::regnamespace
 union all select 'grant:'||table_name||':'||grantee||':'||privilege_type from information_schema.role_table_grants where table_schema='public'
 union all select 'pol:'||tablename||':'||policyname from pg_policies where schemaname='public'
 union all select 'rls:'||relname||relrowsecurity from pg_class where relnamespace='public'::regnamespace and relkind='r'
 union all select 'fn:'||proname from pg_proc where pronamespace='public'::regnamespace) s"
P -f "$D/a010_fixture.sql"
BEFORE=$(P -At -c "$SNAP"); echo "shape before : $BEFORE"
P -f "$D/a010_additive_candidate.sql"; P -f "$D/a010_additive_candidate.sql"   # twice = idempotent
EXISTING_GRANTS_OK=$(P -At -c "select count(*) from information_schema.role_table_grants where table_name in ('locations','sales') and grantee='authenticated'")
echo "authenticated grants on existing tables still present: $EXISTING_GRANTS_OK"
P -f "$D/a010_test.sql" -v negctl=$NEG
if [ $NEG = 0 ]; then
  P -f "$D/a010_rollback.sql"; P -f "$D/a010_rollback.sql"
  # test added org_units 5,6 and locations 10,12,13; remove them to compare shape/data fairly
  P -c "delete from locations where id in (10,12,13); delete from org_units where id in (5,6)"
  AFTER=$(P -At -c "$SNAP"); echo "shape after  : $AFTER"
  [ "$BEFORE" = "$AFTER" ] && echo "ROLLBACK RESTORES ORIGINAL SHAPE: PASS" || { echo "ROLLBACK SHAPE MISMATCH"; exit 1; }
  [ "$(P -At -c 'select array_agg(id order by id) from locations')" = "{1,2,3,4,5,6,7,9}" ] && echo "LEGACY IDS AFTER ROLLBACK: PASS" || { echo "ids changed"; exit 1; }
fi
