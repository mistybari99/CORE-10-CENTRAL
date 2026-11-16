# B-020 — NP01 Owner Control integration, gate 1: unbound RPC fence

Date: 2026-11-16. Branch: `build/chatgpt-np01`. Draft PR #107.
Context: Claude B-010 trunk `a9cc3b3` was merged into NP01 (merge commit `ac429abd`). This did not merge PR #107 into Claude's trunk.

## Evidence
The exact-merge-head B-010 PostgreSQL 17 registry CI failed at `UNMAPPED_STATE_CHANGING_RPC` for the six API-callable VOLATILE functions introduced by NP01 0014/0015:

- `assess_approval_threshold_v1`
- `assess_current_approval_threshold_v1`
- `configure_approval_threshold_v1`
- `request_approval_exception_v1`
- `decide_approval_exception_v1`
- `withdraw_approval_exception_v1`

The merged runner sorts 0014–0017 **before** Claude's 0100–0102. An NP01 migration in its own 0001–0099 block cannot insert or update the registry table that Claude only creates in 0100. Editing Claude's 0102 seed or registering a fake `enforced` status would breach the agreed ownership and bypass security. The registry CI is not disabled.

## Safe interim decision
NP01 migration `0017_np01_unbound_rpc_fence` revokes authenticated EXECUTE on precisely the six not-yet-bound RPCs (PUBLIC was already revoked). The explicit reverse migration restores only their original authenticated privileges. All six are **fail closed** until a correctly sequenced control binding is integrated; this is **not** a completed B-020 or GOV002 feature.

A dedicated SQL regression test enforces the closed API boundary. B-010's registry test should now pass without treating ungoverned functions as certified. Synthetic superuser fixtures continue to test underlying behavior without granting API roles access.

## Owner / Claude integration dependency
B-020 needs a registry update *after* 0102 exists. Request Claude's trunk lane to reserve an NP02 post-0102 integration migration (suggest `0103`, only after Board reservation) to register NP01's six RPCs and promote existing pending mappings as each caller genuinely invokes `core10.control_check_v1`. NP01 will first bind feature RPCs in its own numbered migrations with positive/negative PostgreSQL security tests. Coordinate exact function signatures and rollback order across the two owned blocks. Do not assume a partial B-020 is production ready.

No hosted SQL, staging permission, production release, Cloudflare deployment, IMG-ERP-SG write, or cross-lane branch write occurs in this change.
