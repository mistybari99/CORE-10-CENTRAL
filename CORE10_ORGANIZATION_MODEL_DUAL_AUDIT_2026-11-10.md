# CORE-10-CENTRAL — Organization Model: Dual-Audit & Reconciled Architecture
**Date:** 2026-11-10  
**Status:** Proposed architecture decision for Owner review. No production writes, migration or merge approved.  
**Method:** Two separate analytical audit tracks (not two externally hired human auditors) reconciled against current GitHub `main`, read-only Supabase IMG-ERP-SG queries, existing approved Central Decision Book, and vendor documentation.

## 1. Owner intent / governance
- CORE 10 Central is the **only global owner control center** for managing several businesses.
- From Central, owner can select a Business and add branches, showrooms, factories, godowns/warehouses, and projects **in that selected business context**.
- Business-local management can offer the same creation workflow with the business preselected. ONE shared server-validated creation pathway, never duplicated schemas/forms.
- Staff may access only explicitly assigned business and operational units; they must not discover Central or sibling businesses.
- Preserve Islamia's existing ERP, its stock-location primary keys, accounting data, and brand experience. No active My-tools development.

## 2. Auditor A — Code, model and operational reconciliation
**Evidence inspected:** `businesshub.js`, `org122.js`, `places135.js`, `bizctx.js`, `core10-shell.js`, `core10-business-owner.js`, `locgroups.js`, `CORE10_OWNER_CONTEXT_ARCHITECTURE.md`; read-only live `org_units`/`locations`, `org_tree`, `org_unit_save`, `_org_parent_ok122`.

| Assertion | Observed in actual system | Conclusion |
|---|---|---|
| Global structure ownership | Central Owner `owner.html#/organization` renders portfolio; `#/organization/manage` holds existing `org122.js` management forms. Business-owner route redirects global organization to Central. | **Mostly correctly placed already. Don't delete the structural module.** |
| Database hierarchy | `org_units`: one root `group`, two `legal_entity` records, only ONE `business` under the Sweets legal entity. The Paint legal entity has **no business child**. | Multi-business workspace provision incomplete. A legal entity is not a business workspace. |
| Physical operations | `locations`: 4 showroom, 3 factory, 1 godown; all 8 directly point to the Sweets business `org_unit_id`. No active branch/site org nodes under it. | Physical location type is presently used in place of logical branch/site hierarchy. |
| Existing schema capabilities | `org_unit_save` supports `business`, `branch`, `site`, `department`, `cost_centre`, `project`; `_org_parent_ok122` enforces group → legal_entity → business → branch/site/etc. `locations.org_unit_id` supports assigning physical places to units. | **Reuse, don't redesign from zero.** Factory/godown can be operational site types with physical `locations.kind`. |
| Main product screens | Business context has Owner dashboard + branches/locations links; Central portfolio has business creation; `businesshub.js` groups locations by showrooms/factories/godowns. | UI navigation is partly aligned but grouped location cards are not a complete data model. |
| Business setup wizard | `places135.js` references a **global `org_scope_on` Switchboard toggle** while guiding new business creation. `bizctx.js` still has a first-business fallback on unresolved locations. | Global security rollout flag has leaked into the business setup UX; fallback must be eliminated with regression coverage. |
| Status consistency | Some UI business listings include `status != inactive`, which also admits `planned`; read-only Owner Inbox candidate only accepts `active`. | Differentiate setup-visible planned business from active operational business everywhere. |

**Data preservation:** `locations` is referenced by 136 foreign keys from 130 tables; `org_units` by 72 foreign keys from 69 tables. Retain physical location IDs, don't bulk delete/reseed or blindly reparent; map and test migrations against dependent tables.

