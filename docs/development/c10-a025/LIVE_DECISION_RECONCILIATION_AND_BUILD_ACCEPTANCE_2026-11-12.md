# C10-A025 — LIVE RECONCILIATION ADDENDUM AND FULL BUILD ACCEPTANCE
**Verified 2026-11-12 against the existing native Central Decision Book and GitHub.**
**Purpose:** Mandatory correction to the existing 31 KB Claude Code mandate in PR #75. This is implementation governance, not evidence that an engine already exists.

## 1. EXACT AUTHORITATIVE RECORDS — never guess IDs

Native Sheet: https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit

| Existing tab and row | Verified record | Governing truth |
| --- | --- | --- |
| DECISION BOOK row 37 | C10-D039 | Original integrated ERP Simulation scope approved; old text still describes development defer |
| DECISION BOOK row 38 | C10-D040 | 26 U01–U26 extensions are additive, not a replacement |
| NEXT ACTIONS row 26 | C10-A025 | Draft coding authorized for Claude Code; actual code NOT IMPLEMENTED/NOT MERGED/NOT DEPLOYED; release DEFERRED |
| DECISION REVISIONS row 11 | REV-007 | D040, R089–R114 and U01–U26 extension approval |
| DECISION REVISIONS row 13 | REV-009 | Islamia business logic cannot become universal or shadow core |
| DECISION REVISIONS row 14 | REV-010 | **Claude Code (not Codex) may build and test full isolated draft now.** Production/integration/merge still delayed |
| REQUIREMENTS LOCK rows 85–118 | R081–R114 | Exactly 34 approved A025 requirements and acceptance tests; no ID gaps |
| MODULE BUILD DETAIL rows 488–521 | C10-DETAIL-R081 through C10-DETAIL-R114 | 34 atomic simulation tracking items; currently NOT_CERTIFIED_PER_DETAIL |
| REQUIREMENTS LOCK row 133 | R128 / D049 | Explainable task UX across all ERP modules, including Lab and Quick Simulation |
| REQUIREMENTS LOCK row 134 | R129 / D050 | A054 owns actual payroll policy engine; Simulation consumes future verified read-only adapter |
| REQUIREMENTS LOCK rows 127–130 | R123–R125 | Unified Owner Control Studio and approved synthetic role registry |
| NEXT ACTIONS row 25 | C10-A024 | Commercial SaaS separate and deferred; no billing implementation here |

The complete source wording/acceptance for these 34 requirements is preserved at [LIVE R081-R114 JSON](./OWNER_REQUIREMENTS_R081_R114_LIVE_SNAPSHOT_2026-11-12.json). Re-fetch the live book on every resumption to check for revisions after this date. Do not create duplicate decision, requirement, revision or action numbers. Preserve original approved policies in place. The new research tabs RESEARCH ARCHIVE, CAPABILITY REGISTER, SOURCE TRACE, REQUIREMENT TRACE, MODULE BUILD DETAIL and MODULE DELIVERY are companion planning evidence; do not treat their detailed rows as working software or replace the existing master backlog.

### REV-010 changes exactly ONE gate

**Draft implementation may start now only in a separate Claude Code-owned implementation branch and DRAFT PR inside mistybari99/CORE-10-CENTRAL.** It does not authorize main integration, live navigation, public deployment, production Supabase, paid services or customer data. Main/operational activation still requires 2–3 genuinely completed, fully integrated major ERP packages and verified A018–A023 / P0 security/finance/tenant gates, plus specific release decision. A058 isolated QC PR #73 is not one of those qualifying end-to-end live packages. **Do not reimpose older draft-coding freeze, nor silently remove the release freeze.**

## 2. Other decisions the implementation must honor

