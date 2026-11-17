# NP06 / B-013 — Canonical Money Port foundation (0400)

**Status:** backend foundation candidate on `build/chatgpt-np06-finance`. Disposable PostgreSQL 17 only; not production-ready. This document is not a migration/deployment GO.

## Authority and non-duplication

- Integration base: `ccr-15ed11dd-n3hw5h` at `a9cc3b3e1cb0cabb90cda456e8c505b1e32bbd20`.
- Single Money port: `core10.finance_accounts_v1`, `finance_journals_v1`, `finance_journal_lines_v1`, `finance_periods_v1`. No parallel journal, subledger, auth, approval, audit, or stock balance store.
- Prerequisites: existing `core10.actor_uid`/`can_manage`/`can_see_business`, `core10.control_check_v1` and `core10.control_rpc_map_v1`, and `core10._append_canonical_audit_v1`.
- Migration `0400_np06_finance_foundation.up.sql` with matching rollback. The down migration refuses to erase any finance/accounting or control-history data. Apply only with the canonical migration runner after previous blocks are in place.

## Server-facing Finance RPCs

| RPC | Purpose | Auth scope | Control key |
| --- | --- | --- | --- |
| `finance_create_account_v1` | tenant + business + legal-entity scoped CoA, type/parent and duplicate guard | `can_manage` | `finance.coa` |
| `finance_set_account_active_v1` | activated/deactivated account; active-child guard | `can_manage` | `finance.coa` |
| `finance_set_period_v1` | explicit open/close by month and currency; audit receipt | `can_manage` | `finance.period_manage` |
| `finance_draft_journal_v1` | source-linked draft with exactly scoped accounts and idempotency payload hash | `can_manage` | `finance.journal_draft` |
| `finance_validate_journal_v1` | validate debit = credit, positive amounts, posting account state | `can_manage` | `finance.journal_validate` |
| `finance_post_journal_v1` | atomic posted journal plus immutable canonical audit receipt | `can_manage` | `finance.journal_post` |

All six state-changing functions are mapped to the existing Control registry with status `enforced`, no separate control engine. Non-Owner finance roles are intentionally **not** granted finance posting by a copied role table; permissions require a canonical Auth/Control design. Posted journals and all their lines reject UPDATE, DELETE and TRUNCATE, including privileged accidental SQL.

## Fail-closed status and boundaries

- Default `finance.journal_post` is on with **one approval stage**. Because Finance ↔ GOV-002 approval completion binding is not yet ready, the server returns `FIN_APPROVAL_NOT_CONNECTED` and does not post. An Owner can deliberately set zero approval stages with the canonical Control port for an explicitly permitted direct-post workflow; the server still verifies business, open period, amount limit, account status, and append-only audit. This is not an implementation of approved Finance posting.
- The posting adapter accepts **only canonical finance draft journal lines**. Sales, Procurement, Inventory, Payroll, reversal and credit/debit note adapters are NOT CONNECTED. No simulated adapter can silently mark its document financially posted. Future ingestion must attest source and use a documented bounded command/idempotency contract.
- Periods are explicitly opened, never implicitly opened. Posting waits for the period lock and declines closed or missing periods. Closed periods are not legal-accounting certification.
- `BDT` in tests is illustrative; no tax, localization, regulatory accounting rule, or exchange-rate policy is presumed.
- Currently the API callable Finance mutations require `can_manage` (Owner/business owner), intentionally restrictive. Accountant/cashier posting permissions require a canonical Auth-port extension, not new finance grants.
- Legal entity is inherited from canonical Business, not user-provided, and stored on accounts/journals. One journal is one currency; no cross-currency balancing or FX support.
- Account chart supports a parent ID and immediate type/currency checks. Activation and deactivation lack business-specific policy beyond Owner Control on/off. Deep hierarchy cycle tests, branch-specific chart overrides and multi-entity consolidation are deferred.
- Catalog is bilingual; Central Shell Finance screen is **NOT CONNECTED** until Claude's route contract and signed context are integrated. No mock is represented as live.
- Owner Control applies on the server. A Control override may be consumed on an unsuccessful operation only within the transaction and is reverted if an exception is raised.

## Verification matrix / evidence requirements

- `tests/migrations/np06-finance-e2e.sql`: synthetic CoA, duplicate guards, positive and negative journal validation, draft replay/conflict, post replay/conflict, approval-not-connected, zero-stage Owner configuration, amount threshold, period close, disabled feature, API grants, cross-tenant RLS, unauthorized posting, canonical audit integrity, journal and lines immutable.
- `tests/migrations/migration-contract.test.js`: naming, continuous pack blocks, rollback pair, RLS/permissions/security search paths.
- `tests/migrations/run-updownup.sh`: full migration Up → Down → Up in a disposable PostgreSQL 17 service, repeat apply for idempotency.
- `tests/migrations/control-registry-check.sql`: new state-changing Finance RPCs are `enforced` and mapped; no PUBLIC/anon execution.
- Concurrent posting requires an additional independent-session test; do not claim verified until that CI step runs green.

The Master Plan's 16 synthetic personas are **not** all verified for Finance. This increment covers tenant Owner A, business Owner A, Manager A, Investor A, foreign tenant Owner B and unassigned user at SQL permission level. Accountant, cashier, auditor and remaining persona paths require canonical permission and Central Shell integration. Do not infer signed GoTrue validation from synthetic SQL session claims.

## Dependencies and next work

1. Claude/B-010 and NP01/B-020: Control port catalog/route integration; coordinate bindings in the shared Board. NP06 never changes NP02-owned migrations.
2. Claude/NP03A and Codex/NP03B: Canonical Master/Stock/Orders sources, source-attestation and Money posting adapters.
3. GOV-002: Maker-checker finance approval route and consumed authorization receipt before any nonzero-stage posting; do not implement a parallel approval.
4. F3/F4: AR/AP document allocations, aging, reconciliation, correction/reversal, permission grants, period close/reopen governance; no claims of completion.
5. Central Shell: Signed `{tenant_id,business_id,site_id}`, bilingual 390px/1440px workflow after integration contract.
6. Follow-up test matrix: genuine concurrent sessions, duplicate source races, 16 personas, reversal, migration rollback refusal with real audit history, genuine hosted signed Auth when separately authorized.

**Deployment fence:** no hosted Supabase migration, Cloudflare deployment, PR merge, production schema or IMG-ERP-SG writes from this lane.
