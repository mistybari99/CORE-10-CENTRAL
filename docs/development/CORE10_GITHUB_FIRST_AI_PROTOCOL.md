# CORE-10-CENTRAL — Canonical GitHub-First AI Development & Handoff Protocol

**Version:** 1.0 | **Date:** 2026-11-10 Asia/Dhaka | **Status:** governance candidate in a Draft PR. Not merged or deployed.

## 1. System of record and authority

1. **Product scope & priority:** the existing [CORE 10 Central Decision Book](https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit) and its `DECISION BOOK`, `NEXT ACTIONS`, `REQUIREMENTS LOCK`, `DECISION REVISIONS`, `CHANGE LOG`, `AUDIT EVIDENCE`. Latest explicit Owner instruction supersedes older conflicting wording. Never create an alternative master workbook.
2. **Desired implementation & reproducible database schema:** GitHub `mistybari99/CORE-10-CENTRAL` — verified commit/branch/PR. Once a complete baseline is established, versioned schema + migrations in this repo become the intended state.
3. **Actually running software:** deployed frontend and actual IMG-ERP-SG database. They describe *current runtime reality*, which may differ from GitHub until migrations/deploy are reconciled; read-only verification is required. A PR is not production.
4. **Transition/evidence:** `docs/development/CURRENT_HANDOFF.md` (session checkpoint, not task register), exact commit, PR and CI URLs; Decision Book records status and test outcomes. Do not treat this file as a replacement for the live sources.
5. **Environment:** project IMG-ERP-SG in Singapore (ref `kbuhnpqooycqbzrfejcs`) is current intended production target, NOT staging. No approved separate staging Supabase project was verified at protocol creation.

## 2. Design boundaries — preserve the existing Islamia ERP

- Islamia Misty Ghar's current working business modules are the legacy baseline. Inspect before editing: login/roles, Item Master, purchase, factory, recipes, costing, inventory/transfer, counter/POS, finance/partners, approvals, reports, backup/offline and mobile/desktop.
- Protect existing item IDs, historical location IDs **1,2,3,4,5,6,7,9** as observed on 2026-11-10, related 136 location FKs / 72 org-unit FKs observed then, transactions, ledger calculations, customer data, brand, permissions and visible workflows. Recheck these observations, not permanent assumptions.
- Security bugs and useful enhancements MAY be fixed, but each must pass regression tests; never opportunistically redesign Islamia during an access-control patch.
- Master Central, new businesses, factories/branches and independent tenants MUST be built as real new capabilities within the SAME repo and server-enforced tenant/business/site boundaries, not falsely inferred as complete from Islamia-specific UI or SQL.
- `org_scope_on` is an internal legacy compatibility flag, not a setting to switch on casually. Preserve until safe migration and negative testing demonstrate a replacement.
- Old `My-tools` is excluded. Do not create a second app, repository, parallel enterprise engine or new Decision Book.

## 3. Current execution order

