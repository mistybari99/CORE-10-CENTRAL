#!/usr/bin/env bash
# Actual local GoTrue-issued sessions -> PostgREST -> canonical disposable SQL.
# No hosted Supabase credentials, production project, external email or paid service.
set -euo pipefail
cd "$(dirname "$0")/../.."
[[ "${CORE10_BUILD01_DISPOSABLE_ACK:-}" == I_CONFIRM_BUILD01_DISPOSABLE ]] || exit 2
case "${PGHOST:-}" in localhost|127.0.0.1) ;; *) echo 'Loopback database required'; exit 2;; esac
runtime=$(mktemp -d /tmp/core10-build01-auth.XXXXXX)
database="core10_build01_auth_${BASHPID}"
owned='' auth_pid='' rest_pid='' gateway_pid=''
cleanup(){
  for pid in "$gateway_pid" "$rest_pid" "$auth_pid"; do
    if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  done
  if [[ -n "$owned" ]]; then
    PGDATABASE=postgres psql -X -q -v ON_ERROR_STOP=1 -c "DROP DATABASE \"$owned\"" || true
  fi
  printf 'Disposable runtime logs preserved: %s\n' "$runtime"
}
trap cleanup EXIT
auth_dir=${CORE10_BUILD01_AUTH_DIRECTORY:-"$runtime/auth"}
if [[ -z "${CORE10_BUILD01_AUTH_DIRECTORY:-}" ]]; then
  mkdir -p "$auth_dir"
  curl -fsSL --retry 2 https://github.com/supabase/auth/releases/download/v2.197.0/auth-v2.197.0-amd64.tar.xz -o "$runtime/auth.tar.xz"
  printf '%s  %s\n' b5c2991d1df760c9b099c1c2395a94bd1c2f83ed58901934921997179dc9f7ea "$runtime/auth.tar.xz" | sha256sum --check
  tar -xJf "$runtime/auth.tar.xz" -C "$auth_dir"
fi
rest_binary=${CORE10_BUILD01_POSTGREST_BINARY:-"$runtime/postgrest"}
if [[ -z "${CORE10_BUILD01_POSTGREST_BINARY:-}" ]]; then
  curl -fsSL --retry 2 https://github.com/PostgREST/postgrest/releases/download/v12.2.12/postgrest-v12.2.12-linux-static-x64.tar.xz -o "$runtime/postgrest.tar.xz"
  printf '%s  %s\n' 5de4092f1719da3353c40bf96c8dec6913f2254a7cd0b61cc05f233153b557d5 "$runtime/postgrest.tar.xz" | sha256sum --check
  tar -xJf "$runtime/postgrest.tar.xz" -C "$runtime"
