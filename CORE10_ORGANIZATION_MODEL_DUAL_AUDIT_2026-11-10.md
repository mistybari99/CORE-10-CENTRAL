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
