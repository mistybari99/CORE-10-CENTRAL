#!/usr/bin/env bash
# NP06/F3: 0403 rollback must reject an otherwise empty database that contains
# only an F3 Owner Control override. Run on disposable loopback PG17 only.
set -euo pipefail
cd "$(dirname "$0")/../.."
case "$PGHOST" in 127.0.0.1|localhost) ;; *) echo 'DISPOSABLE_LOOPBACK_POSTGRES_REQUIRED' >&2; exit 2;; esac
DB="core10_arap_override_guard_$$"
cleanup() {
  psql -X -q -d postgres -c "DROP DATABASE IF EXISTS \"$DB\" WITH (FORCE)" >/dev/null 2>&1 || true
}
trap cleanup EXIT
psql -X -q -v ON_ERROR_STOP=1 -d postgres -c "CREATE DATABASE \"$DB\""
export PGDATABASE="$DB"
psql -X -q -v ON_ERROR_STOP=1 -d postgres <<'SQL'
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
  CREATE ROLE authenticated NOLOGIN;
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
  CREATE ROLE anon NOLOGIN;
 END IF;
END $$;
SQL
internal/migrations/run.sh up >/dev/null
# Verify safe 0402-only and 0402+0403 serving states on a fresh database.
# Applying 0402 without 0403 must never expose its incomplete mutations.
[[ "$(psql -X -At -c "SELECT has_function_privilege('authenticated','core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text)','EXECUTE')")" == t ]]
[[ "$(psql -X -At -c "SELECT has_function_privilege('authenticated','core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)','EXECUTE')")" == t ]]
internal/migrations/run.sh down >/dev/null
[[ "$(psql -X -At -c "SELECT count(*) FROM core10.schema_migrations WHERE version=402")" == 1 ]]
[[ "$(psql -X -At -c "SELECT count(*) FROM core10.schema_migrations WHERE version=403")" == 0 ]]
[[ "$(psql -X -At -c "SELECT has_function_privilege('authenticated','core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text)','EXECUTE')")" == f ]]
[[ "$(psql -X -At -c "SELECT has_function_privilege('authenticated','core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)','EXECUTE')")" == f ]]
[[ "$(psql -X -At -c "SELECT count(*) FROM pg_trigger WHERE tgname='finance_arap_source_integrity_v1' AND NOT tgisinternal")" == 0 ]]
# A 0402-only cutover must also keep read RPCs closed to unauthenticated callers.
[[ "$(psql -X -At -c "SELECT has_function_privilege('anon','core10.finance_arap_aging_v1(bigint,date,text)','EXECUTE')")" == f ]]
# 0402-only must not leak mutation privileges through PUBLIC or anon.
[[ "$(psql -X -At -c "SELECT has_function_privilege('public','core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text)','EXECUTE')")" == f ]]
[[ "$(psql -X -At -c "SELECT has_function_privilege('anon','core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)','EXECUTE')")" == f ]]
# PUBLIC must not inherit 0402-only aging read permission either.
[[ "$(psql -X -At -c "SELECT has_function_privilege('public','core10.finance_arap_aging_v1(bigint,date,text)','EXECUTE')")" == f ]]
# Trace RPC is introduced by 0403; in the 0402-only state it must be absent.
[[ "$(psql -X -At -c "SELECT to_regprocedure('core10.finance_arap_trace_v1(bigint)') IS NULL")" == t ]]
internal/migrations/run.sh up >/dev/null
[[ "$(psql -X -At -c "SELECT has_function_privilege('authenticated','core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text)','EXECUTE')")" == t ]]
[[ "$(psql -X -At -c "SELECT has_function_privilege('authenticated','core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)','EXECUTE')")" == t ]]
[[ "$(psql -X -At -c "SELECT count(*) FROM pg_trigger WHERE tgname='finance_arap_source_integrity_v1' AND NOT tgisinternal")" == 1 ]]
# Cutover must not accidentally grant mutation RPCs to PUBLIC.
[[ "$(psql -X -At -c "SELECT has_function_privilege('public','core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text)','EXECUTE')")" == f ]]
[[ "$(psql -X -At -c "SELECT has_function_privilege('public','core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)','EXECUTE')")" == f ]]
# After 0403 cutover, neither anonymous nor PUBLIC callers can invoke AR/AP mutations.
[[ "$(psql -X -At -c "SELECT has_function_privilege('anon','core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text)','EXECUTE')")" == f ]]
[[ "$(psql -X -At -c "SELECT has_function_privilege('anon','core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)','EXECUTE')")" == f ]]
[[ "$(psql -X -At -c "SELECT has_function_privilege('public','core10.finance_arap_aging_v1(bigint,date,text)','EXECUTE')")" == f ]]
# After 0403 cutover, read/trace RPCs remain private to authenticated callers.
[[ "$(psql -X -At -c "SELECT has_function_privilege('anon','core10.finance_arap_aging_v1(bigint,date,text)','EXECUTE')")" == f ]]
[[ "$(psql -X -At -c "SELECT has_function_privilege('anon','core10.finance_arap_trace_v1(bigint)','EXECUTE')")" == f ]]
[[ "$(psql -X -At -c "SELECT has_function_privilege('public','core10.finance_arap_trace_v1(bigint)','EXECUTE')")" == f ]]
# Inspect the actual PUBLIC pseudo-role ACL (grantee OID 0), not merely a login role.
# PostgreSQL's default function ACL grants PUBLIC EXECUTE unless explicitly revoked.
psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
DO $guard$
DECLARE exposed text;
BEGIN
 SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text)
 INTO exposed
 FROM pg_proc p
 CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
 WHERE p.oid IN (
  'core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text)'::regprocedure,
  'core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)'::regprocedure,
  'core10.finance_arap_aging_v1(bigint,date,text)'::regprocedure,
  'core10.finance_arap_trace_v1(bigint)'::regprocedure
 ) AND a.grantee = 0 AND a.privilege_type = 'EXECUTE';
 IF exposed IS NOT NULL THEN
  RAISE EXCEPTION 'FIN_ARAP_PUBLIC_EXECUTE_ACL_LEAK: %', exposed;
 END IF;
