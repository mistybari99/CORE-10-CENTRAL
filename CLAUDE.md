# CORE-10-CENTRAL — Claude Code Project Instructions

**READ THESE TWO FILES IN FULL BEFORE EDITING ANY CODE:**
1. `docs/development/CORE10_GITHUB_FIRST_AI_PROTOCOL.md` — the one canonical development/security/release operating protocol.
2. `docs/development/CURRENT_HANDOFF.md` — latest resumable work checkpoint. Re-verify every SHA/status rather than treating its snapshot as live.

For Supabase work, also read `docs/development/GITHUB_SUPABASE_MIGRATION_RUNBOOK.md`.

## Non-negotiable rules
- Only project/repo: `mistybari99/CORE-10-CENTRAL`. Preserve the existing Islamia Misty Ghar ERP; do not replace it with a generic ERP. Build Central/other industries as properly isolated capabilities IN this repo.
- Master Decision Book (same workbook, no duplicate): https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit . Reconcile `NEXT ACTIONS`, `REQUIREMENTS LOCK`, `DECISION REVISIONS`, `AUDIT EVIDENCE` first.
- Start with **C10-A004** and existing Draft PR #8, branch `security/c10-a004-islamia-cost-rpc-hardening`. Preserve PR #7 (separate unfinished enterprise foundation).
- GitHub-first: commit all intended code, SQL, RLS, RPC, migrations, tests, and deployment config to GitHub BEFORE staging/apply. Existing live DB must be examined **read-only** for parity because historical migrations are missing from git. There is no established git-to-Supabase automatic deployment yet.
- **Owner-approved progressive live releases:** Claude Code should deliver small, backward-compatible, low-risk frontend/UX/bug fixes to the existing live app after reviewed PR, relevant automated tests, actual deployment-path verification and post-deploy smoke tests. The Owner will check the app incrementally; do not block every routine UI release waiting for a separate permission request. See the release classes in the canonical protocol.
- **High-risk changes are different:** Do not apply live Supabase schema/RLS/RPC/permission, stock, costing/finance, org_scope_on, tenant, historical data, destructive migrations, or irreversible changes on mere CI PASS. Require tested migration/dependency plan, staging or equivalent real auth verification, backup/rollback and explicit Owner go/no-go for impactful changes. Never use `supabase db reset --remote` for a linked real project.
- One implementer at a time per branch. Fetch the newest remote SHA, inspect uncommitted changes and open PR/CI before edits. Never overwrite another agent's changes or imply that tests passed without evidence.
- Maintain the handoff file at the end of each work session; the next agent (ChatGPT or Claude) must resume from exact current code and evidence, not from conversational memory. If you hit a limit abruptly, git commits/PRs/CI are the recovery point.
- A passing isolated SQL fixture or frontend test does **not** prove actual Islamia workflows, signed-JWT tenant isolation, or production readiness. Record work honestly as BUILT / TESTED IN ISOLATION / INTEGRATED / STAGING VERIFIED / RELEASED.
- A024 SaaS and A025 Enterprise Simulation remain deferred by the existing Owner decisions.

**Immediate task:** Follow `CURRENT_HANDOFF.md` and implement the next *verified, safe A004 security increment*, NOT another Decision Book-only audit. The current A004 SQL is a candidate in Draft PR #8; it has NOT been applied to live IMG-ERP-SG. For any truly release-ready low-risk frontend increment, publish it through the verified live GitHub Pages path and let the Owner test; do not deploy the still-untested A004 database ACL candidate.

Do not run `/init` to regenerate/overwrite this file; improve the canonical protocol through a reviewed PR when required.
