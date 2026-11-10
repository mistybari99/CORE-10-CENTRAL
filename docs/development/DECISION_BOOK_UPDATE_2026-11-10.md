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

## DEFERRED BY OWNER (record now, do later) — 2026-11-10
| ID | Item | Why deferred | When |
|---|---|---|---|
| DEF-01 | GitHub account 2-factor authentication (Settings > Password and authentication) | Owner action; protects the repo/Pages/deploy path | after current big builds |
| DEF-02 | `main` branch protection (Settings > Branches: require pull request, block force-push) | Prevents accidental direct changes | after current big builds |
| DEF-03 | Move app hosting from GitHub Pages to Cloudflare Pages (free, works with a PRIVATE repo) so the repo can be private. Agent-built allowlist `dist` + migration guide in a draft PR. Note: making the repo private on GitHub Free DISABLED Pages and broke the live app for ~30 min on 2026-11-10; reverted by making the repo public and re-enabling Pages (main / root). | Needs Cloudflare account + Supabase allowed-URL changes + staff re-login | later, tested first |
| DEF-04 | Move security notes / handoff out of the PUBLIC repo into private Drive (repo is public) | Information exposure | with DEF-03 |
| DEF-05 | Enable Supabase "Leaked password protection" (Auth settings) | Plan/dashboard setting | later |
## BIG BUILDS (Decision Book NEXT ACTIONS order) — status 2026-11-10
A010 hierarchy (design PR #12, not applied) -> A011 add Showroom/Factory/Godown -> A012 per-business theme/name/logo -> A013 scoped owner metrics -> A018/A019/A020 enterprise foundation (PR #7, isolated only) -> A021 dual Owner boards -> A022 investor/partner finance -> A023 KPIs & enterprise readiness. A006/A007 owner inbox (PR #4/#5 + mirror-live tests PR) -> A008/A009 approve/reject. A024 SaaS and A025 Simulation remain deferred.
BLOCKER for UI builds: the bundled `core.js` (84 files) cannot be rebuilt exactly from this repo (78/84 pieces verbatim, 6 modified); the original build tool is not in this repo (likely in archived private repo `My-tools`; Claude's access request to it was denied by the session safety classifier). Lazy-loaded screens (e.g. costgap.js, partners.js) are separate files and CAN be edited directly.

## NEW OWNER REQUIREMENT — "INTEGRATION PORTS" (2026-11-10) — proposed R115 / action A026
Owner: spend nothing on external services NOW, but every external connection must already have a ready, OFF-by-default "port" so that later the Owner only connects an account / pastes an API key in a settings screen and it works end to end, nothing to rebuild.
Scope of ports: AI integrations; Facebook Page / Messenger; website & online pages / online store; WhatsApp; SMS; Email; bKash / Nagad / Rocket (mobile money); online payment gateway and bank cards; delivery / courier transactions.
Design rules (Claude decision, to be confirmed): (1) one provider-agnostic adapter contract per channel + provider registry; (2) every port ships DISABLED with a mock/sandbox provider so it can be tested without paying; (3) secrets NEVER in Git, never in the browser: entered once on an owner-only screen and stored server-side (Supabase Vault / Edge Function secrets); (4) outbox/inbox tables with idempotency keys, retries, audit log, per-business scoping (tenant-safe); (5) payments: never store card numbers (hosted/redirect checkout only), webhook signature verification, reconciliation against the ledger; (6) messaging: consent/opt-out, templates (reuse tpl_msgs.js), rate limits; (7) AI: server-side key, per-business budget cap, PII redaction (table ai_redaction_rules exists); (8) each port has an owner switch, a health/test button and a cost/limit field.
Status: design + isolated build starting; nothing applied to production; no keys requested.
