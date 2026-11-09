# CORE-10-CENTRAL — Complete Conversation-to-Decision Traceability Register

**Version:** 1.0 | **Captured:** 2026-11-10 | **Source:** this conversation, earliest CORE-10 step through Owner's latest confirmation | **State:** documented requirements; no operational deployment

## Authority & precedence (essential)

- Owner's **latest explicit correction wins** over earlier suggestions; never silently use the superseded version. Track changes through DECISION REVISIONS.
- The Owner states that unchallenged assistant recommendations can be treated as broadly agreed **design baseline**. They remain distinguishable from explicit Owner requirements; cannot be treated as a permission to deploy, change live data, incur fees, or close a security gate.
- `Approved` in the Google Decision Book means the product requirement/policy is approved; it does not indicate implementation, verification, launch readiness or actual legal compliance.
- Existing C10-D001…D029 remain intact. C10-D030…D037 cover broad new master decisions; the rows below lock the essential smaller behaviors under those parents. D038 will codify this reconciliation/precedence rule.
- **Implementation truth** stays in the main GitHub code, branch PRs, Supabase and CI. Never infer implemented status from this document.
- Core design first; independent SaaS commercial rollout last. Tenant-safe boundaries must still be engineered up front.

## Requirement register — 80 non-duplicative atomic requirements

**Authority legend:** `Owner explicit` = directly requested or corrected by Owner; `Owner agreed`/`Reconciled` = assistant proposal retained after Owner expressed agreement; `Safety reconciliation` / `Required from audit` = protective technical requirement subject to implementation review; `Prior approved` = existing Central Decision Book authority.

