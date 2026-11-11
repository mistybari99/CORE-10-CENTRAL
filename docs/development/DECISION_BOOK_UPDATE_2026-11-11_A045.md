# Master Decision Book — implementation-progress update (C10-A045), 2026-11-11
Source of truth: Google Sheet `1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs`. The Drive connector overwrites whole files, so the sheet was NOT edited by Claude; apply these rows by hand (or via a safe cell-level editor). These are ACTION/EVIDENCE records, **not new Owner decisions**; D033, D045, R014–R026, R123, R124 remain controlling.

| Tab | Row to add/update | Content |
|---|---|---|
| NEXT ACTIONS | `C10-A045` implementation progress | Micro-Engine registry/RPC, certified `threshold_rule_v1`, Workshop UI, multi-business publish/pause/revoke/rollback BUILT in Draft PR #42 (disposable c10_demo). Status stays NOT RELEASED; real GoTrue/RLS staging + SG migration NOT DONE. |
| CHANGE LOG | next free `C0xx` | "A045 code checkpoint: PR #42, branch claude/c10-a045-micro-engine-workshop-v1, see CURRENT_HANDOFF.md for exact SHA + CI run." |
| AUDIT EVIDENCE | next free `E0xx` | CI run URLs and SHA from CURRENT_HANDOFF.md (PostgreSQL 17 SQL E2E, Node unit, Chromium 390/1440). Synthetic fixtures labelled; no real Supabase auth evidence. |
| REQUIREMENTS LOCK | R124 status note | Items 3–4 (Micro-Engine Workshop, business distribution) have a first executable vertical slice for ONE handler; other engine types remain DRAFT / NOT IMPLEMENTED. |
