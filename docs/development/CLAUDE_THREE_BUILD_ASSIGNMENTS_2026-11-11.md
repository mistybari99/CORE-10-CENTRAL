# CORE-10-CENTRAL — THREE CLAUDE DRAFT BUILD WORK PACKAGES

**Owner assignment date:** 2026-11-11 (Asia/Dhaka)
**Status:** Instructions/branch coordination, **not** proof Claude was launched or any new code was completed.
**One repository:** https://github.com/mistybari99/CORE-10-CENTRAL
**Canonical decisions:** https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit (D033/D045/D046/D047/D048/D049/D050; R123–R129; REV-009)
**Codex context:** \`AGENTS.md\` + \`docs/development/CODEX_MASTER_EXECUTION_HANDOVER_2026-11-11.md\`. Owner has not issued the NEXT Codex-specific task; **do not infer an instruction to launch Codex or merge a Claude branch into preview**.
**Preview reference:** Draft PR #60 on \`preview/c10-integrated-20261111-v1\`. It is *source-assembled + synthetic UI*, not authenticated fully integrated ERP.

## Owner's instruction: three substantial real BUILD packages, in Draft only

Claude should work independently on THREE packages: (1) finish existing A055; (2) implement A052 intent/understanding engine; (3) implement A053+A054 workforce-to-portfolio adapter and advanced HR/payroll policy. Every package needs actual SQL/RPC/JS/HTML/CSS as appropriate, meaningful business workflow, calculations, reports, role/tenant security, Node/PG17/Chromium tests and CI. **Plans/architecture/UI mockups alone are not a completed build.** Submit Draft PRs; do not merge.

### PACKAGE CLAUDE-1 — C10-A055 Enterprise Assets, Equipment and Maintenance (CONTINUE EXISTING WIP)

- **Issue:** https://github.com/mistybari99/CORE-10-CENTRAL/issues/58
- **Existing Draft PR:** https://github.com/mistybari99/CORE-10-CENTRAL/pull/59
- **Existing branch:** \`claude/c10-a055-enterprise-assets-maintenance-v1\`. Preserve the WIP; DO NOT start a new branch or recreate it.
- **Observed WIP head:** \`33ebf28619fde2534ac9c49e7935cb89eb72331c\` (reverify).
- **Current blocker:** A055 Actions run #43027595420 FAILED: \`tests/c10_a055_registry_e2e.sql: No such file or directory\`; this missing expected test means **A055 is not CI-complete**. Inspect entire workflow for other missing/incorrect file references, correct real failures and rerun.
- **Build actual source:** canonical per-tenant/business/site asset registry and lifecycle; assignments/location moves; warranties/serials/meters; policy/schedules/reminders suggestions; inspections/calibration; preventive/breakdown work orders DRAFT→SUBMITTED→APPROVED→IN_PROGRESS→COMPLETED→VERIFIED→CLOSED (plus audited exception); downtime, MTTR/MTBF only on valid samples; costs and spares estimated (no direct stock/finance posting); scoped role access and audit; business/site Owner settings; reports safe CSV and explicit formula/metrics; responsive Owner/technician UI and guidance; negative RLS/idempotency/concurrency/cross-tenant tests.
- **Strict ownership:** only \`core10-asset-maintenance*\`, \`internal/enterprise-sql/c10_a055_assets_*.sql\`, \`tests/c10_a055_*\` and A055-specific CI/docs. Do not modify A045/A046/A047/A048/A049/A050/A051/A052/A053/A054 core, \`owner.html\`, \`index.html\`, the preview Worker or live Supabase. Link to A048/A049/A051 via read-only contracts and future adapters; no second stock ledger or payroll.
- **Done:** complete work order and maintenance scenarios under disposable PG17 + Node + signed demo API when possible + Chromium 390/1440, fail-closed rights, exact all-green A055 CI and Draft PR #59 with honest gaps. Real GoTrue/production remain blocked.

### PACKAGE CLAUDE-2 — C10-A052 Universal Owner Intent → Certified ERP Configuration + Guided Explainability

- **Existing Issue:** https://github.com/mistybari99/CORE-10-CENTRAL/issues/53
- **Architecture doc PR:** https://github.com/mistybari99/CORE-10-CENTRAL/pull/54 ; latest D049/R128 architecture is present on Preview #60. Use this as contract, NOT as runtime completion.
- **New dedicated source branch:** \`claude/c10-a052-owner-intent-runtime-v1\` from verified preview integration checkpoint. Independent Draft PR target: \`preview/c10-integrated-20261111-v1\` (not main).
- **Deliver a real P0 vertical slice**, not universal untested magic:
  - Natural-language Owner request intake in Bangla/English; scope to canonical tenant/business/site/role and existing capability/handler; deterministic interpretation or clearly labeled structured clarification with source/version and editable assumptions; unsupported asks \`NEEDS_HANDLER_BUILD\`.
  - Typed **intent/impact/dependency** contract: which entities, formulas, reports, permissions, approvals and downstream modules are involved, what conflicts, what is blocked/missing/unsafe; no posting rights via prompt.
  - Canonical A042–A045 registry adapters; **do not create a second control, auth, stock, workflow execution or audit source of truth**. Certified handler allowlist only. No \`eval\`, dynamic JS/SQL execution, unsafe model authority, arbitrary permission grants.
  - Versioned intake→interpreted→impact preview→validated→approved→published (only for actual certified handler)→audited lifecycle; if no handler, visible engineering ticket/advisory status; real owner/manager negative authorization.
  - Explainable UI metadata and contextual guidance on actual selected controls/report slices, with \`what/why/when/default/exception/consequence/data+formula+units/linked report/effective permission\`. Bangla/English and mobile 390/desktop 1440.
  - At least 3 multi-industry worked cases: sweets wastage threshold advisory; paint pack-size/discount margin calculator with exact units; construction project materials approval/read-only report, plus pending unsupported capability. Before/after sample, safe no-write outcome and accurate output lineage.
  - Disposable PG17/RPC + Node/Chromium 390/1440, two tenants, unauthorized/revoked/stale/replay, invalid locale/calculation/unit/conflict cases. No live network LLM service or API key needed for deterministic v1; later AI adapter must have a secure fallback.
- **Exclusive files:** \`core10-owner-intent-*.html/js/css\`, \`core10-intent-client.js\`, \`internal/enterprise-sql/c10_a052_intent_*.sql\`, \`tests/c10_a052_*\`, \`tests/e2e/core10-a052-*\`, \`.github/workflows/core10-a052-*\`, \`docs/architecture/C10_A052_*\`. Existing A045 Studio and Workshop files are read-only dependencies; create adapter not code fork.
- **Done:** user can submit and preview at least one supported scope-correct config request, see consequences and correctly distinguish supported vs unbuilt handler; real tests green; Draft PR with SHA and exact CI. Not total completion of D049 yet.

### PACKAGE CLAUDE-3 — C10-A053 + A054 Canonical Workforce Integration and Configurable HR/Payroll Governance

- **Existing issues:** A053 https://github.com/mistybari99/CORE-10-CENTRAL/issues/56 and A054 https://github.com/mistybari99/CORE-10-CENTRAL/issues/57 .
- **Sources:** A046 persona PR #44, A050 Owner Portfolio PR #51, A051 Workforce PR #55; the preview branch includes their compatible source files, **not their installed migrations**.
- **New dedicated branch:** \`claude/c10-a053-a054-workforce-integration-policy-v1\` from verified preview integration checkpoint. Independent Draft PR target: \`preview/c10-integrated-20261111-v1\`.
- **Workstream A053:** Map A051 fixture/persona roles to stable A046 registry WITHOUT changing the meaning of existing aliases; fail-closed new scoped fixture aliases rather than silent UUID reassignment. Build an additive, signed, Owner-only A050→A051 READ adapter: business summary, headcount, by-site, payroll liability preview. Server guard \`read_workforce_business_summary_v1\`/\`read_payroll_liability_preview_v1\`, verify authorized business ID, month, counts, \`paid:false\`, \`ledger_posted:false\`, \`money_movement:false\`; NEVER show salary liability to general staff, managers/investors, cross-tenant callers. Missing migration \`NOT CONNECTED\`, not synthetic fabricated real payroll.
- **Workstream A054:** Add Owner-configurable, versioned, effective-dated HR/Reviewer/Preparer/Approver delegation (business/site/period, explicit DENY/expiry/revoke); configurable fixed / percentage allowances and deductions with bases/caps and trace; configurable OT multiplier \`1.00× = 100% base rate\` (not 1%) and approved OFF mode under legal gates; configurable **raw punch-only** retention default 36 months with legal holds/dry-run (not erasing payslips/audit); leave balance accrual/annual carry-forward/cap/grace/expiry/cross-year requests, audit and frozen payroll amendment safety. No invented Bangladesh statutory payroll rates or legal compliance assertions; no bank payout or general ledger.
- **Shared A051 source ownership:** preserve original A051 SQL/UI/JS as read-only baseline. Put additive policy SQL, adapters and UIs in NEW \`c10_a053_*\`, \`c10_a054_*\`, \`core10-workforce-integration-*\`, \`core10-workforce-policy-*\` namespaces and independent CI. If unavoidable patch to A051 contracts is necessary, isolate the minimal change with explicit analysis/tests; do not overwrite Claude's original unmerged PR #55 or A050 source.
- **Release/testing:** 2 tenants/3 businesses, canonical 16 test principals, owner vs staff/counter/manager/investor/revoked/anon negative, overnight/timezone and monthly/cross-year carry-forward, maker-checker, frozen amendment concurrency, rate rounding, effective-dated immutability, CSV privacy and PII checks, Node/PG17/HMAC signed API and actual Chromium 390/1440. State \`GoTrue not tested\` until a real isolated staging project exists.
- **Done:** one working source-backed integration example plus versioned salary/leave policy demo, no real payroll or production writes; Draft PR with complete source/tests, exact CI.

## Shared parallel-build contract

1. All three tasks are **DRAFT-only**, safe SQL on disposable \`c10_demo\` PostgreSQL17; NO \`main\` merge, production Supabase \`IMG-ERP-SG\` writes, real accounts/payroll/stock/bank operations, or autonomous live app deployment.
2. **Source priority:** Latest Owner explicit instruction > single Master Decision Book (D049/R128, D050/R129, REV-009) > repo canonical handoff > these technical briefs > historical drafts. No second Decision Book.
3. The three packages may be developed concurrently ONLY when namespaces stay disjoint. If a required contract change touches a shared source file or depends on another in-flight PR, document contract proposal; do not overwrite or silently cherry-pick.
4. Existing A055 work/PR #59 is actively WIP and has a failing CI. Preserve it, do not restart or call green. Update it with real code and tests.
5. Each new PR should contain actual verified implementation before counting as a built module; a docs-only placeholder PR is **DRAFT INSTRUCTIONS ONLY**.
6. A053 and A054 are one coherent workforce governance package but maintain separate Requirement/Action IDs and tests.
7. Codex: Owner will provide NEW specific Codex instructions later. Keep Codex Preview PR #60 and its \`preview/\` assets free of Claude edits until integration review. The coordination note gives Codex awareness only and does not initiate a new task.
8. Deliver individual Markdown execution reports: source SHA, PR, actual CI URLs, exact tests and 390/1440 proof, supported workflows/limitations, no GoTrue/prod assertions, blocker and next reversible slice.
9. If the chosen branch requires rebase because Codex later updates preview, coordinate through PR compare/review; never force-push or merge to \`main\`.

**Important:** Creating these briefs, issues or branches is not equivalent to launching or completing a Claude Code session. The Owner must invoke Claude Code (or an authorized GitHub action) with the briefs; a draft PR does not self-execute.