| ID | Area | Locked requirement / design baseline | Parent decisions | Authority | Definition of acceptance |
|---|---|---|---|---|---|
| R001 | Identity | CORE 10 Central is Master Owner control for owned portfolio, never an Islamia-only business. | D001,D002 | Owner explicit | Central only for authorized Master Owner; staff cannot navigate it. |
| R002 | Identity | Each selected business has its own FULL Business Owner Board, not only a Central-only control panel. | D003,D004,D033 | Owner explicit | Change business context; same owner has full local control. |
| R003 | Identity | Master Owner has centralized cross-business control AND business-local contextual control. | D002,D033 | Owner explicit | Same business settings visible and editable from both authorized entry points. |
| R004 | Identity | Legal Entity, Tenant, Business, Brand, Operating Unit, Physical Stock Location are not interchangeable. | D008,D036 | Reconciled | Hierarchy documented, mapped to current schema, no implicit new legal entity. |
| R005 | Identity | Location types include Branch/Showroom, Factory, Godown/Warehouse, Project/Site and later extensions. | D007,D008 | Owner explicit | Can create multiple of every type under selected business. |
| R006 | Identity | One operating site can hold several stock locations/bins; keep current location IDs and ledgers unchanged during migration. | D008,D024 | Reconciled | Old 8 places continue to work with all FK/history. |
| R007 | Identity | Central and Business Board Add Site buttons resolve to ONE server-validated creation service. | D007,D009,D032 | Owner explicit | Same persisted business/location mapping regardless of entry point. |
| R008 | Identity | Central may create new businesses under an existing legal entity; do not create a legal company for every store/brand. | D010,D032 | Reconciled | Master business setup separates brand and legal identity. |
| R009 | Identity | Existing Islamia brand/theme, items, stock, account balances and workflows must survive restructuring. | D024 | Owner explicit | Non-destructive read-only baseline and regressions. |
| R010 | Identity | Global Organization Mode UI must not be treated as an Islamia-specific toggle; preserve structure, migrate security flag safely. | D037 | Owner correction | No accidental global flag ON/DELETE; backend transition proven. |
| R011 | Identity | Business owner controls should not appear as global owner-only in a way that prevents local decision-making. | D033 | Owner explicit | Owner can review/edit chosen business locally. |
| R012 | Identity | No second competing ERP or My-tools source: single CORE-10-CENTRAL source repo. | D022 | Prior approved | Changes based on main and approved PRs only. |
| R013 | Permissions | Business staff sees its assigned branded app only; no CORE 10 origin, Master menu, sibling company names or logos. | D005,D006,D027,D033 | Owner explicit | UI, history, search, API results contain no unauthorized company identity. |
| R014 | Permissions | Staff access limited to the assigned Tenant, Business, Branch/Site, Action and Data Scope. | D006,D033,D036 | Owner explicit | Authenticated negative API/RPC/export/storage access tests. |
| R015 | Permissions | No explicit grant = no permission; optional UI visibility must never grant backend access. | D006,D033 | Owner explicit | Direct API must deny ungranted actions. |
| R016 | Permissions | Show/Allowed: visible and usable ONLY if effective permission and module availability both pass. | D033 | Owner explicit | Authorized staff can perform exact granted action. |
| R017 | Permissions | Locked: optionally visible with lock styling, cannot execute without permission. | D033 | Owner explicit | Locked click, copied URL, REST request are denied if lacking grant. |
| R018 | Permissions | Hidden: optionally not rendered in menus, navigation, search or favorites. | D033 | Owner explicit | Hidden option absent from staff navigation; independent API grants still enforced. |
| R019 | Permissions | Owner chooses Show/Locked/Hidden by user and by role and can later reverse choices. | D033 | Owner explicit | Role and user effective visibility updated and audit tracked. |
| R020 | Permissions | Operational feature switches can be ON/OFF at each business independently; optional features not globally forced. | D031,D033 | Owner explicit | Paint-only toggle does not affect Sweets. |
| R021 | Permissions | Central and local Owner boards update same authoritative permission/config records. | D033 | Owner explicit | Single source of truth; no drifting parallel settings. |
| R022 | Permissions | User-specific overrides, role inheritance, exceptions, conflicts and permission expiry need explicit effective-permission preview. | D033 | Reconciled | Owner can explain exactly why a permission is granted/denied. |
| R023 | Permissions | Master/global security/tenant isolation cannot be disabled by an ordinary Business Settings toggle. | D006,D037 | Safety reconciliation | Security tests remain enforced regardless of optional UX choices. |
| R024 | Permissions | Authentication/session switch, inactive/revoked staff, offline caches and direct deep links must fail closed. | D006,D013,D014,D033 | Reconciled | Revoked identity cannot retrieve cross-business or stale private data. |
| R025 | Permissions | Master, Tenant Owner, Business Owner, Manager, Staff, Partner and Investor are distinct permission identities. | D033,D034,D036 | Owner explicit | Equity percentage does not automatically give software access. |
| R026 | Permissions | Business-level modules, rules and setup controls can be owner-editable in normal operation without developer intervention. | D033 | Owner explicit | Owner changes and audit trail persist across sessions. |
| R027 | Configuration | Easy/Quick Setup does NOT reduce ERP features, capacity, report catalog, controls or enterprise completeness. | D030,D032 | Owner correction | Same underlying enterprise engine as Advanced Setup. |
| R028 | Configuration | Advanced Setup exposes full configuration of the same engine; Quick uses proven defaults that remain editable. | D030,D032 | Owner explicit | No hidden permanent feature ceiling after Quick Setup. |
| R029 | Configuration | New business requires only sensible initial inputs and auto-creates identity, branding, locations and full applicable module config. | D032 | Owner explicit | Wizard setup yields complete supported business profile. |
| R030 | Configuration | Future new branch, factory, warehouse, paint store or business using implemented templates needs no code edits. | D032 | Owner explicit | Owner UI/API tests with zero source changes. |
| R031 | Configuration | Provisioning is atomic OR idempotent and recoverable, without duplicate/orphan entities from retries. | D032 | Reconciled | Crash step four, resume once, no duplicate site. |
| R032 | Configuration | Business data/config state must distinguish Draft, Setup Pending/Blocked, Ready and Active. | D032 | Reconciled | Activation blocked until prerequisites pass. |
| R033 | Configuration | 10+ business templates are the baseline, NOT a fixed upper limit. | D031 | Owner explicit | New template pack registered without rewriting common ERP. |
| R034 | Configuration | Ten templates: Sweets/Bakery, Restaurant/Kitchen, Paint/Hardware, Retail/Wholesale, General Manufacturing, Construction, Import–Export, E-Commerce, Technology/Digital Products, Services/Agency. | D031 | Owner explicit / accepted selection | Template catalog lists and scopes all ten. |
| R035 | Configuration | Common ERP Engine is shared, while industry-specific features are composable packs (e.g. sweets with e-commerce). | D031 | Owner agreed | Module compatibility and dependencies enforced per business. |
| R036 | Configuration | Do not delete an irrelevant industry feature: simply hide/not-enable it for that business while retaining shared code. | D031,D033 | Owner correction | Paint staff see no unrelated confectionery production menus. |
| R037 | Configuration | Every module has support/readiness status: tested, implemented-unverified, partial, not-implemented, not-applicable. | D031 | Reconciled | No empty switch misleadingly claims feature operational. |
| R038 | Configuration | Full capability catalog must cover stock, purchasing, inventory, finance, accounting, HR, production, QA, audit, approvals, automation, integrations and extensive reports. | D030,D031 | Owner explicit | Catalog and test coverage show all required use cases. |
| R039 | Configuration | Industry packs must include domain workflows (e.g. Paint tinting/dealers; Food recipes/batches; Construction BOQ/projects; Digital subscriptions; Import/Export shipment/landed cost). | D031 | Owner agreed | Template-to-workflow acceptance matrix. |
| R040 | Configuration | Business-specific reporting and permission defaults apply immediately on setup but remain Owner-customizable. | D031,D032,D033 | Owner explicit | Owner can override without code changes. |
| R041 | Scale | One business must be designed for 100+ branches, 100+ factories and 100+ warehouses, potentially many businesses. | D030 | Owner correction | 300+ site staging load benchmark; not claimed verified today. |
| R042 | Scale | Site-level bulk operations, filters, permissions, identity, stock and transfers must scale beyond fixed lists. | D030 | Reconciled | Bulk setup and paginated APIs pass test dataset. |
| R043 | Scale | No arbitrary 8-site constraints or all-location global aggregation fallbacks allowed in multi-business systems. | D030,D037 | Reconciled | Scoped query and large-site tests. |
| R044 | Scale | Enterprise operations must support concurrent transactions, reliable ledgers, offline sync and recovery. | D030 | Owner agreed | Load/retry/restore drill completed. |
| R045 | Scale | Large business use must not silently lose invoices, stock, permissions, approvals or historical location references. | D024,D030 | Owner explicit | Reconciliation and integrity alerts. |
| R046 | Reporting | Every business Owner Board includes branch/site/factory/godown/brand/product/project/drilldown reports. | D025,D035 | Owner explicit | Business-scoped reports reconcile to ledgers. |
| R047 | Reporting | Central automatically counts each newly activated owned business and its sites, contributions, sales, expenses, profits and dues. | D035 | Owner explicit | Central KPIs update from canonical sources. |
| R048 | Reporting | Consolidated portfolio report must not mix independent customers, unauthorized businesses or sister brands. | D006,D035,D036 | Reconciled | Scoped rollup to owned/authorized tenant only. |
| R049 | Reporting | Internal transfers are not external sales and cannot double-count portfolio turnover/profit. | D035 | Reconciled | Cross-site movements reconcile without duplication. |
| R050 | Reporting | Missing prices, periods, cost/valuation or accounting inputs must show incomplete metrics, not invented profits. | D035 | Reconciled | Data quality flag accompanies each KPI. |
| R051 | Reporting | All critical finance, stock, workforce, investment, operational, exception, audit and management reports must be inventoried. | D030,D035 | Owner explicit | Report catalog and data lineage acceptance. |
| R052 | Ownership | Partner equity, capital contribution, profit/loss sharing, voting/control and ERP access are distinct records. | D034 | Owner explicit | Cap table, capital ledger and role grants remain separate. |
| R053 | Ownership | An agreement may have two, four, five or more Partner/Investor parties with differing percentages and access. | D034 | Owner explicit | Multi-party ownership and payout tests. |
| R054 | Ownership | Non-equity funding must exist for one selected business/project/site and a fixed contract term. | D034 | Owner explicit | No automatic equity issuance from funding agreement. |
| R055 | Ownership | Support percentage of ACTUAL business profit distinct from annual percentage on PRINCIPAL and fixed monetary payouts. | D034 | Owner explicit | Three bases produce clearly differentiated ledgers. |
| R056 | Ownership | Support monthly, quarterly, semiannual, annual and custom payout calendars; maturity, principal return, partial repayment. | D034 | Owner explicit | Due/payable/paid/overdue and principal ledger tests. |
| R057 | Ownership | Partner/Investor contracts support amendments, start/end date, capped returns, carry-forward and configurable settlement rules. | D034 | Owner agreed | Versioned agreement, no overlapping settlement. |
| R058 | Ownership | Each Investor may optionally get restricted portal to own agreement/payments, not full ERP operations by default. | D034 | Owner agreed | Real signed-in investor sees only own contracts. |
| R059 | Ownership | Partnership/Investor ledger must be scoped by tenant AND business/project; never calculate whole-database profit. | D034,D037 | Required from audit | Fix existing partner_calculate business-scope all-locations selection before live multi-business. |
| R060 | Ownership | Multiple agreements must not duplicate the same allocated profit or pay twice, with traceable payout reconciliation. | D034 | Reconciled | Multi-investor funded pool/period and exact repayment tests. |
| R061 | Ownership | Financial legal/tax/sharia classification requires reviewed contract terms; software must distinguish fixed obligation from variable actual-profit sharing. | D034 | Reconciled | Owner reviews agreement classification; no automatic compliance guarantees. |
| R062 | Tenant | Friend/external customer can create a fully independent Tenant with their own Tenant Owner, brand, staff, data and full ERP. | D036 | Owner explicit | Independent onboarding and per-tenant data model. |
| R063 | Tenant | CORE 10 operator does not automatically inherit customer data-reading access merely by providing software. | D036 | Owner explicit | Cross-tenant negative API and operator tests. |
| R064 | Tenant | Owner-approved, scoped, revocable, audited support access can be granted when the customer desires. | D036 | Owner explicit | Consent, expiry and audit of support impersonation/delegation. |
| R065 | Tenant | Platform Admin, Tenant Owner, Business Owner, Staff and Investor are separate roles; global is_owner must be migrated. | D033,D036,D037 | Safety reconciliation | Staff/customers cannot gain a global role. |
| R066 | Tenant | Independent Tenant's reports never appear in owner's own portfolio unless explicitly authorized within agreed scope. | D035,D036 | Owner explicit | No third-party financial aggregation. |
| R067 | Tenant | Future commercial SaaS may provide subscriptions, billing, plans, licensing, branding, support and optionally dedicated deployment. | D036 | Owner explicit / accepted scope | Platform billing separate from operational ERP. |
| R068 | Tenant | Implement tenant-safe foundation early, but external SaaS sales/commercial rollout LAST after ERP readiness. | D036 | Owner explicit | Separate late-phase task, no current SaaS release. |
| R069 | Security | Legacy org_scope_on OFF underpins many policies/functions: preserve until audited safe replacement; do not simply switch ON/remove. | D037 | Audit + owner agreement | Security preflight and rollback to be tested. |
| R070 | Security | Business membership, site grants and tenant identity are verified at backend/RLS/RPC/storage/report boundaries. | D006,D021,D037 | Owner explicit | Live signed JWT denial matrix verified. |
| R071 | Change | Owner's latest explicit correction supersedes an earlier assistant suggestion or interim formulation. | D028,D029 | Owner explicit | Revision history retains old wording and documents replacement. |
| R072 | Change | Unchallenged assistant ideas the Owner states agreement with may become design baseline, but remain differentiated from explicit Owner instructions and cannot authorize deployment. | D028,D029 | Owner explicit | Source/authority labels and no silent implementation claims. |
| R073 | Change | Every important feature is traceable from Master Decision → detailed requirement → planned work → test evidence. | D028,D029 | Owner explicit | Coverage audit reveals unlinked requirements. |
| R074 | Change | Decision Approved means product SCOPE approved, never that feature is implemented, tested or live. | D028,D029 | Prior approved | Status columns remain separate. |
| R075 | Change | No code removal, schema rewrite, SaaS sales activation, production writes, PR merge or live flag switch without explicit separate release authorization. | D029,D037 | Existing governance | Draft-first, staging/test/backup gates. |
| R076 | Change | Complete enterprise capability must not omit real-use workflow or reports; discoveries during operations flow into versioned registry and planned tests. | D030,D031 | Owner explicit | Gap log + documented capability lifecycle; no false guarantees. |
| R077 | Change | Development begins with canonical entity/security/business scope, not isolated industry dashboards or SaaS sales. | D032,D036,D037 | Owner agreed | A018 then A019, A020 etc. |
| R078 | Change | Preserve already built Islamia ERP modules; audit actual mixed Paint/Construction screens before relocating or changing any code. | D024,D031 | Owner explicit | No premature module deletion; mapping table first. |
| R079 | Change | Owner controls can be comprehensive even though the setup wizard is short; default feature toggles must be revisitable per business. | D030,D033 | Owner repeated | Full option registry present in Owner business board. |
| R080 | Change | 10 industry packs must attain full end-to-end workflows/reports/permissions before marked ready; no template-only sales promises. | D031,D030 | Owner explicit | Capability registry proof and staging template checklist. |

