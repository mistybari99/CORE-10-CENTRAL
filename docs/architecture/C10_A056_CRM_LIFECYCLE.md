# C10-A056 Universal CRM, Customer Lifecycle & Sales Integration

Status: DRAFT source build, disposable PostgreSQL only (PR #66). Not production, not GoTrue-verified, no real messaging, no real finance.
Namespace: everything is `a056_*` in schema `c10_demo` (files `internal/enterprise-sql/c10_a056_{core,pipeline,growth}_v1.sql`).
Legacy Islamiya `crm_*.js`, `customers.js`, `website.js` are untouched and are NOT the source of this module.

## Canonical dependencies (reuse, never duplicate)
| Dependency | How A056 uses it |
|---|---|
| A018/A019 tenancy (`actor_uid`, `can_manage`, `can_business`, `can_site`, `can_see_business`) | Single authorization root; checked live on every call, so role revocation is immediate. No second permission system. |
| A049 `create_operation_order_v1`, `read_operation_overview_v1` | The ONLY order integration. Accepted quotation lines become A049 **draft** `sale_issue` orders; fulfilment/posted state is read back via the overview contract. A056 never writes A049/A048 tables (CI asserts the SQL contains no such statements). Confirm/post stay in A049. |
| A047 sites / A046 personas | Site-scoped rows (`site_id`) use A018 site grants. Tests use A046-compatible synthetic UUIDs. |
| A022 / finance read models | No certified customer-receivable read model exists in the repo. A056 exposes a **registry** (`a056_register_finance_source_v1`, Owner only) and shows `NOT_CERTIFIED` / `UNAVAILABLE` / `RESTRICTED` with `null` balances until an Owner registers a certified function. |
| A050 | Same conventions (idempotency keys, versioned writes, signed client). |

Load order: A018 backend + seed, A020, A018 inventory, A048, A049, A050, then `c10_a056_core_v1.sql`, `c10_a056_pipeline_v1.sql`, `c10_a056_growth_v1.sql`. Rollback: drop the `a056_*` tables/functions (additive; nothing else references them).

## Verified journey (tests/c10_a056_crm_lifecycle_e2e.sql)
Lead -> Enquiry -> Opportunity -> versioned Quotation (approval rule, self-approval blocked) -> accepted -> A049 draft order (owner) -> confirm/post in A049 (stock) -> Purchase history/fulfilment `posted` -> Won (only after order) -> Invoice/Payment status (NOT_CERTIFIED until registered) -> Ticket/SLA/resolution evidence -> Follow-ups -> Campaign (consent-aware, NO-OP) -> Reports (dashboard, funnel, retention, repeat business, follow-ups, tickets).

## Design rules
- **Tenancy/RLS**: every table is tenant+business(+site) scoped with RLS enabled; `authenticated` has SELECT-only through row policies (site staff see only their sites), **no** INSERT/UPDATE/DELETE; idempotency, suppression and intake-token tables have no direct grant. All writes go through SECURITY DEFINER RPCs that re-derive authorization. Internal helpers are not executable by `authenticated`/`anon`.
- **Action tiers** (owner/manager/site) come from the versioned, Owner-editable config (stages, permissions, approval rules, SLA, loyalty, intake limits). Invariants cannot be weakened: `settings.write`, `customer.redact`, `finance.register` stay Owner; consent/opt-out and certified-finance rules are not configurable. Module is OFF until an Owner enables it. "Site tier" = any active A018 site grant for that site (the grant model has no CRM-specific actions yet; documented limitation).
- **Idempotency & concurrency**: every write takes a request key (replay returns the original receipt, conflicting reuse fails); advisory lock per key; `FOR UPDATE` + expected versions for merge, quotation revision, stage moves, tickets. `tests/c10_a056_concurrency.sh` proves one-winner behaviour with real parallel sessions.
- **Audit**: append-only `a056_audit` (UPDATE/DELETE/TRUNCATE blocked by trigger); settings history keeps every config version.
- **Customers**: tenant/business customer + organization/contacts, duplicate candidates (email, phone, contact email, name), safe merge (children moved, loser kept as `merged` with snapshot in `a056_merge_log`, loser opt-outs carried to survivor, cross-business merge refused).
- **Consent**: append-only events per channel/purpose; no consent => no send; opt-out creates a suppression keyed by customer and hashed address that wins over any later grant (also across duplicate records) until an authorised, audited lift; marketing opt-out does not block service messages, service opt-out blocks both. Public-intake consent is only a *claim* applied after staff triage and never overrides opt-out.
- **Campaigns**: provider-neutral **NO-OP** only (`provider='NOOP'`, `sent` always 0, statuses `NOOP_NOT_SENT`/`BLOCKED_NOT_SENT`). Real SMS/e-mail/WhatsApp activation is NOT ENABLED.
- **Intake**: per-endpoint token (only sha256 stored, shown once), rate limit, idempotency key, strict payload whitelist/size cap. Public requests become `RECEIVED` (or `DRAFT` for order requests) enquiries; no order, stock, payment or refund is ever created. Return/refund requests are tickets only.
- **Privacy**: export package, CSV export with formula-injection neutralisation (`a056_csv_cell`), owner-only redaction that clears PII everywhere, blocks while work is open, keeps hashed suppressions. HTML is stored inert; renderers must escape (`core10-crm-lifecycle-engine.js` `escapeHtml`).
- **Reports**: counts come from CRM records; money from quotes is advisory; rates are `null` (not 0) when the denominator is 0. Retention/repeat use A049 `posted` status; the purchase date is the CRM order-link date because the A049 overview exposes no posted date (labelled in the response).

## Isolated test adapter
`a056_test_adapter_create_order_v1` (recorded `adapter='TEST_ADAPTER'`, no A049 order, fulfilment always `unavailable`) works only when the A049 contract is absent or simulated absent (`a056.simulate_a049_missing=on`) on a disposable database; otherwise it raises `A056_USE_CANONICAL_ADAPTER`. `a056_test_finance_*` functions exist only inside the test file to exercise the finance registry.

## JS
`core10-crm-lifecycle-client.js` (signed RPC wrappers with arg validation, error-code extraction, public intake, HMAC envelope helpers) and `core10-crm-lifecycle-engine.js` (pure BigInt money/quote maths, consent/SLA/funnel/segment logic, escaping). Node tests in `tests/c10_a056_{client,engine}.test.js`; the client test also checks SQL/contract name sync.

## Known gaps / not claimed
Not tested against GoTrue or production Supabase; no certified finance read model (A022 is funding-only); no loyalty points ledger (config only); no real notification provider; no booking engine; business-hours SLA calendars are not implemented (calendar hours); site-tier uses A018 site grants; A049 overview gives no posted timestamp. Root `AGENTS.md` fails the inherited `forbidden_files` check from the Preview V1 base; A056 files add no offenders.
