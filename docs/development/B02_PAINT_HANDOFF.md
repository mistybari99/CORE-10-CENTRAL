# B02-Paint isolated candidate — 2026-11-26 (RELEASE HOLD)

**Mission:** C10-CAP-PAINT-001 / NPACK-09, source-backed recovery only. Original PR #95 remains untouched; B02 is not the original PR's writer or the canonical integrator.

- Canonical base: `3e008e8ec7db896f46a94ab8ca3d91271905d71d` (`ccr-15ed11dd-n3hw5h`).
- Source: PR #95 `dea1c3f78d6a0c4c08280458038cd0b86ad5769e`; source CI run 43259459019 is historical, not B02 validation.
- Exact byte-identical 12-file recovery commit: `888f62d4ec3d65047e48e8e99ebee05a36d21691`. The original 12 Git blob SHA1 values and SHA256 of each file are retained in CP001.
- Own branch: `build/chatgpt-b02-paint-20261126`; Draft PR #161 targets trunk. Board claim `B02-PAINT-01` row 52. Main-owned RC1 archive and readback-verified publication index are linked below.

## Bounded functional corrections

1. Detail 275 (principal purchase schemes), and dependent 276 (claim settlement): original preview compared unvalidated `invoice.date` lexically, allowing missing dates to become eligible. Apply the existing ISO calendar validator to invoice date, preserve both inclusive scheme boundaries, and reject invoices dated after the requested as-of date. Invalid calendar input now has a stable `INVALID_ISO_DATE` domain error rather than a RangeError. Estimates remain nonposting; do not alter eligibility/rounding/rates or canonical source policy.
2. Detail 280 (hardware serial and warranty): original code assigned sale reference before validating date and customer reference, leaving an unsold serial partially mutated after a rejected sale snapshot. Validate all evidence fields before applying any change, so corrected evidence can be linked normally. No real sale or warranty authority is introduced.
3. New deterministic `b02-functional.test.mjs`: date/boundary/claim rejection and corrected retry, warranty atomicity/retry, and ordinary loopback QC fail/rework/pass/quote/reset flow with synthetic fixtures. Before correction: 3 expected failing regressions, 1 ordinary walkthrough passed. After correction: all 18 selected existing/new ordinary tests passed (exit 0) on Node v22.16.0.

## Reproduction

```sh
P=internal/industry-packs/paint-hardware-v1
node --test --test-name-pattern='recipe version|QC failure|incomplete mix|quoted paisa|defensive reads|4-litre sealed pack|dealer credit exposure|principal scheme estimated|claim submitted|postdated cheque|SDS expiry|returned tint|hardware serial|profit report|B02' "$P/core.test.mjs" "$P/dealership.test.mjs" "$P/b02-functional.test.mjs"
```

Existing tests were not weakened or deleted. Restricted security tests, disposable PG17 suite, signed staging and full browser viewport acceptance were not executed here. No shared CI change; check PR exact-head CI separately, do not infer it from source CI. Lab HTTP walkthrough is not browser 390/1440 proof.

## Preserved scope and dependency gates

Decision Book rows 270–281 remain NOT_CERTIFIED_PER_DETAIL; 520 gap sheet's side-draft classifications remain historical. Existing recipe/volume/QC/quote, pack conversion, dealer credit, scheme/claims, PDC, SDS, return quarantine, serial warranty and conservative report were recovered, not independently rebuilt. All JS remains synthetic, memory-only and nonposting; the recovered disposable SQL is historical, not a canonical migration. No B01 or other builder files, original PR95, canonical trunk, main/preview, protected legacy, hosted DB, real stock/payment/GL, deployment or security retest were changed. No production certification or integration-ready status.

Next cursor: inspect the pack-local QC evidence model against approved row 272 (method/tolerance/evidence history); if source-supported and non-overlapping, prove missing functionality with ordinary regression before changing it. Other source-supported refinements to return disposition/reporting need concrete evidence; no new thresholds or owner policy assumptions. Canonical signed auth/Control, Master item/UOM, Stock/WIP measured yield and return/serial posting, Sales 030x, Finance 040x (real reconciliation and cost), Manufacturing 050x, durable audited workflow/attachments, and role-guided app integration remain dependency-owned or release-blocked. Review the current Board, branch, PR95 and active changed paths before the next increment. Separate Owner GO for integration and hosted acceptance.

