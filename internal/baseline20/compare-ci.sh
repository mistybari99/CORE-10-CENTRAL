#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
: "${PGHOST:?}" "${PGUSER:?}" "${PGPASSWORD:?}" "${BASELINE_PG_CONTAINER:?}"
psql -X -v ON_ERROR_STOP=1 -c 'CREATE ROLE authenticated NOLOGIN; CREATE ROLE anon NOLOGIN;'
createdb core10_original71
createdb core10_np03b_ci_baseline20
PGDATABASE=core10_original71 bash internal/migrations/run.sh up
PGDATABASE=core10_np03b_ci_baseline20 CORE10_BASELINE_ALLOW_EMPTY=YES CORE10_BASELINE_EXPECT_DB=core10_np03b_ci_baseline20 bash internal/baseline20/run.sh
# Compare actual PostgreSQL schema with ACLs, RLS, constraints, function bodies, indexes, sequences, comments.
for db in core10_original71 core10_np03b_ci_baseline20; do
 docker exec "$BASELINE_PG_CONTAINER" pg_dump -U postgres -d "$db" --schema=core10 --schema-only | sed '/^\\restrict /d;/^\\unrestrict /d' > "/tmp/$db.schema"
 # Compare all table rows. Only the two known clock-generated timestamps are normalized.
 PGDATABASE="$db" psql -X -At -v ON_ERROR_STOP=1 -c "SELECT format('SELECT %L,coalesce(jsonb_agg(j ORDER BY j),''[]''::jsonb)::text FROM (SELECT to_jsonb(t)%s AS j FROM core10.%I t) q;',tablename,CASE tablename WHEN 'schema_migrations' THEN ' - ''applied_at''' WHEN 'control_catalog_v1' THEN ' - ''created_at''' ELSE '' END,tablename) FROM pg_tables WHERE schemaname='core10' ORDER BY tablename" | PGDATABASE="$db" psql -X -At -v ON_ERROR_STOP=1 > "/tmp/$db.rows"
 PGDATABASE="$db" psql -X -At -v ON_ERROR_STOP=1 -c "select sequencename,last_value from pg_sequences where schemaname='core10' order by sequencename" > "/tmp/$db.sequences"
done
diff -u /tmp/core10_original71.schema /tmp/core10_np03b_ci_baseline20.schema
diff -u /tmp/core10_original71.rows /tmp/core10_np03b_ci_baseline20.rows
diff -u /tmp/core10_original71.sequences /tmp/core10_np03b_ci_baseline20.sequences
echo BASELINE20_SCHEMA_SEEDS_SEQUENCES_EQUIVALENT
# A second baseline run must fail closed; original runner recognizes all source ledger checksums.
if PGDATABASE=core10_np03b_ci_baseline20 CORE10_BASELINE_ALLOW_EMPTY=YES CORE10_BASELINE_EXPECT_DB=core10_np03b_ci_baseline20 bash internal/baseline20/run.sh >/tmp/baseline-reapply.log 2>&1; then echo REAPPLY_NOT_REJECTED; exit 1; fi
grep -q CORE10_ALREADY_EXISTS /tmp/baseline-reapply.log
PGDATABASE=core10_np03b_ci_baseline20 bash internal/migrations/run.sh up
export PGDATABASE=core10_np03b_ci_baseline20
psql -X -v ON_ERROR_STOP=1 -f tests/migrations/control-registry-check.sql
for f in tests/migrations/np01-bootstrap-cutover-e2e.sql tests/migrations/np02-master-rpc-e2e.sql tests/migrations/np03a-procurement-e2e.sql tests/migrations/np03a-lots-e2e.sql tests/migrations/np03a-supplier-return-e2e.sql tests/migrations/np06-finance-e2e.sql tests/migrations/np06-finance-arap-e2e.sql tests/migrations/np06-sales-finance-bridge-e2e.sql tests/np05a/manufacturing-e2e.sql tests/np05a/canonical-master-e2e.sql; do
 echo "BASELINE20_E2E $f"; psql -X -q -v ON_ERROR_STOP=1 -f "$f"
done
echo BASELINE20_REGRESSION_PASS
