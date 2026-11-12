# CORE 10 CENTRAL — GOV-002 additive Approval UI draft

**Scope:** isolated stacked Draft PR on #83. Source-built UI with real connector contract, not deployed/merged or production-certified. Original Islamiya Misty Ghar ERP UI and archival branch remain untouched (C10-D051 / R130).

## UI surfaces

Responsive at 390px and 1440px: business selector; Owner/maker business-scoped Approval Inbox; pending, approved, rejected, deferred, withdrawn, expired and all tabs; source request detail and version; Stage 1/2; Approve / Reject / Defer / Withdraw with deliberate confirmation; bounded non-bypass escalation request and triage; source-linked Activity Timeline; first-page, business-scoped CSV; explicit synthetic/permission/expired/scope-error states. Bangla-first with familiar English labels. No sales/stock/finance posting UI.

## Integration and safety

`mountSignedGov002Workspace({root,supabaseClient,businessId,businesses,allowSignedMutations,environmentLabel})` is opt-in only, called by a future authorized host. It constructs the existing `createGov002ReviewClient` signed-user adapter (#83), which calls `auth.getUser()` for each operation. The backend's security-invoker projections, RLS, RPC actor identity and business checks are always final. `businesses` are display-only; never grant permissions. Local filter, expired-state display and hidden/disabled buttons are never authorization. Recheck maker-checker, explicit deny, revocation, RLS and fingerprint inside canonical server RPC.

Default `allowSignedMutations:false`; only enable after authenticated staging authorization and Owner gate. No automatic legacy integration and no change to `main` or public Preview One. Static preview under `docs/preview/c10-gov002-approval-preview.html` uses synthetic fixtures, with all actions disabled. It is not a GoTrue test.

## Tests

- PG17 fresh disposable A018→A008 full stack regressions with actual two-session races, unchanged from prior draft suite.
- Node status classification, source/business mismatch fail closed, duplicate identities, approval and exception eligibility, error redaction and no UI posting functions.
- Real browser Playwright/Chromium at 390 and 1440; confirms status tabs, scoped business switch, escalation, activity, no overflow, fixture-disabled actions, DOM escaping, confirmation before mock RPC, one mock decision and no repeat action.
- No real Singapore Supabase GoTrue, A034 effective permission parity, approved migration/backups, release, UI visual design certification or production-domain stock/finance effects.

## GOV-002 12-item acceptance (source-built vs certification)

| Atomic feature | Current draft evidence | Master Detail certification |
|---|---|---|
| Typed approval request | #78 typed submit, #83 review API | NOT_CERTIFIED |
| Maker-checker separation | #69/#78 RPC + PG17 negatives | NOT_CERTIFIED |
| Versioned approval policy | #78 version pin, #80 immutable threshold | NOT_CERTIFIED |
| Multi-step routing | #79 two-step, not arbitrary N-step | NOT_CERTIFIED |
| Bounded delegated approver | #79 ≤24h manager delegation, no A034 parity | NOT_CERTIFIED |
| Threshold and units | #80 BDT/KG/LB/PCS, no generalized FX | NOT_CERTIFIED |
| Stale payload handling | #81 synthetic bound digest/version/receipts | NOT_CERTIFIED |
| Approval expiry and withdrawal | #79 server RPC, UI expired states | NOT_CERTIFIED |
| Concurrent decisions | #79/#81/#82 real two-session races | NOT_CERTIFIED |
| Exception escalation | #82 bounded advisory, this UI triage | NOT_CERTIFIED |
| Approval inbox privacy | #78 scoped views, #83 signed adapter, this UI | NOT_CERTIFIED |
| Execution and reversal link | #81 **synthetic KG only**, no production domain | NOT_CERTIFIED |

**Remaining blockers:** actual signed GoTrue/A034 grant+deny+expiry/revoke staging proof; canonical business/site integration; certified source-bound operational adapters; >2 step and policy risk routing; report exports with server-end authorization & pagination/provenance; comprehensive staged browser/CI security and accessibility; Singapore backup/migration/rollback and Owner release. GOV-003 owned by Claude separately.