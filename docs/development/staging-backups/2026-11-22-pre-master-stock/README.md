# CORE10 staging — pre-Master 0150–0153 + Stock 0200 logical snapshot

Target: CORE10 non-production Supabase `rhrqhbyzrhaafynfhdaf`, project `core10` schema. Source snapshot captured 2026-11-22 **after** successful D063 0115–0118 staging apply and signed Owner bootstrap activation.

`rows.json` contains 14 scoped core10 tables' exact JSON rows, Git blob `e05f1ca22344765e7d3dfe574360229c00b20b74` (27436 bytes); no auth users/sessions/passwords/keys or emails. Ledger: 35 rows, max `0118`. Current existing synthetic businesses: 3, sites: 7, canonical audit: 9, Owner signed tenant bootstrap policy version: 1. Previous targeted snapshot `2026-11-22-pre-d063` and full catalog/rows snapshot `2026-11-22-pre-go2` are retained.

This is a targeted logical backup, **not a full restorable physical backup**. Managed backups remain recovery fallback; never disable immutable Audit guards, change old migration bytes or move to old IMG-ERP-SG.

The numeric rollout sequence: 0150, 0151, 0152, 0153, 0200. All sources must be exact canonical trunk and recorded with SHA256 checksums in `core10.schema_migrations`, one committed transaction per file. Confirm setup/auth unaffected and inspect control registry after each apply.

**Hold 0400+** if unintegrated Sales 0300–0306 cannot be safely applied first; hosted numeric order matters and any skipped lower-version migration will be permanently out of order. No actual FINANCE or Manufacturing production posts are authorized at this stage.
