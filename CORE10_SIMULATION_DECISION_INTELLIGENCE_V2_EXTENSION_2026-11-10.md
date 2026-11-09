# CORE 10 CENTRAL — Enterprise Simulation & Decision Intelligence v2.0 Extension

**Scope**: owner-approved design extension to **C10-D039**, recorded under **C10-D040**; execution remains in **C10-A025**. Detailed requirements: **R089–R114** mapped one-to-one to upgrades U01–U26.
**State**: DESIGN LOCKED / IMPLEMENTATION DEFERRED / NOT BUILT. No new application, repository, SaaS billing project, automation or ERP task list.
**Date**: 2026-11-10. **Canonical decision book**: https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit
**Original approved 18-section directive**: [Enterprise Simulation directive](CORE10_ENTERPRISE_SIMULATION_DECISION_INTELLIGENCE_DIRECTIVE_2026-11-10.md).

## 1. What changes, what does not

- This is an **additive extension**: preserve every original requirement in C10-D039 / R081–R088 and the original 20 simulation model families. U01–U26 assign explicit capabilities, contracts, acceptance tests and relative development priorities; they do not create 26 standalone software services.
- Original UX stays: **one centralized Business Simulation Lab and contextual Quick Simulation** using the same deterministic/versioned calculation engine and secure business scope.
- Original safety stays: **no hypothetical result writes operational records**; approved Apply must call existing domain posting workflows after required review, permission validation, transactional safety and audit. If no validated Apply workflow exists, keep advisory only.
- Original ownership stays: Master Platform Owner owns software/IP/licensing and controls platform entitlements but has NO implicit right to inspect independent customer's financial/operational data. Independent Tenant Owner controls own business scope; secure backend tenant isolation mandatory.
- Original delivery timing stays: **A025 remains DEFERRED until at least two and at most three NEXT major genuinely completed end-to-end ERP packages have been verified (i.e., eligibility after the owner's 2–3-package milestone), plus ALL prerequisite P0 architecture/security gates**. Audits/docs/mock screens/partial UI/green CI alone do not count. This document does NOT begin development or mark any package complete.
- Existing high priority C10-A018–A023 queue is unchanged; C10-A024 commercial SaaS remains separate and later. No implementation is authorized by a product-scope decision.

## 2. New capability inventory and acceptance contract

| Req | Capability | Domain | Priority *inside future A025* | Scope / design rule | Acceptance evidence |
|---|---|---|---|---|---|
| R089 / U01 | Trusted Baseline Engine | Data | P0 | Pull only authorized tenant/business/site/period operational snapshots, preserve source record IDs and transaction cutoffs; prevent accidental mixture of stale sources. | Given same authorized source snapshot and scope, baselines are reproducible and inaccessible to other businesses. |
| R090 / U02 | Data Quality & Readiness | Data | P0 | Identify missing, stale, incomplete, estimated and unverified inventory/cost/sales/finance data; add explicit data readiness flags and corrective prompts. | Unknown is not zero; incomplete financial results cannot masquerade as certified profit/cashflow. |
| R091 / U03 | Certified Model Registry | Data | P0 | Register typed formulas, numeric units, supported business packs, dependencies, versions, tested/partial/unavailable status and fixture certification. | Unverified models cannot be tagged Ready, and saved outputs retain the exact original formula version. |
| R092 / U04 | Financial Definition Engine | Data | P0 | Canonical revenue, contribution, cost, margin, net profit, cashflow, debt/equity/interest, returns, taxes, fiscal periods, currency and accounting basis definitions. | Different pages using the same canonical business data and period agree or explain the difference. |
| R093 / U05 | Scenario Provenance | Data | P0 | Capture model ID/version, data snapshot hash/ref, inputs/overrides, units, author, source time, business/location/period, warnings and history. | Saved scenarios can be reproduced without changing historical interpretation when live ERP data later changes. |
| R094 / U06 | Cross-Module Impact Engine | Feasibility | P0 | Link effects on stock, purchasing, recipes/BOM, manufacturing, delivery, sales, staff, cash, financial obligations and approvals; apply explicit dependency graph without implicit double counting. | Branch expansion example shows upstream production/supply/cash effects and explains missing links. |
| R095 / U07 | Feasibility & Constraint Engine | Feasibility | P0 | Budget, cash buffer, supplier lead time, transport, plant/warehouse capacity, staff hours, machine throughput, space, project limits and availability windows. | An infeasible decision is identified with exact breached constraint; it is not shown as readily executable. |
| R096 / U08 | Integrated Financial Modeling | Finance | P0 | Link profit-and-loss, timing of receipts/payments, working capital, assets/liabilities, loans, principal, investor distribution and restricted cash; staged balance-sheet logic only where ledger contracts support it. | Illustrative profitable-but-cash-negative scenario reconciles, no principal repayment counted as operating expense by mistake. |
| R097 / U09 | Sensitivity & Driver Analysis | Feasibility | P0 | One-way, multi-variable and break-even threshold impact of price, volume, cost, lead time, discount, FX, rent, staff and term length. | Top drivers and exact assumption deltas reconcile to base scenario; all variable bounds validated. |
| R098 / U10 | Risk & Stress Testing | Risk | P1 | Named shocks and combined stress cases: demand fall, inflation, interest/return obligation, vendor delay, breakdown, staffing shortage and project slippage. | Every stress result displays assumptions and range, not a claimed guaranteed future outcome. |
| R099 / U11 | Reverse Goal Planning | Optimization | P1 | Target profit, cash reserve, sales, working capital, service level or capacity with inverse calculation of feasible price/volume/cost and resource requirements. | Shows when target is impossible under existing constraints instead of inventing unattainable numbers. |
| R100 / U12 | Constraint-Based Optimization | Optimization | P1 | Compare feasible resource/budget/capacity/stock/production allocation choices against owner-selected objective (cash, margin, service, risk). | Result declares objective and tradeoffs; honors all hard constraints and never substitutes recommendation for owner approval. |
| R101 / U13 | Multi-Scenario Portfolio | Optimization | P1 | Combine owner-authorized scenarios across same portfolio/business/period and expose concurrent capex, cash, people, stock and machine contention. | Two individually feasible branch expansions with joint cash shortage are flagged; no independent tenant blending. |
| R102 / U14 | Advanced Uncertainty Models | Risk | P2 | Optional probability/range or Monte Carlo only with validated input distributions, correlations, model suitability and documented confidence limits. | Missing statistical basis disables probability claims; output clearly distinguishes illustration from calibrated probability. |
| R103 / U15 | Decision Lifecycle Register | Governance | P0 | Draft → Simulated → Reviewed → Approved/Rejected → Eligible-to-Apply → Applied → Monitored → Closed with actor/role/timestamp and state history. | No direct skipping of required approval gates; approved decisions remain traceable to exact scenario/version. |
| R104 / U16 | Approval Workflow Integration | Governance | P0 | Reuse canonical ERP request/approval service with financial/operational authority, segregation of duties and delegated thresholds. | No new parallel approval engine; rejected/unauthorized execution is blocked at server. |
| R105 / U17 | Actual vs Plan Tracking | Outcome | P0 | Store baseline plan from approved simulation and reconcile future real P&L, volumes, stock, staff, capital and cash outcomes with period/location scopes. | After 30/90 days actuals, variance is derived from verifiable records and planned assumptions. |
| R106 / U18 | Decision Performance Review | Outcome | P0 | Owner sees actual net benefit, liquidity impact, constraint incidence, ROI/payback when valid, variance reasons and retrospective decision notes. | Reviewed case shows realized vs projected outcome without rewriting the historical simulation. |
| R107 / U19 | Forecast Accuracy & Bias | Outcome | P1 | Track comparable forecast-vs-actual accuracy by model, input data period, business, category and horizon; identify persistent bias. | Quality checks handle missing actuals, data leakage, changed definitions and incomparable periods. |
| R108 / U20 | Early Warning & Replanning | Outcome | P1 | Detect cash gaps, stockout, capacity bottlenecks, financing due, large variance and delays; propose refresh/replan, optional authorized alert workflows. | Owner sees evidence and threshold; no automation silently modifies the operational plan. |
| R109 / U21 | Collaborative Scenario Review | Governance | P1 | Role-scoped scenario comments, reviewer roles, business manager/accountant/production advice, attachments and review evidence. | Staff cannot retrieve restricted finance details/other businesses through collaboration or exported reports. |
| R110 / U22 | Multi-Business Consolidation | Integration | P0 | Business/brand/site/factory/warehouse/project comparisons with tenant boundaries, elimination of internal movements, compatible currency/period/accounting bases. | Portfolio summary reconciles without double counting internal transfer or external tenant data. |
| R111 / U23 | Investment & Financing Integration | Integration | P0 | Draw on verified partner/loan agreement definitions: equity, actual-profit shares, principal-based contractual return, loan, repayment/interest, maturity, investor liquidity claims. | Financing cases show cash obligations and classification accurately; no global all-locations aggregation bug. |
| R112 / U24 | Secure Scenario Application | Integration | P0 | Separate simulation read sandbox from proposals; explicit before/after diff, permission and approvals, only domain-validated transactional action, idempotency and audit/recovery; unsupported Apply remains advisory-only. | No unapproved changes to sales/stock/payroll/accounting; direct RPC bypass attempts denied. |
| R113 / U25 | Enterprise UX & Reporting | Integration | P0 | One Simulation Lab + Contextual Quick Simulation, BN/EN support, mobile/tablet/desktop, charts, comparative tables, saved search/export, usable accessibility and safe errors. | Same model yields same result in both entry points; responsive role-scoped UI and exported reports work end-to-end. |
| R114 / U26 | Security, Licensing & Scale | Integration | P0 | RLS/RPC/backend tenant/business/site/user action gates, scenario entitlements, access revocation, authorized cache/offline, bounded compute and 300+ site performance tests. | Real signed-in cross-tenant negatives and 300+ site benchmark must pass before claiming enterprise-ready. |

**Priority is relative WITHIN A025 only**, not permission to jump ahead of current ERP P0 work. All P0 items need to be completed before calling the combined capability ready. P1/P2 are defined scope and can be phased as part of genuinely end-to-end verified package delivery; any postponed advanced feature is flagged visibly in capability registry, not silently claimed to be ready.

## 3. Architecture: one decision lifecycle and shared ERP interfaces

Authenticated context and data readiness → certified/versioned deterministic model and source snapshot → scenarios/constraints/financial projection and comparison → review/approval → **only authorized domain-specific execution** → actual-vs-plan review → forecast accuracy and replanning.

**Existing ERP integration contracts, to be designed after deferral ends:**

- Business/Tenant/Org/Location context resolver (C10-A018–A021): RLS plus explicit business/tenant identity, staff role/operation permission and module entitlements; never use first-business fallback or a global company-allocation shortcut.
- Financial canonical measures (C10-A022–A023): link actual receivables, payables, money movements, capital, investor contract payout, P&L and projected liquidity, without treating capital principal repayment as operating expense or profit share as guaranteed return.
- Inventory/production/branches/projects: reconcile stock ledgers and BOM/yield, verify unit conversion, supplier lead time and capacity constraints before projecting enterprise behavior.
- Owner Approval and actual posting: reuse canonical request and domain-specific posting services; do not build a shadow ERP ledger or new generic SQL mutation API.
- Reporting: canonical business/scope/period/provenance, group elimination for internal stock movement and intercompany entries, exchange rates when needed; consistent report definitions across the Lab and Quick UI.
- Model Registry: types, rounding, fiscal periods, currencies, formula revision, parameter bounds, versioned computation, test fixture and readiness label tested/partial/unavailable; risk models require statistically defensible assumptions.

## 4. Required end-to-end decision workflow

1. **Problem or goal** — authorized owner specifies target, risk appetite, constraints and business/branch/project scope.
2. **Trusted baseline** — selected actual ERP data, snapshot timestamp, freshness and gaps. Unknown never becomes numeric zero.
3. **Scenarios** — baseline, conservative, optimistic, custom, saved alternatives; input/model version is immutable for completed runs.
4. **Feasibility** — assess stock/production/vendor/staff/cash/time/space and finance limits; mark infeasible cases with reasons.
5. **Cross-module impact** — propagate validated dependent effects and compare price/sales/profit/cashflow/capacity, including interactions among multiple concurrent decisions.
6. **Optimization** — goal seek and choose trade-off objective subject to hard constraints; advanced probabilistic risk only with valid distribution evidence.
7. **Owner review** — explicit decisions, evidence, comments, limits, authorization threshold, approved/rejected/deferred.
8. **Apply only if supported** — original scenario stays hypothetical; explicit diff and transactional posting call existing approved ERP workflow; no default write permission.
9. **Outcome review** — later actual-versus-plan, variance reason, realized cash impact, lessons, forecast error and optional replan with new version.

### 4.1 Example: Factory + Branch expansion
Simulate 1 new sweets branch, increasing rent, staff, utilities, raw material costs and sales; quantify current factory output capacity, demand shifts/cannibalization with existing branches, supplier lead times, cash purchase vs supplier credit, stock replenishment, transport/logistics, financed capex and investor payout. Check whether projected profits are feasible **and** whether 13-week/rolling monthly cashflow remains viable. Detect two proposed branches competing for the same cash/production capacity.

## 5. Finance-specific rules

- Use canonical profit definition and accounting basis. Distinguish Revenue, Gross Margin, Contribution, Net Profit, OCF, Free Cashflow, Available Cash, Receivables, Payables, Inventory, Working Capital, Borrowing, Equity and Investor Return.
- Model cash timing vs accrual profitability explicitly; include loan principal, interest/contractual return, investor distribution, inventory buying, capex and dues separately. Include 13-week cash view and multi-month cashflow where input readiness permits.
- Use correct formula units, precision/rounding, currency and period; cap mathematically invalid combinations and division-by-zero; avoid unsupported tax/legal/sharia claims.
- For independent tenants, prohibit shared consolidation or cross-tenant simulation; group/portfolio views only when authenticated Owner authorization and same portfolio semantics support them.

## 6. Role & report rules

- Separate Platform Admin/model/entitlement permissions from Tenant Owner Business simulation and Business Owner local decision permissions. Staff/Manager/Accountant/Investor get only explicitly granted scenarios and fields.
- Role permission and Show/Locked/Hidden UI behavior both apply, but UI state never grants server data access. Ensure finance privacy on drafts, comments, exports, saved snapshots, cached result files and audit history.
- Reports include baseline provenance, decision rationale, tradeoffs, model/formula version, assumptions, missing data, relevant prediction/actual variance, constraint breaches, security scope and signed approval state where needed.
- All UX must have responsive phone/tablet/desktop, natural supported Bangla/Bangla-English/English and keyboard/touch/accessibility validation; direct navigation in existing Owner Board, not a second administration system.

## 7. Delivery gates (NOT CURRENT WORK)

| Gate | Required verified evidence |
|---|---|
| Gate 0: Dependency readiness | Count qualifying 2–3 future major verified ERP packages in existing NEXT ACTIONS, with six required completion properties; C10-A018–A021 safe; relevant A022/A023 calculation/report contracts passed; no outstanding P0 security blocker |
| Gate 1: Calculation foundation | Snapshot, model registry, input schema, typed money/units, deterministic formula version and golden tests |
| Gate 2: Integrated pilot | First complete Industry Pack model, actual ERP data, Scenario Save/Compare/Explain, role security, Lab + contextual Quick, verified report |
| Gate 3: Cross-module & constraint | Multi-workflow dependency graph, financial reconciliation, capacity/cash constraints, no double count, sensitivity and measured feasibility |
| Gate 4: Decision governance | Approval/Apply with proven domain actions only, auditable history, actual-vs-plan and variance tests; otherwise advisory-only |
| Gate 5: Advanced catalog | Reverse goal, optimization, stress/uncertainty (only when statistically valid), model bias/replanning and multi-scenario portfolio |
| Gate 6: Enterprise release | Scoped 10-template coverage status, 300+ site perf target, concurrent users, refresh/recovery, cross-tenant REST/export tests, correct documentation, independent Owner approval |

Do not claim Phase/Gate passage based on a mock or green CI only. Keep incomplete industry models marked Partial/Not Implemented. Preserve original A025 Deferred until pre-development gate passes; independent product approvals for releases remain required.

## 8. Traceability and non-goals

- **C10-D039** original approved directive is unchanged; **C10-D040** extends product scope. Same **C10-A025**, with 26 detailed requirements **R089–R114**, one-to-one U01–U26. Preserve existing R081–R088 and C10-D030–D038.
- SaaS commercialization **C10-A024** is separate; no subscription billing, customer sign-up, tenant migration or external software sales under this extension.
- Do not link Trillionaire Me source/data/repos. Reusable mathematics or concepts must be independently implemented in CORE 10 after development eligibility.
- No live DB writes, RLS switch flip, merges, deployment, code migration or automatic scheduled activation. This is an **approved design specification**, not software execution.

## 9. Upgrade acceptance audit

Every U01–U26 entry has one-to-one R089–R114 traceability, implementation status not-yet-built, formula/data/security/report dependencies, and evidence expectations. The owner can later request more precise model details without reopening or losing the existing approved scope. Any change goes through existing DECISION REVISIONS and NEXT ACTIONS; no new governance book.