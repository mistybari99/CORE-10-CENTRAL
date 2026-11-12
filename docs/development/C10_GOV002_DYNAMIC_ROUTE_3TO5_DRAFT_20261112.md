# GOV-002 — Configurable 3–5 Reviewer Route (Draft, isolated)

## Boundary and intent

Extends the **existing** `c10_demo` policy, route, approval request, immutable approval event and stage-receipt tables. Original two-stage approval API remains available. No standalone authorization table, alternative maker-checker engine, client-granted roles or real stock/finance writes are added. D051/R130 original Islamia ERP and Codex Build01/A034/GOV001 are untouched.

## Implementation

- **3–5 ordered checks**, first by current business owner and last by current tenant owner, with intermediate business-owner, manager or tenant-owner reviewers. Roles may repeat but each stage must be signed by a *different actual user*. Maker can never check their own request.
- **Server-owned immutable route** scoped to a single policy version and business. Creation is owner-authorized, idempotent and serialized on the policy row; cannot be installed after that policy was used. Invalid route length/role/keys fail closed.
- **One canonical `decide_approval` RPC**; intermediate `approve` appends a unique stage receipt, final `approve` commits the state. Reject/defer close the request, while withdraw is unchanged. Existing bounded stage-1 delegation still works; dynamic N-stage delegation was deliberately **not added**.
- **Current membership** is checked at decision time, including optional Build01 `valid_until` if present. Tenant owner checks canonical `can_tenant`; no second identity store.
- The original security-invoker status report now says `awaiting_stage_3`, `_4`, `_5` and reports cardinality. UI presentation translates them to Bangla without adding authority. Scopes and existing RLS are not broadened.
- Existing PG17 suites and new E2E cover stage one/final, maker denial, role mismatch, same actor repeated, immutable route keys, five receipts, report progress and rollback.

## Noncertified limits / handoff

This is **a static configurable ordered route**, NOT full risk-adaptive branching, parallel stages, FX/multicurrency rules, bounded N-stage delegation or legal finance approval. Only BDT/KG/PCS/LB threshold rules from earlier layers exist; policy-defined amount-driven route selection is pending. Without canonical cross-domain commands the approval cannot authorize real posting. Signed GoTrue, A034 approval-specific explicit deny, temporary grant expiry, SG staging, rollback plan, full owner UI integration and owner release are still required. Test JWT users are synthetic; no real user invites were sent.

A manager designated as an intermediate checker can currently call the canonical RPC, but the separate requester/owner-only status view does not automatically expose the manager's pending stage. Dedicated **safe reviewer-inbox visibility** therefore remains an integration prerequisite; do not relax tenant scope via unrestricted manager visibility.

12ui CLI hosted generation was attempted but unavailable in this execution environment. The existing protected Islamia theme was not touched; this PR changes only the new approval UI's stage wording and counts.