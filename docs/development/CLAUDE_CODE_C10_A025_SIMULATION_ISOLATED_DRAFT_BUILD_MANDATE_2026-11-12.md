# CLAUDE CODE — CORE 10 CENTRAL Enterprise Simulation & Decision Intelligence: ISOLATED FULL DRAFT BUILD
**Owner authorization:** 2026-11-12 (Asia/Dhaka)
**ERP repository:** mistybari99/CORE-10-CENTRAL
**Canonical register:** https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit
**Existing policy:** C10-D039; C10-D040; action C10-A025; requirements R081–R114 (original R081–R088 and v2 U01–U26/R089–R114).
**Mandate type:** CLAUDE CODE autonomous implementation instruction, not an instruction to Codex. This file is a coding handoff, not evidence implementation happened.

## ZERO-AMBIGUITY OWNER DECISION — START ISOLATED ENGINE DRAFT NOW
This latest Owner directive revises the **start-of-draft-development timing only** of the older “register now, DO NOT CODE until 2–3 completed packages” restriction. Claude Code may **NOW implement and test** an independent, additive, fully documented draft of C10-A025 in the SAME repository on a unique feature branch and open ONE dedicated **DRAFT** PR. No feature code is authorized for main/active development merges, no deployed URL, live ERP navigation injection or production Supabase schema/RPC/data changes, no public SaaS activation, and no paid service.

The original two-to-three **genuinely completed, fully verified** major packages plus all A018/A019/A020/A021/A022/A023 and P0 security gates **still apply before integration activation, release/merging, actual tenant access or operational use**. A partial or isolated PR (including earlier C10-A058) does NOT count as a fully completed enterprise package. Do not reclassify C10-A025 as operationally BUILT, merged, deployed or ready. Track separately:
- Scope: APPROVED.
- Isolated draft coding: **AUTHORIZED** (new exception).
- Draft implementation evidence: only after real commits and tests.
- Integration/release: **BLOCKED / DEFERRED** pending original owner gates.
- Commercial SaaS C10-A024: entirely separate DEFERRED initiative.

Avoid repeating basic decisions with owner. Make standard technical choices yourself from verified existing code, document them, and escalate only genuinely destructive production, legal policy, security bypass, money movement or irreversible action.

