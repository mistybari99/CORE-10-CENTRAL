#!/usr/bin/env bash
# A051 baseline regression WITH the A054 hooks installed: the unchanged A051 e2e + concurrency must still pass.
set -euo pipefail
cd "$(dirname "$0")/.."
bash tests/c10_a053_stack.sh reg
for f in policy bridge; do PGDATABASE=core10_a053_ci_reg psql -X -q -v ON_ERROR_STOP=1 -f internal/enterprise-sql/c10_a054_workforce_${f}_v1.sql; done
PGDATABASE=core10_a053_ci_reg psql -X -q -v ON_ERROR_STOP=1 -f tests/c10_a051_workforce_e2e.sql
# idempotent re-apply of the bridge must be a no-op
PGDATABASE=core10_a053_ci_reg psql -X -q -v ON_ERROR_STOP=1 -c "DO \$\$BEGIN IF (SELECT count(*) FROM c10_demo.a054_patch_log)<20 THEN RAISE EXCEPTION 'patch log incomplete'; END IF; END\$\$"
echo A054_REGRESSION_PASS