## 3. Auditor B — Security, isolation and international ERP comparison
**Live facts:** `rules.org_scope_on=false`, owner/mapping functions use SECURITY DEFINER, one active business. SQL metadata found **35 RLS policies on 35 tables** referencing `_org_on123()` (all restrictive) and **70 SECURITY DEFINER functions** with dependencies on this flag. When OFF, the conditional restrictive predicate can be relaxed; other permissive policy requirements may still apply. This is NOT proof that every table is exposed. The live multi-business negative test remains unperformed.

**Risk:** a switch in an individual Business's general settings should not be allowed to alter global access behavior. Do not merely turn this switch ON or delete it; that changes the behavior of numerous existing RLS policies and RPC functions. Treat the flag as *temporary internal migration compatibility state*, frozen against routine business changes, with an eventual always-enforced business-isolation backend and audited deprecation plan.

**International comparison (vendor documentation reviewed 2026-11-10):**
- **Microsoft Dynamics 365 Finance:** separate legal entities (statutory/ledger boundary) from operating units, sites, warehouses and financial hierarchies. Design organization hierarchy centrally, distinguish legal and operational reporting. https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/fin-ops/organization-administration/plan-organizational-hierarchy
- **Odoo 19:** multi-company within one database allows authorized centralized management and company-specific warehouses/data, with cross-company consolidated visibility. Warehouse is a physical site; stock location is a finer area inside. https://www.odoo.com/documentation/19.0/applications/general/companies/multi_company.html and https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/inventory/warehouses_storage/inventory_management.html
- **ERPNext:** separate company when legal/accounting boundaries demand separate books; otherwise use branches, cost centers, warehouses beneath the relevant company. https://docs.frappe.io/erpnext/company-setup
- **Microsoft Azure multi-tenant database guidance:** enforce authenticated tenant identity and row-level isolation for shared DB tables; don't rely on display-level filtering alone. https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/service/sql-database

**Independent verdict:** The tree itself is a good foundation, but a business-level toggle controlling company-wide security is architecturally inappropriate. A navigation hierarchy does not itself establish RLS isolation.

## 4. Reconciliation: single recommended target (not yet deployed)

```text
CORE 10 CENTRAL — Owner Control Center (application context, not an IMG business)
└── Portfolio / Group record (organizational root)
    ├── Legal Entity (only when legal/statutory accounting demands it)
    │   ├── Business Workspace: Sweets & Bakery
    │   │   ├── Operating Unit: Showroom / Branch
    │   │   │   └── Physical Stock Location(s): counter, stockroom, shelf
    │   │   ├── Operating Unit: Factory / Site
    │   │   │   └── Physical Stock Location(s): raw, production, finished stock
    │   │   └── Operating Unit: Warehouse / Godown
    │   │       └── Physical Stock Location(s): receiving, storage, dispatch
    │   └── Optional additional Business if actually operated within same legal entity
    └── Other Legal Entity (if truly separate)
        └── Business Workspace: Paint [needs provisioning; not present live]
            ├── Showrooms / Branches
            └── Warehouse / Stock Locations
```

**Meaning:** Central is the cross-business Owner UI; `group/legal_entity/business/branch/site` are legitimate *database entity types*; the physical `locations` registry remains the stock/movement location identity. A factory/warehouse is a type of operating site, NOT automatically a new legal entity or an unrelated business. One site can own multiple physical inventory locations. Where brands such as Misty Bari/Al-Cakiz require independent branding but not their own books, keep them as brands/locations inside the relevant business until an explicit legal/accounting decision is made.

**Creation workflow, exactly one backend:**
Central → select Business → Add Showroom / Factory / Warehouse → business-scoped validated creation endpoint; inside Business Owner → same creation endpoint with selected Business already filled. Central creates a *new Business* through a legal-entity selection, but must not create a dummy legal entity for every brand or branch. Validate legal entity identity, ownership, default currency, location ID mappings, staff grants, and atomic persistence on the server.

