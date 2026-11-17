# CORE-10-CENTRAL — NP01 / B-020 / 0111 restartable handoff (2026-11-17)

## Authoritative checkpoint and ownership
- Repo: `mistybari99/CORE-10-CENTRAL`
- ONLY writable branch: `build/chatgpt-np01`. Owner directive: [GitHub Issue #110](https://github.com/mistybari99/CORE-10-CENTRAL/issues/110).
- Open **Draft** [PR #111](https://github.com/mistybari99/CORE-10-CENTRAL/pull/111) into `ccr-15ed11dd-n3hw5h`. No self-merge.
- Emergency recovery began at the verified `fdaa2d6d4678f26c2a9060c858fdf5a5fafe0922` (4/4 green). `0111` was NOT in the GitHub tree then; pre-existing unpushed work from another session was not assumed.
- First implementation push `aed68d2a626c66b00baba3dfffa53c4e36530d0b`; CI test-only fixes `4dbff08`, `2b055f7`, `07a51ac`; dedicated two-session race test `f8be977223fc26490849b86251b5fd638afa7f4e`.
- `07a51aca28a402d5b66d51ac0a6272f10c859310`: all four exact-head GitHub workflows **PASS**. On `f8be977`, NP01 PG17 including route concurrency **PASS**; other workflows must be verified afresh at the newest head. Do not reuse historical PASS to certify a later SHA.
- Read the live branch/PR/CI and Coordination Board B-020 row before any new write. Recheck whether 0111/0112 exists; use a non-force Git ref lease to avoid concurrent session overwrite.

## Implemented, additive migration 0111 (do not reapply in a new migration)
- Files: `internal/migrations/0111_np01_route_stages_control.up.sql` and `.down.sql`.
- Preserves 0110 as committed and all previous migration checksums.
- `configure_approval_route_v1(bigint,text[],text)`: existing RPC identity/signature, canonical Owner Auth before `core10.control_check_v1(business,'gov002.review',NULL)` before replay/DB write; advisory lock serializes with `control_set_v1` and typed submission; registry is promoted only with `tests/migrations/np01-control-route-stages-e2e.sql` evidence.
- Valid explicit routes: 0 stages = empty roles, nonposting auto receipt; 1 stage = `tenant_owner`; 2–5 stages = business_owner first, tenant_owner last, manager intermediate. No invented domain post.
- Owner's **explicit** effective `gov002.review` stage count must match the route; `CONTROL_STAGE_MISMATCH` blocks conflicting new requests. Existing catalog **default-only** 2/3/5 routes remain backward compatible; an explicit 0/1 setting is required to create those new route shapes. Historical requests with no 0111 pin remain legacy/null rather than fabricated values.
- `submit_typed_approval_v1` pins route cardinality, Control version and source **when inserting** the request. Existing same-key replay is preserved. Stage-0 records exactly one approved request and one canonical approve event (not a Stock/Money posting). A later Owner setting change never changes already pinned request requirements.
- `decide_approval` validates the stored stage pin and prevents spurious vote on a 0-stage completed request; preserves Auth, maker/checker, per-stage receipts and replay rules.
- Down migration reverts only changed function bodies/registry mapping and drops only 0111 columns/check. It deliberately **refuses** rollback if 0/1-stage route records exist; first reconcile such records under a separately authorized data/rollback plan. No silent data loss.
- Only `configure_approval_route_v1` receives new 0111 registry promotion. Previous 0110 three promotions and 0103/0106 bindings are untouched.

## Disposable PostgreSQL 17 evidence
- `tests/migrations/np01-control-route-stages-e2e.sql`: Owner-configured 0,1,2,3,4,5, stage pin/Control version, mismatch rejection, replay, disable-before-replay, maker-checker, foreign-tenant forged JWT metadata, audit verification, rollback fixture.
- `tests/migrations/np01-control-route-concurrency.sh`: separate disposable PG17 database with two real simultaneous SQL sessions per route/write, both 3-stage and 0-stage same-key submissions; one request each, one stage-0 approve receipt, version pin, canonical audit. Its DB is dropped on EXIT.
- Workflow `.github/workflows/np01-s1c-remainder-ci.yml` runs both 0111 cases plus earlier 0110 and GOV002 two-session race.
- All previous S0 up/down/up, S1-c, Control registry/evidence/browser 390+1440, and NP01 suites remain required. If a workflow fails, inspect failed step/job logs and patch in **small commits on the assigned branch only**. No regression gate can be skipped/softened.

## Remaining B-020 (explicitly NOT complete)
- Other pending NP01 Control bindings: `setup001.provision` creation/site limits, GOV003 export/read guard/limits, and six 0014/0015 threshold/exception RPCs still fenced in 0017. Preserve their unavailable API surface until binding, registration and separate evidence are completed.
- A certified stock/finance/source posting adapter, signed GoTrue 16-persona end-to-end matrix, hosted staging validation and full Owner acceptance are **not** claimed.
- Explicit site-scoped routed action requirements are a later adapter concern; the current typed approval RPC is business-scoped.
- B-020 must remain `IN_PROGRESS` on Board until all integration gates and owner authorization are satisfied.

## Next restart action
1. Verify live head and PR #111; confirm 0111 already exists and check all **four exact-head** workflow conclusions; do not duplicate 0111.
2. Update and read back B-020 Coordination Board row, including actual SHA, CI URLs and remaining gaps. Keep a Draft PR, no trunk merge.
3. Continue the next unclaimed NP01 Control binding (reserve `0112` only after checking current GitHub migration tree and Board).
4. Run disposable PG17 proof and safe down/up for each new migration; never use staging for these tests.

## Prohibited
No hosted migrations / Supabase staging edits, Cloudflare deployment, changes to PR #113 or unrelated builder branches, production/IMG-ERP-SG or original Islamiya artifacts, and no automatic integration to trunk.

## Post-recovery increment: 0112 site provisioning Control (2026-11-17 UTC)

- Verified 0112 **source-code checkpoint**: `277eeaa449c45f22df7334d4331bdc7be6a0bd9f`. GitHub 5/5 PASS at that exact source SHA: NP01 PG17 [44169975417](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44169975417), S0 up/down/up [44169975392](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44169975392), canonical Approval/Audit [44169975402](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44169975402), Owner Control registry/browser [44169975560](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44169975560), NP06 Finance [44169975388](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44169975388).
- Added `internal/migrations/0112_np01_site_provision_control.up.sql` and matching `.down.sql`; migration number **0112 is now taken**. Existing `0110` and `0111` are untouched; never edit their checksums. Existing `build01_site_v1(bigint,text,text,text)` retains its signature and original behavior except canonical Auth-before-Control denial and Owner `max_sites` enforcement. The exact same advisory lock as `control_set_v1` serializes site writes with Owner setting changes; business row lock serializes two site writers. Replays cannot bypass disabled Control. Once allowed, an identical replay returns the original receipt, even if a subsequent site cap is below existing count.
- Registry promotion: **only** `build01_site_v1` -> `enforced` with `tests/migrations/np01-control-site-provision-e2e.sql`; inverse returns it to `pending` and restores pre-0112 function source. No new permission grants to public/anon; registry stays inaccessible to API roles.
- Tests: `tests/migrations/np01-control-site-provision-e2e.sql` for toggle, owner site cap, idempotency/replay-conflict, disabled replay, manager and foreign-tenant authorization, audit proof and Control registry; `tests/migrations/np01-control-site-provision-concurrency.sh` for two **independent sessions** competing for exactly one available site slot. The handoff checkpoint also adds a further tenant-B positive-isolation assertion; verify the new exact branch HEAD and CI rather than transferring the earlier 5/5 claim to this documentation/test commit.
- First migration push `b14d45893252110b60b8c854a6f49a8fbc1d0ede` had NP01 fixture failure because `authenticated` cannot read the internal Control registry; corrected test verifier to `RESET ROLE` (privileged runner) at `277eeaa`. No permission checks or production security were weakened.
- Remaining B-020 **IN_PROGRESS**: `build01_setup_v1`, `setup_business_v1`, `setup_industry_draft_v2`, `gov003_audit_readiness_v1`/risk/export and six 0014/0015 fenced threshold/exception RPCs. The new-business setup path needs a careful canonical Control contract because `control_check_v1` requires an existing business; do **not** fake a tenant-level policy, bypass disabled features or provision irrevocably before authorization. Coordinate that boundary with Claude/trunk owner before binding those three RPCs.
- Latest trunk observed `ba1ef9fbec8b46b1f28bfee30d5bc6ffde3e4c3e`, diverged from Build 1; do not auto-merge/rebase, force-push or change 0150+ Master/0400+ Finance files.
- Only branch `build/chatgpt-np01`, Draft PR [#111](https://github.com/mistybari99/CORE-10-CENTRAL/pull/111), live Board B-020. For the **actual** last pushed SHA and current exact-head CI, re-read GitHub PR and Board rather than assuming this documentation commit equals the verified code SHA. No hosted Supabase migration, Cloudflare deployment, trunk/main change, production/IMG-ERP-SG change, GO-2 or GO-3.
