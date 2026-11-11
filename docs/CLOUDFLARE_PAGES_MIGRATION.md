# Cloudflare Pages migration (private repo, free)

Status: BUILT / TESTED IN ISOLATION. Nothing is deployed. No Cloudflare account, API or GitHub Pages setting has been touched.

Why: GitHub Pages on the Free plan needs a public repo. Making the repo private would take the app offline. Cloudflare Pages (free) can build from a private GitHub repo and serve only an allowlist of app files.

## What this PR adds
- `tools/build_dist.js` (Node, no dependencies) copies an allowlist into `dist/` (git-ignored), keeping exact filenames (the service worker precaches `core.js?v=...` style names). It prints every copied file and the total size, and FAILS if `dist/` would contain `*.sql`, `*.md`, `setup-*.html`, `audit-*.html`, `internal/`, `design/`, `security/`, `tests/`, `docs/`, `.github/`, `v2/`, or if index/owner/business/sw.js reference a file that is not copied, or if the CSP in `_headers` drifts from the CSP `<meta>` in `index.html`.
- `public-headers/_headers`: HSTS, nosniff, Referrer-Policy, minimal Permissions-Policy (camera for barcode scan only), CSP (same as the index.html meta plus `frame-ancestors 'none'`), `no-cache` for HTML and `sw.js`, `immutable` 1-year cache for versioned `.js`/`.css`. Copied to `dist/_headers` by the build.
- `tests/dist-smoke.js` (Playwright): login renders, 0 page errors/CSP violations (the real `_headers` CSP is applied by the test server), every script/link in index.html returns 200, service worker registers, app opens offline, forbidden files unreachable.

Allowlist: `index.html owner.html business.html`, root `*.js *.css *.svg *.webp *.webmanifest`, `manifest.json`, `bundle-manifest.json`, `robots.txt`, `sw.js`, `vendor/`, `data/`. Current result: 242 files, about 16.1 MiB.

`v2/` decision: NOT copied. No page, `sw.js` or root `*.js` references `v2/` (checked by grep). If a future change links it, add it to `DIRS` in the build script.

## Owner steps
1. Merge this PR (after review). Build locally if you want to check: `node tools/build_dist.js` then `NODE_PATH=$(npm root -g) node tests/dist-smoke.js`.
2. Create a free Cloudflare account (dash.cloudflare.com). Workers & Pages -> Create -> Pages -> Connect to Git. Authorize the Cloudflare GitHub app for `mistybari99/CORE-10-CENTRAL` only (private repos are supported on Free).
3. Project settings: Production branch `main`; Framework preset `None`; Build command `node tools/build_dist.js`; Build output directory `dist`. Set env var `NODE_VERSION` to `20` if the build image's Node is older.
4. Headers: nothing to type in the dashboard. `dist/_headers` is read automatically. After the first deploy, check with `curl -sI https://<project>.pages.dev/` that the CSP, HSTS and `cache-control: no-cache` appear and that `https://<project>.pages.dev/sw.js` is `no-cache`.
5. Verify on the `*.pages.dev` URL (or a preview deployment of the PR branch) before telling staff: login works, an order/sale save works, barcode camera opens, app opens offline after first visit. A routine app UI smoke test by the Owner is required because the signed-in flow is not covered by `dist-smoke.js`.
6. In Supabase (IMG-ERP-SG) Authentication -> URL Configuration: add the new origin to Site URL / Redirect URLs. Check any CORS/allowed-origins setting in Edge Functions or Storage the same way. Do this BEFORE staff use the new URL.
7. Keep the GitHub Pages site running until step 5 passes. Do not make the repo private until then: Pages stops serving when it does.
8. Switch staff: send the new URL by WhatsApp. Staff open it, log in again, and re-install the home-screen app (see risks). Retire the old URL only after everyone has switched, then make the repo private and disable GitHub Pages.
9. Optional: attach a custom domain in the Pages project (free) so the URL never changes again; add it to Supabase redirect URLs too.

## Rollback
- Before step 8: nothing to roll back; GitHub Pages is still live.
- After step 8: while the repo is still public, staff go back to the old GitHub Pages URL. If the repo is already private, re-publish by making it public again (or pause the Cloudflare deployment: Pages project -> Deployments -> a previous good deployment -> Rollback to this deployment). Every deploy is immutable, so rolling back to the previous one takes one click.
- This change adds files only; it does not change `sw.js`, the app or the database.

## Cost
Free plan: 500 builds/month, 1 build at a time, 20,000 files per deployment (we use about 240), 25 MiB per file (largest here is the OCR wasm, under 25 MiB), unlimited static bandwidth and requests, free `*.pages.dev` TLS, custom domain included. Confirm current limits at developers.cloudflare.com/pages/platform/limits before relying on them.

## Risks and consequences
- Supabase CORS / Auth: the new origin must be in Supabase Auth Site URL and Redirect URLs (and any allowed-origin list). Without it login/password-reset redirects fail.
- PWA / service worker: scope and cache are per origin. Staff who installed the old app must remove it and install again from the new URL. The old service worker keeps serving the old site until they leave it.
- localStorage / IndexedDB / saved sessions are per origin: staff must log in again, and any unsent offline drafts or local-only settings on the old origin do not carry over. Sync or finish pending work first.
- Two live origins at once (during the overlap) both talk to the same Supabase database; that is fine, but staff should use only one.
- The `_headers` CSP is the existing CSP plus `frame-ancestors 'none'`; the build checks that they match. If `index.html` CSP is changed, update `public-headers/_headers` in the same PR.
- Versioned `.js`/`.css` are served `immutable`. This is safe because the app loads them as `name.js?v=<hash>` (the URL changes with content). Unversioned scripts (`sw.js`, `vendor/*`) are `no-cache`. Cloudflare's `_headers` cannot match query strings, so a versioned file requested WITHOUT `?v=` would be cached for a year; none of the app's own references do that today.
- Cloudflare Pages `_headers` merging and `! Header` detach behavior was written from documentation and not run against a real Cloudflare deployment in this PR (not deployed by instruction). Verify with `curl -sI` after the first deploy.
