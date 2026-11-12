# Build 05 · Paint and Hardware industry pack · Draft Integration Handoff

This is **C10-CAP-PAINT-001**, existing Decision Book rows 270–281. Owner's latest instruction: continue Build05 in this single chat. Source ownership: `internal/industry-packs/paint-hardware-v1/` and dedicated CI only. **Codex still owns final reviewed integration/merge; do not auto-merge, deploy or change SG.**

## Actual executable code

`core.mjs` / `core.test.mjs`: versioned synthetic paint formula, 2.5L tint calculation, worker mix, independent QC, fail/rework, idempotent receipt, cross-tenant/business scope and nonposting dealer quote/proposal. Duplicate local ticket IDs are isolated by tenant+business.

`dealership.mjs` / `dealership.test.mjs`: sealed litres/4L pack pricing with no KG conflation; dealer credit exposure and limit using versioned outstanding+pending source snapshots; principal scheme effective dates, net-of-return eligible invoice rebates; separate submitted/approved/receipt-evidenced claim and reconciliation unknown; PDC instrument / maturity / bounce / clearance-evidence-only; SDS revision/expiry/hazard storage draft gate; quarantine and lineage of returned tint; hardware SKU+variant+serial and evidence-linked warranty; profitability showing only certified gross margin, pending rebates separately and unknown net profit.

**All data in these JavaScript modules is local memory, not durable enterprise storage.** Only `synthetic-only` contexts work; self-labelled `canonical-readonly` snapshots are synthetic test inputs and are **not** authenticated or guaranteed canonical. No customer data or actual payment is touched.

## Production-completion blockers — do not claim DONE

1. Persist all 12 details on existing canonical `c10_demo` business/site/tenant authorization with **signed GoTrue**, A034 effective grants and reviewer transitions, RLS, immutable audit and idempotency in PostgreSQL.
2. Exact canonical A048/A049 inventory consumption, yield, return and serial stock/WIP; do **not** build a shadow stock ledger. Handle production base/container/colorant quantities and missing density.
3. Actual posted and reversible sale, source-linked WAC COGS and **balanced** FIN-001 journal. Claim receipts require real bank/AR source reconciliation; never treat PDC or claimed rebate as cash.
4. Secure legally reviewed approved principal schemes, credit source, tax, SDS/unsafe shipment policy, controlled document storage and locale; no assumed Bangladesh VAT rates.
5. Guided BN/EN role-based Android 390px and desktop 1440px front-end, live stage accounts and revocation tests, concurrency/replay, backup and restore, hosted staging demo and Owner release.
6. Read-only reconciliation against existing legacy `tinting129.js`, `schemes128.js`, `cheques127.js`; never copy customized Islamia records/code into common industry template.

**Code status:** working isolated Node 22 source and negative tests after CI. **Decision Book status:** every one of 12 rows is **PLANNED_DETAIL_NOT_CERTIFIED**; full Paint industry module **NOT_COMPLETE_PER_DETAIL**.

## Codex verification / merge sequence
Run:
`node --test internal/industry-packs/paint-hardware-v1/*.test.mjs`

Read PR #95 exact tested head/CI and this README, reconcile Build01 #86 / Build02 #93 / Build03 #85 / Build04 #94 / A048 #49 / A049 #50, then integrate **one canonical signed transaction boundary** in a new staged merge. Preserve legacy D051/R130 and retain this PR Draft until signed E2E, production release authority and migration/rollback checks pass.

## Feature coverage ledger (not certification)
| Detail row | Synthetic coverage | Missing for production |
| --- | --- | --- |
| 270 | Versioned formula and pigment doses | Signed approval, obsolete shade, durable recipe |
| 271 | Mix/dose and rework | Canonical stock movements, real measured yield/density |
| 272 | Independent QC, evidence ref | Instrument calibration proof and signed QC record |
| 273 | 4L sealed pack and pricing | Canonical item/UOM, authorized cost/margin |
| 274 | Approved dealer terms, credit exposure preview | Signed AR snapshot and release authority |
| 275 | Versioned principal scheme, approved net invoice preview | Real approved invoices/schemes |
| 276 | Claim/approval/receipt evidence kept separate | Bank settlement/journal |
| 277 | PDC maturity/bounce/instrument | Bank reconciliation and allocation |
| 278 | SDS expiry, compatibility preview | Verified legal SDS and shipment enforcement |
| 279 | Source-linked tint return quarantine | Stock hold, refund/rework/disposal posting |
| 280 | SKU/variant/serial and warranty lineage | Signed source sale/stock |
| 281 | Net sales/certified gross margin, rebates separately | Fully reconciled costs, GL/net profit |
