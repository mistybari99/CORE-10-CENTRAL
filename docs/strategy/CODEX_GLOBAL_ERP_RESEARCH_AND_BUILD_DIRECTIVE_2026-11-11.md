# CORE 10 CENTRAL — Codex Global ERP Research → Agent Debate → Integration Build Mandate
**Owner directive:** 2026-11-11. **Status:** RESEARCH/PLANNING DIRECTIVE, NOT CERTIFICATION OR RELEASE APPROVAL.

## Source of truth & immediate constraints
- Work only inside existing `mistybari99/CORE-10-CENTRAL`; latest live `main`, deployed serving routes, open/merged PRs, CI, current database and the **existing** [CORE 10 Master Decision Book](https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit) control factual truth. Read current decisions/revisions/requirements/actions before changing source.
- This new **one-time global intelligence and research gate** takes precedence over the older generic “skip research, code first” instruction for the next Codex build. Other locked decisions/release rules remain intact.
- **Do not tweak, replace, merge, rebase or interrupt Claude's current work.** Inspect latest Claude output only after it becomes available; map its tested features into the integration ledger, identify genuine remaining gaps and then build nonoverlapping work.
- **No live business operational data or human test requirement.** Use fictitious demo companies, users, items, sites, transactions, approved no-cost tooling and disposable test databases. No production DB changes, external live provider connection, paid service upgrades, billable API usage, automatic merge or deploy without appropriate authorization.
- Preserve Islamia legacy customized business code/data, exact identifiers and its business-specific reports. Do not clone legacy customization across new tenants. Shared neutral core + industry-specific packs + optional integrations + permission-scoped workspaces. Keep deferred SaaS/simulation gates deferred pending latest owner decision.
- The user aspires to international top-tier completeness and UX. No tool can prove “global #1” or 99% completion based on a demo. Replace claims with measurable traceability, financial correctness, signed role tests, real functional coverage and acceptance evidence.

## Ten logical independent specialist roles — actual concurrency only if supported
**Team A, 4 independent Global Business researchers:**
1. A1 world business models/value chains: B2B/B2C/D2C, retail/wholesale, franchise, projects, services, subscriptions, rentals, distribution, import/export and business lifecycle.
2. A2 detailed real workflows/personas: owner, staff, approver, finance, HR, suppliers, customers, investors, branch/factory/godown/site; exception/failure/returns/reconciliation.
3. A3 industry universe: the existing ten industry families plus logistics, agriculture, hospitality, healthcare, education, real estate, energy, nonprofits, maintenance, automotive and discovered specialties; clearly mark regulated/localization needs.
4. A4 resilience, international operations, localization, abuse/risk, privacy, accessible UX, offline, accounting and exceptional cases.

**Team B, 2 independent software benchmark researchers:**
5. B1 enterprise: Microsoft Dynamics 365/Business Central, SAP Cloud ERP, Oracle Fusion, NetSuite, Workday, Infor, IFS, Sage, Epicor, Acumatica and relevant other platforms.
6. B2 modular/SMB/vertical: Odoo, ERPNext/Frappe, Zoho One, Shopify, Square, Toast, Lightspeed, Dolibarr, Tryton and notable vertical systems.

Benchmark **at least ~25 distinct representative products and ~10 concrete end-to-end process journeys**, or explicitly document gaps caused by source access. Examine configuration, roles, business/site hierarchy, core and vertical modules, UI, automation, data integration, reporting, cost/license and limitations. Prefer dated official documentation; avoid copying proprietary implementation. Primary starting links:
- https://learn.microsoft.com/en-us/dynamics365/business-central/across-business-functionality
- https://learning.sap.com/products/s4hana-cloud
- https://www.oracle.com/erp/
- https://www.odoo.com/page/all-apps
- https://frappe.io/erpnext/modules
- https://www.infor.com/industries/food-beverage/
- https://www.zoho.com/one/
- https://newsroom.workday.com/company-overview-products
- https://help.shopify.com/en/manual/inventory-and-locations/setup/multi-managed-inventory

**Team C, 2 adversarial decision-makers:**
7. C1 Enterprise Architect defends canonical source, modularity, event/transaction correctness, strong role/data isolation, performance, migration and independent industry extensions.
8. C2 UX/Operations Advocate defends ease of use for a novice through enterprise operator: task flows, role/industry-aware menus, search, drilldowns, explainable calculations, Bengali/English, Android and excellent desktop UX. Full functional breadth ≠ a giant cluttered menu.

**Team D, 2 existing-code integrators:**
9. D1 inspect actual repo/PR/CI/deployed UI; exact SHA/path, status, duplicate engines, legacy compatibility and Claude branches. Start from historic foundation PR #7, existing draft operational PRs and new integrated visual preview PR #60; **revalidate as current states change**.
10. D2 inspect actual DB/security/finance/migrations/integration/read models (read-only against production). Map proposed domain concepts to current tables/functions/constraints and credible fixture tests. Do not assert authenticated isolation from synthetic SQL fixtures.

If real Codex subagents are unavailable, document 10 sequential **perspectives** and never pretend 10 agents executed. Different analysts deliver independent evidence before shared judgment. Integration Lead has sole responsibility for conflict resolution, file ownership, dependency and coherent blueprint.

## Required adversarial debate
- **Round 1:** each team separately argues missing business models, features, best patterns and weak competitor assumptions with real sources.
- **Round 2:** architecture vs UX vs security/finance vs cost red-team, and cross-examination for omissions/overlap/duplicate data.
- **Round 3:** neutral consensus + dissent list, decision rationale, uncertainty and exact Owner gates. No silent exclusion.
- Report independently reached positions and source dates, not staged fictional dialogue.

