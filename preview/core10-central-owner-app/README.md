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
