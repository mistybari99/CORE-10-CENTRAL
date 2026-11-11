#!/usr/bin/env bash
# Builds the disposable stacks and runs every A053/A054 PostgreSQL test (needs PGHOST/PGPORT/PGUSER of a disposable cluster).
set -euo pipefail
cd "$(dirname "$0")/.."
bash tests/c10_a054_regression.sh
bash tests/c10_a053_stack.sh full
export PGDATABASE=core10_a053_ci
psql -X -q -v ON_ERROR_STOP=1 -f tests/c10_a054_policy_e2e.sql
psql -X -q -v ON_ERROR_STOP=1 -f tests/c10_a053_integration_e2e.sql
bash tests/c10_a053_stack.sh base
PGDATABASE=core10_a053_ci_noa051 psql -X -q -v ON_ERROR_STOP=1 -f tests/c10_a053_not_connected_e2e.sql
