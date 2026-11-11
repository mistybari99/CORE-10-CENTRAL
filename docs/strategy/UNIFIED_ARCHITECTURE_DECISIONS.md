# Unified Architecture Decisions

**Status:** proposed technical architecture under existing D030–D050/R123–R129; not a new Owner decision or release approval.

## Architecture verdict

Use a modular PostgreSQL-backed monolith now. Extract services only after measured contention or isolation need. Preserve:

`platform → tenant → legal entity → business → operating site → custody/stock location/device`

Bounded contexts own typed writes: Identity/Scope, Party, Catalog, Agreements, Commercial Documents, Fulfilment, Inventory, Manufacturing, Projects/Work Orders, Workforce, Finance, Approval, Reporting, Integration and Audit.

## Decisions

| ID | Decision | Guardrail |
|---|---|---|
| UAD-001 | Reuse A018/A019 hierarchy and additive legacy crosswalk pattern | no rewrite of legacy PKs or mass FK migration |
| UAD-002 | One canonical stock quantity book evolving A018/A048 | packs cannot own balances/movements |
| UAD-003 | Separate order, fulfilment, invoice, journal and settlement events | stock movement never implies revenue/payment |
| UAD-004 | One typed double-entry posting boundary | DR=CR, source/version/currency/period/reversal required |
| UAD-005 | One effective authorization service compatible with A021/A034 | visibility/configuration never grants authority |
| UAD-006 | One typed approval/exception service | payload fingerprint and policy version bind approval |
| UAD-007 | Versioned effective configuration inheritance | invariant→tenant→business→site; explicit deny wins |
| UAD-008 | Industry packs are manifests plus typed extensions | no alternate party, permission, stock, journal or audit stores |
| UAD-009 | Immutable command/idempotency receipt plus outbox | guarantee one local effect; reconcile external outcomes |
| UAD-010 | Reports are source-linked read models | zero, missing, provisional and stale are distinct |
| UAD-011 | Strangler migration uses bridges and read comparison | no uncontrolled production dual-write |
| UAD-012 | PR #27 is the integration framework | Drive/channel providers extend it; no second outbox/secrets engine |
| UAD-013 | Offline captures draft/bounded intent only | server reauthorizes; no cached stock/money authority |
| UAD-014 | A055 is candidate shared physical asset/maintenance code after parity | do not create another generic work-order engine |
| UAD-015 | Contextual task Presentation Contract is non-authoritative | no grants, executable rules, formulas, SQL/code or secrets |

## Command and event contract

Every mutation carries tenant/business/site, stable request ID, payload fingerprint, actor derived from signed session, expected version and typed command. Same key/same payload returns the prior result; same key/different payload conflicts. Domain commit and outbox record are atomic. Provider callbacks are verified by a backend identity and reconciled idempotently.

## Financial and inventory invariants

- DR equals CR per source document and currency basis.
- Stock quantities are conserved; negative stock/duplicate serial/stale count fail atomically.
- Transfer has zero revenue; sale/return and COGS remain source-linked.
- Unknown cost, tax policy or FX rate is `INCOMPLETE/NOT_CONFIGURED`, never zero.
- Posted corrections use linked reversals/compensating documents, never delete history.
- Closed period, revoked identity and stale approval block execution.

## UX/workspace model

Daily entry points are Sell, Buy, Receive, Transfer, Produce, Count, Serve, Approve, Pay, Close and Review. Each resolves to a typed step and shows what changes now, what does not, approval, result location, source/calculation and truth state. Quick/Advanced are views over one engine. Renderer families are simple command, document editor, scan/count, approval, reconciliation, schedule/board and exception recovery; high-risk flows use purpose-built components.

## Owner approval required

Production migrations/RLS, `org_scope_on`, real GoTrue stage/prod identities, partner finance repair adoption, live OAuth/providers, paid tiers, deployment/main merge, A024 commercialization and A025 simulation remain separately gated.