## Corrected or misunderstood interpretations — final reconciled wording

| Previous incomplete interpretation | Correct authoritative interpretation |
|---|---|
| `Easy setup` means fewer features or a starter ERP | **False**. Quick Setup is an onboarding experience; all implemented applicable enterprise capabilities remain available. No deliberate Lite ERP. |
| An `Organization Mode` page should be manually toggled in Islamia | **False**. Existing organization hierarchy belongs to Central; operational feature toggles belong to each Business Owner Board; global data security must never be casual optional toggle. |
| Owner can control everything only through Central | **False**. The SAME owner can manage a business in its own fully capable contextual Owner Board, and from Central. |
| Permission granted simply by seeing a Show/Locked/Hidden UI element | **False**. UI visibility and backend execution grants are different; Locked/Hidden do not add authority. |
| Every Factory/Godown requires creating a new company | **False**. Each selected Business can contain many facilities with distinct operating units and physical locations. |
| A new Paint/Construction template's name guarantees all workflows work | **False**. Not-implemented modules are visible as gaps in Owner capability registry; it is necessary to build and certify them. |
| Partnership and Investor are identical | **False**. Equity stake, true net-profit share, contractual principal-based return and financing are distinct contract and ledger definitions. |
| SaaS platform provider may automatically read all customers' figures | **False**. Customer ownership and data access are separate; optional delegated support only, always subject to technical protections. |
| Target of 100+ sites is already load-tested | **False**. This is a non-negotiable DESIGN and staging-test goal. |
| Approval of a new architecture decision authorizes production changes | **False**. Code/data operations follow governance, test evidence, owner approval separately. |

