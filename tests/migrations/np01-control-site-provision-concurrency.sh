#!/usr/bin/env bash
# NP01/0112 two independent PostgreSQL 17 sessions compete for one site slot.
set -euo pipefail
cd "$(dirname "$0")/../.."
case "$PGHOST" in localhost|127.0.0.1) ;; *) echo 'local PG required' >&2; exit 2;; esac
DB="core10_0112_race_$$"
psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
TMP=$(mktemp -d)
cleanup(){ psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT
export PGDATABASE="$DB"
internal/migrations/run.sh up >/dev/null
psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF; END $$;
INSERT INTO core10.tenants(id,slug) VALUES(99781,'np01-site-race');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES(99782,99781,'NP01 Race');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(99783,99781,99782,'np01-site-race','sweets_bakery','np01_0112_race_biz');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(99781,'99781111-1111-4111-8111-111111111111','tenant_owner');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','99781111-1111-4111-8111-111111111111',false);
SELECT core10.control_set_v1(99783,NULL,'setup001.provision',true,0::smallint,
 '{"max_sites":1}',NULL,false,0,'Only one site is authorized','np01_0112_race_cfg');
SQL
run_site(){
 psql -X -q -At -v ON_ERROR_STOP=0 -d "$DB" >"$TMP/$1" 2>&1 <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','99781111-1111-4111-8111-111111111111',false);
BEGIN;
SELECT 'RESULT '||(core10.build01_site_v1(99783,'showroom','Site $1','np01_0112_race_$1')->>'site_id');
SELECT pg_sleep(0.2);
COMMIT;
SQL
}
run_site 1 & run_site 2 & wait
ok=$(grep -hc '^RESULT [0-9]' "$TMP"/1 "$TMP"/2 | awk '{s+=$1} END{print s+0}')
denied=$(grep -hc 'CONTROL_LIMIT:max_sites' "$TMP"/1 "$TMP"/2 | awk '{s+=$1} END{print s+0}')
count=$(psql -X -At -d "$DB" -c 'SELECT count(*) FROM core10.sites WHERE business_id=99783')
[ "$ok" = 1 ] && [ "$denied" = 1 ] && [ "$count" = 1 ] || {
 echo "SITE_RACE_FAIL ok=$ok denied=$denied count=$count"; cat "$TMP"/1 "$TMP"/2; exit 1;
}
echo 'PASS NP01 0112: one of two concurrent site writers succeeds'

# Establish that the setup statement starts before the Owner's OFF write and
# remains blocked on the same Control lock until that write commits.
psql -X -q -v ON_ERROR_STOP=1 >"$TMP/policy-writer" 2>&1 <<SQL &
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','99781111-1111-4111-8111-111111111111',false);
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('c10ctl:99783:0:setup001.provision',0));
\\! touch "$TMP/policy-lock-held"
\\! timeout 15 sh -c 'until test -f "$TMP/site-request-blocked"; do sleep .05; done'
SELECT core10.control_set_v1(99783,NULL,'setup001.provision',false,0::smallint,
 '{"max_sites":2}',NULL,false,1,'Disable site creation while waiting','np01_site_waited_off');
COMMIT;
SQL
writer=$!
for _ in $(seq 1 100); do
 [[ -e "$TMP/policy-lock-held" ]] && break
 sleep .05
done
test -e "$TMP/policy-lock-held" || { cat "$TMP/policy-writer" >&2; exit 1; }

PGAPPNAME=core10-waited-site psql -X -q -v ON_ERROR_STOP=1 >"$TMP/waited-site" 2>&1 <<'SQL' &
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','99781111-1111-4111-8111-111111111111',false);
SET statement_timeout='20s';
SELECT core10.build01_site_v1(99783,'showroom','Waited site','np01-waited-site');
SQL
waiter=$!
blocked=0
for _ in $(seq 1 100); do
 blocked=$(psql -X -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM pg_stat_activity
   WHERE datname=current_database() AND application_name='core10-waited-site'
     AND wait_event_type='Lock' AND wait_event='advisory'")
 [[ "$blocked" == 1 ]] && break
 sleep .05
done
touch "$TMP/site-request-blocked"
wait "$writer" || { cat "$TMP/policy-writer" >&2; exit 1; }
test "$blocked" = 1
if wait "$waiter"; then
 echo 'Waiting site request ignored the committed OFF policy' >&2
 exit 1
fi
grep -q 'CONTROL_DISABLED:setup001.provision' "$TMP/waited-site"
test "$(psql -X -At -v ON_ERROR_STOP=1 -c 'SELECT count(*) FROM core10.sites WHERE business_id=99783')" = 1
echo 'PASS NP01 0118: a waiting site request sees the newly committed OFF policy'
