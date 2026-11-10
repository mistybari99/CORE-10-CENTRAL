# CORE-10-CENTRAL — Cross-Agent Current Handoff

**Checkpoint prepared:** 2026-11-10 (Asia/Dhaka); release-policy revision pending in this same PR (Owner has authorized incremental safe live UI publishing).
**Checkpoint source:** ChatGPT; intended next implementer: Claude; ChatGPT resumes from Git after Claude's checkpoint or abrupt cutoff.
**This is a working snapshot, NOT a competing Decision Book or a claim that the remote cannot change.**

## Always re-fetch before edits
- Repository: https://github.com/mistybari99/CORE-10-CENTRAL
- Verified `main` BEFORE this handoff work: `da4818a29c291c324531295666c4196091c722ba`. Fetch current main again.
- Active work: `C10-A004` — DB security and Islamia-safe hardening. Master register: https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit .
- **Current work PR:** https://github.com/mistybari99/CORE-10-CENTRAL/pull/8 — branch `security/c10-a004-islamia-cost-rpc-hardening`, DRAFT, UNMERGED.
- A004 security-code baseline SHA BEFORE these documentation commits: `08a6b1a5cf83da6de186f9e206aaf0ca2c2fe483`. **The actual PR head will advance with these governance commits: fetch it again**.
- A004 isolated PostgreSQL CI: [PR run 42729359046](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/42729359046) SUCCESS; [push run 42729291514](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/42729291514) SUCCESS. This proves a synthetic ACL fixture only, not live API security.
- Separate enterprise Foundation work: [Draft PR #7](https://github.com/mistybari99/CORE-10-CENTRAL/pull/7) — A018 incomplete, unmerged. Do not merge/cross-copy while working A004.
- A005 live negative auth tests pending; A024 and A025 deferred.

## What was actually built
- In PR #8: `security/c10_a004_cost_rpc_acl_candidate.sql` and tests/CI for restricted direct EXECUTE on two **existing live** SECURITY DEFINER helper signatures:
  - `public._cost_actual(uuid)` — costs disclosure risk.
  - `public._costx_recompute()` — cost table write risk.
- Live SG catalog read-only inspection confirmed both currently granted direct PUBLIC/anon/authenticated execute and neither body self-checks caller permission. No claim of live external exploitation.
- Candidate SQL not applied to production; no changes to Islamia items, sales, factory recipes, stock, customer data or live database at this checkpoint. **The Owner now wants tested low-risk app/UI increments progressively published live**, not held indefinitely until all ERP modules are built. Higher-risk DB/security/stock/finance changes still need specific go/no-go after full release safeguards.
- Repo `main` had NO `supabase/migrations/` or full schema baseline. Do not guess migration history or assume GitHub push auto-deploys.
- This PR is now adding shared AI agent instructions, migration runbook and a resumable Git handoff. Those **documentation files do not themselves deploy the A004 fix**.

## Exact NEXT executable A004 increment for Claude
1. Re-fetch PR #8 current head, open diff, latest CI. Read `CLAUDE.md`, the protocol, this checkpoint, and the Decision Book A004/R118-R121. Check for concurrent writers.
2. **Verify direct and indirect callers** of `_cost_actual(uuid)` and `_costx_recompute()` in the existing Islamia JS and SQL graph: browser `.rpc(...)` calls, SECURITY DEFINER/INVOKER dependencies, triggers, scheduled jobs, any API/Edge Functions. Avoid exposing production financial data.
3. Make the candidate patch safer if verified callers require direct authenticated execution; prefer explicit authorization checks or audited wrapper rather than breaking a legitimate workflow. Prove with real disposable role tests and negative JWT HTTP/PostgREST fixtures when possible. Keep A004 unmerged.
4. Verify the original Islamia cost board, production/recipe preview, item pricing, stock valuation and staff/owner paths **in safe test environment** before releasing this A004 database permission change. If no staging Auth is available, record the blocker truthfully; do not improvise credentials or use production records as demo data. For unrelated safe UI-only fixes with sufficient tests, verify the real GitHub Pages publishing route and perform **small live releases plus smoke tests** so the Owner can inspect incrementally.
5. Advance Git commit+CI, update THIS checkpoint and the SAME Decision Book's A004/AUDIT EVIDENCE/CHANGE LOG with exact evidence. The A004 privileged costing ACL remains a **candidate** until real compatibility/auth test and specific approval; do not execute it prematurely on IMG-ERP-SG. For actually released UI increments record the deployed SHA, verified live URL, live smoke result, rollback reference and Owner feedback.

## Session checkpoint — A004 caller trace (Claude, 2026-11-10)
**Environment touched:** IMG-ERP-SG via SELECT-only catalog queries (`pg_proc`, `pg_views`, `pg_policies`, `pg_trigger`, `cron.job`); NO DDL/DML. Frontend NOT released this session (no Class L change was ready; see below).
**Findings (read-only live trace):**
- Repo JS/SQL: zero references to `_cost_actual` / `_costx_recompute` outside tests and this PR (grep over whole tree).
- Live DB direct callers: only 5 functions, ALL `SECURITY DEFINER`, owner `postgres`, `search_path=public`: `_costx_rules()` (trigger fn -> recompute), `_costx_snap()` (sale trigger fn -> actual), `cost_extra_group_set`, `cost_extra_item_set` (both -> recompute), `cost_gap_items` (-> actual). The three public wrappers self-guard with `_costx_ok()`. No view, RLS policy or `pg_cron` job references either helper.
- Consequence: revoking `authenticated`/`anon`/PUBLIC EXECUTE on the two helpers should not break these chains because definer-owner keeps EXECUTE. An INVOKER caller WOULD break (proved by negative control below) — none exists in the live catalog today; re-check right before any apply.
**Tests added (isolated, synthetic):** trigger-path fixture in `tests/c10_a004_cost_rpc_fixture.sql` and assertion in `tests/c10_a004_cost_rpc_after.sql`. Ran locally on PostgreSQL 16 (CI uses 17): before -> candidate -> after all PASS; negative control (`_a004_snap_trg` flipped to INVOKER) fails with `permission denied for function _cost_actual`, so the test can fail. Cloud CI on the pushed SHA: see PR #8 checks.
**Status:** A004 cost-RPC ACL = TESTED IN ISOLATION + CALLER-TRACED (read-only). NOT staging verified, NOT released. Class H: still needs real signed-JWT tests on a staging project, backup/rollback and a specific Owner go/no-go.
**Pages route:** GitHub API for Pages settings is blocked from this sandbox (403 via proxy), so the real publishing source (branch/folder vs Actions) is still UNVERIFIED. No workflow in `.github/workflows` has a Pages deploy step by name. Owner can confirm in repo Settings -> Pages (Source). Until verified, no "live release" is claimed.
**Next ONE action:** (1) Owner confirms Settings -> Pages source (or grants a token path) so Class L releases can be verified; (2) create staging Supabase project (or branch) so signed-JWT negative tests for owner/staff/anon can run against the real function set; (3) then Owner go/no-go on applying `security/c10_a004_cost_rpc_acl_candidate.sql`.

## APPLIED TO PRODUCTION — A004 cost-RPC ACL (Claude, 2026-11-10)
- **Owner go/no-go:** explicit "yes, apply" for exactly this change (ACL-only on `public._cost_actual(uuid)`, `public._costx_recompute()`), after being shown scope, caller trace and rollback. Owner declined a separate staging project.
- **Applied via:** Supabase `execute_sql` on IMG-ERP-SG, SQL identical to `security/c10_a004_cost_rpc_acl_candidate.sql` at PR #8 (no migration-history entry was created; schema baseline in Git is still missing — track as drift).
- **Pre-state:** ACL `{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}` for both.
- **Post-state (verified by SELECT):** ACL `{postgres=X/postgres,service_role=X/postgres}`; anon/authenticated EXECUTE = false; service_role = true; the 5 SECURITY DEFINER callers keep owner postgres EXECUTE; owner read of `_cost_actual` works.
- **ROLLBACK:** run `security/c10_a004_cost_rpc_acl_ROLLBACK.sql` (restores exact pre-ACL).
- **NOT verified:** signed-in Cost Board / item pricing / factory production / sale-snapshot flows in the real app. **Owner to check:** Cost Board (cost-gap list), Item cost % settings (group + item), create one test sale with cost-extra on, factory production cost. Any "permission denied for function _cost_actual/_costx_recompute" → run rollback and report.

### Live post-apply negative test (Claude, 2026-11-10, read-only, no writes)
Ran on IMG-ERP-SG via SQL role switch (`SET LOCAL ROLE anon/authenticated`, not signed JWT): direct `_cost_actual` and `_costx_recompute` -> `insufficient_privilege` for both roles (PASS); `cost_gap_items()` as authenticated without owner context -> `not allowed` from its own `_costx_ok()` guard, proving the definer wrapper still reaches the helper chain (PASS). Still NOT a signed-in app test.

### A004/A005 next-scope inventory (Claude, 2026-11-10, SELECT-only, NO change made)
IMG-ERP-SG: 20 public SECURITY DEFINER non-trigger functions are anon-executable; 6 have no guard by a keyword heuristic (heuristic, NOT proof): `_costx_pct`, `login_failed`, `login_precheck`, `staff_directory`, `web_catalog_v2`, `web_site_config`.
- Likely intentional public: `login_failed`, `login_precheck`, `web_catalog_v2`, `web_site_config` (website/login pre-check) — still verify output has no cost/PII.
- **Review first:** `staff_directory` (possible staff PII exposure to anon) and `_costx_pct` (internal costing helper, same family as the A004 pair; check whether it leaks cost %).
- Next increment: read bodies + callers (JS grep + pg_proc), run role-switch negative tests, then propose a narrow ACL/guard patch in Git with rollback and ask Owner for a specific go/no-go. Do not bulk-revoke.

### A004b findings (Claude, 2026-11-10, SELECT-only)
- `staff_directory()`: SAFE — guarded by `is_active()`, anon receives `[]`. No change needed.
- `_costx_pct(uuid)`: unguarded, anon/authenticated executable; all 5 callers are SECURITY DEFINER; no views/policies. Candidate `security/c10_a004b_costx_pct_acl_candidate.sql` + `..._ROLLBACK.sql` committed, **NOT applied, NOT yet isolation-tested** (add to fixture + CI paths first), then ask Owner for a specific go/no-go.

## APPLIED TO PRODUCTION — A004b `_costx_pct` ACL (Claude, 2026-11-10)
- Owner go/no-go: explicit "yes, apply" for exactly `security/c10_a004b_costx_pct_acl_candidate.sql` (CI PG17 PASS on a31674f). Applied via Supabase `execute_sql` (no migration-history row; drift to reconcile).
- Pre-ACL `{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}` -> post `{postgres=X/postgres,service_role=X/postgres}` (verified).
- Live role-switch test PASS: anon/authenticated direct call -> insufficient_privilege; `cost_gap_items()` as authenticated -> own `not allowed` guard; owner-run helper works. Not a signed-in app test.
- ROLLBACK: `security/c10_a004b_costx_pct_acl_ROLLBACK.sql`. Do NOT re-apply.
- Owner to recheck Cost Board + item cost % screens (same list as A004). Next: A005 (needs test owner/staff accounts), Pages source for Class L releases.

## A005 test accounts — verified live Auth inventory (2026-11-10, Asia/Dhaka)

**Read-only source:** Supabase IMG-ERP-SG `kbuhnpqooycqbzrfejcs`, from `auth.users`, `public.profiles`, `public.user_roles`, `public.user_locations`, `public.locations.org_unit_id`, `public.org_units` and `public.user_org_scopes`. No accounts/passwords/tokens/service keys were created, fetched, reset, or saved by ChatGPT during this verification. Email labels do not prove who originally created the accounts.

| Verified test-labelled login email | Actual role/identity state | Verified location/business scope |
| --- | --- | --- |
| `test01@staff.islamia-bos.app` | Auth not banned; profile status `active`. 11 `user_roles`: `carrier`, `cash_controller`, `factory_incharge`, `hr`, `management`, `party_coordinator`, `purchasing`, `recipe_approver`, `salesperson`, `showroom_manager`, `storekeeper`. **NOT a single-role manager/counter fixture.** | 8 assigned legacy `user_locations` IDs **1,2,3,4,5,6,7,9**; all 8 `locations.org_unit_id=3` → existing active `SWEETS` business, including Islamia showroom/factory, Misty Bari, Al-Cakiz, godown. No `user_org_scopes` row. **This account is tied to existing Islamia business locations, not an isolated demo business.** |
| `qa02@staff.islamia-bos.app` | Auth `banned_until > now()`; profile `status=active`; **0** `user_roles`. Not verified as a specifically business-scoped **revoked staff** identity. | 0 `user_locations`; 0 `user_org_scopes`. **No proven business affiliation.** |

- **Totals:** 4 live Auth users, of which **2** have test-labelled emails above; the other **2** have `owner` roles but are not verified as demo/test accounts. **Do not publish their real emails or treat them as test owner accounts.** Only **one** `org_units.kind='business'` record exists (`SWEETS`); `CL-P` is a **legal_entity**, not a second provisioned business. **No isolated Paint/other-business staff account**, distinct counter-only test identity, distinct manager-only identity, or verified business-scoped revoked identity was found.
- **A005 test matrix NOT READY:** 12/12 synthetic signed-JWT/PostgREST fixtures from older isolated CI cannot substitute for separate real Supabase Auth logins with intended business/site scopes. Establish **separate, least-privilege, disposable test users in safe staging** before cross-business negative tests. Do not alter production accounts or reuse real owner logins without Owner-approved design and safety review.
- **Credentials and secure transfer:** No verified password manager/vault, plaintext password storage or recoverable user password has been identified. Supabase Auth maintains credential verification (not a plaintext password retrievable from the dashboard); if a test password is unknown, the Owner must securely set/reset or invite **dedicated staging test accounts**, then store secrets in an Owner-controlled password manager or protected local secret store. For Claude Code, use an Owner-controlled local authenticated browser session or secure local secret injection into tests with logging/traces disabled for secrets. **Never** paste passwords, tokens, service_role keys, session cookies, connection strings, or secret-bearing `.env` contents into chats, PRs, repo files, tests, screenshots or CI logs.
- **GitHub Pages Source NOT VERIFIED:** repository advertises GitHub Pages and `https://mistybari99.github.io/CORE-10-CENTRAL/`, but the GitHub connector rejects the Pages configuration API and browser Settings access is not available in this session. **Unknown whether Source is `Deploy from a branch` (and which branch/folder) or `GitHub Actions`.** Owner: open https://github.com/mistybari99/CORE-10-CENTRAL/settings/pages → **Build and deployment → Source**; provide the selected option and Branch/Folder if applicable. Do not infer Source from `main`, URL, or green CI.
- **Implementation state:** This was SELECT-only live catalog/user-role verification and a GitHub handoff documentation change; **no test logins were performed and no live Supabase data/auth changes were made**. Re-read this inventory against current DB before any A005 run. GitHub commit SHA and PR CI must be fetched after the documentation commit.

## A005 step 1 — live rollback-only exposure scan (Claude, 2026-11-10)
**Method (Owner authorized creating test users, to be removed):** `profiles_no_delete`/`uos123_no_delete` triggers make permanent test users NON-removable and pollute audit logs, so instead `tests/c10_a005_live_rollback_exposure_scan.sql` creates login-less synthetic users INSIDE one transaction and always ROLLS BACK. Verified residue after run: 0 `auth.users`, 0 `profiles`. SQL role+claims switch (PostgREST mechanism), NOT a signed HTTP JWT.
**Result (SELECT visibility over all public tables/views):**
- `anon`: sees rows in NO table. PASS.
- `pending` new user (handle_new_user makes status `pending`, not owner): sees only `profiles`. PASS (expected own row; re-verify it is own-row only).
- `active` user with ZERO roles: sees shared catalog/config only — `items` (no cost/margin/supplier columns exist), `locations`, `settings` (keys seen: business_name, lock/lockout params), `rules`, `roles`, `forms`, `profiles` (all active staff directory) and similar lookup tables. Appears BY DESIGN (`is_active()` read policies), not a cost/finance leak. Low note: lockout params (`max_fails`, `lock_minutes`) readable by any active staff.
**Not yet done (next):** (a) write-denial matrix for the same personas (INSERT/UPDATE/DELETE on stock/sales/finance tables), (b) per-RPC call matrix for pending/no-role/limited-role users, (c) single business exists (`SWEETS`) so cross-business isolation cannot be tested until A018/A019 provision a second business in an isolated fixture. Write tests must also be rollback-only.

## Ending / passing the baton
When approaching a Claude context/usage limit, **commit and push safe work first** and replace this checkpoint with:
- Date, agent, action ID, active PR+branch, actual current git commit after fetch, changed files and exact commands/results/CI links;
- environment and deployment: READ ONLY / STAGING / PRODUCTION; distinguish frontend live site SHA from actual applied Supabase DB migration (include approval receipts where needed);
- which Islamia modules were checked, which remain unchecked and any dangerous regression;
- test status & rollback blockers and next ONE implementable step;
- known uncommitted/unpushed files (these are NOT recoverable by the next agent without being shared).

If Claude stops without updating this file, ChatGPT re-reads GitHub commits, open PR, latest CI and Decision Book; reconstructs from **committed and verifiable** state only. Never assume that ChatGPT automatically sees Claude's private chat, or that Claude automatically sees ChatGPT's private chat.

## Source links
- Canonical protocol: `docs/development/CORE10_GITHUB_FIRST_AI_PROTOCOL.md`.
- Database rules: `docs/development/GITHUB_SUPABASE_MIGRATION_RUNBOOK.md`.
- Owner baseline: `C10-D041`, `C10-D042`, `R118`, `R119` and new GitHub-first handoff requirements to be recorded in the same workbook.
- IMPORTANT: This file captures the next task; it is NOT a declaration that A004, A018, production security or any industry ERP is complete.
