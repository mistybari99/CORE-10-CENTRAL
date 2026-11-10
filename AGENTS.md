# CORE-10-CENTRAL — ChatGPT / Codex / Other Coding Agents

**Shared canonical rules:** Read `docs/development/CORE10_GITHUB_FIRST_AI_PROTOCOL.md` first, then `docs/development/CURRENT_HANDOFF.md`. For database changes read `docs/development/GITHUB_SUPABASE_MIGRATION_RUNBOOK.md`.

This file deliberately points to the **same** authority used by `CLAUDE.md`; it is not a second decision register.

- Sole repo: `mistybari99/CORE-10-CENTRAL`.
- Sole Owner Decision Book: https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit .
- Work on the active verified action/branch/PR, currently A004 / Draft PR #8, without competing concurrent writers.
- Preserve the live Islamia ERP, its existing data, item/stock/location IDs, brand and working workflows. Central and future businesses require separate tenant/business-safe code in the same repo.
- GitHub-first migrations and CI; real Supabase **read-only inspection** until staging/backup, signed-in tests and explicit deployment authorization.
- Never claim that isolated CI PASS means live Auth/RLS verified or a module is Ready to Use.
- On stopping, update the GitHub handoff and the verified action/evidence in the existing Decision Book. To resume after Claude, re-read git/PR/CI, do not rely on pasted claims.
