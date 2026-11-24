# CORE10 TEST-ONLY STAGING — pre Sales 0300–0305 backup (2026-11-24)

Project ref **rhrqhbyzrhaafynfhdaf**, schema **core10**, PostgreSQL 17. Staging is non-production. IMG-ERP-SG and all other projects were not touched.

## Snapshot
- `rows.json` is a read-only logical snapshot of all 53 `core10` base tables (348 rows), taken at 2026-11-24 06:08 UTC.
- Ledger: 46 rows, max `0206`. Every checksum matches the trunk file bytes (no drift).
- The `auth` schema, credentials, JWTs and service keys are not included. The file was scanned for secret markers: 0 hits.
- This is not a `pg_dump` or a PITR point.

## Rehearsal (local PG17)
- Steps:
  - Apply 0001–0206.
  - Load these rows; all 53 table counts match staging.
  - Apply 0300–0305 with `run.sh`.
- Result: all six migrations PASS, with ledger checksums equal to the file sha256.
- Control registry check PASS: 42 enforced, 8 exempt, 0 pending.
- Data changes: only the expected Sales `control_catalog_v1` and `control_rpc_map_v1` rows.

## Staging apply (in progress)
- Method: each file is applied in one transaction containing:
  - an order guard (max version must equal the previous one);
  - the file text;
  - a ledger row with the file's sha256.
- After each file, a schema fingerprint is compared with the rehearsal DB stopped at the same step. It covers functions, columns, constraints, indexes, policies, triggers and ACLs.
- **0300: applied. All 7 fingerprints are equal to the rehearsal.**
- 0301: the call timed out waiting for Owner confirmation in the SQL tool. Before retrying, confirm that staging max is still 300.
- 0302–0305: not yet applied.
