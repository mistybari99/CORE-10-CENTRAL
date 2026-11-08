# CORE 10 — Owner / Business / Branch / Staff release gates

Status: **frontend owner/tenant separation implemented; live multi-business security NOT yet certified**.

## Intended contracts

* CORE 10 is the owner-only software identity. It is not a rename of Islamia Misty Ghar.
* Every business has its own business profile, brand, logo, units, locations, finance and inventory boundaries.
* Non-owner users belong only to explicitly assigned business(es) and operational place(s); role grants determine actions within that scope.
* A staff login must never expose CORE 10 master UI, sister businesses, master settings, owner identity, or another business's business profile.
* A global owner may see all business units and drill down; they must be able to distinguish business totals from consolidated totals.
* Unknown, missing, stale or conflicting assignments must fail closed (no automatic assignment to "first business"). Staff UI resolves a business only from the authenticated `org_unit_scope(p_location)` result for a staff-assigned location. A missing/denied RPC yields no business UI.
* Moving a location between businesses requires separate impact analysis and a deliberate approved operation. Never auto-migrate history.

## Source discovery

Published app: **mistybari99/islamia-bos-app**. Its config points to Supabase project ref **kbuhnpqooycqbzrfejcs**.
Connected Supabase Plugin currently exposes another project (Core-10, ref **luoeyyngayxpqecuuijb**, INACTIVE).
Therefore no live RLS checks, business backfills or permission changes were executed in the production project.

SQL sources available in public deployment:
- Run 17: Phase 122 (org_units / org_tree)
- Run 18: Phase 123 (user_org_scopes, org_scope_on switch, limited RLS and RPC scoping; switch defaults OFF)
- Run 24: Phase 134 (server-side business profile, private org tree per business)
- Run 25: Phase 135 (operational places mapped to business)

**Important:** Phase 123 explicitly documents that the switch ON does not finish scoping all read/RPC families. Do not turn ON without testing all dependent modules and access paths. Do not assume Phase 122–135 are installed just because the HTML setup files are present.

## Read-only preflight

Run `CORE10_SECURITY_PREFLIGHT.sql` in the *actual live application's* Supabase SQL Editor; keep the output private.
Check missing functions; business mapping for every location; role assignments with no business; management grants with no scopes; RLS; and anonymous access to security-definer RPCs.
Run the original Phase 123 `org_scope_preflight()` under a real owner authenticated session (not an unauthenticated SQL Editor context).

## Release blockers — must pass before using with separate real businesses

1. Verify the app's production project identity; back up the schema and data; verify rollback.
2. Confirm Phases 122, 123, 134, 135 and their prerequisites are installed in order.
3. Map existing Islamia operational locations to the Islamia business without altering location IDs or historical transactions. Resolve all unmatched locations and staff.
4. Add business scopes and branch assignments with explicit owner approval. Review all management grants, global grants and impersonation/emergency paths.
5. RLS and security-definer RPC audit for **every** tenant-owned table and API, not just org_tree. Audit SELECT/INSERT/UPDATE/DELETE, aggregates, exports, reporting, logs, photos/storage, realtime and offline sync; do not allow cross-business identifier lookups.
6. Test read AND write operations with real distinct staff test accounts for Islamia, Paint, Construction, Online; also test a branch-scoped staff account and the group owner.
7. Run two-business simultaneous test: business A never sees B's profile, org tree, people, cash, stock, purchases, payments, or analytics; direct REST and RPC calls with B IDs must fail.
8. Test status change: revoke an assignment while session is active, then test access after refresh and session/token renewal. Audit branch transfer/move, export, backup and offline-cache isolation.
9. Only after all tests and user-approved cutover, activate the business scope switch with a controlled transaction, verify immediately, and retain fast rollback.
10. Then run real-money workflow smoke tests: opening stock, POS, transfer, approval, balance, reports and backups for each business.

## Presentation delivered

- `core10-shell.js` implements owner branding and staff-scoped presentation. Staff business identity now requires a server-verified `org_unit_scope` mapping; no local first-business fallback.
- `owner.html` plus `core10-owner.webmanifest` offer the owner a separate CORE 10 installation/launch identity. Existing `index.html` remains Islamia-branded.
- Location, access control and portfolio are still driven by existing Supabase objects. No business or location data has been changed here.
- **Presentation filtering does not make a user secure. RLS and RPC validations are release gates.**

## Acceptance test matrix

| Session | Must see | Must not see |
| --- | --- | --- |
| CORE 10 owner | Master portfolio, all businesses and consolidated reporting | An unexplained blend of business-specific totals |
| Islamia branch counter | Islamia profile, assigned branch, authorized POS/stock | CORE 10, other Islamia branches without grant, any other business |
| Islamia management | Islamia units explicitly in management scope | CORE 10, sister businesses, global owner rights |
| Paint branch staff | Paint business, assigned branch | Islamia content, CORE 10 |
| Construction project staff | Construction project and approved locations | Paint/Islamia data, CORE 10 |
| Online staff | Online business and assigned team | Other businesses and CORE 10 |
| Unassigned/pending/revoked user | No business data | No fallback to the first business |

Never claim `99%` or `production secure` without a real database audit, real staff sessions and repeatable evidence.

## Unchanged Islamia theme and portable workspace boundary

**Implementation:** Islamia remains the original business workspace and retains its complete existing theme, logo, pages, inventory and transaction semantics. No copying, renaming or alteration of Islamia records is performed. CORE 10 shares the current ERP modules and CSS; its owner workspace is a separate entry/identity.

* Islamia remains at `index.html` with the original `manifest.json`, `app.css`, `logo.webp`, `icon.svg` and `mark.svg`. This stage does not edit those assets.
* CORE 10 owner portal remains `owner.html` with its separate installation name and icon. It **uses the same app.css and current theme choices** as Islamia. No new visual theme is applied in this stage. Its distinct icon uses the existing ruby/gold palette.
* Owner theme choice is stored in `core10_owner_theme` instead of `bos_theme`. Initially the owner entry reads `bos_theme` if there is no owner preference. Subsequent owner choices never write `bos_theme`. Islamia users retain their existing theme preference unchanged. Future CORE 10 styling should apply only to the owner workspace.
* Owner users who sign in via the business entry are routed to `owner.html`; non-owners who enter the owner portal are routed back to `index.html` after authentication.
* This is reusable **software architecture**, not a copy-and-diverge codebase. Business / branch identity is resolved by user authorization; backend RLS / RPC security gates documented above remain blockers before expanding to live multi-business operation.

## CORE 10 master → Islamia ERP one-tap entry (2026-11-09)

* The single configured sweets business is displayed as **ইসলামিয়া মিষ্টি ঘর**, not a generic **মিষ্টি ও বেকারি** category. This is display-only; no business records are renamed.
* Owner clicks the Islamia business tile → the existing `index.html?workspace=islamia&biz=<id>#/locations` ERP with the selected business, native Islamia theme and the existing grouped branch/factory/godown location screen.
* The explicit owner-only business workspace bypasses the usual owner→CORE 10 redirect; all regular staff remain on the existing Islamia entry and do not see the CORE 10 workspace return button.
* Within the Islamia ERP, the owner has a clear **← CORE 10** return control. This is a UI navigation mode, not a new login or a new data permission.
* On the CORE 10 **Organization** master portfolio page only, the inherited POS bottom tab bar is suppressed using the `core10-master` body class and owner-scoped CSS. Other routes, including Islamia ERP, retain their prior navigation.
* Data model, database scopes, stock, brand profiles and Islamia CSS remain untouched; full tenant-isolation audits remain release blockers.
