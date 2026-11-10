# Decision Book update to paste (prepared by Claude, 2026-11-10)
Claude could NOT verify write access to the private Google Sheet (Drive connector replaces whole files; a spreadsheet overwrite could corrupt it), so these rows are staged for the Owner/ChatGPT to paste. Evidence: PR #8, docs/development/CURRENT_HANDOFF.md.

## NEXT ACTIONS — replace Status for C10-A004
"In progress — APPLIED to live SG after Owner go/no-go: (1) `_cost_actual(uuid)` + `_costx_recompute()` ACL, (2) `_costx_pct(uuid)` ACL, (3) anon write-class table grants (incl. TRUNCATE) revoked on 14 RLS tables. Isolated PG17 CI PASS; live rollback-only role tests PASS; owner non-regression PASS. Signed-in app regression NOT done; no migration-history rows (drift)."
## NEXT ACTIONS — replace Status for C10-A005
"In progress — live rollback-only matrix PASS: anon sees no rows; pending/no-role users cannot write, self-grant roles/locations or self-activate; owner-only write policies on settings/roles/forms/locations/role_form_perms; 11 RPCs denied for no-role users. NOT done: signed-JWT HTTP tests, cross-business isolation (only one business exists), real-id void_purchase/production_post checks (no recipes/purchase bills in prod)."
## CHANGE LOG (append)
| C0xx | 2026-11-10 | A004 cost-RPC ACL + A004b + A005 anon write-grant revoke applied to IMG-ERP-SG | Close unguarded internal helpers and RLS-bypassing TRUNCATE grants | CI PG17 PASS + live SELECT-only/rollback-only verification | Owner (go/no-go + delegated decision) / Claude | https://github.com/mistybari99/CORE-10-CENTRAL/pull/8 |
## AUDIT EVIDENCE (append)
- Anon exposure scan: 0 tables visible to anon. Escalation probe: no self-grant of owner/management/salesperson. Advisors: no ERROR; WARN: leaked-password protection off, mutable search_path, SECURITY DEFINER exec. Limits: SQL role+claims, not signed JWT.
## NEW RISK to record
Pages appears to publish `main` root (`.nojekyll`, root index.html, no Pages workflow). Do NOT merge PR #8 wholesale to main: `security/`, `tests/`, `docs/development/` would become publicly downloadable on the site. Release frontend by cherry-picking only app files, or restructure publishing to a `dist` folder first.
