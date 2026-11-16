#!/usr/bin/env bash
# CORE10 migration runner (DEC-01). Usage: run.sh up | down | status
# Connection comes from the standard PG* variables / DATABASE_URL. Never point this at the
# protected IMG-ERP-SG database: applying to any hosted database needs a separate Owner GO.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PSQL=(psql -X -q -v ON_ERROR_STOP=1 ${DATABASE_URL:+"$DATABASE_URL"})
q(){ "${PSQL[@]}" -At -c "$1"; }
has_ledger(){ [ "$(q "select to_regclass('core10.schema_migrations') is not null")" = "t" ]; }
applied(){ if has_ledger; then q "select version from core10.schema_migrations order by version"; fi; }
sum(){ sha256sum "$1" | cut -d' ' -f1; }

q "select 1" >/dev/null || { echo "DATABASE_UNREACHABLE" >&2; exit 1; }

case "${1:-}" in
 up)
  for f in "$DIR"/[0-9][0-9][0-9][0-9]_*.up.sql; do
   n="$(basename "$f" .up.sql)"; v=$((10#${n%%_*}))
   [ -f "$DIR/$n.down.sql" ] || { echo "MISSING_DOWN $n" >&2; exit 1; }
   if applied | grep -qx "$v"; then
    [ "$(q "select checksum from core10.schema_migrations where version=$v")" = "$(sum "$f")" ] \
      || { echo "CHECKSUM_DRIFT $n: an applied migration was edited" >&2; exit 1; }
    continue
   fi
   top="$(applied | tail -1)"
   if [ -n "$top" ] && [ "$v" -lt "$top" ]; then
    echo "OUT_OF_ORDER $n: version $v is lower than applied version $top. Numeric order is apply order;" >&2
    echo "  renumber the file above $top on trunk before it reaches this database (see docs/coordination/MIGRATION_RESERVATIONS.json)." >&2
    exit 1
   fi
   "${PSQL[@]}" -1 -f "$f" -c "insert into core10.schema_migrations(version,name,checksum) values($v,'$n','$(sum "$f")')"
   echo "applied $n"
  done;;
 down)
  v="$(applied | tail -1)"; [ -n "$v" ] || { echo "nothing to roll back"; exit 0; }
  n="$(q "select name from core10.schema_migrations where version=$v")"
  "${PSQL[@]}" -1 -c "delete from core10.schema_migrations where version=$v" -f "$DIR/$n.down.sql"
  echo "rolled back $n";;
 status) applied | sed 's/^/applied /';;
 *) echo "usage: run.sh up|down|status" >&2; exit 2;;
esac
