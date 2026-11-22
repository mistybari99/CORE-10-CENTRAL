# Staging rhrqhbyzrhaafynfhdaf — pre-GO-2 snapshot (2026-11-22)

Read-only snapshot of schema `core10` taken via the Supabase Management API before applying 0013–0019, 0100–0106, 0110–0114.
State at snapshot: ledger 0001–0012 (checksums equal to trunk files), synthetic staging data only (2 tenants, UUIDs, no emails).

| File | Content |
|---|---|
| functions.json / function-acl.json | `pg_get_functiondef` of every core10 function; ACL, SECURITY DEFINER, proconfig |
| triggers.json, policies.json, views.json | trigger, RLS policy and view definitions |
| columns.json, constraints.json, acl.json | table columns/defaults, constraints, table ACL + RLS flag |
| rows.json | every row of every core10 table (27 tables) |
| apply-log.txt | per-file apply result + sha256 written to `core10.schema_migrations` |

Second net: Supabase daily backup. Rollback path: `internal/migrations/*.down.sql` newest-first (run.sh down semantics), then restore rows from rows.json if needed.
