#!/usr/bin/env bash
# C10-A055 local/CI loader: disposable DB <- A018 baseline + synthetic seed + A055 SQL files in dependency order.
# Usage: tests/c10_a055_load.sh <dbname> [last_file_suffix]  (needs local PostgreSQL superuser via PGUSER/PGHOST env or `su postgres`)
set -euo pipefail
DB=${1:?db name}; LAST=${2:-all}
cd "$(dirname "$0")/.."
P="psql -X -q -v ON_ERROR_STOP=1"
if [ -n "${PGHOST:-}" ]; then ADM="$P -d postgres"; else ADM="su postgres -c"; fi
if [ -z "${PGHOST:-}" ]; then
  su postgres -c "psql -X -q -c 'DROP DATABASE IF EXISTS $DB'" ; su postgres -c "psql -X -q -c 'CREATE DATABASE $DB'"
  su postgres -c "psql -X -q -d $DB -c \"DO \\\$\\\$BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF; IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF; END \\\$\\\$;\""
  RUN() { su postgres -c "psql -X -q -v ON_ERROR_STOP=1 -d $DB -f $PWD/$1"; }
else
  psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB" -c "CREATE DATABASE $DB"
  RUN() { psql -X -q -v ON_ERROR_STOP=1 -d $DB -f "$1"; }
fi
RUN internal/enterprise-sql/c10_a018_demo_backend.sql
RUN tests/c10_a018_demo_seed.sql
# AM_FILES="core registry lockdown" loads only those (agents work on partial sets); default = every existing file in order.
FILES=${AM_FILES:-"core policy registry planning workorders reports lockdown"}
for f in $FILES; do
  F=internal/enterprise-sql/c10_a055_assets_${f}_v1.sql
  [ -f "$F" ] && RUN "$F"
  [ "$LAST" = "$f" ] && break
done
[ -f tests/c10_a055_seed.sql ] && RUN tests/c10_a055_seed.sql
echo "LOADED $DB"