## Universal feature taxonomy: expand, do not limit
Tenant/org/legal entity/business/showroom/factory/godown/site; platform/owner/staff/partner/investor rights; catalog/items/UOM/price/barcode/lot/expiry; CRM/contracts/quotation; purchase/AP/credit; warehouse/movement/transfer/stock count/traceability/returns; recipe/BOM/MRP/production/QC/waste/maintenance; POS/payment/cash/retail/wholesale/restaurant KOT; paint tinting/PDC/schemes; construction BOQ/projects/retention; trade/FX/LC/landed cost; e-commerce/fulfillment; HR/attendance/payroll; accounting GL/bank/AR/AP/currency/valuation/tax where legally verified; budgeting/profitability/partner settlements; approvals/audit/reconciliation/reports; backups/restore; responsive accessibility; multilingual/offline safe drafts; opt-in connectors/Drive/API/workflows/AI under permissions; future authorized analytics/simulation and SaaS.
Record EVERY discovered feature with ID, industry applicability, user story, canonical data/side-effects, required permissions, UX pattern, source URL/date, existing code/PR/SHA, readiness, ownership, priority, free/paid considerations, fixture/test ID and decision. Status must distinguish `shared-core / vertical-pack / optional-adapter / deferred / research-only / rejected with rationale`. No feature silently discarded; not every candidate is release-ready.

## Free-first + all-demo development requirements
- Keep free/open-source hosting/test/CI compatible and document hard quota, license, security and upgrade caveats; use paid scale tiers only when actually needed **after** explicit owner opt-in. Never claim free unlimited enterprise capacity.
- Seed 2 independent tenants, 3+ fictitious businesses (sweets/bakery, paint/hardware, construction), owners, managers, cashier, factory/warehouse, accountants, auditors, approvers, investor, unauthorized cross-tenant staff, revoked and anonymous identities.
- Include realistic fake item/recipe/expiry/unit/stock/cost/supplier/customer/employee data; 303-site structural fixture and separate measured load/UX evidence.
- E2E golden documents and equations: purchase → receive → transfer → production → sale → return/refund → cost/COGS → balanced ledger → AR/AP → report. Negative-stock, double-post, lost network, unauthorized access and rollback. Missing financial source = incomplete, not invented zero.
- Synthetic PostgreSQL RLS and fake accounts **do not** equal tested real signed Supabase Auth. Real OAuth/authenticated and production impact are separate approval/test gates. All public GitHub artifacts must be demonstrably fictitious and secret-free.

## Google Drive: two distinct contracts
1. **Governance:** use the existing Master Decision Book, never a competing decision register. Update original tabs/rows with research, decisions, latest exact PR/commit CI evidence and owner approvals; if connector cannot write say `NOT WRITTEN` and provide paste-ready changes.
2. **ERP user functionality:** design/test mock Google Drive adapter with explicit tenant-owner OAuth2 consent, least scope, encrypted per-tenant tokens, business/site mapping, secure attachment/exports/reports/optional backup, retry/idempotency/version/audit/revoke/quotas and real restore validation. One platform operator must never see all customer Drive files by default. Live customer connection is not authorized yet.

## Deliver exactly these plan artifacts before next core code build
- `docs/strategy/GLOBAL_BUSINESS_UNIVERSE_2026.md`
- `docs/strategy/GLOBAL_ERP_BENCHMARK_2026.md`
- `docs/strategy/UNIVERSAL_CAPABILITY_REGISTER.csv` (and JSON)
- `docs/strategy/ADVERSARIAL_AGENT_DEBATE.md`
- `docs/strategy/UNIFIED_ARCHITECTURE_DECISIONS.md`
- `docs/strategy/REPO_PR_CODE_RECONCILIATION.md`
- `docs/strategy/END_TO_END_DEMO_TEST_FACTORY.md`
- `docs/strategy/FREE_FIRST_COST_LICENSE_AND_LIMITS.md`
- `docs/strategy/GOOGLE_DRIVE_INTEGRATION_CONTRACT.md`
- `docs/strategy/MASTER_BUILD_ROADMAP.md`
- `docs/strategy/POST_CLAUDE_PARITY_REVIEW.md` **only after actual Claude result**.

## Build order after one-time research gate
B0 current code/PR ownership + safe packaging/CI/migration blockers → B1 tenant identity/RLS + idempotent Quick/Advanced setup + owner/staff authorization → B2 purchase→inventory/transfer→production→sales/return→COGS→balanced GL→reconciled reports → B3 first truly independent industry pack and expansion to ten families → B4 projects/HR/payroll/partnership/financial reports → B5 mock-verified integrations, opt-in Drive/automation/AI/offline drafts → B6 browser/Android/desktop flows, DR, load, security, reconciliation and readiness → B7 previously deferred SaaS/simulation only upon explicit owner gates.

Use additive migration and existing functions when valid; no bulk merges or big-bang rewrite. Maintain source-backed status levels: `proposal | coded | isolated tested | PR reviewed | merged | deployed | signed E2E | operationally certified`. For each real build deliver exact paths, PR/SHA, tests/CI, rollback, existing Decision Book row, and next executable step. Actual feature coding must resume promptly after research/decision gate; do not create endless research iterations.

**Owner-facing updates:** concise Bangla: actual agents or sequential roles executed; dated researched sources; debate decision; registered features/zero unexplained omissions; existing code/Claude mismatch; files committed; tests; actual Drive write status; next concrete safe engineering slice. No claim of 99% completion or real ERP use while only demos exist.