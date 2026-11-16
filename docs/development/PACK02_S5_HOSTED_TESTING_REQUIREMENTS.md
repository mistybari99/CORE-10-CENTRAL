# PACK-02 S5 — hosted authenticated testing: requirements and acceptance status

Preparation only. **Nothing here has been created.** No Supabase staging project, user, secret or migration exists or was changed. Creating any of it needs a separate, explicit Owner approval.

## A. What must exist before S5 can run

| # | Requirement | Owner of the action | State |
|---|---|---|---|
| 1 | Separate Supabase project for staging (never IMG-ERP-SG), region and plan chosen | Owner approval | NOT APPROVED |
| 2 | Schema applied from Git in the documented disposable load order (A018 → A020 → A021 → A034 → Build01 → PACK-02 workspace → A044 → PACK-02 controls, plus PACK-01 adapters). The SQL guards today accept only disposable database names, so a reviewed staging variant of the guards is required | PACK-01 + PACK-02, after Owner GO | NOT STARTED |
| 3 | PostgREST exposes schema `c10_demo` only; `anon` has no grant; browser-reachable RPCs limited to Build01's five + PACK-02's five read RPCs (an API gateway or edge rule equivalent to `tests/build01/gateway.cjs`) | PACK-01 | NOT STARTED |
| 4 | Build01 config accepts a reviewed `staging` mode (today: loopback `isolated-development` only) with the staging URL + publishable key; no service-role key in any browser artifact | PACK-01 | NOT STARTED |
| 5 | Stage-only identities per D046: two unrelated tenants; tenant owner, business owner, manager, staff (one site), investor, revoked, expired, unassigned, platform operator. Passwords kept outside Git, delivered to CI as secrets | Owner approval, then Orchestrator | NOT APPROVED |
| 6 | CI secrets: staging base URL, publishable key, test password. A manually dispatched workflow only (no automatic runs against hosted) | Owner + PACK-01 | NOT STARTED |
| 7 | Backup/restore drill on the staging project and a cleanup plan for stage users and data | Orchestrator | NOT STARTED |

## B. What S5 will run (already written, passing locally against actual local GoTrue)

- `tests/pack02/live-auth-browser.cjs`: signed owner and staff sessions; staff denied umbrella, owner workspace, controls and owner report; anonymous and tampered-signature denied; logout revokes; write RPC unreachable; Build01-hosted panel at 390px and 1440px; panel cleared on sign-out. It currently refuses any non-loopback URL; a staging URL switch is a one-line change to make after approval.
- Additional hosted-only checks to add then: second-tenant owner cannot see first tenant; expired and revoked staff; direct REST with another tenant's business ID; CSV/Storage negatives where PACK-01 exposes them.
- Evidence to capture: workflow run ID, both PR SHAs, screenshots at 390/1440 per role, saved to the Drive Build Folder; Orchestrator Sheet readback.

## C. PACK-02 acceptance status (not VERIFIED_COMPLETE)

| Acceptance item | Evidence today | Status |
|---|---|---|
| Quick/Advanced setup via the canonical engine, idempotent, readback, no duplicate/orphan | SQL `workspace`, `scale`, `concurrency`; real-GoTrue Build01 setup journey | PASS (disposable) |
| Universal Owner / Business Owner / Staff workspaces, strict isolation | SQL `workspace`, `app`, local GoTrue journey | PASS (disposable + local GoTrue) |
| Per-business brand/nav/theme, umbrella hidden from staff | client tests, `app`, local GoTrue journey | PASS (disposable + local GoTrue) |
| Canonical permissions reused, no second engine; DENY precedence | `agreement` (108 checks with PACK-01 adapter) | PASS only when combined with PR #104 |
| Business-scoped and owner-wide reports | SQL `workspace`, `portfolio` | PASS (counts only; no valuation) |
| D045 control placement | SQL `controls`, `app` | PASS (read projection; edits stay in A044) |
| Bangla-first responsive UI 390/1440, basic accessibility | browser suites | PASS (synthetic + local GoTrue); Owner visual acceptance PENDING |
| Signed hosted A/B negative E2E | — | BLOCKED (section A) |
| Both PRs combined on one branch with exact-head CI | only ephemeral local merge | PENDING (needs merge approval path) |
| Drive + Sheet readback by Orchestrator | Drive saved by Claude | Sheet NOT SYNCED |
| Owner preview pair P01 | — | PENDING (needs PACK-01 + PACK-02 complete) |