- D036/D037: Master Platform Owner owns software/IP; independent Tenant Owner has separate business data, with no covert vendor access. Signed server scope, RLS and explicit approvals mandatory. Do not flip legacy org_scope_on.
- D041/D042/D043/D044: one repo, preserve existing Islamia IDs, maintain GitHub-first SQL migration/staging/rollback, no unsafe deployment. The general permission for progressive low-risk UI does NOT override REV-010 simulation-specific non-activation.
- REV-009: do not reuse sweets/Islamia branded operational formulas and report tables as universal multi-business engines.
- D045/R123/R124: reuse canonical Owner Control Studio, A021/A034 role and effective capability/placement services, version/audit rules; never invent a second owner settings registry or role authority.
- D046/R125: use existing A046 16 synthetic personas, multiple businesses/sites and two independent tenants. Synthetic JWT claims are not real Supabase GoTrue Auth.
- D047/D048/R126/R127: A048 inventory, A049 Purchase→Production→Sales and A050 Owner Portfolio are required and not interchangeable. Read-only adapters may use only source contracts verified on exact implementation heads.
- D049/R128: every important simulator input, action, assumption, chart and report explains WHAT, WHEN, WHY, normal recommendation and rationale, consequences, scope/permission, formula/source/version, safe example and resulting report location in understandable Bangla/English.
- D050/R129: payroll/HR actual policy engine is A054. A025 may run stand-alone hypothetical workforce costs and future read-only A054 versioned policy adapter, never duplicate payroll ledger or promise actual salary legal rules.
- A022/A023: audited business finance and KPI models must separate operating profit vs cash, principal vs interest/contractual investor obligation, tax assumptions and data readiness.
- A024 remains separate later SaaS commercialization.

Current GitHub staging includes PR #75 (docs-only mandate), PR #7 (demo foundation), PR #60 (integrated visual preview), PR #73 (isolated QC), PR #59 (Claude assets), PR #67 (Codex research), plus Claude-owned operational/CRM modules. These are dependencies/peer work, not blanket proof of real signed production operations. Never rebase or overwrite their branches. New engine files must be contained in one uniquely Claude-owned implementation branch; use the approved dedicated path only if it does not already exist.

## 3. Complete one-engine contract to actually implement

Every component below requires **real tested source**, not a placeholder screen, generic future proposal or second ERP:

1. Immutable versioned model registry: model ID/version, formula hash, schema, unit/currency/period/source basis, industry packs and business context, permissions, honest status, golden fixtures and retirement/migration.
2. Exact fixed-point calculation kernel: decimal-safe numeric amounts, units and conversions, percent/rate meanings, time horizons, sign rules, display rounding, unknown vs actual zero, no mixed periods or currencies.
3. Authorized context/snapshot interface: canonical tenant/legal entity/business/site/location/role/current grants and source version; mock sources for isolated draft only. Caller-submitted scope cannot authorize itself.
4. Data quality and evidence: Actual/Estimate/Assumption/Scenario/Unknown, source document IDs, time cutoff, hashes, stale/partial data, missing-input prompts, no fake certified financial facts.
5. Full 20 model families: pricing, break-even, P&L, cashflow, inventory/reorder, suppliers, BOM/yield, workforce/capacity, logistics, working capital, capex, ROI/NPV/IRR where valid, loans, contract-specific investment, project BOQ, branch/factory expansion, sales mix, verified tax/fees, no-double-count site consolidation, safe declarative templates. Only call a model implemented when golden cases, negative and result-source tests exist. Unsupported stays NOT_IMPLEMENTED with reason.
6. Scenario lifecycle and persistence: baseline/conservative/optimistic/custom, create/clone, save, reopen, archive, version, compare, ownership scope and audit; immutable model/input/source hash of every result; optimistic revision and same-key retry.
7. Financial/capacity feasibility graph: exact constrained budget, cash buffer, receivables/payables, supplier lead time, production throughput, staff, machinery, warehouse, finance and cross-module dependencies; no double counting internal transfers or financing principal as P&L expense.
8. Sensitivity, stress, reverse planning and bounded optimization: documented objectives, drivers, bounds, feasible/infeasible findings, conditional recommendations and uncertainty disclaimers; statistical probabilities only from validated distribution and correlation evidence.
9. Decision lifecycle and existing approval adapter: draft → simulated → reviewed → approved/rejected → proposal → monitored; create advisory plan only. Apply-to-live ALWAYS disabled in this draft; never use generic write SQL or duplicate ERP approval engine.
10. Scoped reports and exports: JSON/CSV and compatible chart/report outputs with formula breakdown, units, source, actual vs assumed, unknown flags, CSV formula-injection defense, redaction and actor/business scope.
11. Mobile/desktop Lab plus contextual Quick Simulation from the SAME model registry and calculation source. Real forms, sliders where meaningful, saved scenarios, results, assumption editing, comparisons, reusable UX components, error/retry/empty/offline-stale states and keyboard/accessible BN+EN controls.
12. Security/scale and integration contract: isolated PG17 schema if justified, RLS and RPC grants, no platform-vendor bypass, no direct finance/stock mutations, revocation, owner/manager/staff/investor/foreign tenant negative tests, safe cache/export, bounded workloads and 300+ site future benchmark gate.

