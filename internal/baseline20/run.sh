#!/usr/bin/env bash
# Fresh CORE10 only; does not drop or alter an existing core10 schema.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
[ "${CORE10_BASELINE_ALLOW_EMPTY:-}" = YES ] && [ -n "${CORE10_BASELINE_EXPECT_DB:-}" ] || { echo 'Require CORE10_BASELINE_ALLOW_EMPTY=YES and CORE10_BASELINE_EXPECT_DB' >&2; exit 2; }
case "${DATABASE_URL:-} ${PGHOST:-}" in *kbuhnpqooycqbzrfejcs*|*luoeyyngayxpqecuuijb*) echo 'PROTECTED_DB' >&2; exit 2;; esac
node "$DIR/verify.mjs"
PSQL=(psql -X -q -v ON_ERROR_STOP=1 ${DATABASE_URL:+"$DATABASE_URL"})
[ "$("${PSQL[@]}" -At -c 'select current_database()')" = "$CORE10_BASELINE_EXPECT_DB" ] || { echo 'WRONG_DB' >&2; exit 2; }
[ "$("${PSQL[@]}" -At -c "select to_regnamespace('core10') is null")" = t ] || { echo 'CORE10_ALREADY_EXISTS: use the original migration runner for upgrades' >&2; exit 2; }
args=();for f in "$DIR"/[0-9][0-9]_*.sql; do args+=(-f "$f"); done
[ "${#args[@]}" -eq 40 ]
"${PSQL[@]}" -1 -c "select pg_advisory_xact_lock(2050420);" "${args[@]}" -c "DO \$\$ BEGIN IF (SELECT count(*) FROM core10.schema_migrations)<>71 OR (SELECT max(version) FROM core10.schema_migrations)<>504 THEN RAISE EXCEPTION 'BASELINE_LEDGER_MISMATCH'; END IF; IF EXISTS (SELECT 1 FROM core10.control_rpc_map_v1 WHERE status='pending') THEN RAISE EXCEPTION 'BASELINE_REGISTRY_PENDING'; END IF; END \$\$;"
echo CORE10_BASELINE20_APPLIED
