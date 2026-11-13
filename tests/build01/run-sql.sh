#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "${CORE10_BUILD01_DISPOSABLE_ACK:-}" == I_CONFIRM_BUILD01_DISPOSABLE ]] || exit 2
case "${PGHOST:-}" in localhost|127.0.0.1) ;; *) exit 2;; esac
suite=${1:-all}
if [[ "$suite" == all ]]; then
  # Original regressions intentionally COMMIT their fixtures. Each therefore
  # gets a fresh full integration stack, rather than deleting prior evidence.
  for area in baseline setup industry access integration concurrency; do
    bash tests/build01/run-sql.sh "$area"
  done
  exit 0
fi
case "$suite" in baseline|setup|industry|access|integration|concurrency) ;; *) exit 2;; esac
database="core10_build01_sql_${BASHPID}"
owned=''
cleanup(){ if [[ -n "$owned" ]]; then PGDATABASE=postgres psql -X -q -v ON_ERROR_STOP=1 -c "DROP DATABASE \"$owned\""; fi; }
trap cleanup EXIT
PGDATABASE=postgres psql -X -q -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$database\""
owned=$database
export PGDATABASE=$database
bash tests/build01/run-load.sh
# No auth schema exists here: unchanged SQL claim fixtures remain distinct from
# the actual GoTrue-issued sessions tested by run-auth.sh.
case "$suite" in
 baseline) test=tests/c10_a018_demo_e2e.sql;;
 setup) test=tests/c10_a020_business_setup_e2e.sql;;
 industry) test=tests/c10_a020_industry_draft_v2_e2e.sql;;
 access) test=tests/c10_a034_access_e2e.sql;;
 integration) test=tests/build01/access-integration.sql;;
 concurrency) bash tests/build01/run-concurrency.sh; test='';;
esac
if [[ -n "$test" ]]; then
  printf 'TEST %s\n' "$test"
  psql -X -q -v ON_ERROR_STOP=1 -f "$test"
fi
echo 'PASS Build01 original setup/access SQL regressions and new integration; synthetic claim fixtures only'
