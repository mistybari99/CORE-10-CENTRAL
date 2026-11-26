#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../../.."
[[ "${CORE10_W02_DISPOSABLE:-}" == W02_LOCAL_ONLY && "${PGHOST:-}" == 127.0.0.1 ]] || exit 2
unset DATABASE_URL PGSERVICE PGHOSTADDR PGOPTIONS
runtime=$(mktemp -d /tmp/core10-w02-signed.XXXXXX)
database="core10_w02_signed_${BASHPID}"
owned='' auth_pid='' rest_pid=''
cleanup() {
  for pid in "$rest_pid" "$auth_pid"; do
    if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  done
  if [[ -n "$owned" ]]; then
    PGDATABASE=postgres psql -Xq -v ON_ERROR_STOP=1 -c "DROP DATABASE \"$owned\"" || return 1
  fi
}
trap cleanup EXIT

auth_dir=${CORE10_W02_AUTH_DIR:-"$runtime/auth"}
rest_bin=${CORE10_W02_REST_BIN:-"$runtime/postgrest"}
if [[ -z "${CORE10_W02_AUTH_DIR:-}" ]]; then
  mkdir -p "$auth_dir"
  curl -fsSL --retry 2 https://github.com/supabase/auth/releases/download/v2.197.0/auth-v2.197.0-amd64.tar.xz -o "$runtime/auth.tar.xz"
  printf '%s  %s\n' b5c2991d1df760c9b099c1c2395a94bd1c2f83ed58901934921997179dc9f7ea "$runtime/auth.tar.xz" | sha256sum --check
  tar -xJf "$runtime/auth.tar.xz" -C "$auth_dir"
fi
if [[ -z "${CORE10_W02_REST_BIN:-}" ]]; then
  curl -fsSL --retry 2 https://github.com/PostgREST/postgrest/releases/download/v12.2.12/postgrest-v12.2.12-linux-static-x86-64.tar.xz -o "$runtime/rest.tar.xz"
  printf '%s  %s\n' 5de4092f1719da3353c40bf96c8dec6913f2254a7cd0b61cc05f233153b557d5 "$runtime/rest.tar.xz" | sha256sum --check
  tar -xJf "$runtime/rest.tar.xz" -C "$runtime"
fi

PGDATABASE=postgres psql -Xq -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"$database\""
owned=$database
export PGDATABASE=$database
psql -Xq -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
END $$;
SQL
bash internal/migrations/run.sh up
psql -Xq -v ON_ERROR_STOP=1 -c 'CREATE SCHEMA auth'

export CORE10_W02_SIGNER
CORE10_W02_SIGNER=$(node -p "require('node:crypto').randomBytes(32).toString('hex')")
export GOTRUE_JWT_SECRET=$CORE10_W02_SIGNER GOTRUE_JWT_EXP=600 GOTRUE_JWT_AUD=authenticated GOTRUE_JWT_ADMIN_ROLES=service_role
export GOTRUE_DB_DRIVER=postgres DB_NAMESPACE=auth
export GOTRUE_API_HOST=127.0.0.1 GOTRUE_API_PORT=${CORE10_W02_AUTH_PORT:-59997}
export PORT=$GOTRUE_API_PORT GOTRUE_SITE_URL=http://127.0.0.1:58087
export API_EXTERNAL_URL="http://127.0.0.1:$GOTRUE_API_PORT"
export GOTRUE_EXTERNAL_EMAIL_ENABLED=true GOTRUE_EXTERNAL_PHONE_ENABLED=false
export GOTRUE_MAILER_AUTOCONFIRM=true GOTRUE_DISABLE_SIGNUP=true
export GOTRUE_DB_MIGRATIONS_PATH="$auth_dir/migrations"
uri="postgres://${PGUSER:-postgres}:${PGPASSWORD:-}@127.0.0.1:${PGPORT:-5432}/$database"
export GOTRUE_DB_DATABASE_URL="$uri?search_path=auth"
export PGRST_DB_URI="$uri" PGRST_DB_SCHEMAS=core10 PGRST_DB_ANON_ROLE=anon
export PGRST_JWT_SECRET=$CORE10_W02_SIGNER PGRST_JWT_AUD=authenticated
export PGRST_SERVER_HOST=127.0.0.1 PGRST_SERVER_PORT=${CORE10_W02_REST_PORT:-55307}
export CORE10_W02_AUTH_URL="$API_EXTERNAL_URL" CORE10_W02_REST_URL="http://127.0.0.1:$PGRST_SERVER_PORT"

"$auth_dir/auth" >"$runtime/auth.log" 2>&1 & auth_pid=$!
"$rest_bin" >"$runtime/rest.log" 2>&1 & rest_pid=$!
if ! node -e '
(async()=>{
 for(let i=0;i<40;i++){
  try{
   const options={signal:AbortSignal.timeout(750)};
   const a=await fetch(process.env.CORE10_W02_AUTH_URL+"/health", options);
   const r=await fetch(process.env.CORE10_W02_REST_URL+"/", options);
   if(a.ok&&r.ok)return;
  }catch{}
  await new Promise(resolve=>setTimeout(resolve,300));
 }
 throw Error("Disposable GoTrue/PostgREST readiness failed");
})().catch(e=>{console.error(e.message);process.exitCode=1});'; then
  tail -30 "$runtime/auth.log" "$runtime/rest.log"
  exit 1
fi
fixture=modules/paperops/tests/w02-signed
node "$fixture/http-e2e.cjs" users
psql -Xq -v ON_ERROR_STOP=1 -f "$fixture/seed.sql"
node "$fixture/http-e2e.cjs"
