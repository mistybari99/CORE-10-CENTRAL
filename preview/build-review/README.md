# CORE10 Build Review — read-only Cloudflare preview

Owner-requested, ad hoc review of the **real** CORE10 frontend work. NOT VERIFIED_COMPLETE, NOT P01, not Level 2.

| Item | Value |
|---|---|
| Source pin | trunk `ccr-15ed11dd-n3hw5h` @ `fe1c6b676a25156dfac15ff79538a99bfb7218ff` |
| Branch | `preview/claude-real-build-review-20261117` (this package only; no source engine edits) |
| Worker | `core10-build-review` (separate; `core10-central` and `trillionaire-me` untouched) |
| Bindings / secrets | none · outbound network none (`connect-src 'none'`) · only GET/HEAD, all else 405 |

## What is served

| Route | Kind | What it is |
|---|---|---|
| `/` | REVIEW_UI | hub: status, legend, screenshots, Bangla Owner checklist |
| `/live/core10-owner-control-centre.html` (+ deps) | ACTUAL_SOURCE | real B-021 page; shipped config has an empty key → shows NOT_CONNECTED |
| `/live/core10-build01.html` (+ deps) | ACTUAL_SOURCE | real Build01; shipped config `enabled:false` → locked, sign-in disabled |
| `/pack02.html?fx=…` | REVIEW_UI host + ACTUAL_SOURCE renderers | real `core10-pack02-workspace.js` / `-controls.js` on verbatim `tests/pack02/fixtures/*.json` |
| `/live/docs/preview/c10-np01-canonical-reviewer-preview.html` | ACTUAL_SOURCE | existing offline synthetic Approval reviewer, unchanged |
| `/evidence/*.png` | TEST_SCREENSHOT | from `tests/control-centre/owner-control-centre-browser.cjs` (19/19) and `tests/pack02/workspace-browser.cjs` |
| `/manifest.json` | generated | every file: route, source path, git blob, SHA-256 |

`build.mjs` refuses to bundle a `/live/` file that differs from the git blob at the pin (`SOURCE_DRIFT`)
and refuses `config.js`, the SQL gateway and the persona harness (`FORBIDDEN_FILE`).

Not served on purpose: `owner.html`, `index.html`, `core10-shell.js` (legacy BOS + `config.js` dependency, different
Supabase project), signed adapters, the SQL gateway and harness.

## Rebuild and verify

```
node preview/build-review/build.mjs                 # -> dist/worker.mjs + SOURCE_MANIFEST.json
node preview/build-review/verify.cjs                # local, 27 checks
REVIEW_BASE=https://<worker-url> node preview/build-review/verify.cjs   # deployed
```

Screenshots were produced locally: PostgreSQL 16.15 (disposable loopback cluster, synthetic `tests/control-centre/seed.sql`,
migrations 0001–0150 from the pin), Playwright 1.63.0 Chromium. CI uses PostgreSQL 17.

## Limits (need later GO)

- Central shell route contract (CHG-006) not wired; shell still legacy → GO for shell rewrite.
- Owner Control Centre / Build01 / PACK-02 signed flows need Level 2 (publishable staging key, hosted apply B-022) → GO-2/GO-3.
- Master data (B-011) has tables only, no UI. Sweets/Bakery T1 depends on Draft PRs #108/#109/#112 and B-012.

## Bangla Owner checklist

See the "কোথায় ক্লিক করে কী দেখবেন" section on the hub page.

## Deployment record (2026-11-16 UTC)

| Item | Value |
|---|---|
| URL | https://core10-build-review.mistybari99.workers.dev/ |
| Account | `382a468cf1bde26b7b3c480acc409732` |
| Worker | `core10-build-review` (new; name was free) · zero bindings · no schedules · workers.dev on, previews off |
| Active deployment / version | `308c8b13-dd5b-4581-b4c7-37bc11cb4936` / `52b86bc5-4b2b-40d5-89b0-650a378b5147` (100%) |
| Script content | `dist/worker.mjs` sha256 `42952fdfefba3db3743be16bc7d47eefafed17307e365a25b5e78ef76c8c435f` (rebuild from package commit `7b10936`, verified server-side before upload) |
| Public verify | `REVIEW_BASE=<URL> node preview/build-review/verify.cjs` → **27/27 PASS** (incl. 405 on all writes, CSP-blocked fetch to staging, 404 for config.js / SQL gateway / harness) |
| `core10-central` | untouched: deployment `a6d6629f-3004-4720-8b32-6fc5c45d4bd2`, version `b1d80c36-cb9b-4547-ab16-2821eb50e4fa`, etag `336ab7e1…` before and after |
| `trillionaire-me` | untouched (modified_on 2026-11-13) |

Upload path (the Cloudflare API sandbox cannot fetch GitHub): `core10-build-review` was briefly deployed as a
token-protected uploader bound to a temporary KV namespace; the container POSTed `dist/worker.mjs`; the stored
bytes were hash-checked, the script was replaced with the final build, the KV namespace deleted and the
carried-over upload secret deleted (deployment `308c8b13…`, triggered_by `secret`). Old upload endpoint now → 405.
