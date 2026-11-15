#!/usr/bin/env bash
# D051/PACK01: local disposable full data/schema rollback and restore only.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "$CORE10_BUILD01_DISPOSABLE_ACK" == I_CONFIRM_BUILD01_DISPOSABLE &&
   "$CORE10_PREVIEW_DISPOSABLE_ACK" == I_CONFIRM_DISPOSABLE_PREVIEW ]] || exit 2
case "$PGHOST" in localhost|127.0.0.1) ;; *) echo LOOPBACK_ONLY >&2; exit 2;; esac
[[ "$PGDATABASE" == postgres ]] || { echo "NEVER_TARGET_AN_EXISTING_DATABASE" >&2; exit 2; }
source_db="core10_build01_sql_$BASHPID"
restore_db="core10_pack01_restore_$BASHPID"
scratch=$(mktemp -d /tmp/pack01-restore.XXXXXX)
source_owned=0 restore_owned=0
admin(){ PGDATABASE=postgres psql -X -q -v ON_ERROR_STOP=1 -c "$1"; }
cleanup(){
 if ((restore_owned)); then admin "DROP DATABASE IF EXISTS \"$restore_db\" WITH (FORCE)" || true; fi
 if ((source_owned)); then admin "DROP DATABASE IF EXISTS \"$source_db\" WITH (FORCE)" || true; fi
 rm -rf "$scratch"
}
trap cleanup EXIT
admin "CREATE DATABASE \"$source_db\""
source_owned=1
PGDATABASE="$source_db" bash tests/build01/run-load.sh
PGDATABASE="$source_db" psql -X -q -v ON_ERROR_STOP=1 -f internal/enterprise-sql/c10_build02a_approval_permissions_v1.sql
PGDATABASE="$source_db" psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
DO $do$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM c10_demo.business_members WHERE business_id=101
   AND user_id='22222222-2222-4222-8222-222222222222' AND active) THEN
  RAISE EXCEPTION 'PACK01_FIXTURE_NOT_ACTIVE'; END IF;
 BEGIN
  UPDATE c10_demo.business_members SET active=false
   WHERE business_id=101 AND user_id='22222222-2222-4222-8222-222222222222';
  RAISE EXCEPTION 'PACK01_FORCED_FAILURE';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'PACK01_FORCED_FAILURE' THEN RAISE; END IF;
 END;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.business_members WHERE business_id=101
  AND user_id='22222222-2222-4222-8222-222222222222' AND active) THEN
  RAISE EXCEPTION 'PACK01_EXCEPTION_DID_NOT_ROLL_BACK'; END IF;
END $do$;
BEGIN;
UPDATE c10_demo.business_members SET active=false WHERE business_id=101
 AND user_id='22222222-2222-4222-8222-222222222222';
DO $do$ BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.business_members WHERE business_id=101
  AND user_id='22222222-2222-4222-8222-222222222222' AND active)
 THEN RAISE EXCEPTION 'PACK01_TXN_MUTATION_NOT_OBSERVED'; END IF;
END $do$;
ROLLBACK;
DO $do$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM c10_demo.business_members WHERE business_id=101
  AND user_id='22222222-2222-4222-8222-222222222222' AND active)
 THEN RAISE EXCEPTION 'PACK01_TXN_ROLLBACK_FAILURE'; END IF;
END $do$;
SQL
manifest(){
 PGDATABASE="$1" psql -X -qAt -v ON_ERROR_STOP=1 <<'SQL'
SELECT entity||'|'||records||'|'||signature FROM (
 SELECT 'tenants' entity,count(*) records,md5(coalesce(string_agg(to_jsonb(t)::text,'|' ORDER BY to_jsonb(t)::text),'')) signature FROM c10_demo.tenants t
 UNION ALL SELECT 'businesses',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' ORDER BY to_jsonb(t)::text),'')) FROM c10_demo.businesses t
 UNION ALL SELECT 'tenant_members',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' ORDER BY to_jsonb(t)::text),'')) FROM c10_demo.tenant_members t
 UNION ALL SELECT 'business_members',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' ORDER BY to_jsonb(t)::text),'')) FROM c10_demo.business_members t
 UNION ALL SELECT 'site_grants',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' ORDER BY to_jsonb(t)::text),'')) FROM c10_demo.site_grants t
 UNION ALL SELECT 'sites',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' ORDER BY to_jsonb(t)::text),'')) FROM c10_demo.sites t
 UNION ALL SELECT 'stock_locations',count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'|' ORDER BY to_jsonb(t)::text),'')) FROM c10_demo.stock_locations t
) scoped ORDER BY entity;
SQL
}
manifest "$source_db" > "$scratch/before"
test -s "$scratch/before"
PGDATABASE="$source_db" pg_dump -Fc --no-owner -f "$scratch/full.backup"
test -s "$scratch/full.backup"
admin "CREATE DATABASE \"$restore_db\""
restore_owned=1
pg_restore --dbname="$restore_db" --no-owner --exit-on-error "$scratch/full.backup"
manifest "$restore_db" > "$scratch/after"
diff -u "$scratch/before" "$scratch/after"
PGDATABASE="$source_db" psql -X -q -v ON_ERROR_STOP=1 -c \
 "UPDATE c10_demo.business_members SET active=false WHERE business_id=101 AND user_id='22222222-2222-4222-8222-222222222222'"
source_access=$(PGDATABASE="$source_db" psql -X -qAt -v ON_ERROR_STOP=1 -c \
 "SELECT active FROM c10_demo.business_members WHERE business_id=101 AND user_id='22222222-2222-4222-8222-222222222222'")
restore_access=$(PGDATABASE="$restore_db" psql -X -qAt -v ON_ERROR_STOP=1 -c \
 "SELECT active FROM c10_demo.business_members WHERE business_id=101 AND user_id='22222222-2222-4222-8222-222222222222'")
[[ "$source_access" == f && "$restore_access" == t ]] || { echo RESTORE_ACCESS_STATE_FAILED >&2; exit 1; }
PGDATABASE="$restore_db" psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $do$ BEGIN
 IF NOT c10_demo.can_business(1,101) OR c10_demo.can_business(2,201)
 THEN RAISE EXCEPTION 'PACK01_RESTORED_SCOPE_WRONG'; END IF;
 IF NOT c10_demo.can_approval_action_v1(1,101,'approval.submit')
 THEN RAISE EXCEPTION 'PACK01_RESTORED_APPROVAL_WRONG'; END IF;
END $do$;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $do$ BEGIN
 IF c10_demo.can_business(1,101) OR c10_demo.can_approval_action_v1(1,101,'approval.decide')
 THEN RAISE EXCEPTION 'PACK01_RESTORED_FOREIGN_TENANT_LEAK'; END IF;
END $do$;
ROLLBACK;
SQL
echo 'PASS PACK01 disposable rollback/restore: exception+transaction rollback, full PG17 pg_dump/pg_restore manifest parity, source revoke not in restored copy, restored foreign-tenant negative'
