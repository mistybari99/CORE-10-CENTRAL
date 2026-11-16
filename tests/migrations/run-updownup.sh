#!/usr/bin/env bash
# Disposable-database proof for DEC-01: every migration must survive up -> down(all) -> up.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)/internal/migrations/run.sh"
count(){ "$R" status | wc -l; }
# The disposable runner is bare PostgreSQL, not Supabase. Create the synthetic
# PostgREST role required by access RLS/grants; never provision real users here.
psql -X -v ON_ERROR_STOP=1 -c "DO \$\$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
  CREATE ROLE authenticated NOLOGIN;
 END IF;
END \$\$;" >/dev/null
"$R" up; n1="$(count)"
[ "$n1" -gt 0 ] || { echo "no migrations applied" >&2; exit 1; }
for _ in $(seq "$n1"); do "$R" down; done
[ "$(psql -X -At ${DATABASE_URL:+"$DATABASE_URL"} -c "select count(*) from pg_namespace where nspname='core10'")" = "0" ] \
  || { echo "core10 schema survived full rollback" >&2; exit 1; }
"$R" up; "$R" up
[ "$(count)" = "$n1" ] || { echo "re-apply mismatch" >&2; exit 1; }
# core10 and public must be untouched by canonical migrations.
[ "$(psql -X -At ${DATABASE_URL:+"$DATABASE_URL"} -c "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'")" = "${PUBLIC_TABLES_EXPECTED:-0}" ] \
  || { echo "public schema changed" >&2; exit 1; }
echo "MIGRATIONS_UP_DOWN_UP_OK $n1"
