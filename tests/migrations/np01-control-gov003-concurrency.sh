#!/usr/bin/env bash
# NP01 / 0113: real PG17 sessions race a single Owner exception for default-OFF GOV003.
# Test database is local/disposable, never hosted or staging.
set -euo pipefail
cd "$(dirname "$0")/../.."
case "$PGHOST" in localhost|127.0.0.1) ;; *) echo 'local disposable PG required' >&2; exit 2;; esac
DB="core10_0113_gov003_$$"
psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
TMP=$(mktemp -d)
cleanup(){ psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT
export PGDATABASE="$DB"
internal/migrations/run.sh up >/dev/null
psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF; END $$;
INSERT INTO core10.tenants(id,slug) VALUES(99881,'np01-0113-race');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES(99882,99881,'NP01 GOV003 Race');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(99883,99881,99882,'np01-gov003-race','sweets_bakery','np01_0113_race_biz');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(99881,'99881111-1111-4111-8111-111111111111','tenant_owner');
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"99881111-1111-4111-8111-111111111111"}',false);
SELECT set_config('request.jwt.claim.sub','99881111-1111-4111-8111-111111111111',false);
SELECT core10.control_grant_override_v1(99883,NULL,'gov003.review_export',1,
 'Permit one metadata export only','np01_0113_race_override_01');
SQL
session(){
 psql -X -q -At -v ON_ERROR_STOP=0 -d "$DB" >"$TMP/$1" 2>&1 <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"99881111-1111-4111-8111-111111111111"}',false);
SELECT set_config('request.jwt.claim.sub','99881111-1111-4111-8111-111111111111',false);
BEGIN;
SELECT 'RESULT '||count(*) FROM core10.gov003_audit_export_v1(99883,0,2);
SELECT pg_sleep(0.25);
COMMIT;
SQL
}
session 1 & session 2 & wait
ok=$(grep -h -c '^RESULT [0-9]' "$TMP"/1 "$TMP"/2 | awk '{s+=$1} END{print s+0}')
denied=$(grep -h -c 'CONTROL_DISABLED:gov003.review_export' "$TMP"/1 "$TMP"/2 | awk '{s+=$1} END{print s+0}')
consumed=$(psql -X -At -d "$DB" -c "SELECT count(*) FROM core10.control_overrides_v1 WHERE business_id=99883 AND consumed_at IS NOT NULL")
audited=$(psql -X -At -d "$DB" -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=99883 AND action='control.override_consumed'")
[ "$ok" = 1 ] && [ "$denied" = 1 ] && [ "$consumed" = 1 ] && [ "$audited" = 1 ] || {
 echo "GOV003_OVERRIDE_RACE_FAIL allowed=$ok denied=$denied consumed=$consumed audited=$audited"
 cat "$TMP"/1 "$TMP"/2; exit 1;
}
echo "PASS NP01 0113: 2 real sessions, 1 authorized export, 1 Control denial, 1 canonical audit"