**Begin at C10-A004**, existing [Draft PR #8](https://github.com/mistybari99/CORE-10-CENTRAL/pull/8), branch `security/c10-a004-islamia-cost-rpc-hardening`. PR #8 has an isolated SQL ACL candidate and regression; it is NOT installed in live Supabase. Check its latest SHA/CI/changes first. Audit real consumers and permission boundaries, implement the smallest safe next code/test increment, and keep the PR draft until reviewed.

After A004, move through dependencies and the `NEXT ACTIONS` queue (including A005 signed-in RLS/API negatives, A006–A015, A018–A023) based on current verified decision priorities. The existing [Draft PR #7](https://github.com/mistybari99/CORE-10-CENTRAL/pull/7) contains separate unfinished A018 prototypes; do not merge/copy/conflict them silently. A024 SaaS commercialization and A025 Simulation remain explicitly deferred unless the Owner changes their gates.

## 4. GitHub-first engineering loop — mandatory for every agent

1. **Discover:** verify remote `main` SHA, active branch SHA, uncommitted changes, draft/open PRs, current CI, Decision Book action/acceptance, deployment reference and (when relevant) live DB *read-only* schema. Check for other writers or automation before modifying the branch. If the branch changed, reconcile; never force-push another agent's work.
2. **Define acceptance:** one concrete action ID and testable result; list existing Islamia behavior that must remain unchanged. Check `REQUIREMENTS LOCK` for the specific behavior.
3. **Code in Git:** smallest coherent change on the current feature/security branch; stage database changes as versioned SQL/migrations **only after** establishing verified legacy baseline. Keep tests, fixtures and rollback plan in Git. Never store credentials, JWT signing keys, tokens, real customer/employee data, Supabase service-role keys, connection strings or raw PII.
4. **Run tests:** lint/syntax/unit, SQL in disposable PostgreSQL, business calculations, role/tenant/site negatives, duplicate/concurrent requests, expected errors, regressions. Ensure a failing test actually fails, then check latest commit CI. For real authentication, require signed JWT HTTP/PostgREST and staging logins; synthetic `request.jwt.claim.sub` in SQL is **not** equivalent.
5. **PR review:** link exact SHA, diff, test commands, CI jobs, changed data/schema surface, risk, rollback, outstanding unknowns. Do not label unbuilt features completed.
6. **Staging:** only with a separately verified safe test environment, migrations and backups; test the same commit with real demo identities for Owner, Business Owner, Manager, Staff at two sites, independent Tenant, Investor, revoked staff and anon. Check direct REST, RPC, RLS, reports/exports, offline and 300+ site cases where required. Demo records must be disposable, segregated and never mixed with live Islamia data.
7. **Release:** owner explicitly approves a reviewed release candidate, validated migration order, backup/restore and rollback; controlled integration to `main`, then audited production deployment. A merge alone is not proof that Supabase schema was changed. Compare applied migrations and live schema against intended Git SHA.
8. **Evidence & handoff:** update `CURRENT_HANDOFF.md` with exact remaining next action; update the *existing* Decision Book action/evidence/log only when verified. Never claim a task is complete based only on a draft, test fixture or passing green icon.

## 5. GitHub ↔ Supabase reconciliation

Read `docs/development/GITHUB_SUPABASE_MIGRATION_RUNBOOK.md` before touching database code.

**Current known gap:** this repo's `main` had no `supabase/config.toml` or `supabase/migrations/` at the 2026-11-10 check, although real IMG-ERP-SG contains extensive historical SQL/RLS/RPC. Consequently **GitHub does not yet reproduce the full live schema**. A direct GitHub code change cannot be assumed to reach Supabase.

First establish a sanitized, structurally complete, reproducible **schema-only** baseline with verified RLS/grants/triggers/functions/extension dependencies; test its fidelity in a disposable DB. Track drift and only then add ordered versioned migrations. Never apply a generated full baseline as new DDL onto the existing production schema without a designed, reviewed adoption step. Do not invent an automatic deploy pipeline or assume staging already exists.

Target: **GitHub feature branch → code & versioned migration → local/isolated tests → PR/CI → separate staging → real demo E2E → release approval → controlled production migration → post-deploy schema/migration verification**.

## 6. Strict prohibitions and risk gates

- No direct production DDL/DML or security-policy edits through Dashboard, SQL Editor, CLI, a Supabase connector or agent without a separately approved release. Routine inspection is SELECT-only and must avoid personal data.
- No automatic deployment, database reset, remote migration repair, destructive schema diff, altered auth grants, production tenant/role creation, `org_scope_on` toggling, `main` merge or forced branch update unless explicitly and separately authorized by the Owner after verification.
- No broad removal of anonymous grants: public website, legitimate attendance-device or login-precheck endpoints may intentionally require anon access. Review each function and its callers.
- A selective A004 REVOKE could break an undocumented direct app caller: verify actual callers and legitimate flows before staging.
- No blanket statement like "99% ready" without a module acceptance matrix. Distinguish: NOT BUILT; CODED; ISOLATED TEST PASS; INTEGRATED; STAGING VERIFIED; RELEASED.
- No parallel same-branch agent edits. If Claude holds the task, ChatGPT reads it but must not overwrite uncommitted work; if an automation changes the branch, fetch/rebase or pause and reconcile before any write.
- If tools or credentials are unavailable, implement the safe Git-side portion and explicitly mark the exact blocked integration test; do not invent users, URLs, deployments or CI successes.

## 7. Cross-agent handoff: Claude ⇄ ChatGPT

**At start (either agent):**
- Open this protocol and `CURRENT_HANDOFF.md` on the **currently checked-out branch**. Read current Decision Book A004 (then current approved action), the relevant requirements and revisions.
- Fetch GitHub remote, PR and CI; compare current HEAD to the last checkpoint. Check `git status` and do not wipe partial work. Verify actual DB read-only when the task requires it.
- State **the next smallest executable development step** and perform it, rather than writing another audit-only document.

**Before stopping, context limit or handoff:**
- Commit/push actual code+tests to the agreed feature branch (unless unsafe/incomplete; then record uncommitted state without claiming recovery is automatic).
- Verify latest CI; update `CURRENT_HANDOFF.md` in Git with action, checked SHA, PR, changed paths, commands/results, environment touched, missing tests, blockers, and **the exact next command/task**. A checkpoint commit itself changes HEAD, so the next agent must re-fetch newest HEAD.
- Update the same Decision Book's NEXT ACTIONS and evidence/log when a verified milestone warrants it. Do not duplicate the workbook.
- Paste an end-of-session handoff including PR URL, SHA, PASS/FAIL and outstanding risks.

**If Claude hits a limit abruptly:** ChatGPT must independently fetch GitHub commits/diff, PR, CI and current handoff and resume only from verified committed artifacts. Neither agent can magically recover unsaved/uncommitted state from the other's closed session. If there is an unpushed diff, the Owner must share it, or it must be recreated after verification.

## 8. Per-module definition of ready

A business ERP module is "Ready to Use" only after: UI + real backend + versioned database; robust permission/RLS/RPC; real authenticated flows; correct transactions, calculations, ledger and reports; errors, idempotency and rollback; owner/staff/demo acceptance; mobile/desktop/offline where relevant; no Islamia regression; and controlled staging/release evidence. A doc, mock, isolated SQL demo, or green frontend CI alone does NOT meet this bar.

**Language:** communicate operational summaries to the Owner in Bangla; use precise English identifiers, paths, SQL and links for developer artifacts.
