# CORE 10 — GOV-002 ↔ Codex Build 01 executable integration handoff

## Ownership and exact source checkpoints

- ChatGPT GOV-002 current parent: stacked Draft PR #88, HEAD `1a42c6fe305daff1be4de18937b6206b47d31205`. Separate Draft PR on top; never edit Build01 or `main`.
- Codex Build01 source pin: Draft PR #86, **exact observed commit** `0dccbd1808ba16e6ce39e1f7b211e8578a6d2837`. The CI deliberately checks out this immutable SHA, **not** the possibly moving Codex branch.
- `tests/c10_gov002_build01_access_compat_e2e.sql` is a PostgreSQL 17 test *against a single disposable database* that installs both unchanged candidate source trees. Integration testing does not mean the branches are merged, the SQL is authorized for SG, or real GoTrue and A034 approval-specific permission handling is certified.

## What the combined test explicitly proves (once CI passes)

1. Canonical `can_manage` accepts only a current active same-business owner; `can_business` accepts current same-business manager as maker. No client tenant/role claims are used as server authority.
2. Existing typed approval request can be published, submitted, read and reviewed against the same canonical business IDs without spinning up a second permission store or approval engine.
3. Maker cannot approve their own request. Site-only user with forged owner metadata and foreign tenant cannot read approval reports.
4. Build01's **membership expiry and revocation** immediately remove owner/maker GOV002 read/decision/request eligibility in the shared disposable schema.
5. The test transaction rolls back; zero new approvals, exceptions, stock, finance or execution receipts are preserved in the test database. No PR preview deployment or production Supabase writes.

## Not covered, must remain blocked

- Build01 A034's explicit deny catalog currently covers only **`stock.read` / `stock.post`**. It is **not** a generic `approval.decide`, `approval.delegate`, `approval.export` or domain-sensitive action permission resolver. Do **not** infer approval authority from stock permissions, business-picker visibility or a synthetic owner role check.
- Real GoTrue `auth.sessions` and authenticated PostgREST combined GOV002 integration across session expiry/logout/revocation are **not** covered by the synthetic-claims SQL test. Parent Build01's real local-auth tests are separate evidence; they do not prove this combined RPC chain.
- Business/site policy explicit deny for approval actions, delegation parity, N-stage routing, cancellation during concurrent decisions, stale source fingerprint, and per-domain executable posting/reversal need separate integrated signoff.
- Source payload, amount, currency or unit must be validated in authoritative canonical domain service. Never add a domain stock/finance/ledger engine inside GOV002.
- C10-D051 / R130: protect original Islamiya Misty Ghar ERP appearance, source, identifiers, production data and archived branch. No automatic merge, SG deployment or Preview One overwrite.

## Codex handoff contract (no request to change Build01 branch here)

- Expose a **server-side, same-business, signed-current-subject effective-action decision** for the specific GOV002 actions (submit, decide, delegate, withdraw, exception triage, read/export). Explicit deny > allow, expiry, immediate revoke, RLS, and authoritative actor identity must be proven at execution time.
- Preserve existing `c10_demo.can_manage`/`can_business` semantics for old app compatibility; GOV002 owner-role predicate is currently provisional until approval-specific effective-action policy is integrated.
- Once Codex publishes an integration-ready gated API, GOV002 can wrap its existing RPC entry points without copying A034 permission tables or creating a separate owner authority.
- Re-pin the read-only Build01 SHA when it advances, rerun the combined disposable suite, inspect any changed role/expiry semantics and record exact run evidence. This suite must never automatically merge code or write credentials to a hosted database.

## Run conditions

Only GitHub Actions with an ephemeral PostgreSQL17 container, an owned `core10_build01_sql_...` database, and two pinned read-only checkouts. No secrets or Supabase connections. `build01/tests/build01/run-load.sh` and `build02/internal/enterprise-sql/c10_a008_*` source files remain unmodified. The runner treats compile or role mismatches as FAIL, not compatibility success.

**Classification:** executable isolated compatibility test and contract handoff; NOT production-certified GOV002 (12 master details still `PLANNED_DETAIL_NOT_CERTIFIED`).