fi
PGDATABASE=postgres psql -X -q -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$database\""
owned=$database
export PGDATABASE=$database
bash tests/build01/run-load.sh
psql -X -q -v ON_ERROR_STOP=1 -c 'CREATE SCHEMA auth'
export CORE10_BUILD01_TEST_SECRET=core10_build01_disposable_auth_signer_2026_not_production
export CORE10_BUILD01_AUTH_URL="http://127.0.0.1:${CORE10_BUILD01_AUTH_PORT:-59999}"
export CORE10_BUILD01_REST_URL="http://127.0.0.1:${CORE10_BUILD01_REST_PORT:-55300}"
export GOTRUE_JWT_SECRET=$CORE10_BUILD01_TEST_SECRET
export GOTRUE_JWT_EXP=600 GOTRUE_JWT_AUD=authenticated GOTRUE_JWT_ADMIN_ROLES=service_role
export GOTRUE_DB_DRIVER=postgres DB_NAMESPACE=auth
export DATABASE_URL="postgres://${PGUSER:-postgres}:${PGPASSWORD:-}@${PGHOST}:${PGPORT:-5432}/${PGDATABASE}?search_path=auth"
export GOTRUE_DB_DATABASE_URL=$DATABASE_URL
export API_EXTERNAL_URL=$CORE10_BUILD01_AUTH_URL
export GOTRUE_API_HOST=127.0.0.1 GOTRUE_API_PORT=${CORE10_BUILD01_AUTH_PORT:-59999}
export PORT=$GOTRUE_API_PORT GOTRUE_SITE_URL=http://127.0.0.1:58081
export GOTRUE_EXTERNAL_EMAIL_ENABLED=true GOTRUE_EXTERNAL_PHONE_ENABLED=false
export GOTRUE_MAILER_AUTOCONFIRM=true GOTRUE_DISABLE_SIGNUP=true
export GOTRUE_DB_MIGRATIONS_PATH="$auth_dir/migrations"
"$auth_dir/auth" >"$runtime/auth.log" 2>&1 & auth_pid=$!
export PGRST_DB_URI="postgres://${PGUSER:-postgres}:${PGPASSWORD:-}@${PGHOST}:${PGPORT:-5432}/${PGDATABASE}"
export PGRST_DB_SCHEMAS=c10_demo PGRST_DB_ANON_ROLE=anon
export PGRST_JWT_SECRET=$CORE10_BUILD01_TEST_SECRET PGRST_JWT_AUD=authenticated
export PGRST_SERVER_HOST=127.0.0.1 PGRST_SERVER_PORT=${CORE10_BUILD01_REST_PORT:-55300}
"$rest_binary" >"$runtime/rest.log" 2>&1 & rest_pid=$!
if ! node -e '
(async()=>{for(let i=0;i<50;i++){
  try{const a=await fetch(process.env.CORE10_BUILD01_AUTH_URL+"/health");const r=await fetch(process.env.CORE10_BUILD01_REST_URL+"/");if(a.ok&&r.ok)return}catch{}
  await new Promise(r=>setTimeout(r,400));
}throw Error("Local GoTrue/PostgREST readiness failed")})().catch(e=>{console.error(e.message);process.exitCode=1});'; then
  tail -30 "$runtime/auth.log" "$runtime/rest.log"
  exit 1
fi
node tests/api/core10-build01-auth-rest-e2e.js seed
node tests/api/core10-build01-auth-rest-e2e.js test
if [[ "${CORE10_BUILD01_BROWSER:-0}" == 1 ]]; then
  export BUILD01_AUTH_URL=$CORE10_BUILD01_AUTH_URL BUILD01_REST_URL=$CORE10_BUILD01_REST_URL
  BUILD01_PUBLISHABLE_KEY=$(node -e 'const c=require("crypto"),b=x=>Buffer.from(JSON.stringify(x)).toString("base64url");const x=b({alg:"HS256",typ:"JWT"})+"."+b({role:"anon",aud:"authenticated",exp:Math.floor(Date.now()/1000)+3600});process.stdout.write(x+"."+c.createHmac("sha256",process.env.CORE10_BUILD01_TEST_SECRET).update(x).digest("base64url"))')
  export BUILD01_PUBLISHABLE_KEY PORT=${CORE10_BUILD01_GATEWAY_PORT:-58081}
  export BUILD01_BASE_URL="http://127.0.0.1:$PORT"
  export BUILD01_TEST_PASSWORD='Synthetic-Only_Build01_2026!'
  node tests/build01/gateway.cjs >"$runtime/gateway.log" 2>&1 & gateway_pid=$!
  node -e '(async()=>{for(let i=0;i<30;i++){try{if((await fetch(process.env.BUILD01_BASE_URL+"/")).ok)return}catch{}await new Promise(r=>setTimeout(r,200))}throw Error("Gateway readiness failed")})().catch(e=>{console.error(e.message);process.exitCode=1})'
  node tests/e2e/core10-build01-live-browser.cjs
fi
echo 'PASS actual local GoTrue v2.197.0 password sessions + PostgREST 12.2.12 Build01 journey; hosted staging/production NOT certified'
