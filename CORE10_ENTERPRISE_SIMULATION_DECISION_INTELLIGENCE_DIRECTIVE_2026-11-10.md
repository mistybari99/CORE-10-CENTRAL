# CORE 10 CENTRAL — ENTERPRISE SIMULATION & DECISION INTELLIGENCE
## SUPER MASTER DEVELOPMENT DIRECTIVE

**Status:** OWNER-APPROVED PRODUCT SCOPE • **DEFERRED / NOT BUILT** • DOCUMENTATION ONLY  
**Decision:** C10-D039 • **Development action:** C10-A025 • **Requirements:** R081–R088  
**Captured:** 2026-11-10 • **Source:** Owner directive submitted in the CORE 10 CENTRAL development conversation  
**Repository:** mistybari99/CORE-10-CENTRAL • **Authoritative policy:** [Central Decision Book](https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit)  
**Code:** DO NOT implement until the explicitly defined deferred activation gate passes.

This document locks the Owner's complete requested scope for **one** future Enterprise Business Simulation & Decision Intelligence capability **within the existing CORE 10 CENTRAL ERP**. This is **NOT** Trillionaire Me, a separate app, a separate repository, a competing ERP, a license to change production, or a claim of implemented functionality. Generic concepts may be shared conceptually between products; no application code, repositories or business/customer data are to be linked or copied.

## 1. Project identity, governance and baseline
Before any eventual implementation, reconcile latest approved decisions, R001–R088, scheduled priorities, **current main** code, schema, user/session security, deployment configuration and pending PRs. Adopt the existing AI development governance, Decision Book, security release gates and change/revision history. Work only in this ERP repository using existing approved workflows; never duplicate backlog entries or create a second master task list.

Relevant existing sources include the CORE 10 Draft PR #6 architecture, **C10-A018 through A023** foundations, and separate deferred commercial SaaS **C10-A024**. The Decision Book, not this standalone document, owns approval/status precedence; this document is the full technical scope attachment.

## 2. Owner's business objective
Enable a business owner to model decisions **before** committing cash, stock, people, capacity, facilities or operational changes. The system should calculate alternatives, compare assumptions, forecast cashflow/expenses/capacity, expose constraints and risk, estimate margins, profitability and working capital, evaluate procurement/financing/expansion and department impacts, and produce transparent business-scoped decision reports. It must be one professional enterprise decision-support system—not disconnected beginner calculators.

Support existing portfolio businesses and properly authorized future independent customer tenants.

## 3. Absolute timing — REGISTER NOW, DO NOT BUILD NOW
**Hard development stop:** build only **AFTER the next TWO TO THREE major completed and verified ERP development packages** and only after all applicable security, entity, context and calculation/report dependencies have passed. Neither the existence of a design document nor an ordinary CI green check authorizes starting this module.

A **qualifying major completed package** MUST demonstrate:
1. Working end-to-end business workflow.
2. Required database and service integrations.
3. Correct authentication, business scoping and authorization.
4. Relevant reports, calculations and input validation.
5. Automated tests AND integration verification with real evidence.
6. Verified completion and **no unresolved critical defect** affecting that workflow.

**DO NOT COUNT:** documentation-only packages, preliminary audits, cosmetic corrections, partial mock screens, theoretical formulas or modules not fully integrated. Do not invent a package counter or assume a PR is a completed package because CI passed. A concrete evidence link, acceptance outcome, deployment/release status where applicable, and owner governance signoff must support each qualification.

Prerequisite matrix:
| Dependency | Purpose | Required gate |
|---|---|---|
| C10-A018 | canonical Platform/Tenant/Legal Entity/Business/Operating Site/Location + capability registry | verified entity contract, ID continuity, feature manifest |
| C10-A019 | tenant/business isolation and secure owner identity | real signed-session security-negative matrix, RLS/RPC/Storage/export checks |
| C10-A020 | automatic business/site provision and valid operational context | properly mapped business/location and capability readiness |
| C10-A021 | Master + Business Owner controls, module and role permission | authenticated access/visibility tests |
| C10-A022 (relevant) | partner/investor financial agreements and obligations | versioned finance, payout/cashflow/profit basis contracts; no cross-business pooling |
| C10-A023 (relevant) | reporting/KPI calculation definitions | source-of-truth, period/valuation definitions and reconciled financial metrics |

