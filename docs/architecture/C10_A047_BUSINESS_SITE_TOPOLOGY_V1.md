# C10-A047 — Enterprise Business / Site Group Topology

**Owner-approved architecture:** D047/R126 and existing D032/D033/D036/D041/D042/D046. The ERP must become structurally usable with test identities before actual operations. This first slice creates real business-unique group entities and a secure site topology service, not copied stock or a second ERP.

## Canonical model
`Tenant → Legal Entity → Business → Site Group → Site (A018 canonical) → Stock Location (A018 canonical)`.
Business/site grouping affects navigation and structure only, **never permissions, posting or accounting**. Every site is assigned at most one subgroup via unique `site_id`; group includes kind and scope foreign key; moving sites never changes site ID, location ID, item or movement history. A018/A020 business creation remains authoritative and compatible. Existing site rows can be grouped idempotently after the fact.

Five generic kinds: showroom, factory, godown, warehouse, project. Owner can create multiple subgroups of one kind (e.g. North Zone Showrooms). Unknown kinds fail closed. Group members require matching business/tenant through composite FK, and server enforces compatible site-kind on creation and moves. No direct client table DML; top-level signed RPCs verify effective A018 tenant/business authority on **every request**. User-set role labels never authorize writes.

## Actual supported actions
- `bootstrap_site_groups_v1(business, request)`: creates 5 default groups and assigns existing sites without touching locations
- `create_site_group_v1(business, kind, key, label, request)`: one named subgroup, idempotent per business
- `create_site_in_group_v1(business, group, label, request)`: uses A018 `provision_site`, creates canonical stock location and membership in same transaction
- `move_site_group_v1(site, group, expected_version, request, reason)`: optimistic locking, event audit and idempotent replay; stale changes rejected
- `read_site_topology_v1(business)`: grouped sites/stock location IDs, only visible by server-scoped effective role; staff cannot view other sites or audit
- `read_site_topology_audit_v1(business, limit)`: owner-approved audit projection, capped

## Build evidence
Draft PR #45, last code SHA `2cd73a2d54f7f40123495f2771e46553bd6c3c0e`. PostgreSQL17 RLS/RPC E2E includes Owner A, local Business Owner A, scoped Counter Staff A, manager, investor, revoked, Tenant Owner B and anonymous. Stale versions, replay conflict, foreign group, original 5001 Site Location ID and new canonical creation tested. Browser 390px/1440px tests use explicit **synthetic signed-client fixture**, not real GoTrue tokens. CI workflow run https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/43002515565 successful; no live SQL or release.

## Unfinished integration and release gates
Route is source-code working only, not yet added to root Owner workspace navigation. Confirm identity scope and backend in real disposable Supabase GoTrue stage before releasing SQL. A018's manager broad `stock.post` permission and invoker mismatch are not fixed by navigation groups. No alteration to historical Islamia ERP data. Entire 10-industry module matrix is still under development.
