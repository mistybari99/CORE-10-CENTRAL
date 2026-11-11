# CORE-10-CENTRAL — CODEX MASTER EXECUTION HANDOVER & CEO/OWNER PRODUCT CHARTER

**Authoritative working date:** 2026-11-11 (Asia/Dhaka)
**Prepared for:** Codex implementation agent / ChatGPT / Claude, same CORE-10-CENTRAL source repository
**Mode:** IMPLEMENT REAL CODE → AUTOMATED TEST → DRAFT PR → OWNER-REVIEWABLE PREVIEW → document evidence
**Document role:** Codex-specific execution entrypoint; **not** an alternative Decision Book, owner-policy revision, new ERP, or production-release approval. Re-read live sources before every action. All status claims below are a timestamped snapshot.

## 0. Direct instruction to Codex

You are the implementation engineer and integration lead for **the one existing CORE-10-CENTRAL**. The Owner is a non-programmer, CEO, founder and first user of the system. The Owner describes business outcomes; you translate approved intent into correct models, UI, signed APIs, versioned business rules, calculations, audit, reports and tests. Do not demand the Owner specify SQL, schema, formulas, backend patterns or UX details. Make small safe engineering defaults without repeated approval requests. Never silently make a new legal, ownership, statutory, production-financial, security, data-sharing or release policy.

**IMMEDIATE TASK is ONLY the existing first preview's functional/visual integration and correctness.** Do not rush to unrelated broad new packages before the Owner inspects the preview. Continue actual implementation, not another research-only report. Begin with the exact Git commit/PR/CI checks listed below and fix a real blocker or improve a concrete tested preview slice. A good next result is a working, discoverable, mobile/desktop preview of existing code with trustworthy labels and reproducible test evidence—not a static design falsely described as a complete ERP.

## 1. The sole authoritative sources (order matters)