## 0 — AGENT, GIT AND NON-INTERFERENCE
- This implementation is assigned specifically to **Claude Code**. Codex/other concurrent agents may work on separate PRs. Never reset, rebase, auto-merge, cherry-pick or overwrite their work without coordinated ownership. Never push to another agent's branch.
- Source of truth is latest verified Decision Book + revision log and real GitHub state/CI; inspect actual main, open PRs, exact base SHA, .github workflows, project coding/handoff instructions, deployed UI conventions, and migration history before choosing files.
- Create **feature/c10-a025-simulation-isolated-draft-v1** if free; use another collision-free suffix otherwise. Base from the latest safe canonical baseline and explicitly state its SHA. If an unmerged foundation is required, base from the reviewed canonical A018 foundation branch and make draft PR targeting that baseline, not main, to prevent mixing unrelated changes.
- Keep the entire build inside the existing repo: no separate GitHub repository, “Simulation SaaS” app, duplicate ERP, Trillionaire Me code/data, shadow app/accounting ledger or cloned authorization engine.
- Code only in clearly owned additive paths, e.g. modules/simulation/*, internal/enterprise-sql/c10_a025_*, tests/c10_a025_*, .github/workflows/core10-a025-*, docs/development/c10-a025-*. Resolve these paths to the real repository conventions first. Avoid modifying Islamia business-specific code or current enterprise/Claude/Codex feature branches.
- An internal static or browser preview is allowed only as a **simulation module inside the repo**. A separate temporary demo route/page is fine for review, not a separate product and NEVER a live production feature flag.
- No changes to live secrets, paid plans, live production DB, customer data, invoices, bank accounts, stock, salary, payments, purchases, sales, GL, backups or existing operational schema. Fixture-only test DB and mock transport.
- Commit small coherent slices and push actual code; no infinite planning, TODO-only implementation, empty components or invented CI PASS claims.
- Keep same-repo transferability; handoff must allow future agents to continue without the prior chat.

## 1 — PRE-CODE RECONCILIATION (short, bounded, source backed)
- Read C10-D039 18-section approved directive and C10-D040 26-upgrade extension referenced by the Decision Book (do not rewrite or delete them). Verify R081–R114 actual text/acceptance.
- Inspect canonical enterprise hierarchy, C10-A018 business/site/item/catalog, C10-A019 tenant isolation, C10-A020 provisioning, C10-A021 platform/tenant/business authority, C10-A022 financing/profit definitions and C10-A023 KPI reporting. Inspect PR #7, PR #20 existing simulation-like prototypes, PR #60 visual preview and current Claude/Codex PR branches; identify proven reusable contracts, fake-only objects and blocked dependencies. Actual PR numbers/SHAs may have changed.
- Inspect what language and module system truly exist (legacy JS, modules, PG17 Supabase, build/test utilities). Choose a **modular in-repo core**, not a large microservice stack. If the existing app does not use React, do not introduce React solely for this engine.
- Produce a concise existing-code reuse/gap matrix; do not reimplement authenticated RLS, item master, existing A022 finance, production BOM or KPI contracts in parallel.
- Reference source SHAs and precise source files in the technical note. Never infer true Supabase signed Auth production security from fake PostgreSQL role claims.

## 2 — ARCHITECTURE: ONE VERSIONED REUSABLE ENGINE
Construct these cooperating responsibilities, with small explicit contracts rather than excessive services:
1. **Canonical Model Registry** — immutable identifiers, versioned formula specs, input/output schema, units, semantic business definitions, supported industries/contexts/entitlements, availability/testing level, unsupported-source reasons and fixture IDs.
2. **Context Resolver Adapter** — accepts only an already authenticated, authorized tenant/business/legal entity/site/location/user/context/permission result from canonical ERP backend; never trusts browser-supplied IDs. Enforces financial confidentiality.
3. **Input + Provenance Validator** — stable decimal units/precision, currency and price/tax bases, period, scenario horizon, calendar, source hash/last updated/authorization, unknown vs zero, stale data and independent user assumptions.
4. **Deterministic Calculation Kernel** — pure, side-effect-free math; fixed-precision decimal or audited integer minor units and rational rates. Strictly avoid JS floating-point monetary drift.
5. **Scenario Manager** — baseline/conservative/optimistic/custom; create/clone/version/save/reopen/archive/compare drafts, ownership and audit; preserve immutable model/input/source snapshot after calculation.
6. **Projection + Comparison + Sensitivity** — month/week/date-aware projections; one-way & multi-var stress; absolute, percentage and percentage-point deltas; rank drivers; bounds and convergence limits.
7. **Constraint/Feasibility + Cross-Module Graph** — cash buffer, inventory lead time, labor, throughput, recipe yields, sites, financing due, transportation and construction project limits. Declare dependencies/unknowns; prevent double counting internal movements and principal repayments.
8. **Decision Insight Rules** — derived, deterministic and explainable threshold findings, feasibility warnings, tradeoffs and required missing inputs. No “guaranteed ROI” / AI-generated unsupported conclusions.
9. **Decision Lifecycle + Proposal Gateway** — draft → simulated → reviewed → approved/rejected → eligible-to-apply → applied → monitored/closed as **designed contract**. Draft engine must default all Apply actions to ADVISORY ONLY. Never create a generic operational write method; only later attach authorized canonical domain commands after actual approvals, idempotency and full real-auth E2E.
10. **Report/Export Adapter** — JSON reproducible result contract; PDF/CSV only if existing licensed safe export stack is suitable; include scope, units, limitations, formula version, source provenance, confidentiality, no unverifiable tax assertion.
11. **Entitlement/Audit boundary** — future platform licensing contract separate from tenant record ownership; no platform operator covert cross-tenant read; scoped cache/export and audit events.
12. **Industry + Context Adapters** — data-driven catalogs for ten existing families and contexts, one calculation kernel.

Keep registries and formulas under semantic version control. New models enter via a documented registration interface and mandatory new golden fixtures; previously saved scenarios remain pinned to their old formula/model versions. Do not mutate old outputs on release upgrades; use explicit migrate/recompute/compare workflows only.

### Suggested deterministic interfaces (adapt to existing runtime)
- ModelDefinition: id, version, status, industryIds, contextKinds, typed inputs, units, requiredPermissions, dataRequirements, formulaId, outputs, assumptions, limits, fixtureIds.
- ScopeContext: tenantId, legalEntityId?, businessId, siteId?, locationId?, periodStart, periodEnd, currency, userId, grantedCapabilities, sourceAuthRef.
- InputValue<T>: value (decimal string/typed), unit, currency?, periodBasis?, kind = actual|estimate|assumption|scenario|unknown, sourceReference?, observedAt?, confidenceClass?, taxBasis?.
- ScenarioSnapshot: scenarioId, sourceHash, modelId/version, scope, inputs, overrides, riskWarnings, createdBy, createdAt, status, immutable evaluation records.
- SimulationResult: outputs, breakdowns, units, crossModuleImpacts, constraints, sensitivities, warnings, readiness, requiredInputs, formulaVersion, inputHash, computedAt, sideEffects = [].
- ModelPlugin interface: describe(), validate(), calculate(), explain(), testFixtureReferences(). No arbitrary dynamic user JavaScript, eval, SQL expression eval or untrusted arbitrary formulas.
- PermissionAdapter: canReadOperationalSource(), canSimulate(), canSave(), canShare(), canExport(), canPropose(); deny by default.
- DataProvider: authorized **read only** signed scope snapshot, freshness, consistency snapshot, provenance; future fetch by existing API. For draft, mock providers only.

## 3 — MODEL LIBRARY: 20 FAMILIES (DO REAL MATH, NOT PLACEHOLDER LABELS)
Implement a tested shared model kernel, then increase supported models incrementally but substantially within this single draft PR. Include all 20 families in the registry with status only reflecting actual tested implementation:
M01 pricing/markup/gross margin/contribution (different denominators, discounts, rounding).
M02 break-even quantity/revenue, fixed/variable cost, target profit and contribution margin.
M03 operating P&L (cost basis, accrual/cash separation).
M04 receipts/payments cashflow and opening/closing liquidity, working capital.
M05 reorder point, lead time, safety stock assumptions, inventory carrying costs.
M06 supplier quote/unit normalization, bulk discounts, payment terms and landed-cost prerequisites.
M07 BOM, yield, waste/spoilage, labor/energy, per-good-unit production cost.
M08 staff hours, machine/counter capacity, shift coverage and bottleneck constraints.
M09 multi-location transfer/vehicle/shipment/cost and allocation alternatives.
M10 working capital, cash conversion, operational financing.
M11 capital expenditure/payback including nonrecoverable setup costs and residual values.
M12 ROI, NPV, optional IRR using appropriate signed cashflow conventions and bounded solver.
M13 amortized/fixed-principal loan repayment, explicit rates/terms/fees and separate principal vs interest.
M14 contract-specific investor/partner financing: actual profit share vs principal-based fixed contractual payments vs equity vs debt; NEVER classify as guaranteed profit, Sharia-compliant, or risk-free merely by label.
M15 construction project BOQ/material/labor/retention/variation/delay cashflow.
M16 branch/factory expansion start-up cash, staffing, rent, break-even and staged sales forecast.
M17 demand, mix, volume, discounts, channel contribution and sensitivity.
M18 custom tax/fee preview ONLY when configured/verified; do not assert legal Bangladesh VAT rates.
M19 tenant-authorized same-portfolio multi-site comparison and elimination of internal transfers.
M20 owner-authorized **data declarative** simulation templates constrained to allowed typed expressions/model compositions; no arbitrary execution or forged entitlement.

For each truly implemented model deliver:
- data schema, required/optional typed inputs, default policy (unknown ≠ zero), outputs, formula and dimensional-analysis note;
- bounds, precision/rounding, currency/period/accounting semantics, edge cases and disabled unsupported combinations;
- 2+ independently derived numerical goldens incl. at least one adverse case;
- identical results in central vs quick entry;
- model-specific risk/assumption explanation;
- registered implementation/testing status.
For missing robust domain source or unacceptable finance ambiguity: keep registry entry \`research_only\`/\`not_implemented\`, explain blocking source or dependency; never fake calculations to reach arbitrary breadth. Target maximal honest tested coverage, especially price, break-even, cashflow, stock, production, loan and branch expansion first.

## 4 — V2 U01–U26: NO SILENT OMISSION
Implement or explicitly, visibly block each preapproved upgrade with requirement IDs:
- U01 R089 authorized trusted baseline snapshots and cutoff dates
- U02 R090 data quality/freshness/readiness grading
- U03 R091 versioned, fixture-certified model registry
- U04 R092 canonical financial definitions
- U05 R093 scenario provenance/immutability
- U06 R094 cross-module impact dependency graph
- U07 R095 feasibility constraints
- U08 R096 P&L/cashflow/working capital linkage
- U09 R097 bounded sensitivity
- U10 R098 stress testing
- U11 R099 reverse goal planning
- U12 R100 hard-constraint optimization with bounded solver
- U13 R101 coordinated portfolio scenarios, only authorized scope
- U14 R102 optional calibrated uncertainty; uncalibrated Monte Carlo probability claims forbidden
- U15 R103 decision state machine
- U16 R104 existing ERP approval adapter
- U17 R105 future actual vs plan on verified actuals
- U18 R106 decision performance review
- U19 R107 forecast accuracy/bias only on comparable actuals
- U20 R108 early warning and replanning from evidence
- U21 R109 reviewer comments/permissions
- U22 R110 consolidation and intercompany elimination
- U23 R111 funding/partner/loan semantics and liabilities
- U24 R112 safe scenario application gateway locked/advisory by default
- U25 R113 central + contextual UX, reports, BN/EN
- U26 R114 RLS/auth/licensing/perf including 300+ site verified-load target.
Maintain a versioned requirements coverage matrix: \`proposed | implemented | tested | integrated | signed-auth verified | production approved\`; do not claim 26 fully built from their presence in JSON.

## 5 — DATA SAFETY AND SECURITY (MUST BE FAIL-CLOSED)
- Hypothetical calculations NEVER modify inventory, sales, purchase, GL, cash, payroll, bank, invoices, BOM consumption, owner approvals, investor ledger, operational audit or master item state. Scenario persistence is a distinct isolated namespace.
- Build optional **additive scoped scenario tables/RPCs** only in disposable schema/migration draft after verifying canonical FKs and policies. For now use fake tenants and synthetic auth claims for tests; clearly label NOT SIGNED AUTH, NOT PRODUCTION.
- Proposed tables (adapt FKs): model_registry (immutable published version), scenario_drafts (tenant/business/site/user owner and visibility), scenario_inputs, scenario_runs (input+model+source hashes), scenario_comparisons, scenario_annotations, scenario_decision_events (append only), scenario_exports, decision_proposals (advisory-only). Avoid duplicate real canonical entities and needless tables.
- Data constraints: unique tenant/business/request-key; immutable evaluation source snapshots; enum lifecycle transitions; double-submit and concurrent updates protected via revisions/idempotency; audit; optimistic revision/ETag as appropriate; strict saved scenario scope.
- No generic arbitrary RPC write to operations. No admin/service-role browser keys. No SQL SECURITY DEFINER without carefully checked, read-only or scoped operations, explicit search_path, function privilege revokes and vetted object dependency.
- Cover Owner, Tenant Owner, Business Owner, Finance, Manager, Site Staff, Investor (if authorized only), revoked user, unrelated tenant, anonymous. No platform-owner global customer-data privileges by default. Test direct SQL/RPC/REST unauthorized access, reports, exports, caches, scenario share, revoke, cross-site, partner data.
- Scoped tenant owner consent for financial information. An Investor may only see explicitly shared scenarios; their actual participation does not grant global finance data access.
- Truly signed Supabase GoTrue/PostgREST negative tests require a separate staging project and existing P0 migration gates. Fictitious jwt claim SET is a **synthetic preliminary test**, not certification.
- No live production authorization, schema modification, security flags, service keys or read-only “admin fallback” hacks.
- Existing SaaS licensing entitlements are design-only and not commercial billing authorization.

## 6 — CALCULATION CORRECTNESS AND MODEL FITNESS
Financial rules MUST be deterministic, reproducible, audited and unit-aware:
- Monetary quantities as decimal strings or exact minor units; consistent quantity units (kg/g, piece/carton, lb, litre, staff-hour), dimension conversions and explicit currency. If exchange-rate evidence is unavailable, cross-currency result = unknown, not converted.
- Define inclusive/exclusive tax, per-unit vs total, discount-on-gross vs net, revenue vs cash, markup-on-cost vs margin-on-revenue, period alignment and actual vs assumed profit.
- Distinguish annual effective vs nominal rate, compounding frequency, contract rate vs profit share, debt service vs expense, principal as financing cashflow vs P&L cost, projected vs guaranteed payout.
- IRR multiple-root/no-root/nonconvergence is flagged; NPV requires period/rate compatibility; break-even rejects zero/negative contribution when infeasible.
- Do not silently treat missing inputs as 0, valid negative signs as data errors, an unavailable amount as cash or interbusiness transfers as external revenue.
- Each result includes a traceable formula breakdown, input provenance/version/hash, scenario kind, measured/estimated/unknown indicators, exact assumptions, model limitations and warnings.
- Bound runs for CPU, memory, time, scenarios, horizon and input grid sizes, and test deterministic results under repeated requests and new code versions.
- Scenario simulations are not recommendations of guaranteed return or legal advice. Make simulation output advisory and reviewable.

## 7 — TWO UX ENTRY POINTS, SINGLE ENGINE (NO SECOND ERP)
### Central lab (existing owner navigation)
Task-first: choose authorized business/site/period → model or business question → load verified baseline/enter assumptions → choose baseline/conservative/optimistic/custom → compare → sensitivity → cash/capacity warnings → saved scenario → audit/export/report → advisory proposal if eligible. Provide clear input statuses, assumptions/unknown warnings, revisions and quality readiness. BN/EN natural operational labels, role-aware visibility, mobile 390px/tablet 768px/desktop 1440px, keyboard and touch, accessible tables/charts and error/recovery states.

### Contextual Quick Simulation
Provide a small reusable embedded component/controller inside relevant owner-authorized Item, Inventory, Purchasing, Production/BOM, Sales/Pricing, Branch, Transfer, Construction/Projects, Payroll/Staffing, Financing and Expansion workflows. **No existing live screens may be modified at this draft phase.** Instead ship actual adapter interface + isolated integration harness in the same repo with examples proving both entry points call identical registered model/version and compute identical results. Future attached toolbar/menu only when relevant module is enabled and backend authorizes that source/operation.

### Testable demo UI
Use repository's actual UI architecture and styles (preserve branding/legacy). Include meaningful interactive draft preview connected to the PURE engine, not arbitrary hard-coded charts. Synthetic examples across sweets/bakery, paint/hardware and construction, 2 isolated tenants, several sites/actors; no fake “connected/live” badges or pretend Auth. Show rich business choice comparisons and change effects under variable inputs. No standalone public app or separate hosted product.

## 8 — INDUSTRY PACKS
Use the ten canonical business families: sweets_bakery, restaurant, paint_hardware, retail_wholesale, manufacturing, construction, import_export, ecommerce, technology_digital, services. Read exact template IDs from repo before implementing. Packs register model applicability, source adapters, known units, financial conventions, menu contexts and fixtures. Future packs extend via a typed versioned manifest and permission-aware registrations; **not** ten calculator implementations or ten divergent ledgers. No model/pack marked READY without tested end-to-end relevant calculations. If no authenticated source contract exists, allow manual assumptions and show that source as assumed, not actual.

## 9 — SAMPLE GOLDEN BUSINESS JOURNEYS (FAKE ONLY)
A. Shop pricing: selling price, raw cost, wastage and discount changes → contribution, margin, cash timing and break-even.
B. Factory batch: BOM ingredient quantities, yield, machine/staff hours, gas/electricity and expiry waste → cost per sellable piece and throughput bottlenecks.
C. Branch opening: rent, deposit, fit-out, staff, expected daily sales, inventory needs, startup capital, fixed costs, operating P&L and monthly cash gap for conservative/base/optimistic horizons.
D. Purchase choice: two supplier offers, early payment discount, transport, lead time, inventory carrying cost and payment terms → margin/cash/depletion constraints.
E. Investment/loan: at least three structurally distinct contracts (profit participation, fixed contractual obligation and bank-style debt), clearly labelled cashflow/interest/profit definitions, installment timing and liquidity stress.
F. Construction: materials, labor, delay, retention, change order and staged receivables vs cost → project burn, working capital and profit estimates.
G. Multi-site: internal transfer elimination; one tenant 300+ virtual sites scenario under bounded load; external tenant absent from all results.
H. Actual-vs-plan: synthetic future actuals, with immutable original assumptions and separate measured variance.
Each journey has independent manually checked expected numerical outputs, negative tests and snapshot/report evidence. Do not use the owner's actual financial amounts or business/customer secrets.

## 10 — CONCRETE BUILD SEQUENCE, KEEP CODING UNTIL COHERENT DRAFT
B0 1 bounded repo inspection/reuse-gap with real SHA and decisions
B1 exact decimal engine, types/units/formula library, confidence markers, tests
B2 complete versioned model registry and common scenario calculator runner
B3 all defensibly calculable core models (start with pricing, break-even, cashflow, inventory, production, capex/loan, branch feasibility); ensure broad model coverage, not 20 fake stubs
B4 scenario operations, persistent *disposable scoped* SQL if safe, provenance, lifecycle read/write and audits, negative tests
B5 sensitivity, stress, cross-domain impact/constraint graph, safe inverse planning, multi-scenario comparison
B6 one real interactive Simulation Lab and reusable Quick Simulation adapter integrated within the isolated demo harness; BN/EN and role-aware accessible responsive UI
B7 export/report, readiness, detailed explanations, per-industry registry and exact function/version status
B8 enforce security/perf regression, golden cases, property tests, stale/unknown/currency/period and 300+site baseline, signed-auth only after approved non-production stage is available
B9 full quality report and future upgrade-ready handover + DRAFT PR open, maintain blocked release gates.

If a dependency is genuinely not available, implement the safe deterministic core plus honest interface and tests while documenting the unresolved integration gate. Never create fictitious completeness for missing real backend/auth. Do not stop at documentation or wait to request ordinary owner technical choices.

## 11 — TEST MATRIX AND CI
- Pure formula golden references and property/metamorphic tests (scale, conservation, monotonicity where applicable), edge cases, invalid and missing values, nonfinite, malformed decimals, precision/rounding, period/currency mismatch.
- Difference between markup and margin, loss vs profit, cash vs accrual, bank amortization vs profit participation, compounding periods; no payment of projected amount.
- Scenario identity, version pinning, duplicate request idempotency, concurrency, archival, copying, data immutability and changing baseline source.
- Backend scoped API tests for tenant/business/site/user/role, revoked/anonymous/Investor/independent customer, export/cache/RPC scope, direct client-overridden tenantId rejected.
- No operational writes: snapshot/check hash or assert absence of mutation for stock ledger, finance_months/funding_payments and any real canonical test tables before/after every simulation.
- Browser-driven real interactive test on 390px, 768px and 1440px: central vs quick parity, form controls, keyboard, screen reader labels, compare, update, save/reopen, export, invalid/empty/unauthorized errors, no horizontal overflow.
- Memory/time bounds, 10+ scenarios, 300+ site synthetic benchmark; measure actual results and never claim a target passed without measured numbers.
- CI must attach exact SHA, test reports, screenshots and failing blocker evidence, and reproduce on a clean free disposable environment.
- Tests must be green at the FINAL PR HEAD, not merely at a previous SHA. Fix fails; do not bypass lint/security by disabling checks.

## 12 — REQUIRED PR OUTPUTS & UPGRADE EXTENSION SYSTEM
Deliver actual code plus the following under existing repo paths (adapt naming only to current conventions):
- model manifest/registry JSON schema with 20 family IDs, supported/unsupported/verified statuses and paths;
- pure financial decimal/units/calculation core, versioned model implementations and golden tests;
- context+source adapters, synthetic seeded users/tenants/businesses/sites, canonical ledger read mock, fully independent scenario state;
- scenario persistence SQL (disposable only) with RLS & negative tests, **or** a full documented blocked persistence adapter if existing canonical FKs/auth make a safe migration impossible;
- central lab functional UI and quick simulation reusable adapter, at least 3 complete industry demos;
- comparison/sensitivity/constraint/risk/insight/forecast modules and reports with tests;
- ci/workflows including PG17/Node/browser where repo supports it;
- \`docs/development/C10_A025_SIMULATION_DRAFT_DECISION_LOG.md\`: what actually built, model/version, key formulas, scope, exact decisions, source SHA, feature/requirement mapping, tests, known constraints, unresolved approval/security gates;
- \`docs/development/C10_A025_SIMULATION_TECHNICAL_HANDOVER.md\`: exact branch/PR/sha/base, altered paths, start/test commands, CI status, setup/readiness, integration points, defects/limitations, next smallest merge-independent step, rollback and upgrade instructions;
- \`docs/development/C10_A025_SIMULATION_MODEL_COVERAGE.md\`: R081–R114, U01–U26, model family M01–M20 each separately marked actual coded/tested/partial/not built, never inflate;
- \`docs/development/C10_A025_SIMULATION_EXTENSION_GUIDE.md\`: how to add another model/family/formula version, golden test, migrations/fixture and feature toggle without breaking saved historical results.
- One dedicated **DRAFT PR** titled "DRAFT C10-A025 — Enterprise Simulation Engine (isolated, no rollout)" targeting the source baseline, with no auto-merge, no production deploy or high-risk settings changes. Link all evidence and active C10-A025 register, not create a competing governance master.

**Draft PR acceptance:** meaningful full working example of branch expansion, accurate tested engine, versioned extension pattern, role-scoped synthetic scenarios and genuine UI calculations. If infrastructure missing, describe exactly which integration is blocked and preserve honest status. A green disposable CI does not override release gate.

## 13 — AFTER DRAFT CODE IS WRITTEN: HANDOFF, THEN STOP
At completion of meaningful, verified draft:
1. Push branch and create one open Draft PR.
2. Verify exact latest HEAD, passing/failing checks and screenshot/test outputs.
3. Record a **short, clear Decision Log** and full reproducible Technical Handover in the PR itself; store both as committed Markdown.
4. Update the existing Decision Book / NEXT ACTIONS with draft-build evidence **without turning future activation to Approved/Ready**. If Google connector unavailable, mark NOT WRITTEN and provide exact source row and paste-ready change.
5. Clearly say which of 20 model families actually coded, which of U01–U26 verified, which deferred, and what signed/auth or data dependencies remain.
6. Report in concise Bangla: exact PR URL, SHA, tested flows, CI evidence, simulated demo link only if really hosted, and what remains. Do not ask routine questions or promise future background work.
7. Leave PR **DRAFT / UNMERGED / NOT DEPLOYED** and no live customer access until original Owner-gated package milestone and P0 security dependencies pass.

## 14 — SECURITY AND OWNERSHIP FINAL LOCK
CORE 10 Master Platform Owner owns proprietary platform code and entitlements. Tenant owners control their tenant operational data and business roles. A product license is not a business-data visibility grant; no global vendor data read. Data portability and deletion policies future-compliant. No payment subscriptions, public SaaS signup, automatic enforcement of guessed licensing, cloud billing, external user invites or code from Trillionaire Me. Use only free-first local/CI tooling within budgets.

**EXECUTE IMPLEMENTATION, NOT ANOTHER DISCUSSION:** Read this directive, reconcile repo, create the separate implementation branch, build the strongest honest end-to-end isolated simulation draft possible, test it, file one DRAFT PR and a compact decision log/handover. Do not merge, deploy or modify live data.
