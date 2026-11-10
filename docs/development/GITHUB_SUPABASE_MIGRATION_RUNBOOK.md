# CORE 10 CENTRAL — GitHub ↔ Supabase Database Migration & Drift Runbook

**Status 2026-11-10:** PROCESS DESIGN ONLY. This repository's `main` does not yet contain a complete reproducible `supabase/` migration history. No separate staging Supabase project or automatic GitHub→Supabase deployment has been verified. Do not claim this document establishes them.

## Why GitHub review alone was insufficient
The deployed Islamia ERP database (IMG-ERP-SG, project `kbuhnpqooycqbzrfejcs`) has historical tables, RLS, SECURITY DEFINER RPCs, privileges, triggers and functions that are not reproducibly versioned in this GitHub repository. The repo is the intended *desired code* source; current production schema is the observed *runtime* source. Changes to either one alone can cause schema drift.

## Phase 0 — Observe without changing the live project
- Verify exact main SHA, current action/PR and the target Supabase project; check whether any existing migration history or custom SQL deploy pipeline has appeared since this snapshot.
- Use SELECT-only catalog queries and security advisors to capture table/column/index/FK/trigger/function/owner/GRANT/RLS/policy/extension inventories. Avoid reading customer records, auth credentials, secrets or individual staff/customer PII. Do NOT commit raw `pg_dump` output until vetted and sanitized for secrets and identifying values.
- Compare against existing SQL files, current runtime and the actual deployment configuration. Report drift rather than quietly fixing it in Production.

## Phase 1 — Safely establish a version-controlled baseline
- First check current Supabase CLI official docs and the installed CLI `supabase --help`/`supabase db --help`/`supabase migration --help`; command syntax and supported schema tools change. Keep credentials out of git.
- Create `supabase/config.toml` and a **verified schema-only baseline** in a Git feature branch using a reviewed CLI workflow. Never invent applied migration timestamps or copy customer data.
- Verify a clean, disposable PostgreSQL/Supabase environment can reconstruct tables, foreign keys, functions, views, RLS policies, grants and needed extensions without production data. Investigate fidelity gaps; historic objects are numerous.
- Critically: the live target already contains this schema. A baseline migration must **not simply be replayed over live tables**. Agree on an explicit non-destructive migration-history adoption plan, drift checks, rehearsed backup/restore and owner authorization before recording any baseline as applied in Production.
- If unable to reproduce enough of legacy SQL safely, mark BASELINE NOT READY and continue isolated A004 code/testing. Do not advance to a production migration.

## Phase 2 — Every new DB change follows GitHub first
1. Modify reviewed declarative schema / SQL and generate a **versioned migration** in Git; keep access policies, dependent function changes, indexes, defaults, triggers and rollback notes in the same PR.
2. Rebuild disposable DB from the baseline plus ordered migrations; run fixtures, negative role tests, and Islamia regression checks.
3. On a separately confirmed staging Supabase target, apply exactly the Git-reviewed migration and test actual Auth/JWT, POST/REST/RPC/RLS, business/site scoping, data calculations and recovery. Never use production credentials or a live customer snapshot.
4. For impactful live DB/security/stock/financial changes, obtain specific Owner go/no-go for the reviewed commit, target and rollback path. Routine frontend-only releases are separately permitted by the Owner's standing progressive-release instruction and do not require a Supabase DB migration.
5. Apply controlled production migrations from that same git SHA using a configured, audited deployment mechanism; verify migration history, desired objects, RLS/grants, drift and real operation after deployment.

## What not to assume
- `git push` **does not inherently change Supabase**. The repository advertises a GitHub Pages website URL, but its actual publish trigger/source still needs verification; a frontend deployment is NOT a Supabase DB schema migration. A reviewed CI/CD integration or controlled DB deployment step must exist and be configured; no Git→Supabase auto migration has been certified.
- `supabase db reset --remote`, destructive recreations, arbitrary `supabase migration repair`, untracked direct Dashboard SQL and automatic main→production **database migration** must not run on IMG-ERP-SG. This does not prohibit safe green-CI frontend website publishing.
- Supabase paid preview branching is not mandatory for GitHub-first. A separate staging project or disposable local database may be used subject to actual availability and owner constraints; do not silently incur costs.
- Running a SQL fixture in GitHub Actions proves only that the fixture worked. It does not certify the entire live SG schema or existing Islamia UI.
- When an emergency fix is truly needed, explicitly arrange and log the exception, pre-change backup, exact versioned patch, post-change drift reconciliation and owner authorization. Do not normalize untracked hotfixes.

## Migration release receipt (fill after a real, authorized deployment)
- Action ID / source decision:
- PR / exact approved commit:
- Migration file path(s), checksums:
- Source environment / destination environment (verified project IDs):
- Baseline version / schema drift check before:
- Staging run, actual login identities, REST/RPC/RLS and Islamia regressions:
- Backup location **reference only** (never key or raw data in Git):
- Owner approval reference:
- Production apply time and job/run:
- Post-deploy migration history & drift parity:
- Rollback tested / incident:
- Decision Book evidence ID:
