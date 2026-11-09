# CORE 10 — Double-Auditor Review, Round 1 and Round 2

Review date: 2026-11-09
Scope: multi-business owner/tenant boundary and scoped approval inbox.
Review method: two **analysis roles** (not externally hired agents) independently review ERP correctness and security integrity before and after each change. All assertions are grounded in current repository and mocked tests. Production DB has NOT been queried.

## A. Auditor 1 — ERP & operations, first pass
- The same user is CORE 10 Master Owner and local Business Owner, not two accounts.
- Master portfolio and business owner dashboards are distinct views.
- Each operational location has one parent business; same-business branches can be combined.
- Approval source must be canonical, not copied or re-created per business.
- **Risk flagged:** the new `core10_owner_inbox_v1` is a placeholder; it currently does not exist in the inspected repository/database access. Never show a fake count.
- **Risk flagged:** existing `nav.js` loads counts using `entries`, `release_requests`, `profiles`, `item_changes` and calls to counts RPCs without a demonstrated business filter. Existing Owner Board/Reports are not yet proved tenant-scoped.

## B. Auditor 2 — security/integrity, first pass
- `core10-shell.js` previously presented the successful subset of a staff member's assigned locations **before all RPC mapping checks completed**, and could accept incomplete mappings. 
- An explicit server-provided business ID is required; the first-business fallback in `bizctx.js` remains a **known release blocker**.
- API caller can forge URL business ID; neither URL selection nor UI filtering grants permission.
- Validation previously lacked a strict 40-row upper limit, typed positive numeric business IDs, canonical request ID limits, and consistent metadata. The front end is only defense in depth, not an authorization proof.

## Debate → Decision (Round 1)
Auditor 1 requested continuity for Islamia's existing ERP. Auditor 2 refused to enable uncategorized cross-business approval results. Agreed:
1. Keep Islamia's theme and legacy approval/transaction code unchanged.
2. Fail closed on incomplete staff mapping; wait for **all** scope RPCs.
3. Harden front-end read-only inbox response validation; no decision writes.
4. Keep `org_scope_on` untouched (not certified).
5. Expand read-only production preflight instead of guessing an approval SQL migration.

## Round 2 — independent re-audit acceptance gates
### Auditor 1: operations
- Owner retains access to business selection/master and local owner landing.
- Staff assigned multiple branches of the SAME business works only after *all* RPCs return.
- Existing business/branch/item IDs, ledger history, sales and reports unchanged.
- Missing inbox API must show unavailable, not 0 approvals.
### Auditor 2: security
- Partially resolved or mixed-business staff assignment returns zero locations and zero business options.
- A scope change invalidates old mapping until reverified.
- Inbox rejects >40 rows, duplicate IDs, string business IDs, foreign business IDs, wrong scope, unrecognized business IDs and malformed payloads.
- Cross-business Owner approval reads remain blocked pending authenticated production RLS/RPC tests.
- Frontend controls DO NOT establish actual RLS isolation.

## Verified vs pending
- Code-level checks and mocked tests can verify frontend guards and data schema validation.
- Database RLS, RPC body, source mapping, transaction atomicity, staff API denial and offline cache isolation remain **NOT VERIFIED**.
- Live app points at Supabase ref `kbuhnpqooycqbzrfejcs`; connected Supabase only exposes inactive `luoeyyngayxpqecuuijb`. No production SQL writes, no approval requests or business data altered.
- Do not put new businesses and staff into real operation until negative direct-API tests pass.

## Action sequence after real DB access
1. Run `CORE10_MULTIBIZ_AUDIT_READONLY.sql` and `CORE10_SECURITY_PREFLIGHT.sql` on the live project. Record private outputs.
2. Identify each approval source and exact business-scoping linkage.
3. Create a minimal server-verified read-only `core10_owner_inbox_v1` endpoint using only proven business mappings and authenticated owner scope, with stable canonical IDs.
4. Implement and test tenant-scoped source RLS/RPC and staff REST/RPC negative tests; keep production switch OFF until gates pass.
5. Build audited transactional decision endpoints with idempotent transition, approval policy, actor/business checks and audit log; then add Approve/Reject UI.
6. Verify master rollup and local business inbox deduplicate the same request IDs.

## Round 3 — Tenant identity adapter hardening (2026-11-09)
- Audit role A: Current legacy Business Profile, signed Logo URL and location names must not break for authorized single-business staff or owner.
- Audit role B: Even when `BOS.biz.locBizId` uses fallback internally, *staff-facing adapter* must return null if any location mapping is pending, denied, mixed across businesses or does not contain requested place ID. Profile/logo/profileFor also fail closed.
- Agreed changes: wrap staff `locBizId`, `profileFor`, `profile`, and `logo` at the existing shell boundary. Keep original owner calls unchanged; no SQL/table writes.
- Added regression checks to `tests/core10-complete-mapping-smoke.js`; both audit rounds must pass on actual Node in GitHub Actions.
- Owner-side unlinked-location fallback in bundled `bizctx.js` remains separate release blocker pending a coordinated source/bundle migration. This guard cannot replace database authorization.


## Round 4 — Pending request cross-session data race and UI cleanup

Auditor A (operations) requires owner switch and logout to render a clean local business inbox and leave Islamia legacy operations untouched. Auditor B (security) found that inbox request `key` previously lacked the owner's authenticated profile ID, so an old response for the same business could overwrite another owner's session view. They agreed to bind both business and master request keys to `ctx.profile.id`, reject responses/errors from a stale scope or node, refuse a missing profile ID, and immediately clear stale inbox content on signout/unset scope.

**Two rounds of regression** now exercise both network response orders (old-first and new-first), then logout cleanup. This proves only UI behavior; production API/RLS remains unverified.