Main-owned archive: https://drive.google.com/drive/folders/1QqvZTkrjBqIJd18KRcxQF2AxmFztLVD6
Shared index: https://docs.google.com/document/d/1nn6i13AdiG71RE0qhXv7i2Ye-nZLWo626YD3ScJqmn4/edit

## CP003 — Detail 272 QC evidence increment

Parent tested head `54e61aaaf007a9efe9799e9023735d60477d0e9c`; restored CP002 verified 24/24 manifest entries and 14/14 Git blobs. Decision Book MODULE BUILD DETAIL row 272 requires method, tolerance and reviewer, and flags uncalibrated instrument/hidden rework; recovered disposable SQL already uses `method`, `instrumentRef`, `calibrated` (mock only). Node previously accepted QC without those fields and retained neither method nor threshold in QC history. The new implementation requires the existing SQL-shaped method/instrument refs and a boolean true fixture calibration assertion, validates before mutation, and preserves each check with actual delta E, pinned recipe/version threshold, mix round, reviewer, evidence ref and result in the ticket and local event history. Proposal includes the same last check and remains nonposting. The existing demo displays method, measured value/threshold, reviewer and failed/rework/pass history. Calibration remains explicitly `SYNTHETIC_ASSERTION_ONLY`; no real certification, new thresholds, SQL changes or auth policy changes. Existing fixture inputs updated only where needed; original assertions preserved.

Reproduce (Node v22.16.0):

```sh
P=internal/industry-packs/paint-hardware-v1
node --test --test-name-pattern='recipe version|QC failure|incomplete mix|quoted paisa|defensive reads|4-litre sealed pack|dealer credit exposure|principal scheme estimated|claim submitted|postdated cheque|SDS expiry|returned tint|hardware serial|profit report|B02' "$P/core.test.mjs" "$P/dealership.test.mjs" "$P/b02-functional.test.mjs" "$P/b02-qc-evidence.test.mjs"
```

Before fix: 3/3 new regressions failed (exit 1). After fix: 21/21 selected ordinary tests pass (exit 0); includes loopback HTTP and evidence history. `node --check` core and lab JS pass. No restricted security tests, PG17, signed staging or viewport browser acceptance run; no exact-head CI result inferred. Next: inspect source-backed Detail 279 return/disposition and Detail 281 profitability evidence, prove concrete functional gaps before repair; do not invent owner policy. RELEASE HOLD.

## CP004 — Details 279 and 281 return / profitability evidence

Parent `46b493942e57c5f312aecdba70ac65c8e47e42b0`; CP003 ZIP and receipt SHA256 matched and 33 manifest entries verified. Decision Book row 279 requires preserved original genealogy and quarantine; row 281 requires explainable separation of margin, pending rebates, credit and incomplete costs, including hidden returns/missing freight negatives. Return records now copy pinned recipe version, base SKU/volume, all mix rounds and all QC checks from the original passed tint ticket. The quarantine event records source ticket/recipe/version/QC reference and reason/evidence. Disposition remains review-only, never saleable or refunded. No new partial-return, refund, or disposal policy. Profitability now exposes gross sales and returns separately, keeps the same net-sales/margin formula, explains missing certification and freight separately, and labels source authenticity synthetic/unproven. Neither rebate estimate nor receipt evidence enters gross margin. Actual cash/net profit remain unknown. No change to canonical ledgers or posting.

Three new ordinary tests fail on unchanged CP003, all 24 selected ordinary tests pass on correction (Node 22.16.0). Reproduce using CP003 command with additional `"$P/b02-return-profit.test.mjs"`. No existing assertion removed. No full browser, PG17, signed staging or exact-head CI proof. All 12 details remain NOT_CERTIFIED_PER_DETAIL. Next: bounded remaining pack-local acceptance inventory and verified functional gaps; if none, hand off to canonical integration owner, not endless synthetic refinements. RELEASE HOLD.
