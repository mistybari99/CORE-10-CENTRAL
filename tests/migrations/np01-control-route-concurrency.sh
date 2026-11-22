#!/usr/bin/env bash
# NP01 B-020 0111: disposable PG17 independent two-session replay races.
set -euo pipefail
cd "$(dirname "$0")/../.."
case "${PGHOST:-}" in localhost|127.0.0.1) ;; *) echo DISPOSABLE_PGHOST_REQUIRED >&2; exit 2;; esac
db="np01_race_0111_$$"; tmp="$(mktemp -d)"
cleanup(){ psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $db WITH (FORCE)" >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT
psql -X -q -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE $db"
PGDATABASE="$db" internal/migrations/run.sh up >/dev/null
psql -X -q -v ON_ERROR_STOP=1 -d "$db" <<'SQL'
INSERT INTO core10.tenants(id,slug) VALUES (99601,'route-race-0111');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (99611,99601,'Route Race');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (99621,99601,99611,'route-race','sweets_bakery','np01_route_race_business');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES (99601,'99611111-1111-4111-8111-111111111111','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,approval_actions)
 VALUES (99601,99621,'99622222-2222-4222-8222-222222222222','manager',ARRAY['approval.submit']);
SQL
owner=99611111-1111-4111-8111-111111111111
maker=99622222-2222-4222-8222-222222222222
session(){
 local who="$1" stmt="$2" outfile="$3"
 psql -X -qAt -v ON_ERROR_STOP=1 -d "$db" >"$outfile" 2>&1 <<SQL
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"$who"}',true);
SELECT set_config('request.jwt.claim.sub','$who',true);
$stmt;
COMMIT;
SQL
}
number(){ grep -E '^[0-9]+$' "$1" | tail -1; }
race(){
 local label="$1" who="$2" stmt="$3" a b x y
 session "$who" "$stmt" "$tmp/$label-a" & a=$!
 session "$who" "$stmt" "$tmp/$label-b" & b=$!
 wait "$a"; wait "$b"
 x="$(number "$tmp/$label-a")"; y="$(number "$tmp/$label-b")"
 if [[ -z "$x" || "$x" != "$y" ]]; then echo "RACE_FAIL:$label $x $y" >&2; cat "$tmp/$label-"* >&2; exit 1; fi
 echo "$x"
}
session "$owner" "SELECT core10.control_set_v1(99621,NULL,'gov002.review',true,3::smallint,'{}'::jsonb,NULL,false,0,'Require three stage reviewers','np01_race_ctl_one_0111')" "$tmp/ctl3"
session "$owner" "SELECT core10.publish_approval_policy_v1(99621,'inventory','adjust',120,'np01_race_policy_0111_3')" "$tmp/pol3"
p3="$(number "$tmp/pol3")"; test -n "$p3"
route="$(race route "$owner" "SELECT core10.configure_approval_route_v1($p3,ARRAY['business_owner','manager','tenant_owner']::text[],'np01_race_route_0111_3')")"
[[ "$route" = "$p3" ]] || exit 1
q3="$(race submit3 "$maker" "SELECT core10.submit_typed_approval_v1(99621,'inventory','adjust','src3',1,'{\"quantity\":3}'::jsonb,'np01_race_submit_0111_3')")"
session "$owner" "SELECT core10.control_set_v1(99621,NULL,'gov002.review',true,0::smallint,'{}'::jsonb,NULL,false,1,'Permit zero stage approval only','np01_race_ctl_two_0111')" "$tmp/ctl0"
session "$owner" "SELECT core10.publish_approval_policy_v1(99621,'inventory','zero',120,'np01_race_policy_0111_0')" "$tmp/pol0"
p0="$(number "$tmp/pol0")"; test -n "$p0"
session "$owner" "SELECT core10.configure_approval_route_v1($p0,ARRAY[]::text[],'np01_race_route_0111_0')" "$tmp/route0"
q0="$(race submit0 "$maker" "SELECT core10.submit_typed_approval_v1(99621,'inventory','zero','src0',1,'{\"quantity\":0}'::jsonb,'np01_race_submit_0111_0')")"
checks="$(psql -X -qAt -d "$db" -v ON_ERROR_STOP=1 -c "SELECT
 (SELECT count(*) FROM core10.approval_routes_v1 WHERE policy_id=$p3)=1
 AND (SELECT count(*) FROM core10.approval_requests WHERE id=$q3 AND status='pending' AND route_stages_pinned_v1=3 AND route_control_version_v1=1)=1
 AND (SELECT count(*) FROM core10.approval_requests WHERE id=$q0 AND status='approved' AND route_stages_pinned_v1=0 AND route_control_version_v1=2)=1
 AND (SELECT count(*) FROM core10.approval_events WHERE request_id=$q0 AND action='approve')=1
 AND (SELECT count(*) FROM core10.approval_requests WHERE business_id=99621 AND submit_key_v1='np01_race_submit_0111_3')=1
 AND (SELECT count(*) FROM core10.approval_requests WHERE business_id=99621 AND submit_key_v1='np01_race_submit_0111_0')=1;")"
[[ "$checks" = "t" ]] || { echo "RACE_PERSISTED_STATE_INVALID:$checks" >&2; exit 1; }
session "$owner" "SELECT (core10.verify_canonical_audit_v1(99621)->>'ok')::boolean" "$tmp/audit"
grep -qx t "$tmp/audit" || { echo RACE_CANONICAL_AUDIT_INVALID >&2; exit 1; }
echo NP01_0111_ROUTE_STAGE0_STAGE3_TWO_SESSION_REPLAY_OK
