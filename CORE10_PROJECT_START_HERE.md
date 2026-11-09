# CORE 10 CENTRAL — PROJECT START HERE / LONG-TERM HANDOVER

**Purpose:** A short, durable orientation file for the owner's long-running CORE-10-CENTRAL ChatGPT Project and future development chats. **This file is an INDEX, not a competing decision register, code repository or approval mechanism.**

**Last reconciled:** 2026-11-10 (Asia/Dhaka)  
**Canonical implementation repository:** [mistybari99/CORE-10-CENTRAL](https://github.com/mistybari99/CORE-10-CENTRAL), **main**.  
**Decision source of truth:** [CORE 10 — ERP Master Decision Book & Execution Register](https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit).  
**Detailed requirements:** The SAME Sheet's [REQUIREMENTS LOCK](https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit#gid=4106).  
**Development queue:** The SAME Sheet's `NEXT ACTIONS`.  
**Decision history:** The SAME Sheet's `DECISION REVISIONS` and `DISCUSSION LOG`.  
**Architecture/audit and proposed documents:** [Draft PR #6](https://github.com/mistybari99/CORE-10-CENTRAL/pull/6), branch `audit/c10-central-organization-reconciliation`. **Draft ≠ merged, deployed or verified.**

## 1. Project mission
Develop **one existing FULL enterprise ERP**: CORE 10 CENTRAL, using one reusable ERP core and 10+ composable industry templates. The owner has multiple owned businesses, including sweets/bakery, paint/hardware, construction and potentially further businesses. The platform must eventually support independent customers and licensing as an optional later commercial SaaS capability **without confusing IP/platform control with customer data-reading rights**.

**Never create a second ERP or parallel codebase.** This is NOT Trillionaire Me; do not link or copy code/data from that other product.

## 2. Latest authoritative scope (check live decisions each session)
- **C10-D001–D029:** existing Central/Business hierarchy, staff isolation, owner context, stable stock-location identities, reports, development governance and migration policy. Consult exact current Decision Book rows; do not infer details from this summary.
- **C10-D030–D038:** Enterprise Scale (target 100+ branches, 100+ factories and 100+ warehouses **per business**, not yet certified), 10 industry templates & extensible packs, Quick/Advanced dynamic setup with **no feature reduction**, Master Owner AND individual Business Owner Boards, Show/Locked/Hidden and explicit permissions, partnership/investment/equity/financing, scoped consolidated reporting, independent tenants/later SaaS, non-toggleable data isolation, and full requirement/change traceability.
- **C10-D039:** one Future Enterprise Simulation & Decision Intelligence capability **inside** this ERP with standalone Lab + contextual Quick Simulation; approved SCOPE, **NOT BUILT**.
- **C10-D040:** approved additive Simulation v2.0 extension: 26 capability contracts covering data trust, model certification, cross-module impact, feasibility, integrated profit/cash/working-capital, sensitivity, risk, reverse goals, optimization, decision lifecycle, actual-vs-plan, performance monitoring and enterprise integration. Does NOT replace D039.
- **R001–R114** in REQUIREMENTS LOCK are binding scope/acceptance details. The original R001–R080 historical traceability document predates R081–R114; consult the Sheet for the COMPLETE latest ledger.

## 3. Technical specification links (draft, not current production behavior)
1. [Full organizational architecture and audit](CORE10_ORGANIZATION_MODEL_DUAL_AUDIT_2026-11-10.md).
2. [Owner requirement baseline (R001–R080) with links to newer scope](CORE10_OWNER_REQUIREMENTS_TRACEABILITY_2026-11-10.md).
3. [Original 18-section Simulation directive, D039 / R081–R088](CORE10_ENTERPRISE_SIMULATION_DECISION_INTELLIGENCE_DIRECTIVE_2026-11-10.md).
4. [Approved Simulation v2.0 extension, D040 / R089–R114, U01–U26](CORE10_SIMULATION_DECISION_INTELLIGENCE_V2_EXTENSION_2026-11-10.md).

These links are relative to the GitHub Draft PR branch containing this index; the Google Sheet remains authoritative for approval/priority. Always check the most recent main/PR, live DB and deployed state before coding or describing a capability as ready.

## 4. Existing approved queue and order
**First priority:** `C10-A018` canonical Platform → Tenant → Legal Entity → Business → Operating Site → Stock Location architecture, capability registry, compatibility with legacy IDs; then `C10-A019` tenant/business isolation, and the dependent enterprise provisioning `A020`, dual owner control `A021`, partnership/finance `A022` and reporting `A023` packages. Stage and test dependencies; do not assume these are completed simply because plans exist.

**`C10-A024`:** external SaaS commercialization **deferred later**, separate from the ERP core.

**`C10-A025`:** Enterprise Simulation **DEFERRED / NOT BUILT**. Start its code **only AFTER the next 2–3 genuinely completed and independently verified major ERP development packages**, **AND** applicable C10-A018/A019/A020/A021 P0 security/architecture gates and A022/A023 finance/KPI contracts. A qualifying package has working E2E operations, DB/service integration, authorization, calculations/reports, automated/integration tests, completion evidence and no unresolved critical defects. Documentation/CI alone, mock screens and partial features **do not count**. No automatic activation from a scheduled reminder.

## 5. Security and data correctness — hard safety invariants
- Staff belongs to explicitly authorized tenant/business/operating locations, sees only its own business branding; never sees CORE 10 Master identity or sister businesses by default. **Show, Locked and Hidden are UI presentation; actions require real backend grants/RLS/RPC checks.** No permission means no data/action.
- Master Platform Owner owns source/IP and entitlements, not private operational data of independent customer tenants. Any support access requires explicit narrow grant, revocation and audit. Global security cannot be a casual owner toggle.
- The current legacy `org_scope_on` compatibility switch (formerly observed OFF) is tied to policies/functions. **Never flip/delete it without migration analysis, staging negative security tests and owner release approval.**
- Old IMG/Sweets item/location IDs and ledger references must be preserved. No direct live production writes, destructive migrations, automatic PR merges, settings toggles, deployment or financial posting without separate authorization/release gates.
- Operational metrics must be scoped, reconciled and avoid double-counting internal transfers. Treat incomplete accounting as incomplete; do not invent profits or imply that a UI mock is working software.
- Investor and partner Equity, Capital, actual-profit share, fixed principal-based contractual obligation, payout cadence and application access must be modeled separately; historical `partner_calculate` business-scope aggregation has known isolation issue needing fix before real multi-business usage.
- Scenario simulation is hypothetical/read-only with respect to actual ERP ledgers, stock, payroll, invoices, cash or investor payouts. Real apply requires explicit proposal → diff → permission → approval → existing validated domain posting → audit.

## 6. State and evidence at the time this index was authored
- On 2026-11-10, `main` contained existing legacy forecasting UI `forecast.js` and SQL `fc_scenario`, but **not** the full future Simulation module.
- Simulation `C10-D039`/`D040` scope is approved; action `A025` remains **DEFERRED / NOT BUILT**.
- Draft PRs #3–#6 were still unmerged. The docs in PR #6 are a reviewed scope/reference, **not** production.
- Current implementation/CI/deployment/DB state can change at any time; verify before each development move.

## 7. Protocol for every new Project chat or development session
1. **READ** the current Central Decision Book (especially latest decisions, REQUIREMENTS LOCK, NEXT ACTIONS, DECISION REVISIONS) before proposing changes.
2. **VERIFY** GitHub `main`, pending PRs/CI, relevant code, current Supabase schema and security flags, and actual deployment/tenant state. Read-only inspection first.
3. **RECONCILE** the requested scope with the exact existing decision IDs/requirement IDs and current implementation maturity. Do not duplicate master logs, modules, settings engines or apps.
4. **PLAN** the smallest coherent E2E package, with test criteria, DB migration/backup/rollback steps and security negatives. Keep in the existing NEXT ACTIONS.
5. **BUILD ONLY WHEN AUTHORIZED**, usually code-review draft PR/staging first; do not infer approval for irreversible, production, billing or sensitive security changes. Never declare complete until verified end to end.
6. **RECORD** evidence, acceptance, blockers and necessary explicit decision revision into the existing Decision Book. **Latest explicit Owner correction overrides older suggestions**; unchallenged design recommendations may be baseline but do not grant release authority.
7. **HAND OVER** the exact verified work state, commit/PR and remaining next gate for smooth long-term continuation.

## 8. Current preferred next action
Begin/continue **C10-A018** foundation reconciliation, producing a canonical entity model, tenant-safe mapping plan, industry capability matrix and clear implementation/test status for R001–R114. Do not start Simulation A025 or SaaS A024 prematurely.

---
**IMPORTANT:** This is a lightweight Project onboarding index. The **Google Central Decision Book and current verified code/database are the sole authoritative sources for product policy and live implementation respectively**. Keep this index updated when entry-point links or major milestones change, instead of duplicating or rewriting all 114 requirements here.
