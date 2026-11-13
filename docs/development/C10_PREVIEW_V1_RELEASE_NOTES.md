# CORE 10 CENTRAL — Preview V1 (synthetic, no production access)

This is a **preview-only** integrated source branch, not a production deployment or merged main release.

## Actual source assembled
- A045 Workshop (original demo HTML/JS with in-memory synthetic backend)
- A046 synthetic persona registry
- A047 site grouping
- A048 stock commands
- A049 purchase/production/sales workflow slice
- A050 portfolio workspace
- A051 workforce/payroll
- A052 owner intent architecture documentation
- A053/A054 requirements pending; A055 is work-in-progress and intentionally excluded from the merged preview source.

All copied module files retain their original blob SHA and names from corresponding Draft PR branches. The canonical foundation is PR #7; no original business data or migrations were applied.

## Hosting
\`preview/worker.mjs\` serves a polished, responsive, interactive **synthetic** visual shell and proxied original A045 in-memory workshop demo assets from a pinned integration source SHA. No application API or authenticated Supabase access is wired.

Only five explicitly allowlisted A045 demo HTML/JS/CSS files may be fetched by the Worker from GitHub. Other source is private to the code branch, **not published by this Worker**. Preview CSP blocks external connections, forms, embedding and production transactions. No real owner/staff account, PII, sales or payroll data are included.

## Test and gating
\`node --test tests/core10-preview-v1.test.mjs\` checks synthetic labels, source pins, allowlist, no writes, unexposed internal paths and security headers.

Independent PR-specific SQL/Node/Playwright CI is not integration/staging certification. Real GoTrue sessions, cross-module migration ordering, identity integration, accounting certification and security sign-off remain missing.

DO NOT merge into main or modify production Supabase without explicit Owner approval. Do not treat the synthetic UI as a financially operative ERP.
