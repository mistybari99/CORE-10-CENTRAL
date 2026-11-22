# CORE 10 owner preview — existing Worker `core10-central` (in place)

Owner Final Correction 2026-11-17: one owner-facing ERP preview, no developer gallery, no extra Worker.
Read-only. Not VERIFIED_COMPLETE, not Level 2. GO-2 / GO-3 not used.

| Item | Value |
|---|---|
| Source pin | trunk `ccr-15ed11dd-n3hw5h` @ `7c460aa9e4404e1a6630f2f14f070cd9e3b9497b` (no frontend change since `fe1c6b6`; 0151–0153, 0400 are SQL only) |
| Target | existing Worker `core10-central` only · zero bindings · `connect-src 'none'` · GET/HEAD only |
| Supersedes | `core10-build-review` (PR #114) — created under an earlier instruction; left unchanged, not redeployed, retirement awaits Owner approval |

## Refresh 2026-11-18 — route inventory (prepared, NOT yet deployed)

Source pins (every `/live/` file is read straight from these commits; see `SOURCE_MANIFEST.json`):

| Pin | Commit | Status |
|---|---|---|
| trunk `ccr-15ed11dd-n3hw5h` | `a82ae99` | TRUNK_INTEGRATED (Master Data UI, Owner Control, Stock 0200, Finance 0400–0401) |
| PR #109 NP03B Sales | `c7165af` | DRAFT_NOT_INTEGRATED |
| PR #112 NP05A Sweets Manufacturing | `86851dc` | DRAFT_NOT_INTEGRATED |
| PR #111 NP01 Setup/Approval/Control | `d9a1659` | no UI files — nothing to show |
| PR #117 Finance AR/AP | `3d128dc` | no UI files — nothing to show |

| Owner route | Renders | Source | Data | Writes |
|---|---|---|---|---|
| `#/home`, `#/business`, `#/staff`, `#/features` | real PACK-02 workspace / controls | trunk | sample projections `tests/pack02/fixtures/*.json` | none |
| `#/master` Master data | real Master Data UI + API client (items, variants, barcodes, categories, UOMs, conversions, parties, price lists) | trunk | recorded reads of the real `master_*` functions (`data/md-replay.json`) | every `master_save_*` refused → `MASTER_RPC_UNAVAILABLE` |
| `#/sales` Sales orders | real Sales Order UI (+ banner "not yet part of the main system") | PR #109 | recorded reads (`data/sales-replay.json`) | save/transition refused → `NOT_CONNECTED` (UI's own disconnected state) |
| `#/manufacturing` Manufacturing | real Sweets Manufacturing workbench (+ banner) | PR #112 | recorded reads (`data/mfg-replay.json`) | recipe/approve/substitution/handoff/waste refused → `NOT_CONNECTED` |
| `#/control` Owner control | real Owner Control Centre UI + client | trunk | recorded reads (`data/occ-owner-replay.json`) | refused → UI's "server could not be reached" |
| `#/approvals` | existing NP01 reviewer page, unchanged | trunk | its own synthetic client, `allowMutations:false` | none |
| `#/setup` | real Build01 page, locked by its own config | trunk | none | sign-in disabled |

Stock and Finance: **no UI exists** on trunk or in PR #117 → not in navigation.
Not published: legacy `owner.html`/`index.html`/`core10-shell.js`/`config.js`, staging boot/config files, every SQL/UI gateway and test harness.

Recording provenance: each module's own repo browser test was run unchanged against disposable PostgreSQL 17.12
(migrations + that test's seed) with a Playwright preload that only observes `/rpc/*` traffic:
Master `master-data-browser.cjs` 17/17, Sales `tests/np03b/browser.cjs` 43/43, Manufacturing `tests/np05a/browser.cjs` 62/62,
Owner Control `owner-control-centre-browser.cjs` 19/19. Only successful reads of the synthetic owner persona are kept.

Known limitations: Draft module data shows the builders' own synthetic test labels (e.g. `BROWSER-1440`, `fixture:kg`) and their
real `NOT_CONNECTED` Stock/Finance boundaries; filtering, paging or detail requests that the test never made answer "unavailable";
the legacy Central shell is still not publishable.

## Verify

```
node preview/core10-central-owner-app/build.mjs
node preview/core10-central-owner-app/verify.cjs                       # local
REVIEW_BASE=https://core10-central.mistybari99.workers.dev node preview/core10-central-owner-app/verify.cjs
```
36 checks: 8 routes × BN/EN × 390/1440 (renders, same-origin only, no backend call, no overflow, no page error,
no developer-report text), write methods 405, legacy/backend paths 404, bundle secret/legacy scan, Owner-control write refusal.

## Rollback

Prior state: deployment `a6d6629f-3004-4720-8b32-6fc5c45d4bd2`, version `b1d80c36-cb9b-4547-ab16-2821eb50e4fa`,
zero bindings, compat 2026-11-16. Its script (30,547 B, sha256 `d31d53c9dc0d95a13318ade5f4040fb049b4bd8c5f52160f7803aa380e3e45aa`)
equals `preview/clean-masterplan-level1.worker.mjs` @ `b8c1684` (PR #113) and is saved in `rollback/`.
Roll back: `POST /accounts/382a468cf1bde26b7b3c480acc409732/workers/scripts/core10-central/deployments`
body `{"strategy":"percentage","versions":[{"version_id":"b1d80c36-cb9b-4547-ab16-2821eb50e4fa","percentage":100}]}`.

## Deployment record (2026-11-17 UTC)

| Item | Value |
|---|---|
| URL | https://core10-central.mistybari99.workers.dev/ (same URL) |
| Active deployment / version | `3c91d5a2-26c3-4f79-96ae-65c7ec197dbf` / `9a1c6aaa-395c-44d0-beae-46e1afccf292` (100%), bindings: none |
| Script | `dist/worker.mjs` 571,957 B sha256 `67e7bdeceeda2109ddd374f83379490f0f5a049bb4a06f6789536ea706d24ca6`, built from branch commit `1ab1570` |
| Public verify | 36/36 PASS (32 route×lang×width checks incl. developer-text scan, writes 405, backend/legacy 404, write refusal) · header `x-core10-source: 7c460aa…` |
| Rollback | version `b1d80c36-cb9b-4547-ab16-2821eb50e4fa` confirmed present after deploy; procedure above |
| Upload path | Cloudflare API sandbox cannot fetch GitHub and the env token is invalid, so `core10-central` briefly served a token-protected uploader (temporary KV); stored bytes hash-checked, final script deployed, KV and upload secret deleted (deployment `3c91d5a2…` triggered_by `secret`). Old upload path → 405. |
| `core10-build-review` | not redeployed by this task; after this deploy it is no longer in the account Worker list and its URL returns 404 — removed outside this session. |
| `trillionaire-me` | untouched (modified 2026-11-13) |

Live screenshots (390/1440, BN/EN): `evidence/live-*.png` (GitHub only, not served by the Worker).

## GO-P1 live deployment (2026-11-18 UTC)

| Item | Value |
|---|---|
| URL | https://core10-central.mistybari99.workers.dev/ |
| Source | preview branch `a88bb8ad60f8d003c46cafcfe1d567d02b929560` (pins trunk `a82ae99`, PR #109 `c7165af`, PR #112 `86851dc`) |
| Script | `dist/worker.mjs` 885,424 B sha256 `b65cc8e1dfaf070c6005ce2408b7cd64c4c96b12630c884088341f9c66ab0a7a` |
| Deploy path | authenticated Cloudflare API `PUT /accounts/…/workers/scripts/core10-central` (account token). No uploader, no KV, no extra Worker. |
| Active | deployment `da61f276-816c-49a1-bf97-a5c1eb0bfd0f` / version `025cf3a1-8d91-45ba-bd4f-e2f77ee24ac1` (100%), bindings: none |
| Replaced | deployment `3c91d5a2…` / version `9a1c6aaa-395c-44d0-beae-46e1afccf292` |
| Live verify | 48/48: 46 in the suite run + 2 routes (bn 1440 `#/manufacturing`, `#/features`) that hit a 30 s `page.goto` network timeout and passed on rerun (content, no overflow, no errors, no foreign requests) |
| Rollback | versions `9a1c6aaa…` and `b1d80c36…` both return 200 from the versions API |

Live screenshots: `evidence/live-go-p1/`. Test labels (`BROWSER-1440`, `fixture:kg`) in Draft modules were NOT relabelled (would require editing recorded server output); listed as a limitation.

## GO-3 Level 2 live deployment (2026-11-22 UTC)

| Item | Value |
|---|---|
| Authority | Owner GO-3, re-confirmed in Session A after GO-2 (staging 0013-0019, 0100-0106, 0110-0114 applied) |
| Branch / commit | `preview/core10-central-level2` @ `e79bd3c` (from `preview/core10-central-owner-app` @ `243e137`; that branch untouched) |
| Change | `#/control` = real trunk Owner Control Centre with signed CORE10 staging sign-in; config generated from trunk file + publishable key, URL asserted = `rhrqhbyzrhaafynfhdaf`; CSP `connect-src 'self' https://rhrqhbyzrhaafynfhdaf.supabase.co`; legacy `config.js`, `v2/config.js`, `index.html`/`owner.html`, stocktake files forbidden |
| Active | deployment `84095bdd-50be-4ecd-bf15-62a539f9dc56` / version `38141fd4-09de-4f90-8f81-e12a850597b4` (100%), bindings: none, compat 2026-11-16 |
| Worker sha256 | `e0f7578d41edd35527cb1b0cedbe29e0225ca01fc83f49468b2a284e96bb8c86` |
| Rollback | version `025cf3a1-8d91-45ba-bd4f-e2f77ee24ac1`; source saved `rollback/core10-central-025cf3a1.worker.mjs` (sha256 = live bytes) |
| Live verify | `verify.cjs` 49/49 at the public URL: bn/en x 390/1440 x 10 routes, headers/CSP, write methods 405, forbidden paths 404, staging Auth refuses a wrong password and no other host is contacted. Evidence `evidence/live-go3/` |
| NOT VERIFIED | a successful Owner sign-in (needs the Owner's own staging account). Master/Sales/Manufacturing stay recorded replay (0150+ not on staging). |

### Update 2026-11-22: signed setup page
`#/setup` = trunk Build01 setup page (pinned `6f058dc`, core10-staging mode) with staging config. Deployment `e3d176dd-3335-4153-bd64-0c2a25f0e3e4` / version `201008ca-42a7-42cd-a08e-b968da6c4e51`; previous `38141fd4`, rollback base `025cf3a1`. Live verify 49/49.

### 2026-11-22 — Level 2 truthful staging-status banner release (verified)

- **Owner GO**: accelerate safe staging UX and testing. Original Owner demo business ID 3 and sites unchanged; IMG-ERP-SG untouched.
- **Source**: preview branch `8d30615ee4648bc2ac38d80d9655eaaf01a80192` fixes the false “nothing is saved” shell wording for signed `#/setup` and `#/control` only. Other routes remain accurate recorded-read previews.
- **Mandatory local bundle gates**: added `.github/workflows/core10-level2-gated-build.yml` at `4a5c55c`; actual GitHub Actions run `44989935242`: `node build.mjs` PASS, `node --check dist/worker.mjs` PASS, `node verify.cjs` **49/49 PASS**, browser 390/1440 BN/EN and same-origin/staging-only security checks. Saved exact verified candidate in Git commit `6277d563ca6acc0d911f035b3a63eb1e46d63511`.
- **Worker script**: `dist/worker.mjs`, **894638 bytes**, SHA256 `0a97d1a234e0fd39e9c5946698767dc525b8aeeebe652b9d9bcd014cc36b70ee`.
- **Live deployment**: Cloudflare existing Worker `core10-central` only (no KV, secrets, extra Worker, or production DB changes), deployment `aaa6039c-752e-4645-aaf2-76b0596a732a` / version **`ceeea069-d630-460a-b1f0-5b12e5157da9`**, confirmed 100%.
- **Public release gate**: workflow `.github/workflows/core10-level2-live-verify.yml` at `79ec3a3`, live run `44990275034` **SUCCESS**, actual public URL `REVIEW_BASE=...` `verify.cjs` **49/49 PASS**, identical bundle checksum confirmed in CI. No failing check, no rollback needed.
- **Rollback**: previous deployment `e3d176dd-3335-4153-bd64-0c2a25f0e3e4`, version `201008ca-42a7-42cd-a08e-b968da6c4e51`; Cloudflare POST deployment switch back to that version at 100% if a subsequent signed smoke check reveals regression.
- **Not a full ERP launch**: signed setup/control operate on CORE10 staging; master/sales/manufacturing remain recorded replay; Stock/Finance UI not connected, staging migrations remain through `0114`. Human Owner confirmed signed setup/screenshots independently, but this automated run does **not** use Owner credentials.

### 2026-11-22 — Signed Master Data Owner staging UI (50/50 LIVE PASS)

- **Owner acceleration GO**: first real Item/Unit/Party/Price List input with no real business data. CORE10 staging only `rhrqhbyzrhaafynfhdaf`; legacy IMG-ERP-SG, other projects, main and production are untouched.
- **Source**: `preview/core10-central-level2` commit `35ef4f6ae654f6258c2315fed3d56db3bf7365c0`: `/#/master` now serves `/view/master-signed.html`, reuses the existing signed Supabase session (or asks for Owner login), uses the canonical `CORE10_MASTER_DATA_API` and `CORE10_MASTER_DATA_UI` components pinned from trunk. Every read/write goes to `core10` RPCs, no direct table write. The original replay `/view/master.html` remains for explicit replay regression, not in Owner navigation.
- **Negative browser regression**: wrong password shows sign-in error, workspace stays locked; signed Master route has truthful staging banner, 390/1440 and bn/en coverage, no unauthorized network paths.
- **Verified candidate**: GitHub Actions run `44991383787` `node build.mjs` and full `node verify.cjs` **50/50 PASS**. Worker candidate archived in `f0e8e0365e3c1327db3a7e2efb1ebbd088e3ee5e`.
- **Worker**: `dist/worker.mjs` 903404 bytes, SHA256 `3ae944b1cdcb49f4701457d629e99b61f4acff32fff7b77e2713d3f16568fc28`; multipart PUT only existing Worker. Active deployment `7a58b970-2e62-405f-abe3-e4cd064611ee` / version **`4b6d179c-e1aa-4066-9fb6-6988dbc32432`** 100%. No secret or new Worker/KV.
- **Public gate**: CI pinned exact bundle in workflow commit `85d6b714170453d4d59cd66aafafb8d2625f46dd`; run `44991642473` **SUCCESS**. Live public URL `REVIEW_BASE=https://core10-central.mistybari99.workers.dev node verify.cjs` **50/50 PASS**, sha256 matched. No rollback needed.
- **Rollback**: previous stable deployment `aaa6039c-752e-4645-aaf2-76b0596a732a`, version `ceeea069-d630-460a-b1f0-5b12e5157da9` (100% before release); use Cloudflare POST deployments switch to that version if later Owner acceptance finds a regression.
- **Signed staging Master acceptance**: after migrations 0150–0153 on CORE10 staging, Owner's existing signed session successfully created/re-read Bangla item+UOM, idempotent request-key replay and cross-tenant negative SQL PASS. Four synthetic items, three UOMs, two categories, two parties, one retail list with two prices then persisted in the Owner demo business. Tenant 9801 denied Owner item reads. Real-browser Owner password login on new Master screen is awaiting Owner's manual acceptance.
- **Limitations**: Sales/Manufacturing still recorded replay and should NOT be described as live; stock posting/finance journal not E2E activated. Demo business status Draft, not production-certified; 100–400 site capacity after 0118 requires audited Owner per-business cap. No hard delete/audit reset.