END
$guard$;
SQL
echo FIN_ARAP_0402_0403_CUTOVER_GUARD_PASS

psql -X -q -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO core10.tenants(id,slug) VALUES (96811,'arap-override-only-rollback');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (96812,96811,'Rollback Guard');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (96813,96811,96812,'arap-override-guard','sweets_bakery','arapguardbusiness');
INSERT INTO core10.control_overrides_v1
 (tenant_id,business_id,feature_key,reason,request_key,granted_by,expires_at)
 VALUES (96811,96813,'finance.arap_link',
 'Hold F3 rollback while an authorized override remains in history',
 'arapOverrideOnly1','91111111-1111-4111-8111-111111111111',
 clock_timestamp()+interval '4 hours');
SQL
[[ "$(psql -X -At -c "SELECT count(*) FROM core10.finance_arap_links_v1")" == 0 ]]
[[ "$(psql -X -At -c "SELECT count(*) FROM core10.finance_arap_allocations_v1")" == 0 ]]
[[ "$(psql -X -At -c "SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE action IN ('finance.arap_link','finance.arap_allocate')")" == 0 ]]
[[ "$(psql -X -At -c "SELECT count(*) FROM core10.control_setting_versions_v1 WHERE feature_key IN ('finance.arap_link','finance.arap_allocate')")" == 0 ]]
[[ "$(psql -X -At -c "SELECT count(*) FROM core10.control_overrides_v1 WHERE feature_key='finance.arap_link'")" == 1 ]]
# A rejected rollback must preserve the exact applied migration ledger record,
# not merely leave version 0403 present with a changed or missing checksum.
ledger_before="$(psql -X -At -c "SELECT version || ':' || name || ':' || checksum FROM core10.schema_migrations WHERE version IN (402,403) ORDER BY version")"
[[ "$(printf '%s\\n' "$ledger_before" | wc -l | tr -d ' ')" == 2 ]]
output="$(mktemp)"
trap 'rm -f "$output"; cleanup' EXIT
if internal/migrations/run.sh down >"$output" 2>&1; then
  cat "$output" >&2
  echo FIN_ARAP_OVERRIDE_ONLY_ROLLBACK_UNEXPECTEDLY_ALLOWED >&2
  exit 1
fi
if ! grep -q 'FIN_ARAP_INTEGRITY_ROLLBACK_DENIED_HISTORY' "$output"; then
  cat "$output" >&2
  echo FIN_ARAP_OVERRIDE_ONLY_WRONG_ROLLBACK_ERROR >&2
  exit 1
fi
[[ "$(psql -X -At -c "SELECT count(*) FROM core10.schema_migrations WHERE version=403")" == 1 ]]
[[ "$(psql -X -At -c "SELECT version || ':' || name || ':' || checksum FROM core10.schema_migrations WHERE version IN (402,403) ORDER BY version")" == "$ledger_before" ]]
[[ "$(psql -X -At -c "SELECT count(*) FROM core10.control_overrides_v1 WHERE feature_key='finance.arap_link'")" == 1 ]]
[[ "$(psql -X -At -c "SELECT count(*) FROM pg_trigger WHERE tgname='finance_arap_source_integrity_v1' AND NOT tgisinternal")" == 1 ]]
# Failed rollback is atomic: keep both authenticated mutation grants intact.
[[ "$(psql -X -At -c "SELECT has_function_privilege('authenticated','core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text)','EXECUTE')")" == t ]]
[[ "$(psql -X -At -c "SELECT has_function_privilege('authenticated','core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)','EXECUTE')")" == t ]]
echo FIN_ARAP_OVERRIDE_ONLY_ROLLBACK_GUARD_PASS