Unresolved P0 security or critical data integrity blocks override the 2–3-package milestone. Do not interrupt existing higher-priority queue to make this work eligible. Update **existing C10-A025** only when verified evidence, sequencing or status changes. **C10-A024** remains the separately deferred SaaS commercialization scope.

## 4. Platform ownership, tenant ownership and commercial boundary
**Master Platform Owner** exclusively owns/control CORE 10 software source code, IP, architecture, product releases, platform-wide module catalog, licensing, subscription/commercial products, authorized customer onboarding, platform configuration, and explicitly authorized tenant provisioning/support grants.

**Independent Tenant Owner** owns/controls the authorized tenant's actual business operations, records, assigned staff, branches and allowed settings. **Business Owner** manages correctly scoped businesses. **Staff/Manager/Accountant/Approver/Investor** have only their granted business/site/data/action permissions.

These identities are **not interchangeable**. Software/IP ownership does **NOT** imply silent access to an independent customer's private operational data. No covert super-admin tenant reads, hidden data aggregation or bypass. Enforce independent tenant isolation, lawful data processing/retention/deletion, portability, explicit narrow support grants, revocation and audit. Design future platform-wide entitlements now; implement public customer subscription billing, external onboarding, white-label sales and dedicated deployments **later under C10-A024**, not in this module.

## 5. One integrated modular architecture
These are cohesive **logical responsibilities**, not a mandate for ten new microservices or duplicate implementations:
- **Simulation Model Registry:** typed model definitions, formula references/versions, supported datasets and industry packs, inputs/units, permissible business contexts, output contract and release/readiness state.
- **Context Resolver:** authenticated tenant/business/site/location/user, active workflow, permission/feature entitlement, valid input records and applicable models.
- **Deterministic Calculation Engine:** decimal-safe calculations, units, periods and explicit validated assumptions; pure and reference-tested where practical.
- **Scenario Manager:** create/save/duplicate/compare/archive/restore owner-authorized hypothetical scenarios; preserve input snapshots and scope.
- **Comparison and Sensitivity Engine:** price, rate, costs, demand, volume, duration and resource constraints with alternative outcomes and uncertainty.
- **Projection Engine:** time-indexed cashflow, operational output and forecasts with clear source assumptions.
- **Decision Insight Engine:** explainable thresholds, cost drivers, trade-offs, bottlenecks, risk warnings and actionable alternatives; calculations, not unverifiable AI certainty.
- **Scenario Approval and Application Gateway:** proposed real action must pass preview, actual workflow validation, authorization/approval, transaction, idempotency and audit; no generic writes.
- **Reporting and Export Layer:** scoped charts, historical scenarios, business decision report and exports.
- **Permission, Audit and Entitlement Layer:** platform/tenant/business/site/location/user/role/action and model licensing, source provenance, revocation, history.

Inspect current calculation modules and existing ERP services **before** designing a new formula API or UI component. Prefer a maintainable single modular architecture over infrastructure overengineering.

## 6. TWO first-class experiences: full lab AND contextual quick simulation
### A. Central Business Simulation Lab
A distinct authorized Business Simulation / Decision Intelligence area **inside existing ERP navigation**, not a new ERP or a duplicated administration system. Choose the currently authorized business/site scope and category; retrieve valid data, manually add missing assumptions, choose models, edit amounts/sliders, compare cases, show charts/tables and calculation steps, save drafts, review previous runs, export and submit authorized proposals when supported.

