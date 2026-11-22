# CORE10 Owner staging — demo setup and signed Master Data (2026-11-22)

## Scope
Only CORE10 staging `rhrqhbyzrhaafynfhdaf` (schema `core10`). All records are synthetic test data, not real trading/financial postings. Separate legacy IMG-ERP-SG and other Supabase projects remain untouched.

## Existing business and sample data
- Tenant `core10-owner-group` ID 1, legal entity 1, Owner tenant_owner.
- Draft business ID 3 `core10-demo-sweets-20261122`, `CORE10 DEMO Sweets (TEST ONLY)`, sweets_bakery template.
- Four sites: Demo Showroom, Demo Factory, Demo Warehouse, and Owner-created trial showroom `ASIAN Paint` (belongs to the sweets demo, not a separate business).
- Four items: `DEMO-RASGULLA` (রসগোল্লা), `DEMO-SANDESH` (সন্দেশ), `DEMO-SUGAR` (চিনি), `DEMO-MILK` (দুধ); three UOMs PCS/KG/BOX, two categories, two demo parties, one BDT retail price list, two test prices. Saved via signed canonical Master RPCs.
- Synthetic tenants 9801/9802 retain separate businesses and cannot read Owner Master records (negative SQL test PASS).

## Mobile workflow
1. [Signed Business Setup](https://core10-central.mistybari99.workers.dev/#/setup): sign in with existing Owner staging account; screenshot previously verified login and four-site selector.
2. [Signed Master Data](https://core10-central.mistybari99.workers.dev/#/master): same CORE10 staging Auth session may be reused, otherwise sign in. This route is signed database-backed, not recorded replay.
3. Select the DEMO Sweets business. Search `রসগোল্লা`, inspect the four seeded items, UOMs, dummy parties and price list, and test an authorized edit. Human Owner mobile Master edit is still pending acceptance; full automated browser and signed database tests PASS.
4. Never use these dummy SKUs for live commercial stock/accounting.

## Reset
Fresh = a new clean TEST ONLY business instance, not erasure of previously audited events. CLI `node scripts/staging/create-fresh-owner-demo.mjs --fresh` uses protected environment credentials, the exact CORE10 staging endpoint and signed setup RPC, then verifies three sites. Mocked unit tests 5/5 PASS; networked Owner CLI acceptance remains untested. A manual new business in signed `/#/setup` also works. Do not hard-delete immutable audit records or bypass triggers. True archive/delete requires a separate tested forward migration and retention approval.

## What is verified and what remains
- Staging ledger: 46 versions, last `0206`; D063 0115–0118, Master 0150–0153 and Stock foundation 0200 and operational Stock/Procurement migrations 0201–0206 applied by numeric order and exact-file SHA256. Owner bootstrap policy initialized at 0116.
- Scoped backup evidence: `docs/development/staging-backups/2026-11-22-pre-go2`, `2026-11-22-pre-d063`, `2026-11-22-pre-master-stock`. These logical snapshots do not replace a full database restore.
- Cloudflare Worker `core10-central`: version `4b6d179c-e1aa-4066-9fb6-6988dbc32432`, bundle SHA256 `3ae944b1cdcb49f4701457d629e99b61f4acff32fff7b77e2713d3f16568fc28`, local real Chromium `44991383787` **50/50 PASS**, live URL CI `44991642473` **50/50 PASS**. Previous stable rollback version `ceeea069-d630-460a-b1f0-5b12e5157da9`.
- Sales/Manufacturing pages are recorded replay only; Stock has signed canonical receive/transfer/PO/GRN/QC backend and synthetic posted inventory sample; write UI not yet released; Finance 0400+ not hosted. No production certification. D063 post-cutover site limit defaults to 50; auditable per-business Owner Control cap increase and new stress tests needed for 100–400.

## Post-D063 50/400 Site capacity evidence (2026-11-22)

Executed against real CORE10 staging PG17 with Owner's existing session, **without permanent writes**:
- Default cap: 4 existing Owner demo sites plus 46 new sites = 50 PASS; attempted site 51 was rejected with `CONTROL_LIMIT:max_sites`.
- Applied audited per-business Owner Control `setup001.provision` with `{"max_sites":400}` version 1 in a trial transaction; 396 new sites brought the total to 400 PASS; attempted site 401 rejected with the same limit error.
- Both transactions used `BEGIN/ROLLBACK`; follow-up SQL confirmed Owner demo has exactly 4 sites, 0 business-specific cap settings; ledger remains 40/max `0200`. This validates database/business-rule capacity, **not** phone usability or high-concurrency production scale.

## 2026-11-22 Stock/Procurement and Owner Business dashboard — synthetic acceptance

- Integration Draft PR #129 ([exact diff](https://github.com/mistybari99/CORE-10-CENTRAL/pull/129)) was security-hardened against permission revocation *after acquiring a row lock*, with a real two-session membership-revocation race test, then merged to canonical trunk at `ac86ee809157af13458b5607132f00a3d72caec9` (six exact-head CI workflows PASS). Original Claude Stock PR #123 remains unmodified.
- Before apply: [scoped 30-table backup](staging-backups/2026-11-22-pre-stock-0201-0206/README.md). Six exact numbered migrations 0201–0206 were applied to the **same CORE10 staging database**, one transaction + SHA256 ledger each. Ledger now **46, maximum 0206**. Owner signed stock receive→confirm→post and cross-tenant 9801 denial PASS in transactional rehearsal.
- Signed Owner business `CORE10 DEMO Sweets (TEST ONLY)` #3 already had four `MAIN` stock locations corresponding to each of its four sites. No duplicate location was inserted.
- **Persisted six TEST ONLY stock posts, eight stock movements, six balance rows, zero unreconciled**. Examples: Demo Warehouse (site 7) **Sugar 25 KG, Milk 10 KG**; Demo Factory (site 6) **Rasgulla 20 PCS, Sandesh 15 PCS**; Demo Showroom (site 5) **Rasgulla 10 PCS, Sandesh 5 PCS**. Factory→Showroom transfers happened through the canonical inventory command RPC. `ASIAN Paint` trial showroom (site 8) has no stock movement.
- Owner dashboard route `/#/business` is now configured to call signed read-only canonical `owner_portfolio_v1`, `owner_business_sites_v1`, `inventory_list_balances_v1`, `inventory_list_commands_v1`, `procurement_list_pos_v1`; it is **LIVE read-only** after Cloudflare post-deploy gate `44996166820` **50/50 PASS**. Active Worker `2d9894b8-279d-4772-91f6-be46a54d98e3`, local Chromium `44995895627` 50/50 PASS, public live `44996166820` 50/50 PASS, previous validated rollback Worker `4b6d179c-e1aa-4066-9fb6-6988dbc32432`. This screen is view-only and requires a signed Owner session; if signed out, use `/#/control` first.
- Stock/Procurement write screen still needs the next build. Sales, Finance and Manufacturing operational releases still held. No actual business turnover, payments, valuation, invoices or independent user training performed.

Owner opens the [read-only signed Business/Stock dashboard](https://core10-central.mistybari99.workers.dev/#/business); if prompted to sign in, visit [Owner Control](https://core10-central.mistybari99.workers.dev/#/control) first. This is read-only **even though** the underlying Stock RPC writers exist; the signed Stock command workbench is a separate next step.