## Existing system evidence and blockers at time of recording

- UI has `optviews.js`, `nav.js`, and backend `my_option_views`, user/role setting RPCs. Live role form permissions present. UI Show/Locked/Hidden exists but complete user-session, API and logout regression not yet certified.
- Existing `org_units`, `locations`, `business_profiles`, `org_unit_save`, `places135.js` support partial business/facility setup; 1 active Sweets business, 2 legal entities, 8 physical locations directly under Sweets in live SG; Paint business not provisioned.
- Existing partner/finance modules `partners.js`, `partner_ventures`, `partner_agreements`, `agreement_parties`, `partner_capital`, `partner_rules`, `partner_settlements` and calculations; no live ventures/settlements; templates examples inactive. `partner_calculate()` currently chooses all locations at business scope and must be fixed BEFORE multi-business settlements.
- `org_scope_on` remains OFF in live environment; ~35 RLS policies and ~70 functions tied to it; do NOT manually flip or delete, and do NOT interpret UI restrictions as data safety.
- Only Food Manufacturing template is marked available; other business packs need real implementation. Independent tenant/SaaS platform components are not yet production-ready. No claim of completeness.

## Work plan and verification linking

| Milestone | Parent requirements | Exit gate |
|---|---|---|
| C10-A018 Canonical Foundation | R001–R012, R027–R045, R062–R068, R071–R080 | Versioned entity relationships, compatibility plan, complete feature/template registry and owner approval. |
| C10-A019 RLS/authorization | R013–R026, R059, R062–R070 | Signed user/role/tenant/business/location REST+UI+export negative tests pass without revealing sibling data. |
| C10-A020 Dynamic Setup | R005–R009, R027–R044 | New business plus 100/100/100 site test, idempotent retry and no location ID breakage. |
| C10-A021 Dual Owner Boards | R002–R003, R011, R013–R026, R046 | Central and business-local complete settings, staff view and visibility tests pass. |
| C10-A022 Partnership/Investor | R052–R061 | Scoped investment profit, equity, term/return, principal, payout and investor-access tests pass. |
| C10-A023 Reporting/Scale | R041–R051, R080 | Business+portfolio ledgers reconcile; no transfer double-count; capacity/recovery tests pass. |
| C10-A024 SaaS (last phase) | R062–R068 | Independent secure external tenant, support delegation and billing production certification, after earlier gates. |

