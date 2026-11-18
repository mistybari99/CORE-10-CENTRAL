# NP06 / B-013 — Shared Finance CI unblock and F3 integration preflight

**Date:** 2026-11-18. **Authority:** code, CI and independent review preparation ONLY. **NO Owner merge GO, no GO-2 staging, no GO-3 deployment.**

## Canonical state (verify live before resuming)

- Repository: `mistybari99/CORE-10-CENTRAL`; Claude trunk: `ccr-15ed11dd-n3hw5h`. Initial latest verified trunk: `a82ae993b93c1460898b9022bb56b7a995d96437`.
- Finance F2 `0401` **integrated** by Claude: PR #115, merge commit `532bd36`. Never re-implement or amend the applied 0400/0401 migrations.
- Shared CI correction **Draft PR #118**: `build/chatgpt-np06-shared-ci-fix` against live trunk.
- Finance F3 `0402/0403` **Draft PR #117**: `build/chatgpt-np06-arap`, last verified head `3d128dc4df1b8860ce46a3aaae9960843d382c0f`. F3 is not integrated; F3 authorization is separate.
- Cross-lane exact heads reviewed at initial checkpoint: NP01 PR #111 `d9a1659af5a62940b719fca3b443fe7b6e3c9a52` with 0113 GOV003, Sales PR #109 `c7165af0162123c39154445b07d1b730c048519c` with 0304 invoice drafts, Manufacturing PR #112 `86851dc4a09bb71c051e3fb82b8fddc9d0b4ec1b` with 0504 canonical Master. **Pins are intentionally hard-fail guards** if any PR advances.

## Exact CI-fix scope

1. Trunk `.github/workflows/core10-np06-finance-ci.yml` no longer pins obsolete NP01 `c858084d`: it verifies the exact new `d9a1659` SHA and runs 0110–0113 including GOV003 read, Owner Control, audit and independent-session race. PR111 is locally fetched with read-only repository permission; NO push or shared-branch alteration.
2. Old generic `run.sh down` assertion incorrectly targeted whichever version was highest. New `tests/migrations/np06-finance-rollback-boundary.sh` calls *exact* `0401.down.sql` and `0400.down.sql` separately in `BEGIN READ ONLY` transactions and requires their **original** errors: `FIN_REVERSAL_ROLLBACK_DENIED_HISTORY`, `FIN_ROLLBACK_DENIED_PERSISTED_HISTORY`. It verifies applied 0400/0401 SHA256 checksums, complete `core10.schema_migrations` ledger, posted original/reversal, immutable lines, Owner settings and audit event counts before/after, and validates the canonical audit chain **as an authenticated synthetic tenant Owner**. This neither calls production `run.sh down` nor edits migrations.
3. New read-only cross-lane CI `.github/workflows/core10-np06-crosslane-ci.yml` pins and locally merges Sales PR109 and Manufacturing PR112 separately. Each matrix leg does full disposable PG17 Up→Down→Up, Control mapping evidence, Finance 0400/0401 E2E, real independent-session posting/reversal, target rollback guard and domain tests. Manufacturing executes its own E2E and concurrency; Sales uses a separate **disposable Sales-named PG17 database** for unchanged invoice negative/zero-Money and Sales concurrency tests, while the primary combined DB proves Finance reversal works *with* 0304 installed. This preserves both lanes' safety assertions without hiding or weakening them.
4. Small CI-only scope: no Finance SQL or migration checksum edits, no NP01/Sales/Manufacturing code edits, no new approval, Auth, Money, customer, supplier or payment engines.

## Test checkpoints

- Exact code checkpoint `8b156af450a04829ad07d21729d7ee6d3fd08c9f`:
  - Finance workflow: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44366597749 (both normal and NP01 compatibility jobs)
  - S0: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44366597681
  - Cross-lane Sales + Manufacturing matrix: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44366597656
  - NP02 Master/Owner Control: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44366597780
- **Always recheck all exact-head workflow conclusions** after any docs/CI change. Report PASS only when job result is actually success; not when queued/in progress. S1-c Approval/Audit is covered by canonical Finance E2E and live shared CI; when a separate S1-c workflow is triggered, record it explicitly.

## F3 integration preparation — NO merge yet

Read-only inspection of F3 against latest F2-integrated trunk shows **exactly ten F3-owned additional paths**, with no modified 0400/0401 files: `0402_np06_arap_links_allocations` up/down, `0403_np06_arap_trace_integrity` up/down, F3 race/SQL regressions, F3 CI and two F3 docs. The old PR #117 base still points to Finance F2 feature branch and its old shared CI; re-targeting it before the reviewed #118 CI fix integrates would produce predictable stale-pin/rollback failures. **Do not weaken either test or pollute F3 diff with shared CI changes.**

After Claude/Owner independently reviews and integrates PR #118 (with a separate GO):
1. Re-fetch latest actual trunk and PR #117 HEAD. Confirm no other builder has introduced F3 paths.
2. Compare F3's ten SHA-verified unique files to trunk. Use a normal, non-forced two-parent merge to sync trunk into `build/chatgpt-np06-arap`, preserving the original 0402/0403 up/down bytes and all history. Ensure 0400/0401 blobs match the integrated trunk.
3. **Only then** re-target Draft PR #117 to `ccr-15ed11dd-n3hw5h`; require diff exactly F3-owned paths and no shared CI/old F2 migration modifications.
4. Run full F3 PG17 E2E, Master party links, same actor replay, partial/over-payment, derived as-of aging, Auth/RLS/Control/Audit, three independent-session races, 0401 compatibility, NP02 Master/Owner Control and shared Finance/Approval/S0 checks at the new exact F3 SHA.
5. Ask Claude for a **separate independent F3 code review and separate Owner F3 GO**. No self-merge.

**F3 fail-closed blockers** remain: actual NP03B Sales invoice and NP03A procurement bill attestation, bank/receipt proof and true GOV002 Finance 1+stage adapter NOT CONNECTED; only explicit Owner/manual Money posting usable in disposable tests. Allocated document/payment reversal denied pending allocation-reconciliation adapter. Valuation/COGS, signed 16 personas, FX/tax, reconciliation, Finance Shell/UI and hosted testing are NOT COMPLETE.

## Absolute HOLD

Never apply hosted Supabase migrations, deploy Cloudflare/Workers, alter main/production/IMG-ERP-SG or push to another builder branch. Finance PR #115 is ALREADY integrated; do not repeat it. Shared CI PR #118 and F3 PR #117 both stay Draft until independent Claude/Owner decision.
