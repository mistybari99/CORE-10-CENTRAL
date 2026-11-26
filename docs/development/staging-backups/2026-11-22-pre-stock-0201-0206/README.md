# CORE10 TEST-ONLY STAGING — pre 0201–0206 Stock/Procurement backup (2026-11-22)

Project ref **rhrqhbyzrhaafynfhdaf**, schema **core10**, PostgreSQL 17. CORE10 non-production staging only. No access to IMG-ERP-SG or any other Supabase project.

## Snapshot
- `rows.json` is a **read-only logical snapshot** of 30 impacted/related `core10` base tables, Git blob `59bf00bbcda44cc1e99f5dda3b5c04428235c710`, 69,311 UTF-8 bytes.
- Pre-cutover ledger: **40 applied migration rows, max `0200`**. Zero stock balances and zero stock movements. Four Owner-demo Master items, three UOMs, two parties, 7 total sites (4 Owner-demo), 4 existing locations (all are the Owner demo's per-site MAIN locations), 23 canonical Audit rows. Includes item, Master request, Control versions, audit-chain and ledger rows in source form.
- Excludes `auth` schema, Auth sessions/users credentials and JWTs, service-role secrets, third-party account data; contents scanned for obvious secret marker names before saving.
- This is **NOT** a complete `pg_dump`, full DDL backup, PITR point or guaranteed restore procedure. Supabase-managed backup / separately reviewed restore is needed to recover a failure. Never disable immutable Audit or restore by deleting live audit rows.
- Earlier snapshots: `2026-11-22-pre-go2`, `2026-11-22-pre-d063`, `2026-11-22-pre-master-stock`.

## Intended cutover
Original Claude-owned Draft PR #123 head `54bc588978c885ee5a93df53536bbea64234fef7`; exact 34 changed-file Git blobs re-based (no conflicting paths) on current trunk at `591603a817efd38cdcdf54b995f0c6c06fa32c1c` in integration Draft PR #129, head `f525cab2272d91b40ed2e572b461afbf9e1e529b`. Six source-head workflow suites PASS and six candidate-head workflow suites PASS after rebase.

Against existing CORE10 staging rows, exact 0201–0206 source code inside `BEGIN/ROLLBACK` succeeded with signed Owner `owner_portfolio_v1`, `owner_business_sites_v1`, and existing Master Data read. A separate `BEGIN/ROLLBACK` used the real Owner session with one synthetic test stock location and existing Owner demo Sugar item: canonical `create_inventory_command_v1(receive)` → confirm → post → balance 25, replay idempotency PASS and cross-tenant 9801 read denied. Rolled back without persisting any location, stock, command, posting, or new migration.

To deploy after acceptance: assert current hosted ledger max `0200`, backup complete, run migrations `0201` through `0206` one per committed transaction and insert matching exact-source SHA256 in `core10.schema_migrations`. Reverify ledger/Owner signed positive and RLS negatives; do not mix arbitrary repair SQL or touch higher version until this succeeds. Do not publish Owner Stock UI as signed/live until real browser gate passes.

Note: Readback correction (2026-11-22): Owner-demo business 3 already had **four** `stock_locations`, MAIN at site IDs 5, 6, 7 and 8 (location IDs 5–8). This was confirmed by signed/SQL readback after hosted migration. No new/duplicate location was created.

## Actual hosted outcome, 2026-11-22

The earlier draft preflight text above describes the **historical** candidate. Final exact-head integration PR #129 was subsequently security-hardened (permission recheck after row lock in 0201/0203/0206; real two-session revocation regression) and merged at `ac86ee809157af13458b5607132f00a3d72caec9`. All six workflows PASS at hardened final `e6ea21003da828a53db5c464c1f20281f5686b4f`. The original Claude PR #123 was not modified.

The final 0201–0206 code was rehearsed as a group on real staging data inside `BEGIN/ROLLBACK` with signed Owner inventory receive/confirm/post and cross-tenant denial. After backup, all six migrations were applied in numeric order, **one transaction per file with SHA256 exact SQL + `core10.schema_migrations` row**. Final ledger 46 rows, max 0206.

Expected checksums (exact final migration bytes):
| Version | SHA256 |
|---|---|
| 0201 | `c044c87be240ddb34f38a4de54f7937d80589a436be2d83018cd4578382c2d90` |
| 0202 | `8346af72fe899e25181c5807a0c898627fd6603b41b95d3db1059cbd28040e19` |
| 0203 | `0e593d16373366d7dc5686561168aa23351300745906ed008286f1b97b4a85d3` |
| 0204 | `fd74c952e6a8ee77a16b3ebb0d8f18f4ffe90050559b939715ea8cefad7be0c8` |
| 0205 | `0e353c3a0877dd3422f0e762d295b9e82c29a4d3eac130efc214529613bf440a` |
| 0206 | `1b9078224e02b108e18f9bff695497c9052e7d331361811a9234bf51c6d47d12` |

An Owner-signed TEST ONLY fixture (business3) was then created **through canonical Stock RPCs**, not direct balance DML: six posted commands, eight ledger movements (two transfers each generate two movements), six location/item balance rows, zero unreconciled. Four old site locations reused, Master data intact. No production, IMG-ERP-SG, Finance ledger or human external business activity.