1. **Owner's latest explicit instruction** and the [Master Decision Book](https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit): DECISION BOOK; REQUIREMENTS LOCK; DECISION REVISIONS; NEXT ACTIONS; DISCUSSION LOG; AUDIT EVIDENCE; CHANGE LOG; DEMO TEST USERS; START HERE; ARCHITECTURE MAP. This is the **only** policy/decision register.
2. **GitHub repo:** https://github.com/mistybari99/CORE-10-CENTRAL . Implementation truth is exact source commits and reproducible tests; deployed truth requires deployed URL/runtime evidence.
3. **Current foundation handoff** on branch \`feature/c10-a018-foundation-catalog-v1\`: \`docs/development/CURRENT_HANDOFF.md\`. This file is **not necessarily present on main**. Inspect the branch-relative path, not only default branch.
4. **D049 owner intent architecture guide:** https://docs.google.com/document/d/1VNB-ub0V49fg1QAPqyALk-1P79eqgbHJZwAdbq5-mCg/edit
5. Original uploaded reading references (may need Owner-provided Codex attachment if Codex lacks ChatGPT Project file access): \`CORE10_CENTRAL_DEVELOPMENT_HANDOVER_2026-11-10.md\`, \`CORE10_CENTRAL_INDEPENDENT_AZ_DEEP_RESEARCH_2026-11-11.md\`, \`CORE10_Master_Build_Prompt.md\`. Historical source material, not later-than-live evidence.
6. Existing \`AGENTS.md\` (if present), repo tests, release workflows, linked GitHub PRs/issues, CI logs. Do not treat GitHub issue text as approval for production.

**No competing decision book, duplicate role/ledger/service, parallel copy of the old IMG ERP or independent incompatible app.** If connected Google Drive is inaccessible inside Codex, use this brief as a safe baseline, note \`Decision Book NOT VERIFIED\`, and request user-connected access/export only when a material owner decision truly needs it.

## 2. Nonnegotiable CEO/Owner mission (D049/R128 and latest reiterated vision)

Design **one configurable, explainable, multi-tenant, multi-entity, multi-business, multi-site, multi-industry ERP platform** with a self-service **Owner-intent → scoped system engineering** experience. First deployment is for the Owner's own businesses, later productized for other unrelated companies without exposure of their business data to the vendor or one another. Broad extensibility is a **product requirement**, not an assertion that every conceivable functionality already exists.

The Owner should be able to express in natural Bangla or English, for ANY supported industry and ANY module: “I want this workflow / formula / report / dashboard / approval / permission / leave policy / notification / website / sales channel / branch setup / payment method / dashboard widget, and if I change it, what happens?” The software must make the supported route understandable and usable **without Owner programming**.

### Universal Owner Intent lifecycle (applies ERP-wide, not just three modules)

1. Capture intention in plain language **with actual authorized tenant/business/site/product/role context**, using existing record context; ask only necessary missing facts.
2. Show clear interpretation (“You asked for”), scope, units, assumptions, expected effect, uncertainty, a before/after preview, affected modules and planned report destinations.
3. Resolve to the **one canonical capability registry**, entity/data contracts, dependency graph, permission model, versioned rule/handler, calculated outputs, workflow transitions, UI placement, reports and integrations.
4. Classify truthfully: \`CONFIGURABLE_NOW\` (existing, verified supported handler), \`NEEDS_HANDLER_BUILD\`, \`ADVISORY_PREVIEW_ONLY\`, \`BLOCKED_SAFETY_OR_DATA\`, \`RELEASE_GATED\`. Do not pretend that a new arbitrary description executes code by magic.
5. Permit certified bounded settings: default/alternatives, feature ON/OFF, role/site scopes, user DENY, delegated approval, threshold, conditional routing, schedule, reporting, reallocation or placement—**where implemented and legal**.
6. Show implications and complete calculation explanation: input source, dates, formula/version, rounding, units, tax basis, outputs, risk, alternate outcome, owner approval and which report/dashboard/notification changes.
7. Preview with synthetic reversible examples or isolated simulation; versioned changes, audit actor, effective date, approval/revocation and rollback where safe. AI-generated advice must not directly run SQL/JS eval, bypass permissions, post stock/money, or impersonate users.
8. If unsupported, generate typed capability blueprint including schema/API/engine dependencies/tests for engineering; only advertise it after handler code, QA and certification.

**Every meaningful action in every module** should offer brief contextual guidance: what, why, when, recommended default, alternatives, consequences of changing it, permission/approval, linked records and reports, exact formula if calculated, and a safe sample walkthrough. Friendly, legible Bangla/English language. “Owner control” is not unlimited authority to disable secure invariants.

## 3. Multi-business / independent-customer structure

- \`Platform → Tenant → Legal Entity → Business → Operating Site → Stock Location/Bin\`. Business group / Store/Showroom / Factory / Godown/Warehouse / Project distinctions must be explicit.
- Master Owner portfolio across **authorized** businesses, direct Business Owner spaces per business, Managers, Counter, Factory staff, Reviewers, Approvers, HR, Payroll, Partner/Investor restricted viewers.
- One canonical business/site/item/person/staff/transaction identity and role engine; no duplicated shadow permissions, dashboards backed by unrelated records, or hidden-menu-only authorization.
- Separate **Control Studio** permanently discoverable centrally, with Central Only / Business Only / Both / Hidden menu placement; authorized search should still find hidden settings. Placement ≠ feature enabled ≠ data rights ≠ approval authority.
- Site/role/user permission grants: scope, time bounds, explicit deny, approval, revocation and audit. Server-side RLS/RPC enforcement; demonstrate negative tests for external tenant, revoked staff and anon.
- Per-business themes/branding, currencies and other supported configuration; customer-tenant branding must not leak software vendor identity or another business.
- Quick & Advanced onboarding share **one full-power engine**; Quick config uses reversible recommended defaults, not permanently limited capabilities; role-controlled and idempotent tenant/business/site provisioning. Per-business 100+ branches, factories and warehouses are **scale design targets, NOT proven capacity**.
- Preserve existing Islamia and Misty Bari location/item/stock/report historical IDs and correct business ownership. **REV-009:** never clone a customized Sweets/Islamia application as generic platform logic or as another company's ERP. Extract brand-neutral contracts/handlers with tests; keep custom industry adapters isolated.

### First Owner portfolio / illustrative businesses

Islamiya Misty Ghar (multiple showrooms, production/factory and storage), Misty Bari (dine/dessert), Al-Cakiz and Cake Factory, paint/hardware dealership, JABEDA WHITE CITY CONSTRUCTION, and later digital/technology projects. These are **business examples**, not unverified new production tenants. Store/business names are not an identity or authorization credential.

### 10 template families (capability registry, not 10 completed products)

1. Sweets/Bakery; 2. Restaurant/Food service; 3. Paint/Hardware/Dealership; 4. Retail/Wholesale; 5. Manufacturing; 6. Construction/Project; 7. Import/Export; 8. E-commerce/Online store; 9. Technology/Digital business; 10. Services. Support more by compliant registered extension, never rely only on label or branding to assert operational readiness.

## 4. A–Z functional product coverage — target architecture, NOT automatic build completion

**CEO executive area:** company portfolio; owner KPIs; profit/cash/debt/stock/wages/obligations; comparisons by business/site/project; alerts, approvals, milestones, budgets, risk, opportunities, variance, break-even, forecast evidence, actions and drilldowns; partner/investor capital/settlement rights. Explain every total.

**Master data & operations:** legal entities, branches/sites, categories and units/UOM conversion, item variants, barcode/QR, product/service catalogs, suppliers/customers, price lists, batches/lots/expiry, reorder and quality flags, equipment/assets, BOM/formulas/recipes, production plans/actual, subcontracting, material consumption, procurement requests → PO → receipts → invoice → AP; inventory locations, counts, transfers and inventory valuation; order/quotation/return/refund; retail counter/POS; delivery/fulfillment and logistics.

**Finance & accounting:** double-entry GL/chart of accounts, vouchers/journal, petty cash, cash drawer, bank and reconciliations, AR/AP invoices/aging/settlement, payroll liabilities distinct from PAID, COGS/WAC/valuation, sales tax/VAT *only from approved jurisdiction rules*, budget/cost centers/project profitability, period close/lock/adjustments, owner-authorized statements, cash flow, departmental/site rollups. Accurate numbers are mandatory; missing source cost ≠ zero.

**CRM + customer growth:** contacts/leads, interaction history, customer consent/preferences, segmentation, enquiries, quotes, opportunities/pipeline, order/conversion and retention, support/ticket/SLA, complaints/feedback/returns, loyalty where lawful, campaigns/attribution and lead-to-sale/source links. CRM actions must connect back to real orders, fulfillment, receivables, customer permission and audited communication.

**Website, online store & online business:** individual tenant storefronts and service/business websites, domains and pages, product catalog synchronized to authoritative inventory/prices, online quote/order/booking channels, checkout/payment status via verified gateway, invoices, delivery, returns, customer portal; content/CMS/SEO, channel analytics, online/offline shared workflow. No creating live website domain, connecting payments, public publishing or paid service without relevant authorization.

**HR / workforce / payroll (D050/R129):** staff identity/assignment, join/exits, shifts, attendance, holidays, leave balances/accrual/carry-forward/caps/expiry, overtime, policy versions, allowances/deductions, salary reviews/advances, payroll DRAFT→REVIEWED→APPROVED→FROZEN, amendment and payslip, supervisor/delegated HR access, expiry/revocation/approval, audit and owner-authorized payroll liability preview. Multiplier \`1.00×\` = 100% hourly base, NOT 1%. Provisional punch retention 36 months = punch records only; payroll history/audit retention separate and legal-hold aware. No unauthorized withholding or statutory-rate assumptions; approval ≠ payment.

**Enterprise fixed assets & maintenance:** cross-business/site asset registry, serial/warranty/ownership, assignment, preventive schedules, inspection/calibration, fault reports, repair/service work orders, spares, cost/downtime, replacement lifecycle and reporting. A055 remains Claude-owned WIP until CI/compatibility evidence.

**Projects & vertical operations:** construction estimates/BOQ, procurement, contract, labor, material, progress/cost/billing; paint color/tinting and dealership workflows; sweets/bakery recipe, batch, production, transfers, freshness, retail; restaurant tables/kitchen/orders; import/export landed costing, currency/risk and documents; service scheduling, timesheets and fulfillment. Shared core + tested domain pack, never cross-use incompatible business rules.

**Approval, contracts & governance:** scoped multi-step approval/exception, delegation, thresholds, owner/reviewer separation, audit history, notification settings, document/attachment provenance, bank/payment authorization gates, versioned config, legal policy management, permission review and data retention.

**Reports, BI & intelligence:** each module's operational reports, source transactions, drilldowns, filters by authorized tenant/business/site/period, exports, formula trace, dashboard widgets, exceptions, trends, reconciliation, audit and reproducible snapshots. Do not treat 193 customized Islamia report declarations as fully executed generic enterprise reports.

**Offline/PWA:** mobile-first and desktop-quality progressive interfaces, install/update handling, encrypted tenant/user-bound offline-safe drafts, visibly stale status, queue/outbox, background retry and conflict review when online; **never local stock/financial/payment posting disguised as authoritative**. Offline accounting entry is draft/proposal until signed server validation/period rules approve.

**Automation + integration + AI:** provider-neutral signed adapters, provider event validation, queues/idempotency/outbox/inbox, error handling/replay/audit, safe notification, email/SMS/social integrations, webhooks, external CRM/accounting/commerce APIs, marketing channel publishing only with consent/approval, market intelligence with evidence/date/confidence, AI agents limited by real scoped tools and human confirmation for consequential operations. Camera/OCR/barcode assist with user-confirmed ambiguous recognition. Website/social/event outcomes return to same ERP records.

**Commercialization:** customer-facing SaaS tenant onboarding, billing/licenses, security/privacy and subscriptions only when existing deferred \`A024\` is specifically activated. Simulation Lab and in-page Quick Simulation with scenario isolation and Apply-to-Plan require later \`A025\` gate; do not silently pull them into the current preview build.

These form a **traceable architecture and eventual roadmap**, not a statement that every requested capability is already executable. Implement vertical slices until actual acceptance criteria are met.

## 5. Cross-module invariants / business logic examples

- A purchase receipt creates an authorized **stock receipt** and proper AP/expense mapping where certified; it is not itself evidence of cash payment.
- Factory production has approved BOM/recipe, material issue, WIP and finished goods receipt; batch cost must reconcile, not fabricate wastage or margin.
- Branch/factory/warehouse transfer updates authorized locations without inflating consolidated sales/revenue. Same-business transfers ≠ sales.
- POS/online sale links customer/order, stock issue, revenue, cash/AR, tax if supported, COGS and transaction audit. Return/refund creates a bounded, source-linked reversal and fulfillment consequences.
- Payroll approved vs payroll paid vs bank disbursed are distinct states; no auto finance journal/payment without certified handler and authority.
- Customer refund/online checkout “success” requires signed provider event + amount/currency order match; retries must be idempotent.
- Investor, partnership, debt, capital/equity and fixed percentage obligations are distinct contracts; never call a hypothetical profit guaranteed or assign a false legal/sharia classification.
- Report “Net profit” requires complete sales + verified COGS + expenses + period/tax/adjustment basis; otherwise display \`INCOMPLETE\`, not a confident zero or invented percentage.
- Every relationship is scoped by tenant/business/site/location, effective date and authorization. A module's view must never auto-authorize an upstream mutation.
- Balanced journal \`sum(debit) == sum(credit)\`, source-event idempotency, undo via reversal, conserved stock moves, exact units and rounding, immutable posted history.
- Contextual help must explain expected effects (“what changes now / what does not change”), dependencies and report destination. Offer safe demo before real changes.

## 6. Owner-approved decision map — re-read exact canonical wording, never overwrite

- Foundational D001–D014 etc.: Owner/Business separation, legal entity and site identity, staff scope, full business workspaces.
- D028/D029 and latest revision history: single existing repository, live Master Decision Book, shared AI development handoff and governance.
- D030–D038 / R035–R080: brand-neutral core, 10 industry target families, full Quick/Advanced setup, large site scale design, finance/ownership/investor and tenant scope.
- D033/D045 / R014–R026/R123/R124: full Universal Owner Control Studio (not just fixed 18 toggles); one registered lifecycle; placement and business projections; central discoverability and delegated approval.
- **REV-009:** Islamia customized legacy belongs only to that Business Workspace; do not clone to generic tenant/industry.
- D039/D040 / R081–R114: simulation product vision, **deferred** until its own approval/gates.
- D041/D042: build end-to-end before live use, protect historical Islamia data and role/transaction correctness.
- D043: GitHub-first migrations and one continuous handoff.
- D044: reviewed low-risk incremental frontend deployment allowed only under its actual checks; high-risk production DB/financial release separately gated. The **current preview handover specifically disallows merging to main without fresh explicit Owner approval**.
- D046/R125: canonical test-only synthetic identities, not real staff users.
- D047/R126: complete genuinely connected demo-operational ERP before real business rollout.
- D048/R127: A048 + A049 + A050 **all** required; no substituting one for another.
- **D049/R128: UNIVERSAL natural-language Owner intent, explainable and extensible engineer-backed capabilities ERP-wide**, adopted in this session as comprehensive CEO mission.
- **D050/R129: HR/Payroll configurable delegation, allowances/deductions, OT, retention, leave carry-forward**, legally constrained.

No fresh \`D051\` or new \`Rxxx\` is claimed by this handover. If a decision is genuinely missing, propose it through the Master Decision Book and preserve revisions. Existing policy decisions are not erased by a new technical design.

## 7. What is **actually built** as of latest Codex-preparation snapshot

**Source foundation:** \`feature/c10-a018-foundation-catalog-v1\` (PR [#7](https://github.com/mistybari99/CORE-10-CENTRAL/pull/7)), baseline \`1c55625f36ffff8a54d3dab431ad52e0c484bd6b\`; dynamically inspect latest head.

**Existing Draft PR families (check latest current head/CI before building):**
- [#42](https://github.com/mistybari99/CORE-10-CENTRAL/pull/42) A045 Micro-Engine Workshop: in-memory runnable demo and isolated SQL; only certified nonmutating handler subset.
- [#44](https://github.com/mistybari99/CORE-10-CENTRAL/pull/44) A046 synthetic 16-persona registry.
- [#45](https://github.com/mistybari99/CORE-10-CENTRAL/pull/45) A047 business/site topology.
- [#49](https://github.com/mistybari99/CORE-10-CENTRAL/pull/49) A048 inventory command lifecycle, **first slice**.
- [#50](https://github.com/mistybari99/CORE-10-CENTRAL/pull/50) A049 purchasing/production/sales source, **first slice**, BOM posting and certified COGS incomplete.
- [#51](https://github.com/mistybari99/CORE-10-CENTRAL/pull/51) A050 owner portfolio read/workspace source.
- [#55](https://github.com/mistybari99/CORE-10-CENTRAL/pull/55) A051 workforce/payroll isolated engine.
- [#54](https://github.com/mistybari99/CORE-10-CENTRAL/pull/54) A052 universal intent documentation, **NOT** universal runtime engine.
- [Issue #56](https://github.com/mistybari99/CORE-10-CENTRAL/issues/56) A053 persona/workforce/portfolio integration pending; [#57](https://github.com/mistybari99/CORE-10-CENTRAL/issues/57) A054 advanced payroll configurable features pending.
- [Issue #58](https://github.com/mistybari99/CORE-10-CENTRAL/issues/58) A055 Claude branch WIP, verify its latest artifacts and protect file ownership.
- Legacy/coexisting other code: PRs #21 costing, #22 access, #23 offline proposals, #27 integration ports and A018–A044 foundation. **Do not assume their source is already compatible or merged.**

**Current first Preview integration:** [Draft PR #60](https://github.com/mistybari99/CORE-10-CENTRAL/pull/60), branch \`preview/c10-integrated-20261111-v1\`, latest observed SHA (recheck) \`42aecebfd460915394c6f1bfbbc69c8b5189981f\`. In that branch, selected nonconflicting source blobs of A045–A051 and D049 architecture were assembled on PR #7 foundation; this is **source assembly, NOT proof of combined backend migration or runtime data linking**.

**Preview URL:** https://core10-central-preview-v1.mistybari99.workers.dev/ — Cloudflare Worker responsive synthetic visual shell and original A045 in-memory Workshop demo. Preview worker source \`preview/worker.mjs\`; tests \`tests/core10-preview-v1.test.mjs\`, \`tests/core10-preview-live-smoke.mjs\`, \`tests/e2e/core10-preview-v1-browser.cjs\`. Only allowlisted A045 demo files are fetched from pinned GitHub source SHA, no production Supabase transactions.

**Observed verified runs at preview SHA \`42aecebfd460915394c6f1bfbbc69c8b5189981f\`:** Preview static security, public Chromium 390/1440 smoke, browser forbidden files, and A045/A046/A047/A048/A049/A050/A051 isolated CI all reported SUCCESS in GitHub Actions; always recheck run history and source matching before restating. **No real GoTrue-issued user/staging/production authenticated E2E, no combined schema migration certification, no main merge, no production Supabase deployment.** Do not assert visual sample rows are actual business records.

## 8. CODEX FIRST EXECUTABLE WORK PACKAGE — preview-first (priority P0)

**Owner request:** “First show me a physical app preview of what has already been built. Let me inspect it; then continue new feature builds.” Current preview exists, but must become a useful trustworthy integrated walkthrough of existing source, **not** a manufactured full-ERP success story.

Codex MUST:
1. Verify latest main SHA; PR #7/#42/#44/#45/#49/#50/#51/#54/#55/#60 branch heads, CI, merge bases and changed-file collisions; inspect \`docs/development/CURRENT_HANDOFF.md\` from foundation branch. Do not cherry-pick blindly.
2. Open the *actual* deployed Preview V1 URL on mobile (390px) and desktop (1440px) automated browser; capture relevant screenshots/console/errors. Confirm navigation, layout, text, no horizontal overflow and honest demo labels.
3. Review current \`preview/worker.mjs\` for CSP correctness, asset loading and blocked production network. Fix nonfunctional preview parts; **no** deceptive fake server or misleading success numbers. Keep original A045 actual runnable in-memory demo accessible and stable.
4. Inspect A048/A049/A050/A051/A047 actual HTML/JS and signed client dependencies; create a **safe bridge/visual walkthrough** for those where no real authenticated staging exists. Explicitly distinguish clickable synthetic examples vs source-backed authenticated feature when unavailable. Prefer adapting actual module UI to an isolated, canonical test adapter rather than drawing unrelated mock screenshots.
5. Resolve any CI/red gate or source-assembly error in preview branch; compare Pages allowlist / root/v2 deploy packaging and forbid SQL/internal/credentials from public served assets. Fix test failures rather than disabling the checks.
6. Improve discoverability: Owner Portfolio → business → location → relevant operational module, mobile side nav & desktop information density; contextual how/why/effect/report destinations. No duplicate identity/stock/permission engine.
7. If it can be done without unsafe staging credentials or release, add a reproducible browser fixture that links a **single illustrative end-to-end story** (purchase → stock → production plan → sale → report) while clearly marking every uncertified calculation and prohibited posting. Never imply COGS or bank payment works unless real certified code backs it.
8. Run Node, PostgreSQL17 disposable, signed-HMAC PostgREST, browser 390/1440, public HTTP, deployment checks as appropriate. Label synthetic-JWT vs GoTrue separately. Owner's live data must not be modified.
9. Push isolated preview-branch commits / Draft PR only. Capture commit SHA, exact CI run links, and working review URL; record status/evidence to existing Master Decision Book (when accessible). No main merge, real Supabase migration, real staff creation, payout or production release.
10. End with a concise Bengali Owner report: \`WHAT NOW WORKS\`, \`WHAT IS DEMO ONLY\`, \`WHAT IS PENDING\`, \`WHERE TO CLICK\`, \`SHA/CI/PR\`. **Stop at Owner preview/review gate before broad next build work.**

### Acceptance criteria

- One public preview URL loads with no visible fatal error at 390/1440; root and original A045 demo work, accurate navigation and source status.
- A meaningful usable preview walkthrough for integrated existing modules, not blank “Verifying session” forever.
- Clear identity: **real module source vs synthetic in-memory illustrative UI**.
- No real tenant, payroll, bank, inventory or production transaction modified.
- One isolated branch/PR and exact-head CI links, no unresolved high-severity public asset leak.
- Screenshots/automated browser evidence and a short Owner-led walkthrough.
- No claims that full enterprise ERP or 10 industry packs are “complete”.

## 9. Subsequent executable development after Owner reviews Preview V1

Integrate in reviewed coherent vertical slices with non-conflicting file ownership:
- Phase I: A018/A019/A020/A021/A031/A034 canonical tenant/business/site scoped security + signed identity; Preview→real business/site read models; migration drift reconciliation, explicit staging.
- Phase II: A047+A048+A049+A050+A051 plus A053/A054 and dedicated A055; **no duplicate ACL or posting engines**. Complete real purchase/receive/transfer/BOM/produce/sale/return/COGS/accounting/payroll/report workflows with scoped roles and reversibility.
- Phase III: complete Owner Control/Workshop, certified extensible registered handlers, versioned settings and contextual intent-to-implementation, including real dependency resolution and audited self-service settings.
- Phase IV: industry-specific independently tested packs; CRM, websites/storefront, customer orders, online payment integrations, marketing and automation providers, offline-safe workflows, CEO decision intelligence and complete multi-business reporting.
- Deferred: external SaaS commercialization A024 and simulation A025 according to their prior Owner approvals/gates.

Build deep tested slices, not just exhaustive list pages. Each supported capability must link to its upstream source record, downstream impacts and reports.

## 10. Platform, QA, privacy, finance and release gates

- **Do not merge to \`main\` without explicit current Owner approval**; do not modify production IMG-ERP-SG, production schema/RLS, existing accounting, real inventory, external messaging/ads or real users without separate authorization.
- Browser UI cannot grant access by hiding buttons; backend scope is final. Verify anon, invalid/revoked, unrelated tenant, staff vs reviewer/owner, business/site scoping and stale-version/idempotent retries.
- Enforce tenant isolation even with cross-business Master portfolio. Do not make software vendor automatically omniscient about customer financials; owner-authorized portfolio rollup only.
- No legal/statutory tax, leave, payroll, retention or guaranteed-return rate invented. Locale/currency, effective date, source and jurisdiction are required; controversial configurations get legal/owner gate.
- Use PostgreSQL17 disposable SQL checks, signed API negative tests, browser responsive/keyboard/accessibility, authenticated GoTrue staging only when independently provisioned, versioned migration/rollback and actual REST network proof.
- Prevent unscoped \`SECURITY DEFINER\`, auth spoofing, allowlist leakage, public-source SQL or secrets, multi-permissive RLS OR exposure and bypass in stock/finance. Historic known risks in earlier independent A–Z audit warrant **re-verification**; they are not all confirmed current vulnerabilities.
- Original legacy live data and existing IDs must remain untouched. Preserve \`v2/\` parity, PWA offline cache compatibility and Pages publication boundaries.
- GitHub workflows that are all green do NOT equal real Supabase migration or legal/accounting certification.

## 11. Multi-agent engineering coordination

Use bounded collaborators when Codex tooling truly supports them; otherwise work sequentially. Suggested independent responsibilities:
- Agent A: repository/PR reconciliation, canonical tenant/security/RLS/API testing; owns no frontend visual files.
- Agent B: operations/inventory/costing/payroll read-model integration and signed fixture tests; owns isolated module adapters only.
- Agent C: responsive preview UX, accessibility/CI/deployment browser smoke; owns \`preview/\` and UI-only tests.
One **integration owner** approves compatibility/reconciles shared identity/database contract. Claude's A055 branch is separate; do not concurrently overwrite Claude files. Do not claim agents ran unless actual tool execution exists.

## 12. Definition of Done & concise Bengali report format

For each meaningful code slice record:
- Decision/Requirement/Action ID and user-visible acceptance;
- exact branch/path/file owner, GitHub commit SHA and Draft PR;
- Node, SQL/RLS, signed-API, browser 390/1440 test result **at the exact commit**;
- deploy/GoTrue/staging/prod states separately;
- module readiness: PROPOSED / CODED / ISOLATED-TESTED / INTEGRATED / STAGING-VERIFIED / LIVE-RELEASED / PRODUCTION-READY / BLOCKED;
- safeguards, data lineage, finance/stock audit, rollback evidence;
- Decision Book UPDATE with precise tab/row; if access missing: \`NOT WRITTEN\` and exact pending delta;
- one next executable action plus Owner-only decision gate.

**Communicate with Owner in Bangla, straightforward and compact.** Show progress with working links and results, not repeated long plans or technical permission questions. When a task cannot be fully completed, commit the safe complete work, disclose remaining blockers and give one precise continuation.

## 13. Codex launch instructions (user-side action)

Use Codex Cloud (web/desktop), log in with the same ChatGPT account and connect/authorize GitHub **mistybari99 / CORE-10-CENTRAL** in the Codex environment if it is not already selected. Choose the existing repository; select \`preview/c10-integrated-20261111-v1\` as the starting source if supported, or ask Codex to fetch it and branch without touching \`main\`. Codex's GitHub environment permissions are separate from this ChatGPT chat's GitHub connector.

**Paste this exact short launch request into Codex:**

> You are the implementation lead for CORE-10-CENTRAL. Read \`docs/development/CODEX_MASTER_EXECUTION_HANDOVER_2026-11-11.md\` and \`AGENTS.md\` on branch \`preview/c10-integrated-20261111-v1\`, and \`docs/development/CURRENT_HANDOFF.md\` on \`feature/c10-a018-foundation-catalog-v1\`. Respect Master Decision Book D033/D045/D046/D047/D048/D049/D050, R123–R129 and REV-009. Start with Section 8, the **real Preview V1 integration/UX/safety work**. Verify latest branches/CI and deployed URL; implement actual source changes, test responsive navigation and runnable demos, fix failures, push isolated commits and Draft PR, report live URL/CI/SHA and what remains synthetic. Do not merge main, touch production Supabase, create real users, fake success or start unrelated feature packages before Owner preview review.

---

**Handover status:** GitHub-ready source artifact; no Codex Cloud task has been launched by writing this file. The Owner must choose/authorize the Codex Cloud environment and start the task. Source and CI status are snapshots until reverified by Codex.