## Exceptions not to invent or pre-approve

- Exact billing prices, payment processors, local company formation, accounting/tax structure, partner legal contract language, production hosting topology, and specific optional feature defaults must be configured or separately authorized as they arise.
- The Owner expects full business completeness; an unbounded claim that every conceivable future industry feature is already built would be false. Report newly discovered needs in the versioned capability register with requirements and acceptance tests.
- The current document records **product scope**, not permission for a live migration, module removal, SaaS launch, binding financial obligation or capital distribution.

## Final lock checklist

- [x] Reconciled Owner corrections and the unchallenged baseline rule.
- [x] Atomized staff Show/Locked/Hidden and business identity isolation.
- [x] Atomized both Owner Boards and local/global mirrored control.
- [x] Atomized dynamic 10-template setup, full enterprise features and 300+ site target.
- [x] Atomized partnership, non-equity investment, payoff and financial distinctions.
- [x] Atomized independent tenant and SaaS-later boundary.
- [ ] Software implementation, real-user security test, performance test, and live release — **not done**.

## Post-R080 approved scope extensions — 2026-11-10

This file intentionally preserves the earlier R001–R080 reconciliation as a historical versioned baseline, **not** the complete latest ledger. The CURRENT complete owner requirement ledger is the existing [REQUIREMENTS LOCK Google Sheet](https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit#gid=4106) containing **R001–R114**.

- **C10-D039 / R081–R088**: Original owner-approved 18-section [Enterprise Simulation & Decision Intelligence directive](CORE10_ENTERPRISE_SIMULATION_DECISION_INTELLIGENCE_DIRECTIVE_2026-11-10.md), 20 registered model families and the hard deferred-build gate.
- **C10-D040 / R089–R114**: Owner-approved [Enterprise Simulation & Decision Intelligence v2.0 extension](CORE10_SIMULATION_DECISION_INTELLIGENCE_V2_EXTENSION_2026-11-10.md), 26 additional detailed capability contracts U01–U26 spanning trusted data, model certification, cross-module impacts, cashflow/feasibility, optimization, governance, monitoring and future platform integration.
- **Same C10-A025** remains **DEFERRED / NOT BUILT** until the next two-to-three *genuinely completed and verified* ERP packages, plus P0 security and relevant architecture/finance/report contracts. Documentation and preliminary audits do not count.
- **C10-A024** SaaS commercialization remains a separate later-phase action. No new ERP codebase, external product data sharing, production DB writes, merges or deployment authorized by these additions.