### B. Contextual Quick Simulation
Place **Calculate / Simulate / What If** directly inside relevant existing workflows, using the SAME models/permissions and correctly resolved business context:
- Item/Product: price, gross/net margin, discount, packaging cost and cost sensitivity.
- Inventory: reorder quantity, safety stock, stockout, carrying cost and working capital.
- Purchasing: supplier comparison, bulk discount, credit terms and cash effect.
- Food Manufacturing/Bakery: BOM/recipe/yield, production batch volume, ingredient costs, waste/spoilage, labor, energy and unit cost.
- Branch/Showroom: feasibility, sales volume, rent, staffing and break-even.
- Transfer/Logistics: fuel, vehicles, transport, route/shipment assumptions and allocation.
- Sales: price/discount policy, targets, mix and contribution.
- Projects/Construction: BOQ/material/labor budget, progress/completion, variations/overrun and cashflow.
- Investment/Financing: funding, equity/partner/non-equity investor agreement, principal, payment schedule, obligations and alternatives.
- Expansion: new branch, new factory, business launch, capacity, capital needs and constraints.

Show **ONLY** models that are actually supported by the active business industry pack, permission/entitlement, trustworthy context and tested engine. No meaningless calculator appended to every page for decoration.

## 7. Extensible enterprise model universe — twenty families
1. Pricing, markup, margin, contribution.
2. Break-even volume/revenue/cost.
3. Profit & loss alternatives.
4. Cashflow and liquidity projection.
5. Inventory replenishment, stock holding and stockout.
6. Supplier procurement and payment term scenarios.
7. Production costs, yield, waste and efficiency.
8. Staff and operating-resource capacity.
9. Transport, transfer, distribution and logistics costs.
10. Working capital and business funding.
11. Capex, depreciation considerations and payback where valid.
12. ROI, NPV and IRR only on correct, explicitly stated assumptions.
13. Loan repayments, fees, financing and interest obligations.
14. Investor/partner agreement cashflow, profit-based shares and contractual returns.
15. Project costing and completion scenarios.
16. Branch, warehouse and factory expansion.
17. Product/sales mix, price sensitivity and demand.
18. Industry-specific tax, duties, discounts and fees only when configured and validated.
19. Multi-site operational and group comparisons with anti-double-counting.
20. Owner-authorized custom simulation templates, using validated extension points.

This list is the **intended catalog**, not a declaration that any model is ready. Do not conflate interest, actual profit-based payouts, debt liabilities, equity ownership/returns and hypothetical forecast. NEVER guarantee returns, future sales, savings or profit.

## 8. Shared engine plus ten industry packs
Support Sweets & Bakery, Restaurant/Kitchen, Paint & Hardware, Retail & Wholesale, General Manufacturing, Construction, Import & Export, E-commerce, Technology & Digital Products and Services/Agency. Reuse one calculation engine; customize relevant inputs, BOM/price/production/industry units, validated formulas, role rules, outputs and report templates through registry/pack configuration. Allow verified future industry additions without recreating the engine. Do not mark a pack Ready until formula, workflow, data and security tests pass.

## 9. Scenario lifecycle, comparison and labeling
Support at minimum **Current Baseline, Conservative, Optimistic, Custom** and multiple saved owner alternatives. Compare sales/output, required capital, expenses, liquidity, costs/margins, projected profit under stated assumptions, capacity/resource constraints, risk/trade-offs and time-based outcomes.

Preserve tenant/business/site/user ownership, source ID references, input snapshot/time, hypothetical overrides, currency/units, analysis window, model/formula version, generated time and key calculations. Provide clear chart/table comparison where useful. Explicitly label every value **Actual / Estimate / Assumption / Scenario / Unknown**. Unknown, unavailable and null values must NEVER silently be treated as zero. Saved scenarios cannot overwrite current real business tracking merely because a user previews a different assumption.

## 10. Non-negotiable separation from operational data
Simulation calculations must **NOT** silently update stock quantity, stock valuation, sales, purchase, invoicing, accounts/ledger, payroll, inventory/production consumption, investor settlements, bank/cash balance, period close or audit history. Reading an authorized operational snapshot is allowed; writing real ERP transactions from a what-if calculation is not.

Future approved apply sequence:
**Scenario → Proposed Change → Before/After Preview → Permission Validation → Necessary Approval → Validated Transactional Operational Workflow → Audit Trail**.

