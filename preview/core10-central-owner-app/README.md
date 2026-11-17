# CORE 10 owner preview — existing Worker `core10-central` (in place)

Owner Final Correction 2026-11-17: one owner-facing ERP preview, no developer gallery, no extra Worker.
Read-only. Not VERIFIED_COMPLETE, not Level 2. GO-2 / GO-3 not used.

| Item | Value |
|---|---|
| Source pin | trunk `ccr-15ed11dd-n3hw5h` @ `7c460aa9e4404e1a6630f2f14f070cd9e3b9497b` (no frontend change since `fe1c6b6`; 0151–0153, 0400 are SQL only) |
| Target | existing Worker `core10-central` only · zero bindings · `connect-src 'none'` · GET/HEAD only |
| Supersedes | `core10-build-review` (PR #114) — created under an earlier instruction; left unchanged, not redeployed, retirement awaits Owner approval |

## Route inventory and audit

| Owner route | What renders | Source | Data | Writes |
|---|---|---|---|---|
| `#/home` Owner home | real PACK-02 workspace (Universal Owner) | `core10-pack02-workspace.js/.css` | sample projection `tests/pack02/fixtures/universal-owner.json` | none (nav items disabled by the source: not wired) |
| `#/business` Business | real PACK-02 workspace (business owner, branded) | same | `business-owner-branded.json` | none |
| `#/setup` Setup & access | real Build01 page, locked by its own shipped config | `core10-build01.*`, `core10-enterprise-client.js`, `vendor/supabase.js` | none | sign-in disabled by source |
| `#/master` Master data | one-line unavailable message | — (no UI on trunk yet; B-011 SQL 0150–0153 only) | — | — |
| `#/control` Owner control | real Owner Control Centre UI + real API client | `core10-owner-control-centre-ui.js`, `core10-owner-control-client.js`, `.css` | read-only replay of responses recorded from the real core10 SQL functions (`data/occ-owner-replay.json`) | every write refused → UI's own "server could not be reached" |
| `#/features` Feature permissions | real PACK-02 controls UI (Central) | `core10-pack02-controls.js` | `controls-central.json` | none |
| `#/approvals` Approvals | existing NP01 reviewer page, unchanged | `docs/preview/c10-np01-canonical-reviewer-preview.html` + `internal/enterprise-client/c10_np01_*` | its own synthetic client, `allowMutations:false` | none |
| `#/staff` Staff workspace | real PACK-02 workspace (staff, one site) | PACK-02 | `staff.json` | none |

Not published (blocker, not a fake substitute): `owner.html`, `index.html`, `core10-shell.js` and its legacy chain
(they require the legacy BOS app and `config.js`, which points to a non-CORE10 Supabase project). The new shell
(`site/index.html`, `app.js`, `app.css`) is presentation glue only: navigation + module frames, no engine, no data.
Also not published: `core10-control-centre-config.js` / `core10-owner-control-centre.js` (real boot needs the
staging key, GO-2/3), SQL gateway, persona harness, signed adapters.

Replay provenance: trunk `7c460aa` migrations on disposable local PostgreSQL 16.15 → `tests/control-centre/seed.sql`
→ the real 19-step `owner-control-centre-browser.cjs` (19/19 PASS) → recorded every read RPC
(`build01_context_v1`, `control_read_v1`, `control_history_v1`, `control_audit_v1`, `control_overrides_v1`) as the
synthetic owner. Writes were never recorded and are never answered.

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
