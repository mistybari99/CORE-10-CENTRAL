# B-020 — verified RPC inventory and Claude handoff (2026-11-16)

**Source at NP01 commit `9fa72b3`:** `internal/migrations/0102_np02_control_seed.up.sql`,
`0017_np01_unbound_rpc_fence.up.sql`, `0018_np01_approval_policy_control.up.sql`,
`0019_np01_review_control.up.sql`, and `tests/migrations/control-registry-check.sql`.

**Inventory rule:** only VOLATILE `core10` functions callable by `authenticated` are in the
DEC-08 registry. A `pending` registry row stays pending even if the implementation now
calls the canonical Control port; no premature `enforced` status. Explicit
`REVOKE EXECUTE` is a fail-closed fence, *not* a promotion.

## A. 0102 registry: 21 state-changing API RPCs

| RPC | Catalog feature | Current 0102 status | Effective code as of 0019 | Responsible lane |
| --- | --- | --- | --- | --- |
| `build01_set_access_v1` | — | EXEMPT | Auth administration (canonical scope, audited) | NP01 |
| `change_access_v1` | — | EXEMPT | Auth administration, not business feature switch | NP01 |
| `build02a_set_approval_policy_v1` | — | EXEMPT | Auth permission grant administration | NP01 |
| `control_set_v1` | — | EXEMPT | Control-port Owner self administration | Claude |
| `control_revert_v1` | — | EXEMPT | Control-port versioned undo | Claude |
| `control_grant_override_v1` | — | EXEMPT | Control-port one-time exception grant | Claude |
| `control_revoke_override_v1` | — | EXEMPT | Control-port one-time exception revoke | Claude |
| `publish_approval_policy_v1` | `gov002.approval_policy` | PENDING | **CALLS `control_check_v1`** via 0018; TTL default | NP01 |
| `configure_approval_route_v1` | `gov002.review` | PENDING | NO direct check, stage-count binding missing | NP01 |
| `submit_typed_approval_v1` | `gov002.review` | PENDING | NO direct check, stage-count binding missing | NP01 |
| `decide_approval` | `gov002.review` | PENDING | **CALLS `control_check_v1`** via 0019 | NP01 |
| `delegate_approval_stage_v1` | `gov002.review` | PENDING | NO direct check | NP01 |
| `revoke_approval_delegation_v1` | `gov002.review` | PENDING | NO direct check | NP01 |
| `withdraw_typed_approval_v1` | `gov002.review` | PENDING | **CALLS `control_check_v1`** via 0019 | NP01 |
| `build01_setup_v1` | `setup001.provision` | PENDING | NO direct check; scope and max_sites pending | NP01 |
| `build01_site_v1` | `setup001.provision` | PENDING | NO direct check; business/site limit pending | NP01 |
| `setup_business_v1` | `setup001.provision` | PENDING | NO direct check | NP01 |
| `setup_industry_draft_v2` | `setup001.provision` | PENDING | NO direct check | NP01 |
| `provision_business` | `setup001.provision` | PENDING | A018 legacy fixture; supersession/retirement pending | Claude B-009 |
| `provision_site` | `setup001.provision` | PENDING | A018 legacy fixture; supersession/retirement pending | Claude B-009 |
| `post_stock_event` | `inventory.stock_event` | PENDING | NOT NP01; canonical Stock owner B-012 | Claude |

**Live 0102 registry counts at this code head:** 0 enforced / 14 pending / 7 exempt.
Of those 14 pending, exactly 3 have direct `control_check_v1` calls now (0018 + 0019);
the other 11 lack such calls. Of those 11, eight are NP01; three are Claude-owned.
The 3 direct calls have not been falsely marked `enforced`.

## B. Six 0014/0015 state-changing APIs fenced in 0017

| RPC | Current API status | Further work |
| --- | --- | --- |
| `assess_approval_threshold_v1` | authenticated EXECUTE revoked | Control binding, registry classification |
| `assess_current_approval_threshold_v1` | authenticated EXECUTE revoked | Control binding, registry classification |
| `configure_approval_threshold_v1` | authenticated EXECUTE revoked | Owner Control threshold limits, registry |
| `request_approval_exception_v1` | authenticated EXECUTE revoked | exception escalation parameter, registry |
| `decide_approval_exception_v1` | authenticated EXECUTE revoked | exception review/override policy, registry |
| `withdraw_approval_exception_v1` | authenticated EXECUTE revoked | exception withdrawal control, registry |

These are **not** registered as callable and **not** considered enforced. The PG17
`np01-unbound-rpc-fence.sql` verifies the grant remains revoked.

## C. Read-only or internal surfaces

- `gov003_audit_readiness_v1`, `gov003_audit_risk_v1`,
  `gov003_audit_export_v1`: STABLE, Auth-scoped reads. Exempt from the
  **VOLATILE API registry**, but the off-by-default `gov003.review_export`
  feature is **not functionally enforced yet**; `max_rows` bound is pending.
  A VOLATILE override-consuming check must not be silently injected into
  a STABLE read-only function; coordinate a safe read guard or explicit design.
- `my_routed_review_tasks_v1`: STABLE reviewer inbox; scoped Auth read,
  not a state-changing control registry entry.
- `assert_approval_threshold_v1`, `_can_review_stage_v1` and other
  `_*` helpers: internal, not registered API mutation endpoints.
- `control_check_v1`: internal canonical Control port, never an exposed API.

## D. Verified 0019 increment

- Up/down migration pair: restores pre-0019 function bodies exactly on rollback;
  no changes to 0011, 0100–0102 or any previous migration checksum.
- New PG17 E2E: 3 synthetic identities in two tenants, review switch off/on,
  maker cannot self-approve, foreign tenant cannot review, disabled withdrawal
  does not write, replay stable, canonical audit integrity.
- Exact source SHA `9fa72b3bdff3ca1351144e98146abc0fc5db700f`: **4/4 GitHub workflows PASS**.
  - NP01: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/43913294062
  - Owner Control registry: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/43913294048
  - Full PG17 migrations rollback/reapply: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/43913294147
  - S1-c Approval/Audit: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/43913294057

These are disposable PG17 results, **not** the full 16-persona signed UI→RPC→DB→report
matrix. Only these three new synthetic personas are exercised by this specific 0019 test.

## E. Integration dependency / next safe steps for Claude

1. **Do not edit 0102 in NP01.** 0019 runs before NP02 0100–0102; there is no
   safe NP01-only registry promotion after 0102. Claude should reserve a
   post-0102 NP02 migration (number to be agreed on the Board) for promoting
   *only* directly checked functions, and registering later newly bound RPCs.
2. Next NP01 migrations must bind `submit_typed_approval_v1`,
   `configure_approval_route_v1` including enforced `stages`, then
   delegation/revoke, setup scope/site limits and six fenced threshold/exception
   APIs with bounded registration and PG17 security/rollback proof.
3. Preserve 0017 fail-closed fences until the corresponding RPCs are
   controlled and separately registered.
4. Staging B-022 and signed GoTrue B-018 remain Claude-owned and require
   separate Owner GO. **No hosted migration or Cloudflare deployment authorized.**

Owner release status: **B-020 IN_PROGRESS; PR #107 remains Draft.**