Only use proven domain-specific ERP posting functions; NO generic SQL mutation gateway. Where no safe Apply workflow exists, the simulation remains an advisory proposal. Apply operations must have idempotency, rollback/recovery rules and correct transaction boundaries. Real data and legacy identifiers remain intact.

## 11. Calculation precision, sources, formula governance
Every model must document typed input and output definitions, monetary decimal arithmetic, appropriate precision, units/UOM conversions, date/time and period basis, currency conversion/FX source if used, percent/rate basis, tax/discount assumptions, signed cashflows, profit basis, accrual vs actual basis, rounding policy, validation and division-by-zero/invalid-input guards.

Maintain immutable model/formula version, reproducible input snapshot, full calculation breakdown, data source/provenance, limitations, uncertainty/missing flags and reference fixtures/regression tests. Never mix incompatible currencies, units, business scopes, periods or profit definitions. A transfer between company/warehouse accounts must not be double-counted as new external revenue or consolidated profit.

An AI explanatory layer may be added later, but it cannot replace verified deterministic calculations, provide fictional certainty or bypass role/approval gates.

## 12. Enterprise tenant and business security
Use the existing evolving hierarchy:
**Platform → Tenant → Legal Entity → Business → Operating Site → Stock Location**, retaining compatibility with existing IDs/mappings.

Secure all scenario definitions and rows, input data, model access, saved snapshots, charts/results, exports, comments, audit, reports, caches and shared links at the correct tenant/business/site/location/user scope. Enforce authentication and RLS + server REST/RPC validation, privilege-specific finance data restrictions, create/edit/archive/share/delete/approve/Apply permissions and feature entitlements. Verify true signed-session cross-tenant/business negative cases including revoked users, direct routes, export/report/cache and role changes.

