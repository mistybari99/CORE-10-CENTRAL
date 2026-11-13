#!/usr/bin/env bash
# Candidate SQL in an explicitly disposable loopback database, never a hosted project.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "${CORE10_BUILD01_DISPOSABLE_ACK:-}" == I_CONFIRM_BUILD01_DISPOSABLE ]] || exit 2
case "${PGHOST:-}" in localhost|127.0.0.1) ;; *) echo 'Loopback database required'; exit 2;; esac
[[ "${PGDATABASE:-}" =~ ^core10_build01_(sql|auth)_[0-9]+$ ]] || { echo 'Owned Build01 database prefix required'; exit 2; }
psql=(psql -X -q -v ON_ERROR_STOP=1)
"${psql[@]}" -c "DO \$\$ BEGIN IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF; IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF; END \$\$"
for file in \
 internal/enterprise-sql/c10_a018_demo_backend.sql \
 tests/c10_a018_demo_seed.sql \
 internal/enterprise-sql/c10_a018_inventory_v1.sql \
 internal/enterprise-sql/c10_a020_business_setup_v1.sql \
 internal/enterprise-sql/c10_a020_industry_draft_v2.sql \
 internal/enterprise-sql/c10_a021_owner_controls_v1.sql \
 internal/enterprise-sql/c10_a034_access_governance_v1.sql \
 internal/enterprise-sql/c10_build01_access_integration_v1.sql; do
  printf 'LOAD %s\n' "$file"
  "${psql[@]}" -f "$file"
done
