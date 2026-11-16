# CORE10 canonical migrations (DEC-01)

Engine tables and RPCs live in schema `core10`. `c10_demo` is fixture/test only. The protected
legacy IMG-ERP-SG `public` schema is never a target (D051).

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

Porting a module from `c10_demo` to `core10` is one numbered migration per module, in wave order
(S1 access → S2 master data → S3 stock → S4 sales → S5 finance), keeping the module prefix
(`wf_`, `am_`, `a056_`) and re-running that module's existing test suite against `core10`.