### All U01-U26 must be represented explicitly and truthfully

- U01/R089 Trusted Baseline; U02/R090 Data Quality; U03/R091 Certified Model Registry; U04/R092 Finance Definitions; U05/R093 Provenance.
- U06/R094 Cross-module Impact; U07/R095 Feasibility; U08/R096 Finance and cashflow; U09/R097 Sensitivity; U10/R098 Stress.
- U11/R099 Reverse Goal; U12/R100 Optimization; U13/R101 Scenario Portfolio; U14/R102 calibrated uncertainty only; U15/R103 Decision Lifecycle.
- U16/R104 Existing approval; U17/R105 Actual vs Plan; U18/R106 Decision Performance; U19/R107 Forecast Accuracy; U20/R108 Early Warning.
- U21/R109 Collaboration; U22/R110 anti-double-count consolidation; U23/R111 Finance and Partner semantics; U24/R112 advisory-only application gateway; U25/R113 UX/reporting; U26/R114 Tenant security/licensing/scale.

A U capability may be registered but still UNIMPLEMENTED or DEFERRED. Never label a model Ready based solely on documentation, mock charts or isolated mathematical tests.

## 4. Required synthetic business acceptance (end to end)

**Branch opening:** Demonstrate rent/staff/raw-cost/sales/capex/funding changes for two fictional branches and 12-month cashflow. Show one profitable month with negative cash due to payments, and mark feasibility failure. Differentiate refundable deposit, investor obligation, capital purchases, loan principal and recurring operating expense.

**Production and food:** Show ingredient quantities/UOM, waste/yield, energy/labor, batch constraints, raw price sensitivity and sellable output. Any missing actual A049/A058 source must be explicit and cannot become actual stock or actual COGS. No inventory posting.

**Paint and wholesale:** Supplier quote, packaging/unit conversion, discount, transport, credit term, estimated stock cost, working capital and procurement cash timing; no duplicate inventory expense/COGS.

**Construction:** BOQ, progress and variation/change order, staged receivables, supplier/staff obligations, retention, delay and cash gap. Never assume Bangladesh legal tax/default rules without verified configuration.

**Loan/investor:** Compare debt service, contractual fixed principal-based periodic payments, actual-profit-variable share and equity scenarios with correct legal/economic classifications; state uncertainty. No promises of guaranteed income or claimed Sharia classification.

**Security:** Two fictional tenants, three+ businesses, four+ sites, sixteen reusable roles; cross-tenant and revoked owner/manager/anonymous/investor/platform operator direct RPC/export access denied. No dangerous default permission; no true signed-auth certification until staging.

**Model migration:** A saved scenario bound to formula v1 must reproduce v1 after registry v2; explicit v1-v2 comparison never rewrites historical decision.

**No side effects:** Scenario calculation/save/review/export touches only separate scoped scenario data (or local fixture). Confirm canonical stock, sales, purchase, production, GL, payroll, invoice, investor and owner settings records unchanged across positive, retry, rejected and concurrent operations.

## 5. Definition of a finished DRAFT engine and handoff

Required files/outputs in the SINGLE future Claude Code implementation PR:
- Versioned contracts + calculation code + tested model and U coverage map with evidence.
- Additive scoped scenario persistence and backend tests, if isolated SQL required; no SG production DDL.
- BOTH working Lab and Quick Simulation demo UI, 390px Android and 1440px desktop real browser testing, full BN/EN guidance.
- Per-model golden numbers and adverse/negative/unknown cases, deterministic versioned outputs and trustworthy descriptions.
- Scenario lifecycle, compare, constraint, stress, reverse-goal and reporting that actually work in mock isolated context; no fake services.
- Security negative matrix, exact Git commit and CI run URLs, known blockers and recovery instructions.
- Implementation decision log, architecture/extension SDK, per-feature coverage matrix and TECHNICAL_HANDOVER with safe future upgrade protocol.
- No premature main merge, production schema/auth/tenant data or live navigation, and no separate app/repo.

**Actions:** Claude Code reads current Book and PR #75 + both companion docs; verifies whether A025 implementation branch already exists; then codes substantial cohesive slices, commits, runs tests and opens its OWN distinct DRAFT implementation PR. Never ask routine technical defaults; apply safe engineering judgment. Report actual gaps and any unsupported models with statuses.

**Only the official Decision Book controls future release authorization.** This addendum is subordinate to a later verified Owner revision. Its presence does not claim that Claude Code has already started or that the Simulation Engine is complete.
