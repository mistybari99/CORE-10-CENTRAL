# Restartable handoff — Real build review preview (Issue #110 format)

| Item | Value |
|---|---|
| Branch | `preview/claude-real-build-review-20261117` (preview-only; Draft PR → `ccr-15ed11dd-n3hw5h`) |
| Source pin | trunk `fe1c6b6` (unchanged by this branch; no source engine edits) |
| Deployed | Worker `core10-build-review`, deployment `308c8b13…`, version `52b86bc5…` — see `preview/build-review/README.md` |
| Not touched | `core10-central`, `trillionaire-me`, Supabase (staging and IMG-ERP-SG), main, trunk, other builders' branches |
| Local-only work | none |

## Resume
1. `git fetch origin ccr-15ed11dd-n3hw5h`; if trunk moved, update `PIN` in `preview/build-review/build.mjs` (SOURCE_DRIFT tells you which files changed).
2. Rerun screenshots: disposable loopback PG + `tests/control-centre/owner-control-centre-browser.cjs` (OCC_SHOTS) and `tests/pack02/workspace-browser.cjs` (PACK02_SCREENSHOT_DIR); copy into `preview/build-review/evidence/`.
3. `node preview/build-review/build.mjs && node preview/build-review/verify.cjs`.
4. Redeploy the same Worker name only; then `REVIEW_BASE=https://core10-build-review.mistybari99.workers.dev node preview/build-review/verify.cjs`.

## Blocked (needs Owner GO)
- Level 2 (staging key + hosted apply B-022) for signed Owner Control / Build01 / PACK-02.
- Central shell rewrite off legacy BOS/config.js (CHG-006) before any shell route can be shown.
