#!/usr/bin/env bash
# Disposable-database proof for DEC-01: every migration must survive up -> down(all) -> up.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)/internal/migrations/run.sh"
count(){ "$R" status | wc -l; }
"$R" up; n1="$(count)"
[ "$n1" -gt 0 ] || { echo "no migrations applied" >&2; exit 1; }
for _ in $(seq "$n1"); do "$R" down; done
[ "$(psql -X -At ${DATABASE_URL:+"$DATABASE_URL"} -c "select count(*) from pg_namespace where nspname='core10'")" = "0" ] \
  || { echo "core10 schema survived full rollback" >&2; exit 1; }
"$R" up; "$R" up
[ "$(count)" = "$n1" ] || { echo "re-apply mismatch" >&2; exit 1; }
# c10_demo and public must be untouched by canonical migrations.
[ "$(psql -X -At ${DATABASE_URL:+"$DATABASE_URL"} -c "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'")" = "${PUBLIC_TABLES_EXPECTED:-0}" ] \
  || { echo "public schema changed" >&2; exit 1; }
echo "MIGRATIONS_UP_DOWN_UP_OK $n1"
