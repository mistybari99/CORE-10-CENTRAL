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