**Permissions:** same person remains Master Owner across all businesses and full Business Owner in selected context; Business Manager has explicitly delegated business permissions; Branch Staff has only assigned sites. Core central rollups always use server-authenticated business IDs; transaction/report/storage/RPC paths are isolated without depending on a user-facing organization-mode switch. Shared item/master data requires explicit audited share rules.

## 5. Decision to adopt and decisions to reject
**RECOMMEND, Owner signoff pending:**
1. **Retain** the existing Central `Organization / Manage Business Structure` route as Owner-only portfolio/structure administration; rename visible controls if needed to `Manage Businesses & Locations`. Do not create a second Organization Mode page inside IMG.
2. **Remove the business-facing Organization Mode switch from normal UX** after controlled rollout; keep any security compatibility flag backend-only until all dependent policies/functions have been replaced and tested. Security isolation must be mandatory, not toggled per Business.
3. **Complete the model** using existing `org_units`, `legal_entities`, `locations` with validated parent-child relations; distinguish operational facilities from inventory sublocations, retaining IDs/FKs.
4. **Allow Central and local Owner entry points** to the **same** Business-scoped create/edit flows, with no duplicate data or separate ERP implementation.
5. **Do not auto-promote** legal entity to business, or each brand/store to legal entity. Reconcile Paint's unfinished business and Islamia's 8 location mappings in staging before any live changes.

**REJECT:** a new independent Organization Mode under Islamia, deleting `org_units`, globally turning ON `org_scope_on` without impact testing, and treating every branch/factory/warehouse as an independent company.

## 6. Implementation gates (only after explicit approval)
- **Gate A — schema/flow spec:** map 8 existing location IDs and stock links; identify legal versus business records; design one server-verified create API/flow; resolve `planned` status display mismatch.
- **Gate B — isolation security:** audit all 35 conditional RLS policies and 70 affected SECURITY DEFINER functions plus legacy report, accounting, stock, storage/export and offline paths; isolate data by canonical business ID; replace first-business fallback; verify negative API tests across two businesses with real authenticated sessions in **staging**. Never run unreviewed migrations live.
- **Gate C — rollout:** backup + restore drill; owner-approved staged migration; verify branch/site→location linking without changing existing `locations.id` and dependent FKs; test inventory transfers, shared item rules, staff visibility, local/master dashboards, all approvals, rollback.
- **Gate D — deprecate switch:** only after all dependencies safely migrated, remove normal UI switch and retire internal global-flag dependency; do not simply flip it or delete it.

**Release NO-GO:** organization mode currently OFF, only 1 business, cross-business real-session security not certified, and owner inbox RPC remains an unmerged Draft PR. This audit authorizes **no DB DDL, flags, record moves, merges or deployment**.

## 7. Source-of-truth reconciliation
Existing approved Central Decision Book decisions **C10-D001, D002, D006, D007, D008, D009, D010, D021, D024, D025** already broadly align. Owner's clarified desire to add sites *from Central* can be implemented as an additional entry point to the same business-local server-verified form; this updates UI convenience, not the underlying source of authority. No duplicate or routine Decision Book audit rows were created. Amend a **single relevant master architecture decision** only after Owner approves this proposal.

**PR nature:** Documentation-only Draft, no production or current app behavior changed.


## 8. Follow-up: Owner-controlled UX, strict permissions, dynamic business templates (2026-11-10)

**Owner clarification:** One-time configurable ERP; staff sees only the assigned branded business, may see a navigation option **Allowed / Locked / Hidden** as explicitly configured; Owner retains authority over optional feature toggles and delegated access. Creating a new Paint / Construction business or facility should automatically link its database identities and settings and never require new coding for already-supported workflows.

### Track 1 — Permission evidence (read-only, not equivalent to an authenticated user acceptance test)

