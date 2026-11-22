# Central application shell (trunk, Owner §7b.3)

Imported 2026-11-22 from the **existing** `preview/core10-central-level2` branch at exact commit `e9dd90d2c1616711378f657c4e5e0ce08e0d9db9`. This is the one source-controlled home for the current shell, **not** a production release.

The original `site/`, `data/`, `build.mjs`, `worker-runtime.mjs` and `local-serve.mjs` were copied as exact Git objects. The copied `verify.cjs` only points its existing legacy-host negative assertion to the approved relocated `legacy/islamia-erp/config.js`; no assertion was removed.

After fetching the pinned source commits, run `node apps/central/build.mjs` and `node --test tests/core10-central-shell-provenance.test.js`. The compiled Worker **must** have SHA256 `ba530d45179f9ea146bccb0a04899213a3e396adf7fe6030b28eebf938a5f4b2`; run `node apps/central/verify.cjs` for all 56 local browser tests and `REVIEW_BASE=https://core10-central.mistybari99.workers.dev node apps/central/verify.cjs` for public verification (read-only).

**No deployment is authorized by import.** Current live deployment continues only by the established preview branch procedure and all gates in handover §4. Do not make signed Staging Sales/Mfg claims from sample/replay routes; no real customer or Owner data is in these fixtures. Never use the protected IMG-ERP Supabase projects.
