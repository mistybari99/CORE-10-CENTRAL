#!/usr/bin/env bash
# B-009: schema drift between the old installer files and the numbered migrations.
# Builds two disposable databases, snapshots the core10 catalog of each, and reports every
# object the old installer creates that the migrations do not create identically.
# Objects only in the migrations are listed for information (they are newer work).
# Exit 1 on any drift. Accepted, reviewed drift lives in tests/migrations/b009-accepted-drift.tsv
# (one line per object key, with a reason); nothing else is ignored.
set -euo pipefail
cd "$(dirname "$0")/../.."
export PGHOST="${PGHOST:-localhost}" PGUSER="${PGUSER:-postgres}"
# Same order as the old A018/A020/A034 CI; the demo seed is data the A020 file needs (template rows), not schema.
LEGACY=(internal/enterprise-sql/c10_a018_demo_backend.sql tests/c10_a018_demo_seed.sql internal/enterprise-sql/c10_a018_inventory_v1.sql
        internal/enterprise-sql/c10_a020_business_setup_v1.sql internal/enterprise-sql/c10_a020_industry_draft_v2.sql
        internal/enterprise-sql/c10_a034_access_governance_v1.sql)
OUT="${B009_OUT:-$(mktemp -d)}"; mkdir -p "$OUT"
q() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }
for db in b009_legacy b009_mig; do q -d postgres -c "DROP DATABASE IF EXISTS $db" -c "CREATE DATABASE $db"; done
q -d postgres -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF; IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF; END \$\$;"
for f in "${LEGACY[@]}"; do q -d b009_legacy -f "$f" >/dev/null; done
PGDATABASE=b009_mig internal/migrations/run.sh up >/dev/null

snap() {  # one line per object: kind|key<TAB>md5(normalized definition)
psql -X -At -v ON_ERROR_STOP=1 -F $'\t' -d "$1" <<'SQL'
WITH n AS (SELECT oid FROM pg_namespace WHERE nspname='core10')
SELECT 'table|'||c.relname, md5(c.relkind::text||':rls='||c.relrowsecurity||':force='||c.relforcerowsecurity) FROM pg_class c WHERE c.relnamespace=(SELECT oid FROM n) AND c.relkind IN ('r','v','m','p')
UNION ALL SELECT 'column|'||c.relname||'.'||a.attname, md5(format_type(a.atttypid,a.atttypmod)||':nn='||a.attnotnull||':def='||coalesce(pg_get_expr(d.adbin,d.adrelid),''))
  FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
  WHERE c.relnamespace=(SELECT oid FROM n) AND c.relkind IN ('r','v','m','p') AND a.attnum>0 AND NOT a.attisdropped
UNION ALL SELECT 'constraint|'||c.relname||'.'||k.conname, md5(pg_get_constraintdef(k.oid)) FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid WHERE c.relnamespace=(SELECT oid FROM n)
UNION ALL SELECT 'index|'||i.relname, md5(pg_get_indexdef(i.oid)) FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid WHERE i.relnamespace=(SELECT oid FROM n)
UNION ALL SELECT 'policy|'||c.relname||'.'||p.polname, md5(p.polcmd::text||':'||p.polpermissive||':'||array_to_string(ARRAY(SELECT rolname FROM pg_roles WHERE oid=ANY(p.polroles) ORDER BY 1),',')||':'||coalesce(pg_get_expr(p.polqual,p.polrelid),'')||':'||coalesce(pg_get_expr(p.polwithcheck,p.polrelid),''))
  FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid WHERE c.relnamespace=(SELECT oid FROM n)
UNION ALL SELECT 'grant|'||c.relname||'.'||r.rolname, md5(array_to_string(ARRAY(SELECT a.privilege_type FROM aclexplode(c.relacl) a WHERE a.grantee=r.oid ORDER BY 1),','))
  FROM pg_class c CROSS JOIN pg_roles r WHERE c.relnamespace=(SELECT oid FROM n) AND c.relkind IN ('r','v','m','p','S') AND r.rolname IN ('anon','authenticated','service_role','public')
  AND EXISTS (SELECT 1 FROM aclexplode(c.relacl) a WHERE a.grantee=r.oid)
UNION ALL SELECT 'function|'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',
  md5(pg_get_functiondef(p.oid)||':exec_auth='||has_function_privilege('authenticated',p.oid,'EXECUTE')||':exec_anon='||has_function_privilege('anon',p.oid,'EXECUTE'))
  FROM pg_proc p WHERE p.pronamespace=(SELECT oid FROM n) AND p.prokind IN ('f','p')
UNION ALL SELECT 'trigger|'||c.relname||'.'||t.tgname, md5(pg_get_triggerdef(t.oid)) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relnamespace=(SELECT oid FROM n) AND NOT t.tgisinternal
ORDER BY 1;
SQL
}
snap b009_legacy > "$OUT/legacy.raw"; snap b009_mig > "$OUT/mig.raw"
sort "$OUT/legacy.raw" > "$OUT/legacy.tsv"; sort "$OUT/mig.raw" > "$OUT/mig.tsv"
if [ ! -s "$OUT/legacy.tsv" ] || [ ! -s "$OUT/mig.tsv" ]; then echo "B-009 FAIL: empty catalog snapshot"; exit 1; fi
ACC=tests/migrations/b009-accepted-drift.tsv; touch "$OUT/acc"; [ -f "$ACC" ] && grep -v '^#' "$ACC" | cut -f1 | sed '/^$/d' | sort -u > "$OUT/acc"
join -t $'\t' -a1 -e MISSING -o 0,1.2,2.2 "$OUT/legacy.tsv" "$OUT/mig.tsv" | awk -F'\t' '$2!=$3{print ($3=="MISSING"?"MISSING_IN_MIGRATIONS":"DIFFERENT")"\t"$1}' | sort -k2 > "$OUT/drift.tsv"
cut -f2 "$OUT/drift.tsv" | sort | comm -23 - "$OUT/acc" > "$OUT/unaccepted"
comm -13 <(cut -f1 "$OUT/legacy.tsv") <(cut -f1 "$OUT/mig.tsv") > "$OUT/only_mig"
stale=$(comm -13 <(cut -f2 "$OUT/drift.tsv" | sort) "$OUT/acc" | wc -l)
echo "B-009 legacy objects: $(wc -l <"$OUT/legacy.tsv")  migration objects: $(wc -l <"$OUT/mig.tsv")"
echo "drift: $(wc -l <"$OUT/drift.tsv") (accepted $(( $(wc -l <"$OUT/drift.tsv") - $(wc -l <"$OUT/unaccepted") )), unaccepted $(wc -l <"$OUT/unaccepted"), stale accept lines $stale)  only-in-migrations: $(wc -l <"$OUT/only_mig")"
awk -F'\t' '{split($2,k,"|"); c[$1" "k[1]]++} END{for(x in c) print "  "x": "c[x]}' "$OUT/drift.tsv" | sort
if [ -s "$OUT/unaccepted" ]; then echo "UNACCEPTED DRIFT (first 40):"; grep -F -f "$OUT/unaccepted" "$OUT/drift.tsv" | head -40; exit 1; fi
if [ "$stale" -gt 0 ]; then echo "Accepted-drift entries that no longer drift; remove them:"; comm -13 <(cut -f2 "$OUT/drift.tsv" | sort) "$OUT/acc"; exit 1; fi
echo "B-009 PASS"
