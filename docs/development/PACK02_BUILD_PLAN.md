# PACK-02 — Persisted Business Setup + Owner/Staff Workspaces (Claude)

Implementation evidence for BUILD LEDGER row PACK-02 (A020, A021, A042, A043, A044). Not a second Decision Book.
Owner GO: `OWNER_GO_PACK02_CODE_ONLY_CLAUDE_2026-11-15` (BUILD LEDGER A3:R3 readback verified 2026-11-15).
Decisions: D030, D032, D033, D045, D049, D051, D054. PACK-01 (ChatGPT, PR #104) owns authorization.

## Short technical plan

| Slice | Content | State |
|---|---|---|
| S1 | Setup readback + integrity, Quick/Advanced via existing `build01_setup_v1`, one workspace resolver (Universal Owner / Business Owner / Staff), business + owner scoped reports, Bangla-first client, 390/1440 browser check | **CODED, local tests PASS** (this checkpoint) |
| S2 | Wire client into Build01 signed page (`core10-build01.html`) as workspace switcher; real GoTrue journey via `tests/build01/run-auth.sh` gateway allowlist | Needs PACK-01 gateway coordination (Build01 files are PACK-01 owned) |
| S3 | D045 control placement projection (A043/A044 `control_settings`) inside Business Owner workspace; staff-hidden controls | Next independent slice |
| S4 | Owner-wide report reuse of A050 portfolio contract; 300-site load (D030 target) for readback/workspace | Pending |
| S5 | Signed hosted A/B negative E2E, Drive + Sheet readback, Owner preview pair P01 | Blocked on PACK-01 signed staging |

## Reuse, not rebuild

- Authority: `c10_demo.actor_uid / can_tenant / can_business / can_manage / can_site / can_see_business` (Build01). Called only; never redefined. No new permission table, grant, role or audit store.
- Setup: `build01_setup_v1` → original `setup_business_v1` / `setup_industry_draft_v2`. PACK-02 adds `pack02_setup_business_v1` (engine receipt + persisted readback, fails if integrity check fails).
- PR #94 (`internal/setup001`, Draft, advisory only) not cherry-picked; its profile hints remain advisory and do not create or activate anything.
- PR #104 (PACK-01) files untouched.

## New files (Claude-owned paths)

- `internal/enterprise-sql/c10_pack02_workspace_v1.sql` — additive disposable SQL: `pack02_setup_readback_v1`, `pack02_setup_business_v1`, `pack02_workspace_v1`, `pack02_business_report_v1`, `pack02_owner_report_v1` (+ internal `pack02_nav_v1`, `pack02_brand_v1`).
- `core10-pack02-workspace.js`, `core10-pack02-workspace.css` — projection validator/renderer. Fails closed on umbrella/tenant/actor/sister leaks, nav exceeding site actions, duplicates, bad brand, stale responses. Unwired nav renders disabled.
- `tests/pack02/run-sql.sh` (`workspace`, `regression`), `tests/pack02/workspace-e2e.sql`, `tests/pack02/workspace-client.test.cjs`, `tests/pack02/workspace-browser.cjs`, `tests/pack02/fixtures/*.json` (verbatim SQL output).
- `.github/workflows/core10-pack02-workspace-ci.yml`.

## Verified behaviour (disposable PostgreSQL, synthetic claims)

- Quick and Advanced setup through the canonical engine; replay returns byte-identical receipt + readback; one business, one receipt, no duplicate sites; changed payload, casefold duplicate site and quick-with-sites refused with no orphan business; cross-tenant legal entity refused; business owner / staff cannot set up.
- Readback checks: legal entity same tenant, configuration present, single receipt, ≥1 site, every site has MAIN location, no orphan locations, no duplicate sites, modules locked, not activated. Seed businesses without receipts correctly report `integrity_ok=false`.
- Universal Owner: only own tenants (T1 owner never sees T2 independent customer; T2 owner only 201). Business owner (non tenant owner): own business only, no umbrella, no sister business. Manager: no owner workspace. Staff: only granted site, own brand, no umbrella/tenant/legal/sister/actor data; Build01 explicit deny removes `stock.post` from nav; expiry and revoke close the workspace. Investor, inactive manager, other-tenant staff, unrelated operator, anonymous: denied. `anon` has no schema access; internal brand helper not executable by `authenticated`.
- Unchanged `tests/build01/access-integration.sql` passes with PACK-02 loaded.
- Browser: all four projections at 390px and 1440px — no horizontal overflow, ≥44px targets, `lang=bn`, staff text has no CORE 10 / sister data, no external requests.

Local run: PostgreSQL 16.15 (CI uses 17), Node 22, Playwright Chromium.

## Limits (not claimed)

Synthetic `request.jwt.claim.sub` only — not GoTrue/hosted signed proof. No production SQL, SG migration, merge, deploy, Cloudflare, real stock/money/users. D051 Islamia files, routes, IDs untouched. Workspace UI is not yet linked from any published page. PACK-02 is **not** VERIFIED_COMPLETE.

## Checkpoint 01

| Field | Value |
|---|---|
| MAJOR_BUILD | PACK-02 |
| ASSIGNED_AGENT | Claude Code |
| BRANCH | `claude/core10-pack02-build-8ii000` (session-assigned Claude branch) |
| BASE_SHA | `e76cf8a3db1a385726a1637683c972e99a193fec` (`preview/c10-integrated-20261111-v1`) |
| HEAD_SHA | see Draft PR head (recorded after push) |
| OWNED_PATHS | `core10-pack02-*`, `internal/enterprise-sql/c10_pack02_*`, `tests/pack02/**`, `docs/development/PACK02_*`, `.github/workflows/core10-pack02-workspace-ci.yml` |
| PR | Draft PR → `preview/c10-integrated-20261111-v1` |
| CI | `CORE10 PACK-02 setup readback and workspaces` (verify on exact head) |
| LAST_VERIFIED_AT | 2026-11-15 Asia/Dhaka (local) |
| WAITING_DEPENDENCIES | PACK-01 signed gateway/allowlist for S2; hosted GoTrue staging for S5 |
| HANDOFF | S3 control placement projection is next independent slice |

## SHEET UPDATE REQUEST (for ChatGPT Orchestrator — Claude does not write the Sheet)

- Target: `BUILD LEDGER` row 3 (Major ID `PACK-02`), existing row, no new row.
- Expected current: Stage `APPROVED_TO_BUILD`, Git column empty, Signed E2E `UNTESTED`.
- Proposed: Stage `IN_PROGRESS`; Git/PR/CI = Draft PR number + exact head SHA + PACK-02 workflow run IDs; Signed E2E = `S1 DISPOSABLE_SYNTHETIC_SQL+BROWSER PASS; SIGNED GOTRUE UNTESTED`; Reports = `pack02_business_report_v1 / pack02_owner_report_v1 counts only, no valuation`; Blockers/Next = `S2 needs PACK-01 gateway coordination; S3 control placement next`.
- Evidence: this file at the PR head, PR checks page.
- Status: NOT SHEET_SYNCED until Orchestrator readback.
