# CORE10 canonical migrations (DEC-01)

Engine tables and RPCs live in schema `core10`. The former `c10_demo` schema name was retired in
S1-a (one mechanical rename of the whole integrated line); synthetic fixtures are rows loaded by
tests, not a separate schema. The protected legacy IMG-ERP-SG `public` schema is never a target (D051).

| Rule | Detail |
| --- | --- |
| File name | `NNNN_<pack>_<name>.up.sql` plus matching `.down.sql`; numbers contiguous from `0001` |
| Immutability | An applied `up` file is never edited; the runner stops on `CHECKSUM_DRIFT`. Fix forward with a new number |
| Ledger | `core10.schema_migrations` (version, name, checksum, applied_at, applied_by) |
| Tables | `tenant_id` + `business_id` (and `site_id` where relevant), RLS enabled, `REVOKE ALL … FROM PUBLIC` |
| Access | Versioned `SECURITY DEFINER` RPCs with pinned `search_path`, calling the Auth port |
| RPC versions | Keep `_v1`; a breaking change ships as `_v2` and the old one stays until callers move |
| Proof | `tests/migrations/run-updownup.sh` on a disposable database: up → full down → up |
| Hosted databases | Applying to any hosted database needs a separate Owner GO |

```bash
node --test tests/migrations/migration-contract.test.js     # static contract
PGHOST=… PGUSER=… PGDATABASE=… internal/migrations/run.sh up|down|status
```

Converting engine files to numbered migrations: the engine SQL still loads from
`internal/enterprise-sql/*.sql` in the order the test harness uses. Each file becomes a numbered
migration with a rollback in wave order (S1 access → S2 master data → S3 stock → S4 sales →
S5 finance); until then `0001` and the engine files are not applied to the same database
(`c10_a018_demo_backend.sql` still creates the schema itself in disposable test databases).
Side Draft PRs written against `c10_demo` apply the same rename when they are reconciled.