UI hide or lock does not provide database security. DO NOT flip or delete legacy \`org_scope_on\` or deploy unsafe global RLS changes; complete already approved P0 migration gates first.

## 13. Master Owner entitlements and licensing boundary
Master Platform Owner may **eventually** grant complete ERP, selected industries, Simulation access, feature bundles, higher analytics, authorized staff/owner roles and subscription-level commercial entitlements. Entitlements must be enforced on server/backend, not only front-end toggles.

Independent Tenant Owner may manage authorized operational staff/permissions/settings without acquiring source code/IP, platform admin access or visibility into sibling tenants. Explicit time-limited support grants may be offered; platform licensing/IP control is never a hidden business-data privilege. Commercial billing, public signup, white-label onboarding and external SaaS deployment are **outside the present Simulation build** and remain C10-A024.

## 14. ERP-grade UX, localization and accessibility
Both mobile-first and responsive tablet/desktop. Reuse existing ERP navigation, business branding, role-specific menus and localization conventions. Use understandable labels/units, numerical fields and sliders where suitable, readable responsive scenario tables/charts, contextual tooltips, search/filters/history, keyboard accessibility, screen reader support, touch targets, and robust loading/empty/invalid/error/recovery states.

Keep natural Bangla, established Bangla-English mixed terminology and English if supported by existing localization architecture. Do not ship visually impressive yet disconnected or inaccessible calculators. A feature is usable only when it actually computes correctly and saves/retrieves authorized scenarios.

## 15. Performance and scalability
Design for current enterprise goal of **100+ branches, 100+ factories and 100+ warehouses in one business** and multiple authorized businesses/tenants; this is a capacity verification **TARGET**, not a current benchmark result.

Use efficient scoped queries/indexes, bounded heavy calculations, safe caching of authorized data/models, versioned input snapshots, shared formula reuse, scalable comparison data, controlled report generation without blocking operational posting and real concurrent-user performance tests. Record limits, resource/cost behavior and latency; do not introduce unneeded microservices.

PWA pure local simulations are permissible with valid cached authorized models/inputs, but label stale cache as stale and never pass stale results off as current operational facts or permit offline bypass of write approval.

## 16. End-to-end completion contract (when eligibility eventually passes)
Completion requires ALL of:
A. **Data contracts:** scenario types, model versions, typed field definitions, provenance, scope and lifecycle.
B. **Engine:** verified model-specific math and deterministic calculation.
C. **Backend:** scoped persistence, validation, policy enforcement, audit, authorized reporting.
D. **UI:** full standalone Lab AND contextual Quick Simulation.
E. **ERP integrations:** validated links with supported inventory, purchasing, manufacturing, sales, projects, finance, reporting.
F. **Security:** role/entitlement, RLS and negative access tests.
G. **Experience:** responsive mobile/desktop, supported localization/accessibility.
H. **Verification:** unit/reference fixtures, integration, scenario isolation, security, regressions, persistence/retry/recovery, browser checks.
I. **Release:** documented assumptions, backup/rollback when relevant, reviewed evidence and separate Owner approval.

A pretty form displaying numbers alone is NEVER module completion.

## 17. Operating and development governance
**NOW:** verify D039/A025/R081–R088; don't duplicate; store full directive and dependencies; keep D039 approved **scope** and A025 **DEFERRED/NOT BUILT**; advance approved higher priority ERP tasks.

**LATER — only after the explicit activation gate:** verify 2–3 actual finished major packages and all dependencies; audit latest actual code/database; reconcile old calculator/forecast functions; design implementable interfaces; build cohesive verified ERP-integrated stages; test and fix; record evidence; respect reviewed DB/PR/deployment owner release gates.

Do not ask Owner routine coding questions when safe evidence-based choices exist. Escalate ambiguous business-policy decisions, commercial terms, ownership/license rights, destructive operations, exceptions to security or irreversible financial/operational transactions. Do not consume engineering resources repeatedly rewriting identical architecture docs.

## 18. Definition of success
An authorized owner asks:
> "I want to open a new branch. If rent increases, staff costs change, sales rise or fall, raw-material prices change, and different investment structures are considered, show me the financial and operational impact **before** I make the actual decision."

The system accesses only authorized scoped data, surfaces missing assumptions, allows adjustments and comparisons, calculates validated projections, explains limits/bottlenecks/trade-offs, saves reviewable scenarios, and optionally submits an authorized proposal **without modifying real operational data** until a separate approved workflow.

**Final Owner Directive:** ONE powerful, modular, secure enterprise-grade Simulation and Decision Intelligence capability **within CORE 10 CENTRAL**, preserving software IP/licensing under Master Platform Owner while respecting independent tenant data. **REGISTER NOW; BUILD ONLY AFTER next 2–3 genuinely completed major packages AND cleared architecture/security dependencies.** No separate app, duplicate architecture, premature go-live or false completion status.

## Read-only baseline note — NOT A BUILD
As checked on 2026-11-10: live IMG-ERP-SG had **one active business**, \`org_scope_on=false\`, no installed \`core10_owner_inbox_v1\` RPC. Legacy \`forecast.js\` and \`public.fc_scenario\` exist and are potential future audit/reuse targets, not a completed enterprise Simulation Engine. No public table named with \`simulation\` or \`scenario\` was observed in the checked public schema; these partial findings are **not** a comprehensive inventory of all calculation code. Existing GitHub PRs #3–#6 were still Draft and not merged as observed. Future work must recheck this baseline; nothing here authorizes altering live SG.

## Traceability and activation evidence
- **Master decision:** C10-D039 (Approved scope, NOT built); **Action:** C10-A025 (Deferred), **Requirements:** R081–R088 on REQUIREMENTS LOCK.
- **Prior linked scopes:** D030 Enterprise Scale; D031 industry modules; D032 provisioning; D033 permissions; D034 investment; D035 reporting; D036 independent tenants; D037 security migration; D038 decision traceability.
- **Backlog dependencies:** A018–A023; **unrelated deferred commercialization:** A024.
- **Activation rule:** no coding, migration, implementation PR, UI screen or real-data simulation write under A025 until BOTH qualifying package count (2–3) and blocker/test dependencies are evidenced in existing development register. A qualifying package must have all six properties in §3. A package with evidence incomplete or critical defects unresolved counts **zero**.
- **Governance:** no need for a second project/agent/automation/task list. No live database writes, toggles, deployment or PR merges now.
