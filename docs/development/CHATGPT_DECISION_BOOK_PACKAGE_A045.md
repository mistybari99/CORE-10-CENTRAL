# C10-A045 — Master Decision Book package (give this file to ChatGPT / paste into the Google Sheet)
Sheet: https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit
Why a file: the Drive connector replaces whole files, so Claude did not write into the sheet. These are IMPLEMENTATION-PROGRESS / EVIDENCE records, NOT new Owner decisions. D033, D045, R014-R026, R123, R124 stay controlling.

## 1) NEXT ACTIONS  (row for C10-A045)
- Action ID: C10-A045
- Title: Owner Micro-Engine Workshop + registered rule runner + multi-business publishing v1
- Status: BUILT in Draft PR #42 (disposable c10_demo + static demo preview); NOT RELEASED; NOT applied to IMG-ERP-SG; real Supabase GoTrue proof NOT DONE.
- Evidence: PR https://github.com/mistybari99/CORE-10-CENTRAL/pull/42 ; exact SHA and CI run URLs are in docs/development/CURRENT_HANDOFF.md.
- Next: real GoTrue staging negative tests (needs Owner-approved disposable staging project + keys); rebase when PR #7 base advances; certify further handler types one by one.

## 2) CHANGE LOG  (next free Cxxx)
"A045 code checkpoint on branch claude/c10-a045-micro-engine-workshop-v1: additive SQL (engine registry, immutable versions, per-business assignments, per-site overrides, receipts, append-only audit, config-only rollback, approval queue), one certified advisory handler threshold_rule_v1, Owner Workshop + Business UI, A044 Controls Micro-Engines panel, static DEMO preview page. No production change."

## 3) AUDIT EVIDENCE  (next free Exxx)
- PostgreSQL 17 SQL E2E (tests/c10_a045_micro_engine_e2e.sql): Owner / Business Owner / Manager / Staff / Revoked / other-tenant / anonymous; lifecycle DRAFT>VALIDATED>PUBLISHED>PAUSED>REVOKED; stale, replay, payload tamper, approval bypass, invalid DSL, immutability, site overrides, rollback.
- Signed-JWT PostgREST HTTP E2E (tests/api/core10-a045-engine-rest-e2e.js): repo demo tenant/staff identities + forged/expired/spoofed tokens; real stock postings unaffected by engine config. HMAC-signed, NOT Supabase GoTrue.
- Node unit + Chromium 390px/1440px (synthetic RPC fixture, labelled) + static demo preview.
- Honest limits: no real GoTrue; no SG migration; only threshold_rule_v1 executable (other types stored inert, canExecute=false by Claude decision: one certified handler is enough for v1).

## 4) REQUIREMENTS LOCK  (note under R124)
Items 3-4 (Micro-Engine Workshop; business distribution of one canonical engine) have an executable first slice for ONE handler. Site-level overrides built. Other engine types: DRAFT / NOT IMPLEMENTED until certified.

## 5) Decisions taken by Claude on Owner's instruction ("decide yourself, do not wait")
1. Ship ONE certified handler (threshold_rule_v1), not eight.
2. Engine overrides support only `threshold` and `outcome` keys (fail-closed on anything else).
3. Rollback restores assignment config only; per-site overrides are versioned separately and not part of rollback.
4. Business-owner site overrides allowed only when local_edit_mode=business_owner; request_approval mode covers business-wide params only.
5. A DEMO preview page with in-memory demo accounts was added for trying the UI without any backend; it is clearly labelled and never used as test evidence of security.
