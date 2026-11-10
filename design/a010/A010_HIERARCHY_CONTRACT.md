# C10-A010 Hierarchy Contract: Business -> Operating Site -> Stock Location

Status: DESIGN / BUILT + TESTED IN ISOLATION only. NOT applied to live IMG-ERP-SG. Class H (schema): needs read-only parity check, staging proof, backup/rollback and explicit Owner go/no-go. `org_scope_on` stays OFF and is not touched.

## Assumed live shape (verify read-only before apply)
`org_units(id, parent_id, kind, name, ...)` tree: group -> legal_entity -> business. `locations(id, org_unit_id, ...)` with 8 rows (IDs 1,2,3,4,5,6,7,9), all `org_unit_id = 3` (SWEETS business). 136 FKs reference `locations`, 72 reference `org_units`. Column names are inferred from the repo audit SQL, not from a live dump.

## Entities and keys
| Entity | Where | Key |
|---|---|---|
| Group / Legal entity / Business | existing `org_units` (kind) | `org_units.id` (unchanged) |
| Operating site (NEW) | `c10_operating_sites` | `id`; unique `(business_id, code)`; unique `(id, business_id)` |
| Stock location (existing) | `locations` | `locations.id` (unchanged, never renumbered) |
| Location->site link (NEW) | `c10_location_site_map` | PK `location_id`; composite FK `(site_id, business_id)` -> sites |

## Invariants
1. A site's `business_id` is an `org_units` row of `kind='business'` (trigger).
2. A location maps to at most one site (PK) and, after seeding, exactly one.
3. The mapped business must equal the business derived from `locations.org_unit_id` by walking `parent_id` (trigger `c10_map_guard`); NULL `org_unit_id` is rejected.
4. Mapped sites/locations cannot be deleted (RESTRICT); a mapped site's business cannot change.
5. `c10_hierarchy_violations` must be empty (`no_site`, `business_drift`). Because existing tables are not altered, later edits to `locations.org_unit_id` are caught by this view, not by a trigger.

## Legacy mapping (no renumbering)
The seed creates one `legacy-default` site per business that has locations (today: 1 site for SWEETS) and maps all 8 legacy locations (1,2,3,4,5,6,7,9) to it. No ID in `locations`, `org_units` or any of the 136/72 referencing tables is read-modified. Splitting into real sites (showroom, factory, godown...) is a later, Owner-decided data change: add sites, re-point map rows. No FK-referencing table changes.

## Stored vs derived
Stored: sites, the location->site map, `business_id` on the map (denormalised only to enforce the composite FK; trigger forces it to equal the derived value).
Derived: business of a location (`c10_business_of_unit(org_unit_id)`), views `c10_location_hierarchy`, `c10_hierarchy_violations`.

## Security posture of new objects
RLS enabled, no policies, all privileges revoked from PUBLIC/anon/authenticated (so Supabase default privileges do not expose them). Views are `security_invoker`. No grant/RLS/policy change on any existing table. Read access for the app needs a separate reviewed RLS design.

## Rollback
`a010_rollback.sql` drops only the 2 views, 2 tables, 3 functions (idempotent). Because nothing existing was altered, rollback fully restores the prior shape; the test proves identical schema/constraint/grant/policy/RLS/function snapshot hash before apply vs after rollback. Take a backup before any real apply regardless.

## Evidence (synthetic PG16 fixture, `run_a010_tests.sh`)
22 checks PASS; candidate applied twice (idempotent); rollback twice; shape hash equal; legacy IDs equal after rollback. Negative control (`negctl`: guards/PK sabotaged) FAILS 8 checks as intended. This does not prove behaviour against real Islamia data, signed-JWT isolation, or app workflows.

## Open questions for the Owner
1. Is one default site for SWEETS acceptable initially, or define the real site split of locations 1-7,9?
2. Should a site be allowed to belong to a legal entity rather than only a business?
3. Which roles should read sites (needs RLS design) and does `org_scope_on` stay OFF until then?
4. Confirm live `org_units`/`locations` column names via read-only dump before staging.
