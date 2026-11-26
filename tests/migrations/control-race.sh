#!/usr/bin/env bash
# NP02 / B-010: real concurrent sessions against the Control port (disposable database only).
# 8 writers with the same expected version: exactly one wins, seven see CONTROL_STALE_VERSION.
# 8 writers with the same request key and payload: all succeed with one stored version.
# 6 consumers of one one-time exception: exactly one is allowed.
set -euo pipefail
cd "$(dirname "$0")/../.."
case "${PGHOST:-}" in localhost|127.0.0.1) ;; *) echo "disposable local host required" >&2; exit 2;; esac
DB="core10_race_$$"; export OLDDB="${PGDATABASE:-postgres}"
psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
cleanup(){ psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1 || true; rm -rf "${TMP:-/nonexistent}"; }
trap cleanup EXIT
export PGDATABASE=$DB
internal/migrations/run.sh up >/dev/null
psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF; END $$;
INSERT INTO core10.tenants(id,slug) VALUES (951,'race-a');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9501,951,'Race A');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES (9551,951,9501,'race-a','sweets_bakery','seed-race-a');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES (951,'a1111111-1111-4111-8111-111111111111','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES (951,9551,'a2222222-2222-4222-8222-222222222222','manager');
SQL
TMP=$(mktemp -d)
sess(){ # $1 user, $2 sql, $3 out file
 psql -X -q -At -v ON_ERROR_STOP=0 -d "$DB" >"$3" 2>&1 <<SQL
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"$1"}',false), set_config('request.jwt.claim.sub','$1',false);
$2
SQL
}
OWN=a1111111-1111-4111-8111-111111111111
# 1. same expected version, different keys
for i in 1 2 3 4 5 6 7 8; do
 sess $OWN "SELECT 'RESULT '||(core10.control_set_v1(9551,NULL,'gov002.review',false,1::smallint,'{}'::jsonb,NULL,false,0,'race writer $i wants change','race_key_diff_$i')->>'version');" "$TMP/a$i" &
done; wait
ok=$(cat "$TMP"/a* | grep -c '^RESULT 1$' || true); stale=$(cat "$TMP"/a* | grep -c 'CONTROL_STALE_VERSION:1' || true)
[ "$ok" = 1 ] && [ "$stale" = 7 ] || { echo "RACE1 FAIL ok=$ok stale=$stale"; cat "$TMP"/a*; exit 1; }
[ "$(psql -X -At -d "$DB" -c "select count(*) from core10.control_setting_versions_v1 where business_id=9551")" = 1 ] || { echo "RACE1 rows"; exit 1; }
# 2. same key and payload
for i in 1 2 3 4 5 6 7 8; do
 sess $OWN "SELECT 'RESULT '||(core10.control_set_v1(9551,NULL,'gov003.review_export',true,0::smallint,'{\"max_rows\":300}'::jsonb,NULL,false,0,'same request sent eight times','race_key_same_01')->>'version');" "$TMP/b$i" &
done; wait
[ "$(cat "$TMP"/b* | grep -c '^RESULT 1$')" = 8 ] || { echo "RACE2 FAIL"; cat "$TMP"/b*; exit 1; }
[ "$(psql -X -At -d "$DB" -c "select count(*) from core10.control_setting_versions_v1 where feature_key='gov003.review_export'")" = 1 ] || { echo "RACE2 rows"; exit 1; }
# 3. one-time exception consumed by six concurrent callers (feature is switched off by race 1)
sess $OWN "SELECT core10.control_grant_override_v1(9551,NULL,'gov002.review',4,'one exception for six callers','race_ovr_0001');" "$TMP/g"
psql -X -q -d "$DB" -c "CREATE FUNCTION core10._t_race_action() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS \$f\$ BEGIN RETURN core10.control_check_v1(9551,'gov002.review',NULL); END \$f\$; GRANT EXECUTE ON FUNCTION core10._t_race_action() TO authenticated;"
for i in 1 2 3 4 5 6; do
 sess a2222222-2222-4222-8222-222222222222 "SELECT 'RESULT '||(core10._t_race_action()->>'override_used');" "$TMP/c$i" &
done; wait
used=$(cat "$TMP"/c* | grep -c '^RESULT true$' || true); denied=$(cat "$TMP"/c* | grep -c 'CONTROL_DISABLED:gov002.review' || true)
[ "$used" = 1 ] && [ "$denied" = 5 ] || { echo "RACE3 FAIL used=$used denied=$denied"; cat "$TMP"/c*; exit 1; }
[ "$(psql -X -At -d "$DB" -c "select count(*) from core10.canonical_audit_events_v1 where action='control.override_consumed'")" = 1 ] || { echo "RACE3 audit"; exit 1; }
v=$(psql -X -At -d "$DB" -c "select set_config('request.jwt.claims','{\"sub\":\"$OWN\"}',false)" -c "select (core10.verify_canonical_audit_v1(9551)->>'ok')" | tail -1)
[ "$v" = "t" ] || [ "$v" = "true" ] || { echo "audit chain broken after races: $v"; exit 1; }
echo "PASS CONTROL RACES: 1 winner of 8 writers, 8 replays one version, 1 consumer of 6 exceptions, audit chain ok"
