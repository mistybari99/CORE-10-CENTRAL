#!/usr/bin/env bash
# Run original signed-HMAC HTTP and real-DOM tests while combined DB is alive.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "${CORE10_PREVIEW_DISPOSABLE_ACK:-}" == I_CONFIRM_DISPOSABLE_PREVIEW ]] || exit 2
[[ "${PGHOST:-}" == 127.0.0.1 || "${PGHOST:-}" == localhost ]] || exit 2
[[ "${PGDATABASE:-}" =~ ^core10_a048_ci_preview_[0-9]+$ ]] || exit 2
export CORE10_CI_JWT_SECRET=core10_preview_disposable_a055_hmac_signer_only_2026
export PGRST_DB_URI="postgres://${PGUSER:-postgres}:${PGPASSWORD:-}@${PGHOST}:${PGPORT:-5432}/${PGDATABASE}"
export PGRST_DB_SCHEMAS=c10_demo PGRST_DB_ANON_ROLE=anon
export PGRST_JWT_SECRET=$CORE10_CI_JWT_SECRET PGRST_JWT_AUD=authenticated
export PGRST_SERVER_HOST=127.0.0.1
export PGRST_SERVER_PORT=${CORE10_PREVIEW_REST_PORT:-55300}
export CORE10_CI_REST_URL="http://127.0.0.1:$PGRST_SERVER_PORT"
rest_log=$(mktemp /tmp/core10-preview-postgrest.XXXXXX.log)
container="core10-preview-rest-${BASHPID}"
rest_pid=''
cleanup() {
  if [[ -n "$rest_pid" ]]; then
    if [[ -z "${CORE10_PREVIEW_POSTGREST_BINARY:-}" ]]; then
      docker stop --time 3 "$container" >/dev/null 2>&1 || true
    else
      kill "$rest_pid" 2>/dev/null || true
    fi
    wait "$rest_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
if [[ -n "${CORE10_PREVIEW_POSTGREST_BINARY:-}" ]]; then
  "$CORE10_PREVIEW_POSTGREST_BINARY" >"$rest_log" 2>&1 &
else
  docker run --rm --name "$container" --network host \
    -e PGRST_DB_URI -e PGRST_DB_SCHEMAS -e PGRST_DB_ANON_ROLE \
    -e PGRST_JWT_SECRET -e PGRST_JWT_AUD -e PGRST_SERVER_HOST -e PGRST_SERVER_PORT \
    postgrest/postgrest:v12.2.12 >"$rest_log" 2>&1 &
fi
rest_pid=$!
if ! node -e '
 (async()=>{for(let i=0;i<40;i++){
   try{if((await fetch(process.env.CORE10_CI_REST_URL+"/",{signal:AbortSignal.timeout(1000)})).status===200)return}
   catch{} await new Promise(r=>setTimeout(r,500));
 }throw Error("Disposable PostgREST readiness timed out")})().catch(e=>{console.error(e.message);process.exitCode=1});
'; then
  tail -40 "$rest_log"
  exit 1
fi
node tests/api/core10-a055-asset-maintenance-rest-e2e.js
node tests/e2e/core10-a055-asset-maintenance-browser.js
echo 'PASS combined-schema A055 signed-HMAC HTTP + mobile/desktop browser; NOT GoTrue'