- **Already implemented**: \`public.role_form_perms\` has 118 rows; \`can_do(form,action)\` returns role-based view/enter/approve; \`has_grant(grant,location)\` supports owner, roles, user grants and emergency grants. \`role_form_overrides133\`, \`rule_grant_overrides133\`, \`rule_overrides\` provide business-specific override storage. Live \`rules\` include many optional switches.
- **Already implemented**: \`optviews.js\` is listed in bundle-manifest, \`nav.js\` loads \`my_option_views\` and calls \`optviews.apply\`. The dedicated Owner-only \`Who sees what\` screen sets Show/Hide/Locked for individual users and roles using server RPCs. A locked link is annotated and click-captured to display a lock sheet; Hide filters menu entries. \`settings2.js\` also includes global \`ui_noperm_mode\` (lock or hide for no permission).
- **No current live evidence**: both \`user_option_view\` and \`role_option_view\` have zero records as of this audit. The existing UI/endpoint implementation therefore has **NOT** been certified for actual newly applied visibility changes, deep-link bypass, refresh, session switch, offline/stale caches, revoked permission, role precedence or full server access denial. Do not mark it “complete”.
- **Critical semantic distinction**: Show/Hide/Locked controls presentation. It MUST NOT grant permission. Render \`Allowed\` only when module available AND business active AND role/user permission AND assigned business/location all pass at the server. Locked can be visible but non-actionable; Hidden must not appear in menu/search/favourites or branded staff UX. Direct URL/REST/API cannot bypass database access. Check whether a Hidden-but-authorized deep link is intentionally permitted (UX preference) or should be denied by a separate route policy.
- **Grant precedence**: \`_ov_effective\` applies per-user override before role defaults; when multiple roles conflict, the existing role visibility merge favors Show over Locked over Hide. This should be explicitly presented to Owner and tested: broad role grants must never quietly override an Owner's expected restricted staff access.
- **RLS dependency**: With \`org_scope_on=false\`, \`can_do\` takes its legacy global role matrix; business \`_form_eff133\` only applies in the ON branch. Other conditional RLS policies similarly relax business scoping when OFF. Keep optional operations switches Owner-controlled, but **do not leave tenant isolation switchable or grant-dependent** during multi-business production. Rebuild consistent backend isolation and retest all affected code.
- **Staff branding**: \`core10-shell.js\` obtains a verified business ID for all assigned locations using \`org_unit_scope\`, blocks mixed/ambiguous mappings and suppresses Central navigation; \`business_profiles\` stores branding. Still audit every direct page, browser history/search, exports, storage, and RPC, not just the shell.

### Track 2 — Exact module/template reconciliation

Current \`business_templates\` live states:
- \`food_manufacturing\`: **available**; module list includes POS, Stock, Purchase, Production, Costing, Accounting, Reports.
- \`hardware_paint\`: **not_implemented**, despite registered built partial features \`cheque_pdc\`, \`principal_schemes\`, \`tinting\`; variants, business-specific parties, dealer POS and scheme accounting paths are registered as not built.
- \`dealership\`: **not_implemented**, though some cheque/scheme features exist.
- \`construction\`, \`technology\`, \`online_store\`: **not_implemented**. \`import_export\`: **needs_setup**.
- \`businesshub.js\` assigns *portfolio categories* from regex on business code/template/name. \`ia.js\` contains broadly shared route groups including factories/production, finance, settings, paint tinting, etc., with permissions but not a fully certified per-business module eligibility service. A category label is not a secure module manifest; don't remove code or physically move tables based on category names.

**Recommended separation** (configurable, not destructive):
| Layer | Modules / examples | Visibility rule |
|---|---|---|
| CORE 10 master-only | multi-business portfolio, global organizational and legal setup, group settings, cross-business consolidated views, system/security governance | Authenticated Master Owner; never staff |
| Shared Business Core | Item Master, category, purchase, inventory, location, transfer, POS where relevant, accounts, CRM, staff, approval, local reports | Enabled only if template supports it and user has appropriate business/location grant |
| Food / Bakery | batch production, recipes/BOM, cake, doi/sweets, expiry, food wastage/QC, factory/store transfers | Sweets template default, other businesses only when explicitly applicable |
| Paint / Hardware | tinting, size/shade/variant, manufacturer brand, dealer scheme, cheque/PDC, paint inventory | Paint template default only after certified workflow completion |
| Construction | job/project, BOQ, site material issue/return, subcontractor work, contract billing, project costing | Construction template when implemented |
| Technology / Digital | project/service delivery, subscriptions, client invoicing, automation, digital integrations | Technology template when implemented |

**Business-scoped on/off** should have these independent concepts: (1) feature supported by deployed software, (2) feature enabled for this business by Owner, (3) action permitted for this user and location, (4) UI display preference Show/Locked/Hide. No “enable” setting should pretend a \`not_implemented\` template feature is already deployable. Shared module code remains present once; each business only sees an eligible/configured workspace.

### Track 3 — Dynamic provisioning and safe Owner changes

**Desired creation transaction:** Central selects existing/new legal entity → new Business record → approved template/modules → business profile/brand → default role settings/permissions with deny-by-default → business-scoped numbering + item namespace + warehouses/branches/sites → operational \`locations\` with server-resolved \`org_unit_id\` → initial reporting scopes → activation readiness checks. Use one reusable RPC/service and idempotency key; no per-business hardcoded code or separate app builds.

The current \`places135.js\` wizard does individual \`org_unit_save\` (legal entity, business, branch) and \`business_place_create135\` RPC calls in sequence. Each RPC has its own transaction; a failure partway can leave a partially provisioned business. Client IDs reduce duplicate retries but do not make the entire wizard atomic. Add a transactional provisioning coordinator or explicit \`DRAFT -> SETTING_UP -> READY -> ACTIVE\` state machine with resume/compensating rollback, and clear evidence of what was completed. Never change existing \`locations.id\` values.

**Owner administration plan:** \`Central > Business > Settings\` (per-business modules/branding), \`Central > Security > Users / Roles\` (scope, action permissions, visibility) and \`Central > System\` (global safety/migrations, restricted). The staff app remains business-branded, grants are business/location-specific, and a staff account with no grant sees nothing sensitive. Include **View as Staff** preview with signed-session API verification (not only frontend simulation), effective-permission explanation, impact review, versioned configuration history, reversible changes, and capability rollout states.

### P0 acceptance before declaring “everything is ready”
1. Owner tests Role- and User-specific Show, Locked, Hidden; wrong link and direct REST deny; no Central or sibling business logo/name; revoked user cannot access cached, API, export, reports or storage.
2. Set up an isolated new Paint business and at least one branch/warehouse without code changes; ensure labels/stock/items/roles/reporting/billing are correctly scoped, while \`not_implemented\` modules remain unavailable with accurate status.
3. Simulate a crash during 4th provisioning step and retry with same key: exactly one business and expected sites, either fully configured or explicitly recoverable in DRAFT; no orphan/unmapped sites.
4. Validate full cross-business movement safety, data retention and audit trail, one business at a time, then secure activation. Repeat with Construction only once its template has real implementation.
5. Keep legacy Sweets workspaces operable and preserve stock/account data during every change.

**Disposition:** Architecture analysis and recommended gates only; no production data changes, module removal, switch toggles, merge, or live activation. Retain the existing Owner option controls rather than rebuilding them; prioritize integration verification, scope hardening and template readiness.

## 9. Non-negotiable enterprise scale: EASY SETUP ≠ LITE ERP (owner clarification)

**Enterprise product requirement; not a claim of current delivery:** Quick Setup minimizes user input and clicks, never features, reports, controls, business complexity or scale. Advanced Setup exposes the SAME architecture and capabilities at finer granularity. Never split this into weak "basic ERP" and separate enterprise ERP products.

### Explicit scale target
- Support and load-test **100+ branches/showrooms, 100+ factories/production sites, and 100+ warehouses/godowns inside a single business**, and multiple such businesses in one Central Portfolio. This is a DESIGN/TEST OBJECTIVE, not a verified capacity claim.
- No hardcoded location or business counts, fixed branch arrays, arbitrary per-business facility ceilings or linear API fan-out for portfolio totals. Use proper canonical business/unit/location IDs, indexed scoped queries, pagination, filters, bulk setup/import, transactional stock ledgers, bounded background reporting jobs and monitored retries.
- Keep physical stock Location IDs and existing links stable. Model groups, legal entities, business workspaces, operating sites and multiple stock bins/locations as distinct hierarchy levels.

### Universal enterprise capabilities (composable 10+ industry templates)
All supported business types must be able to select compatible capabilities from a comprehensive registry, including:
1. Master data: items/variants, UOM conversion, brands, locations/sites/stock bins, prices, customers/suppliers, legal entities, multiple currency/tax schemes, cost centers and numbering.
2. Operations: purchasing/PO/receiving/returns, stock ledger/transfers/in-transit, warehouse replenishment, manufacturing BOM/recipe/routing, batches/expiry/serial, quality control, waste, cost valuation, POS, invoicing, delivery and online orders.
3. Finance/control: accounts receivable/payable, cash/bank, GL and reconciliation where actually implemented, financial periods, budgets, approval thresholds, segregation of duties, owner exceptions, audit history and reports.
4. Workforce, integrations and enterprise governance: branch staff/roles, attendance, payroll where implemented, notifications/automation, offline synchronization, API/web integration, data backup/restore, audit and activity logs, change-control, secrets/security.
5. Enterprise reports: portfolio, business, brand, branch, factory, warehouse, project and product drilldowns; sales, gross/net profit, margin, stock valuation/aging, production output/yield/waste, purchases, customer/supplier dues, cash flow, forecasts, KPI trends, approvals, exceptions and exports.
6. Industry packs: Sweets/Bakery, Restaurant/Kitchen, Paint/Hardware, Retail/Wholesale, Manufacturing, Construction, Import-Export, E-commerce, Technology/Digital, and Services.

**Critical distinction:** An extensive catalog is not the same as completed software. Every capability in a versioned feature registry must disclose supported-and-tested, implemented-unverified, partial, not-implemented or not-applicable status, dependencies, relevant business templates, role permissions, report coverage and acceptance tests. The application must never mark an incomplete business template fully ready or silently hide missing functionality. Owner controls may configure existing functionality; genuinely unbuilt features still require development and verification.

### Master AND individual Business Owner Boards
- CORE 10 Central controls multi-business portfolio, legal entities, group-wide configuration, all identities/roles, business creation and consolidated performance.
- Every business also contains a full Business Owner Board for its own branches, facilities, operational modules, staff grants, user/role Show-Locked-Hidden choices, business-specific workflow rules, approval thresholds, local analytics, finances, reports and brand settings.
- Both views use one authoritative configuration and permission model. A change scoped in a Business Owner Board is instantly reflected in Central; no duplicated ownership data or conflicting systems.
- Staff sees its verified business brand and only its authorized sites, transactions and actions. Hidden and Locked are UI options; backend authorization is mandatory regardless of presentation or direct URL/API.
- Optional operational switches remain Owner-configurable. Database tenant isolation and global security are NOT ordinary optional business switches.

### Quick vs Advanced setup — identical feature completeness
- Quick Setup asks just essentials: business category/template, legal entity, name/brand, initial facilities, chosen default role/module profile. Then it PROVISIONS all applicable fully implemented enterprise capabilities and safe defaults, keeping advanced fields adjustable.
- Advanced Setup exposes detailed accounting/stock/procurement/production rules, roles, access visibility, sites, integration, approval, numbering and reporting configurations on exactly the same engine.
- One transactional or auditable resumable provisioning coordinator ensures no partially active businesses, duplicate sites or inconsistent role/ledger records if a setup step fails. Idempotent retry/repair is mandatory.
- For an already-implemented industry capability, future business/branch/factory/warehouse creation MUST require configuration only, not code edits.

### Enterprise readiness acceptance — NOT yet passed
- In isolated staging, provision at least two active businesses, ten category templates and **100 branches + 100 factories + 100 warehouses within one business**, using the normal UI/API without code edits.
- Validate stock/production/purchases/transfers/approvals under concurrent staff operations, inter-site operations, retry/crash/offline recovery, and balances against audit ledgers. Test business-scoped reports and Central consolidated report reconciliation, no internal-transfer double counting.
- Prove real authenticated user/role/business/location permissions for Show/Locked/Hidden plus direct REST, reports, exports, storage, offline and revoked users; no cross-business leakage.
- Run production-like load, query-plan and p95 latency benchmarks, recovery/restore drills and capacity/cost checks before claiming enterprise ready; don't invent passing numbers.
- Confirm each of ten templates is FULLY IMPLEMENTED before activating it for real businesses; report partial/not-built modules and all missing reporting coverage without concealing them. Preserve existing Islamiya live data and workflows.

**Sequencing:** isolate tenant data and role semantics -> consolidate reusable ERP/catalog registry -> scalable automatic provisioning and 300+ site structure -> Master & Business Owner Boards -> reporting definitions and reconciled aggregates -> industry template build-out -> production-like resilience/performance certification.

**Governance:** Scope clarified in the existing Draft PR only. No production DB writes, migrations, toggles, PR merges, deployment, or new Decision Book audit-log rows.

## 10. Finance, independent tenant and scope lock (Owner-approved product scope, 2026-11-10)

**Decision status:** Owner has affirmed these modules must exist in the final enterprise software. APPROVED describes the **scope**, not a claim that the implementation is ready. Commercial SaaS **delivery** is a late-phase feature, but the separation of tenants must be designed in the foundation now.

### Scope A — Partnerships, non-equity investment and financing: one composable Finance Engine
- This is an advanced **Investment, Equity & Agreements** capability, not a second ERP and not the same as automatic software access. Keep legal ownership, capital contribution, contractual share of profit/loss, return obligation and application permissions as **separate ledgers/roles**.
- Per-business, per-branch, per-factory, per-project and potentially per-product-line agreements can have multiple counterparties, individually versioned dates/terms, electronic documents, approval rules, amendment history, principal payments and reconciliation.
- Types supported by design: (1) true equity partnership/cap table with voting and ownership changes subject to jurisdiction-specific legal confirmation; (2) non-equity actual profit-based investment, percentage applied to a documented profit basis and loss rules; (3) non-equity financing with a contractual rate/repayment obligation; (4) debt/loan; (5) franchise/royalty; (6) hybrids via separately versioned agreements. Realized-profit percentage, investment-principal annual percentage and fixed scheduled monetary amount MUST NOT be conflated.
- Investment schedules: capital events, payment frequency monthly / quarterly / half-yearly / annually / custom, start/end/maturity, partial withdrawal and repayment, compounding where contract allows, caps/floors/catch-up, penalty policy where legally applicable, multiple investors, independent agreement conditions, projected vs accrued vs paid vs overdue, withholding/tax and cash requirements, payable aging, partner statements and audit evidence.
- Optional Investor Portal receives **only that investor's contractual reports and payouts**, never access to other businesses or operational actions unless separately granted by owner. Equity percentage never automatically grants login, a business owner role or an elevated permission.
- **Existing code to preserve:** live public tables partner_ventures, partner_agreements, agreement_parties, partner_capital, partner_rules, partner_settlements, partner_settlement_lines, partner_settlement_payments, partner_templates; UI partners.js. Current owner-only guard _a44_guard and 4 illustrative templates already exist. These have not been through real customer/end-to-end tests; there are 0 live venture, agreement, capital, settlement records.
- **Known P0 defect:** public.partner_calculate currently uses **all public.locations** for venture scope='business'. This can contaminate investor payouts across businesses. DO NOT enable multi-business investor settlement until canonical business_id/tenant_id and correct scoped profit base are enforced in the database with direct real signed-session regression tests. Prevent double-payment and double-counting across simultaneous agreement periods.
- Existing example templates investor_payback, fixed_return_loan, partnership_5050 and franchise are INACTIVE examples; don't represent them as production-ready. Additional scheduler, maturity repayment, capital-versus-profit ledger segregation, reconciled book entries, per-investor portal and complete legal/finance checks remain work.
- Require statutory/accounting, relevant Bangladesh legal, tax and (when claimed) Sharia review of each contract classification. Don't label a fixed contractual return as realized profit sharing.

### Scope B — Independent owners and commercialization
- **Platform** is the software operator/developer; **Tenant** is an independent customer's security and billing boundary; **Legal Entity** is a company's legal/accounting person; **Business** is an operational workspace; **Partner/Investor** is a contractual counterparty. These identities must never collapse into one `owner` flag.
- A friend's new store must belong to the FRIEND'S tenant with that friend as Tenant Owner. They create businesses/locations/staff using the same Enterprise ERP templates, with separate branding, settings, identifiers, stock/finance and reports. No implied master access for CORE 10's owner to a customer's data. Delegated support access must be explicit, consented, time-limited, least privilege, revocable and audited. Hosting-level privileged access still requires technical privacy controls.
- The current public.is_owner() checks a **global user_roles owner**, and current public org_units has one root group, two legal entities and one business; neither is yet a secure independent multi-tenant product. Need tenant identity and membership/role grants, tenant_id propagation to all relevant transactional/partner/report/storage entities, comprehensive RLS and SECURITY DEFINER hardening, background-job and export scoping, separate owner, tenant-admin, business-owner, business-staff and optional investor portal identity.
- Commercial SaaS = separate **platform administration/billing module** over the SAME enterprise ERP engine; later features include signup/onboarding, subscription/plans/billing, license/state, support tickets, feature bundles, white labeling, data export/portability, quota monitoring, suspension with safe access/export, and optional dedicated deployments. Do not treat a staff role or separate theme as tenant isolation.
- **Phase policy:** implement tenant-safe data ownership boundaries and extensibility in early schema/security work; actual external SaaS sales, subscription billing/marketing and white-label commercialization may be the LAST rollout after core ERP, industry packs, owner boards, finance, reporting, data isolation and load certification.

## 11. Locked decisions vs development status

- Central Decision Book owns short stable, owner-approved policies. This GitHub Draft PR retains the full capability specification and acceptance gates. Do NOT add 50 micro-decisions for every screen, workflow or CI run.
- Decision IDs to record/maintain: Enterprise Full Scale, 10 Template Catalog & Add-ons, One-Time Setup Engine, Central & Business Owner Control, Equity/Investor/Financing, Consolidated Reports, Independent Tenant & Future SaaS, and Global Organization Security Mode Migration. Reference previous C10-D001–D029 rather than erasing/replacing them.
- **All capability packs start with honest statuses**: supported_and_tested / implemented_unverified / partial / not_implemented / not_applicable, with a published inventory and tests. A template cannot claim Enterprise Ready until its required flows, reports, permissions, performance and disaster recovery pass.
- **Delivery priority:** Foundation hierarchy and tenant identity; strict business/tenant security; legacy data reconciliation; registry of templates/modules; transactional/resumable provisioning; full dual Owner Boards; finance/partner/investor engine and verified investor accounting; comprehensive dashboards; remaining industry packs; 300+ site performance certification; external SaaS commercialization LAST.
- The Owner has mentioned an additional unspecified late-stage idea without enough details. Do not invent its feature, price, use case or technical module; capture later when concretely described.
- All work remains in draft/code review until a separate owner-approved release. No production DDL, live toggle, automatic PR merge, or untested real-money usage.
