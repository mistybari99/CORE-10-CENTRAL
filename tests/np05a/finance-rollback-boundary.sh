#!/usr/bin/env bash
# Integration regression: Finance is not the highest migration once NP05A is installed.
# Reuse the canonical NP06 synthetic fixture/race, then test its exact rollback file atomically.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ "$(psql -X -At -c 'select max(version) from core10.schema_migrations')" -ge 500 ] || { echo NP05A_HIGHER_BLOCK_REQUIRED;exit 1; }
bash tests/migrations/np06-finance-race.sh
out=$(mktemp);trap 'rm -f "$out"' EXIT
if psql -X -q -v ON_ERROR_STOP=1 -1 -f internal/migrations/0400_np06_finance_foundation.down.sql >"$out" 2>&1;then
 cat "$out";echo FIN_ROLLBACK_UNEXPECTEDLY_ALLOWED;exit 1
fi
grep -q FIN_ROLLBACK_DENIED_PERSISTED_HISTORY "$out" || { cat "$out";exit 1; }
[ "$(psql -X -At -c "select count(*) from core10.finance_journals_v1 where business_id=9711 and status='posted'")" = 1 ]
[ "$(psql -X -At -c 'select count(*) from core10.schema_migrations where version=400')" = 1 ]
echo NP05A_FINANCE_EXACT_ROLLBACK_HISTORY_GUARD_OK
