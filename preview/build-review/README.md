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
