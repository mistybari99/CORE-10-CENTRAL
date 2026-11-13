# Build 01 — Business Setup, Login & Permissions Integration

Action **C10-A059**, Issue #68. This is implementation evidence supporting the existing Master Decision Book, not a second decision register.

## Connected implementation

The isolated browser signs in through actual local Supabase Auth (GoTrue), obtains server-authorized business context, creates draft businesses and sites, grants or revokes canonical membership/site access, and reads effective stock permissions and the original audit history. Quick and Advanced setup reuse the original setup engines. Industry templates remain draft configurations, not certified operational industry products.

Original A034 history is merged unchanged; its SQL moved to `internal/enterprise-sql/c10_a034_access_governance_v1.sql` with blob `8eab115ad5775cb4d7d1811ea27dd857d1ee392c`. The additive Build01 SQL extends existing membership, site-grant and access-event tables. It does not introduce a second permission store. Claude module source remains unchanged.

- `core10-build01.html`, `.css`, `.js`: bilingual responsive login, setup, site, access, effective-permission and audit interface.
- `core10-build01-client.js`: fresh server user verification before RPCs, actor/scope checks, original setup validation, local signout.
- `core10-build01-config.js`: disabled by default. No fallback to the existing production configuration.
- `internal/enterprise-sql/c10_build01_access_integration_v1.sql`: canonical integration, explicit deny, expiry, version checks, request replay and append-only evidence.
- `tests/build01/gateway.cjs`: loopback-only gateway for an allowlisted packaged artifact, Auth and five Build01 RPCs. No admin/signup route, service key, arbitrary proxy or raw repository serving.

## Reproduce

Use disposable PostgreSQL 17 with loopback `PGHOST`, `PGPORT`, `PGUSER` and optional `PGPASSWORD`. The runners create and remove only their own databases. Never supply production credentials.

```sh
node tests/build01/client.test.cjs
node tests/build01/gateway.test.cjs
CORE10_CHROMIUM_PATH=/usr/bin/chromium node tests/e2e/core10-build01-locked-browser.cjs
CORE10_BUILD01_DISPOSABLE_ACK=I_CONFIRM_BUILD01_DISPOSABLE bash tests/build01/run-sql.sh all
CORE10_BUILD01_DISPOSABLE_ACK=I_CONFIRM_BUILD01_DISPOSABLE CORE10_BUILD01_BROWSER=1 CORE10_CHROMIUM_PATH=/usr/bin/chromium bash tests/build01/run-auth.sh
```

The Auth runner downloads checksum-pinned official GoTrue v2.197.0 and PostgREST 12.2.12 binaries. It creates fictitious users locally and uses actual password login sessions. SQL-only fixtures are separately labelled synthetic claim tests. Real local Auth evidence does not certify hosted staging or production.

The optional `CORE10_PREVIEW_BUILD01=1` mode of `tests/preview-one/run-combined.sh` loads the additive integration atop the complete existing preview stack. Original module tests remain unchanged.

## Release boundaries and remaining acceptance

Public Preview One is a separate deployed synthetic preview; this local authenticated surface is not automatically published there. No production migration, main merge, operational data, money movement or paid service is part of this build.

Build01 explicit action-deny controls currently cover `stock.read` and `stock.post`. They do not constitute a complete HR/payroll/finance permission catalog. Existing downstream module readers `wfi_ctx`, `wf_my_businesses_v1`, `ami_ctx` and `ami_wk_assignee_ok` query active membership without the new expiry. Their definer execution cannot be corrected with a generic membership RLS policy. These require explicit reviewed adapters and negative tests before universal permission certification; Build01's gateway does not expose those RPCs. Business membership revocation also does not mean revocation of independently granted workforce employee or asset permissions. Do not mark all Build01 or all 520 detailed acceptance items complete from this slice.

Live Book continuity checked on resumption: D051/R130 protects the original Islamia ERP and archive; GOV-002 Build02 PRs78–83 and Claude GOV-003 Issue84/PR85 are separate reserved tracks. Their code and log entries are not replaced by this build.

Rollback before release is to remove the isolated test database and leave the locked default configuration disabled. There is no authorized production SQL rollback or production deployment in this change.

## Verification record

2026-11-12 resumed from saved branch after interruption: client **5/5 PASS**, gateway **2/2 PASS**, locked browser **390px/1440px PASS**. SQL, real Auth/browser, combined regressions and exact-commit remote CI are recorded below only after completion.

- Ten industry families × Quick/Advanced: **20/20 SQL cases PASS**, including matching replay, conflicting request, site counts, audit and locked-module invariants.
- All seven combined-stack areas **PASS**: cross-module, operations, intent, CRM, workforce, workforce-policy and assets. Includes original concurrency suites and six separate asset areas; original assertions unchanged. This regression evidence does not close the downstream expiry gap described above.
- Concurrency **PASS**: eight simultaneous identical setup/site/grant requests produce one outcome, competing expected-version writes produce one success/seven stale refusals, and a business-owner writer revoked while waiting for its lock is denied.
- Final SQL revision with actual GoTrue password/getUser/logout, signed PostgREST and live Chromium **PASS at 390px and 1440px**. Covers setup/site/grant/deny/expiry/revoke, append-only audit, wrong password/signature/tenant, forged user metadata and old-token rejection after logout. No network mocking or role dropdown authentication.
- Strengthening the concurrency harness to check every child exit exposed a setup retry race. Fixed in the additive wrapper with a transaction lock scoped to tenant/request, followed by an authorization recheck. All six SQL suites now pass, including eight-way retries through both original setup engines. Tests do not accept unique-constraint errors as successful retries.
- The actual GoTrue API suite also covers all ten industry families in both modes: **20 signed setups with matching replay and draft/site-count checks PASS**.

Remote CI must be checked against the pushed commit; local success is not a remote-CI claim. The dedicated workflow runs six canonical SQL suites, seven existing-module regression areas and one genuine Auth/browser job.
