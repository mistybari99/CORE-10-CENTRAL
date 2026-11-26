# CORE10 staging safety snapshot before D063 0115–0118 (2026-11-22)

Target database: ONLY Supabase `rhrqhbyzrhaafynfhdaf`, PostgreSQL 17.11, schema `core10`. Synthetic TEST data; **NOT** IMG-ERP-SG, production, or other Supabase projects.

## Data backup
`rows.json`: exact `to_jsonb` row projections captured READ ONLY immediately before 0115, 14 selected directly impacted / linked tables. Original auth.users, auth.sessions, passwords, API keys, and secrets are NOT included. No email addresses. Git blob `b607cabf0a6803bd286d57d1dfed67e92aa4d22b`, data bytes 24417.

Verified pre-migration baseline counts:
- 3 tenants, 3 tenant members, 3 legal entities, 3 businesses, 7 sites, 4 stock locations
- 1 setup run, 1 business configuration, 7 business module settings
- 6 access-change events, 8 immutable canonical audit events, 2 audit chain heads
- 0 control-setting versions, migration ledger 31 entries, highest applied 0114

This is a **targeted logical row snapshot**, not a full `pg_dump` or full restorable cluster backup. Existing `docs/development/staging-backups/2026-11-22-pre-go2/` includes the earlier catalog and schema snapshot; Supabase's managed backups are a separate safety layer. For rollback or restore, never DELETE immutable audit or disable audit triggers; require a reviewed restore procedure using database backups.

## Rehearsal
Original 0115–0118 D063 migrations (exact PR #121 blobs integrated on trunk under PR #127) were executed against **current staging rows inside BEGIN/ROLLBACK**. DB readback showed Owner's existing tenant starts `bootstrap_policy_initialized=false`; the new provision-site capacity guard exists during the transaction. A separate `BEGIN/ROLLBACK` proved the Owner's existing *signed session* can call `control_set_bootstrap_policy_v1(1,true,NULL,0,...)`, producing version 1 and a canonical tenant audit entry **within the rolled-back transaction**. No D063 rows were permanently applied during these rehearsals.

IMPORTANT: 0116 activates the signed bootstrap check; Owner's existing tenant must be opted in **atomically with 0116** or existing business setup is denied until the Owner acts. 0118 introduces a default **50-site cap**, with Owner Business Control options to raise it to 100–400. Never assert the pre-D063 400-site stress test applies to 0118 without the approved per-business cap.

Numeric versioning, checksum ledger, per-file one transaction, unchanged old migration files and cross-tenant tests remain mandatory. Do not apply any higher migration until D063 passed and Owner sign-in reverified.
