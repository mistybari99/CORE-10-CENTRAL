# C10-A037 Production Costing, COGS & Inventory Valuation (Claude Build 2)

Status: BUILT and TESTED IN ISOLATION (disposable PostgreSQL). NOT integrated, NOT staging-verified, NOT released,
NOT audited accounting. Nothing was run against IMG-ERP-SG. Synthetic signed JWTs are not real Supabase Auth proof.

Files (owned paths only): `scripts/c10_a037_costing_engine_v1.sql`, `tests/c10_a037_costing_e2e.sql`,
`tests/c10_a037_costing_rest_seed.sql`, `tests/api/c10-a037-costing-rest-e2e.js`,
`.github/workflows/core10-a037-costing-ci.yml`, this file.

## Rule (deterministic)
Moving weighted average per (location, item). Immutable journal `cost_events_v1`; `cost_valuation_v1` is a projection
changed only by the SECURITY DEFINER posting functions. Precision: qty numeric(15,3), unit cost numeric(18,6), value numeric(20,4).

| Flow | Source (verified) | Effect |
|---|---|---|
| Purchase receipt | POSTED `purchase` operational document | value = line amount less pro-rata document discount (last line takes rounding remainder) |
| Production | POSTED batch + BOM; ingredients costed by verified purchase/production events | ingredients issued at average; output = ingredients + owner-REFERENCED overhead; price/overhead/yield variances stored |
| Sale COGS | POSTED `sale` document | qty x average, snapshotted per line; margin view |
| Transfer | `stock_transfers_v1` | moves cost at source average, never revenue |
| Return | POSTED sale return | reverses at ORIGINAL snapshot unit cost, bounded by costed qty |

BLOCK rule: when verified cost does not cover the quantity (uncosted opening stock, manual rates, unposted source, actual yield
different from posted stock, overhead without reference) nothing is written; a reasoned `status:'blocked'` JSON is returned and
the reconciliation view names the uncosted quantity. Manual `item_cost_rates_v1` are never used for certified COGS.

## Security
Posting and reading costs: tenant owner / business owner only (`can_manage`). Manager, investor, site staff, revoked, other tenant,
anon: denied. No DML grants for API roles; ledger rows cannot be updated/deleted/truncated by anyone (trigger). Internal appliers are
not executable by API roles. No secret keys, no production grants.

## Tests
`tests/c10_a037_costing_e2e.sql` (accounting math, BLOCK cases, idempotency, immutability, role matrix) and the signed-JWT HTTP test
with 12 parallel same-document and 12 parallel distinct-document postings. Local PG16 run of the SQL test: PASS; negative controls
(owner guard removed, BLOCK rule disabled) make it fail. The HTTP test runs in CI only (PostgREST/docker).

## Limitations (not done)
Tax/VAT, WIP between start and finish, purchase-return costing, ingredient lots/FIFO, wastage/packaging, legacy Supabase item
migration, real Supabase Auth users, UI. Do not present as live or audited.
