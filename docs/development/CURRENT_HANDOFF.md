# CORE-10-CENTRAL — Cross-Agent Current Handoff

**Checkpoint prepared:** 2026-11-10 (Asia/Dhaka)
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
- Candidate SQL not applied to production; no changes to Islamia items, sales, factory recipes, stock, customer data or live database at this checkpoint.
- Repo `main` had NO `supabase/migrations/` or full schema baseline. Do not guess migration history or assume GitHub push auto-deploys.
- This PR is now adding shared AI agent instructions, migration runbook and a resumable Git handoff. Those **documentation files do not themselves deploy the A004 fix**.

## Exact NEXT executable A004 increment for Claude
1. Re-fetch PR #8 current head, open diff, latest CI. Read `CLAUDE.md`, the protocol, this checkpoint, and the Decision Book A004/R118-R121. Check for concurrent writers.
2. **Verify direct and indirect callers** of `_cost_actual(uuid)` and `_costx_recompute()` in the existing Islamia JS and SQL graph: browser `.rpc(...)` calls, SECURITY DEFINER/INVOKER dependencies, triggers, scheduled jobs, any API/Edge Functions. Avoid exposing production financial data.
3. Make the candidate patch safer if verified callers require direct authenticated execution; prefer explicit authorization checks or audited wrapper rather than breaking a legitimate workflow. Prove with real disposable role tests and negative JWT HTTP/PostgREST fixtures when possible. Keep A004 unmerged.
4. Verify the original Islamia cost board, production/recipe preview, item pricing, stock valuation and staff/owner paths **in safe test environment** before any release. If no staging Auth is available, record the blocker truthfully; do not improvise credentials or use production records as demo data.
5. Advance Git commit+CI, update THIS checkpoint and the SAME Decision Book's A004/AUDIT EVIDENCE/CHANGE LOG with exact evidence. Do NOT write to live IMG-ERP-SG.

## Ending / passing the baton
When approaching a Claude context/usage limit, **commit and push safe work first** and replace this checkpoint with:
- Date, agent, action ID, active PR+branch, actual current git commit after fetch, changed files and exact commands/results/CI links;
- DB and deployed environment: READ ONLY / STAGING / PRODUCTION (with approval receipts if applicable);
- which Islamia modules were checked, which remain unchecked and any dangerous regression;
- test status & rollback blockers and next ONE implementable step;
- known uncommitted/unpushed files (these are NOT recoverable by the next agent without being shared).

If Claude stops without updating this file, ChatGPT re-reads GitHub commits, open PR, latest CI and Decision Book; reconstructs from **committed and verifiable** state only. Never assume that ChatGPT automatically sees Claude's private chat, or that Claude automatically sees ChatGPT's private chat.

## Source links
- Canonical protocol: `docs/development/CORE10_GITHUB_FIRST_AI_PROTOCOL.md`.
- Database rules: `docs/development/GITHUB_SUPABASE_MIGRATION_RUNBOOK.md`.
- Owner baseline: `C10-D041`, `C10-D042`, `R118`, `R119` and new GitHub-first handoff requirements to be recorded in the same workbook.
- IMPORTANT: This file captures the next task; it is NOT a declaration that A004, A018, production security or any industry ERP is complete.
