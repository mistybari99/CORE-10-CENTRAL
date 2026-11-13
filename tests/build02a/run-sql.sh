#!/usr/bin/env bash
# Disposable Build 02A SQL only. Never points at hosted or production data.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "${CORE10_BUILD02A_DISPOSABLE_ACK:-}" == I_CONFIRM_BUILD02A_DISPOSABLE ]] || exit 2
case "${PGHOST:-}" in localhost|127.0.0.1) ;; *) exit 2;; esac
database="core10_build02a_sql_${BASHPID}"
owned=''
cleanup(){ if [[ -n "$owned" ]]; then PGDATABASE=postgres psql -X -q -v ON_ERROR_STOP=1 -c "DROP DATABASE \"$owned\""; fi; }
trap cleanup EXIT
PGDATABASE=postgres psql -X -q -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$database\""
owned=$database
export PGDATABASE=$database
psql -X -q -v ON_ERROR_STOP=1 -c "DO \$\$ BEGIN IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF; IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF; END \$\$"
for file in \
 internal/enterprise-sql/c10_a018_demo_backend.sql \
 tests/c10_a018_demo_seed.sql \
 internal/enterprise-sql/c10_a018_inventory_v1.sql \
 internal/enterprise-sql/c10_a020_business_setup_v1.sql \
 internal/enterprise-sql/c10_a020_industry_draft_v2.sql \
 internal/enterprise-sql/c10_a021_owner_controls_v1.sql \
 internal/enterprise-sql/c10_a034_access_governance_v1.sql \
 internal/enterprise-sql/c10_build01_access_integration_v1.sql \
 internal/enterprise-sql/c10_build02a_approval_permissions_v1.sql \
 tests/build02a/approval-permissions.sql; do
 psql -X -q -v ON_ERROR_STOP=1 -f "$file"
done
echo 'PASS Build02A approval action resolver; disposable PostgreSQL only'
