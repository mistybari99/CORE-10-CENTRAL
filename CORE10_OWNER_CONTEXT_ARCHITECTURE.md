# CORE 10 — Master Owner and Business Owner (Architecture Decision)

Status: **Approved owner context model; UI navigation partially in place; live business-scoped approval data NOT certified.**

## Single account, two operating contexts

The same authenticated user has global `MASTER_OWNER` authority and exercises `BUSINESS_OWNER` capabilities when viewing a selected business. It is not a second account, not a restricted staff role, and not a downgrade of owner privileges.

- **Master Context (CORE 10):** business portfolio, business creation, cross-business overview, master governance, consolidated reports and a rollup of owner decisions across businesses.
- **Business Context (business_id):** full business owner access for Islamia or Paint or another business: owner dashboard, the business's pending approvals, operations, staff permissions, branches/factories/warehouses, finance and reports. Brand and selected business ID are fixed in the context.
- **Staff Context (assigned business_id and optional location/project):** only explicitly authorized business routes and data. No discovery of CORE 10 or sister businesses.

## Owner user flow

CORE 10 -> select **Islamia Misty Ghar** -> Islamia Business Owner Dashboard (`index.html?workspace=islamia&biz=ID#/home`) -> approve Islamia requests, manage its branches, view its reports -> back to CORE 10.

CORE 10 -> select **Paint Business** -> Paint Business Owner Dashboard (`business.html?workspace=business&biz=ID#/home`) -> decide Paint requests, manage Paint branches and reports -> back to CORE 10.

Business Workspace shows a return-to-CORE-10 control; it must not show the global business switcher or the master organization menu. CORE 10 remains the place to switch businesses.

## Single approval record, two owner views

A decision request belongs to one business_id and may have location_id/project_id, request type, requester, status, authorizing role/user and audit events. The **business inbox** shows only the selected business. The **CORE 10 inbox** rolls up all businesses using the SAME underlying request IDs. Approve/reject/escalate must be atomic and authorized server-side; decision in either view updates both, not duplicated queues.

## Code audit

- Existing `ownerboard.js` and `pending`/exceptions routes already support owner-facing work, including `needs_you_oldest`.
- The contextual Business Owner Home UI was added in `core10-business-owner.js` and launches from CORE 10 business cards via `#/home`.
- Current change suppresses global business switcher inside business-owner context and redirects the master organization route to CORE 10.
- **Unverified:** existing `needs_you_oldest`, pending counts, Owner Board widgets, reports and direct REST/RPC requests cannot yet be asserted to obey business_id filters. No business-specific approval count is claimed to be accurate until live DB audit.
- The business context must be asserted by the server, never trusted from the URL. Existing first-business fallback in `bizctx.js` needs controlled removal.
- Business owner dashboard preferences should be keyed by user and business (not only user).
- Islamia's original visual theme and records are unchanged. Existing business/branch/group structure is unchanged.

## Production blockers

1. Connect the **actual live Supabase project** used by the published app; current connector exposes a different inactive project.
2. Audit and repair RLS, SECURITY DEFINER RPCs, approval/report filtering, stock/accounts, storage, offline caches.
3. Build a server-verified business-specific Owner Inbox and the consolidated CORE 10 Inbox from one request source of truth.
4. Test owner acting inside Islamia, owner inside Paint, consolidated owner rollup, staff direct API denial and revocations.
5. No real cross-business activation before the above checks pass.
