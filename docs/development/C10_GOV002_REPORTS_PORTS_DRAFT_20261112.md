# C10-CAP-GOV-002 — Page-scoped Reports and Operational Port Contracts (DRAFT)

**Date:** 2026-11-12  
**Source:** stacked Draft #88 on Draft #87 → #83 → #82 → #81 → #80 → #79 → #78 → #69.  
**Safety:** This is source-built/isolated-tested ONLY; it is NOT integrated into real signed Supabase GoTrue staging, original Islamiya ERP or production business operations.

## Read-only six-report bundle

`internal/enterprise-client/c10_gov002_scoped_reports_v1.mjs` exports:

- `createGov002ReportReader(signedReviewClient)`: reads the existing three signed-user RLS projections via the already built PR83 client. Every read authenticates again; server RLS and effective grants remain authoritative. It fails the whole report if any one source fails.
- `summarizeScopedApprovalPages(...)`: validates 1 explicit business, page-size <=1000, server-returned business/row IDs and duplicate IDs, source version, fingerprint and status. Produces (1) approval status, (2) pending summary and stage counts, (3) bounded exception/escalation, (4) reviewer event activity, (5) rejected/withdrawn analysis, and (6) source-linked evidence and business approval history. All results are **bounded page observations**, NOT definitive full-history aggregates or certified GOV-003 audit.
- `coverage=SERVER_SCOPED_FIRST_PAGE_ONLY`, `may_have_more` and per-source page sizes prevent a synthetic or truncated summary from being mistaken for whole-business totals. The RLS client itself has existing upper bound of 1000 rows, so the report never claims to scan beyond the first page.
- Rejects malformed/mixed-business or duplicate records without a fallback. Local output omits source raw payload and exception freeform reason. No CSV assembly or direct DB access is added; the existing PR82/83 safe one-business activity CSV remains the only export contract.
- Apparent execution/movement references in source data are **labelled synthetic or uncertified**, never an operational posting/reversal receipt.

## Seven fail-closed operational integration ports

`internal/enterprise-client/c10_gov002_domain_adapters_contract_v1.mjs` exposes immutable, typed, **non-executable** descriptors for:

1. Inventory adjustments
2. Stock transfers
3. Purchase operations
4. Sales exceptions
5. Production exceptions
6. Financial approvals
7. High-risk administrative changes

The port descriptor has a validated business, optional required site, source reference, source version and configured unit `BDT`, `KG`, `LB`, or `PCS`. Frontend role, tenant, actor, policy, purported receipt, fingerprint or service-role claims are rejected. All seven return `BLOCKED_CANONICAL_DOMAIN_ADAPTER_NOT_CERTIFIED`, `side_effects_enabled:false` and explicit missing contract gates; NONE of these descriptors invokes any posting, reversal, bypass or approval decision RPC. Currency conversion and amount valuation are intentionally absent. The authoritative source and identity must be re-derived by certified domain service and A034 authorization before a real approval becomes eligible.

## Test/evidence and remaining gates

- `tests/c10_gov002_scoped_reports_v1.test.mjs`: scoped positive/negative report projections, full business mismatch, duplicate IDs, tampered fingerprint, expired state, source limit, silent privacy reduction, signed client errors/denial, all seven blocked domain ports, malicious authority keys, invalid source/site/units. Node tests require no actual business DB.
- `.github/workflows/c10-gov002-review-ui.yml` extended to run the new tests **along with** full parent PostgreSQL17 integration/E2E and real two-session race suites, existing signed-client/CSV tests and real Chromium 390px/1440px browser tests.
- **Not built:** actual certified production command handlers and posting/reversal adapters, real GoTrue/A034 privilege parity, 3+ stage policy/risk/FX, signed comprehensive exports, GOV003 audit engine, deployed enterprise owner integration, SG backup/migration/rollback and release.
- **Owner preservation:** C10-D051/R130 original Islamia ERP, protected archive, theme/identifiers/records and original interface untouched. No changes to Codex Build01 or Claude GOV003 source.
- **GOV002 master matrix:** all 12 rows remain `PLANNED_DETAIL_NOT_CERTIFIED`; overall `MODULE DELIVERY` remains `NOT_COMPLETE_PER_DETAIL`.

Do not display raw page metrics as global authoritative totals; do not attach execution controls to port descriptors; do not claim certified source posting from the `c10_demo` synthetic movement reference.