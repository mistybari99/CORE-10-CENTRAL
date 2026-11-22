# CORE10 TEST-ONLY STAGING — pre 0201–0206 Stock/Procurement backup (2026-11-22)

Project ref **rhrqhbyzrhaafynfhdaf**, schema **core10**, PostgreSQL 17. CORE10 non-production staging only. No access to IMG-ERP-SG or any other Supabase project.

## Snapshot
- `rows.json` is a **read-only logical snapshot** of 30 impacted/related `core10` base tables, Git blob `59bf00bbcda44cc1e99f5dda3b5c04428235c710`, 69,311 UTF-8 bytes.
- Pre-cutover ledger: **40 applied migration rows, max `0200`**. Zero stock balances and zero stock movements. Four Owner-demo Master items, three UOMs, two parties, 7 total sites (4 Owner-demo), 4 existing locations (not in the Owner demo), 23 canonical Audit rows. Includes item, Master request, Control versions, audit-chain and ledger rows in source form.
- Excludes `auth` schema, Auth sessions/users credentials and JWTs, service-role secrets, third-party account data; contents scanned for obvious secret marker names before saving.
- This is **NOT** a complete `pg_dump`, full DDL backup, PITR point or guaranteed restore procedure. Supabase-managed backup / separately reviewed restore is needed to recover a failure. Never disable immutable Audit or restore by deleting live audit rows.
- Earlier snapshots: `2026-11-22-pre-go2`, `2026-11-22-pre-d063`, `2026-11-22-pre-master-stock`.

## Intended cutover
Original Claude-owned Draft PR #123 head `54bc588978c885ee5a93df53536bbea64234fef7`; exact 34 changed-file Git blobs re-based (no conflicting paths) on current trunk at `591603a817efd38cdcdf54b995f0c6c06fa32c1c` in integration Draft PR #129, head `f525cab2272d91b40ed2e572b461afbf9e1e529b`. Six source-head workflow suites PASS and six candidate-head workflow suites PASS after rebase.

Against existing CORE10 staging rows, exact 0201–0206 source code inside `BEGIN/ROLLBACK` succeeded with signed Owner `owner_portfolio_v1`, `owner_business_sites_v1`, and existing Master Data read. A separate `BEGIN/ROLLBACK` used the real Owner session with one synthetic test stock location and existing Owner demo Sugar item: canonical `create_inventory_command_v1(receive)` → confirm → post → balance 25, replay idempotency PASS and cross-tenant 9801 read denied. Rolled back without persisting any location, stock, command, posting, or new migration.

To deploy after acceptance: assert current hosted ledger max `0200`, backup complete, run migrations `0201` through `0206` one per committed transaction and insert matching exact-source SHA256 in `core10.schema_migrations`. Reverify ledger/Owner signed positive and RLS negatives; do not mix arbitrary repair SQL or touch higher version until this succeeds. Do not publish Owner Stock UI as signed/live until real browser gate passes.

Note: Existing Owner-demo business 3 has 4 sites but **no `stock_locations` yet**. Do not claim inventory operations usable for that business until a reviewed canonical stock-location provisioning workflow or a clearly labeled staging-only Owner fixture creates suitable locations.
