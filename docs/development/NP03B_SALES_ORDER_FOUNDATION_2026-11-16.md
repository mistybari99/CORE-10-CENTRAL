# B-014 / NP03B first increment: non-posting Sales Order foundation

Audit baseline: trunk `f34459f06291bba7d4a709ce6f7c21c25b804b1a`. Before delivery, fast-forwarded
latest trunk `48d78955c6d98b9f39fc044dcbf6860acbd76cdc` (no rebase/force-push). B-014 was OPEN; Codex claimed
`build/codex-np03b-sales` and `0300–0399` in the live Coordination Board `Untitled!A16:M16`,
then read the row back on 2026-11-16. The shared checked-in reservation file is trunk-owned
and has not been edited. Draft PR targets `ccr-15ed11dd-n3hw5h`, never main.

## Implemented scope and reuse

See [source/diff reuse matrix](NP03B_SALES_REUSE_AUDIT_2026-11-16.md). No historical PR was merged.
`0300` adds a customer order aggregate with scoped header/lines and command receipts.
It is distinct from A049's single-item inventory operation instruction. `0301` adapts
A026 multi-line validation and A049 Auth-before-replay / row-lock / expected-version patterns,
using the existing Auth, Control, Approval and canonical Audit implementations unchanged.
No second stock, financial, customer, item, role or approval engine was added.

RPCs (all `core10`):

| RPC | Contract |
| --- | --- |
| `save_sales_order_v1(business,site,order,expected,document,key)` | `order=NULL,expected=0` creates; existing order requires current version and draft state. Payload- and actor-bound exact replay returns its original receipt. Lines are atomically replaced on amendment. |
| `transition_sales_order_v1(business,site,order,action,expected,approval,key)` | `confirm` or `cancel` from draft only. Locks the live order and checks current Control stages, exact source/version/payload, approval expiry and route cardinality. Confirm revalidates Master, current limits and totals. No fulfilment/reservation/posting. |
| `read_sales_orders_v1(business,site,order=NULL)` | owner-authorized site-scoped read, at most latest 100. No direct API table access. |

Document shape: `{customer_id,price_list_id,currency,lines:[{item_id,variant_id?,uom_id,
quantity,unit_price,discount_percent,tax_percent}]}`. IDs reference canonical Master;
no free-text customer copies. Unknown properties and nonnumeric/missing/negative/overprecision
values are rejected. Totals use exact PostgreSQL numeric, per-line gross rounding to the
configured `money_scale`; this is a disclosed calculation contract, not jurisdiction/tax advice.

Every successful command appends exactly one canonical audit event in the same transaction.
Command receipts are scoped, closed to API roles, and link to that canonical event. All three
tables have default-deny RLS, composite scope FKs and no API table/sequence grants. No PUBLIC
execution; internal helpers are also closed to authenticated. Rollback of `0300` refuses to
erase populated order history. `0301` rollback refuses while append-only Control settings
reference its catalog rows; integration rollback on a populated system requires a forward plan.

## Owner Control and approval

Both features default **OFF**. `sales.order_draft` configures max lines, quantity, discount,
order total, money scale and tax enabled (default false). `sales.order_transition` configures
0–5 approval stages (default 1). Both mutations call their exact mapped `control_check_v1`
after Auth and before replay. Disabled negative tests are in `tests/np03b/sales-orders.sql`;
both registry rows are enforced with that CI-run evidence reference.

Approval payload: `{order_id,site_id,version,document,total,action,required_stages}`;
source key `sales-order:<id>`, source version is the locked current order version, domain
`sales`, action `confirm` or `cancel`. Approval maker must be the latest order editor.
Canonical GOV002 implements maker/checker. Sales verifies exact current stage count and
also checks the current `gov002.review` switch, because NP01 review bindings are still pending
on this trunk. Cancellation of confirmed orders is blocked until fulfilment/reversal contracts
are implemented. One-time Control exception consumption follows the canonical port semantics,
including on exact retries; it is not a second Sales override implementation.

## Coordination requests — required before integration/operational completion

1. **NP02 Master / B-011:** accept or replace this proposed internal port:
   `core10.master_validate_sales_order_v1(bigint business,bigint site,jsonb document) RETURNS boolean`.
   It must validate the complete customer/item/variant/UOM graph, active scope, immutable
   price-list version identity, authoritative unit prices, currency and tax configuration.
   It must stabilize the validated Master versions for the transaction (appropriate row locks
   or immutable versions). TRUE must mean the full input is valid. No caller-supplied role,
   price or tax can be trusted. NP03B probes for the signature and raises
   `NOT_CONNECTED:MASTER_SALES_VALIDATION` when absent; FALSE/NULL is rejection.
   **This is a proposed contract, not a verified existing Master API.** The sole implementation
   in this branch is a deliberately synthetic test double outside migrations. Production order
   creation/amendment/confirmation therefore remain blocked on current trunk.
2. **NP01 Auth:** register Sales read/write/confirm/cancel/cashier/return/refund actions in the
   canonical allow/deny/expiry resolver and shell context. Until accepted, this increment is
   restricted to `can_manage` owners, plus `can_site(...,'stock.read')` as an additional explicit
   site-deny fence. Stock permission alone never authorizes Sales. Managers/cashiers/agents are
   denied, rather than getting invented Sales grants. Full Sales permission acceptance is pending.
3. **Claude trunk infrastructure:** reconcile reservation owner in
   `docs/coordination/MIGRATION_RESERVATIONS.json`. The initially detected fixed catalog-size
   assertion was fixed independently by Claude in trunk `8b6ed24`, including the browser test;
   latest trunk was fast-forwarded before delivery. NP03B did not edit those owned files.
4. **NP03A:** accept Stock fulfilment/reservation/return adapter contracts before implementing
   any order fulfilment. No stock movement/reservation is claimed in this increment.
5. **NP06 / PR108:** agree immutable invoice/collection/refund source keys, allocation and
   reversal contracts. The draft Finance engine is not copied or installed here.
6. **Shell/CRM:** later replace A056 conversion boundary with a canonical header/lines adapter,
   and register navigation through canonical context. Existing UI was inspected and preserved.

## Reproducible synthetic validation

Local target: isolated Docker `postgres:17`, database `core10_np03b_ci`; no host ports exposed.
Tests refuse other database names and any database containing `auth.users`. The fixture reuses
A018 topology and all 16 A046 UUID aliases; it does not create signed Auth users. Two owner
aliases exercise make/check; all other aliases are explicitly denied for business 101. This
is **16-persona scope coverage, not 16-persona successful end-to-end Sales certification**.

Five illustrative sweets products: Rasgulla Box BDT300, Sandesh Box BDT420, Mixed Sweets 1kg
BDT850, Chocolate Cake BDT1200, Butter Cookies BDT250. Synthetic customer `7001`, variant/UOM,
retail `7101`, wholesale `7102` at 90%, tax zero, configurable discount and approval cases.
No legal/tax policy or production pricing is implied. Fixtures are deterministic, transactional
and rolled back; the two-session suite creates and drops its own disposable race database.

```sh
node --test tests/migrations/migration-contract.test.js
bash tests/migrations/run-updownup.sh
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/sales-orders.sql
bash tests/np03b/concurrency.sh
psql -X -v ON_ERROR_STOP=1 -f tests/migrations/control-registry-check.sql
bash tests/migrations/control-registry-evidence.sh
```

Evidence results and exact pushed SHA/CI links are recorded in the Draft PR and live Board.
Do not substitute baseline trunk CI or an earlier local run for exact-head CI.

## Still not done

Canonical Master acceptance; Sales-specific Auth; integrated approval submission UI; full
2–5-stage Sales persona journeys; CRM adapter; ATP/reservation/backorders; invoice numbering,
issue/credit lifecycle; POS sessions/tenders/receipts; collection/refund and bounded returns;
Stock/Money adapters; signed hosted Supabase Sales tests; Central-shell UI at 390/1440 and
visual screenshots. No UI/screenshot or full Order→Invoice→Collection→Return success is claimed.
The independently safe foundation is testable, but the complete first S1 deliverable remains
NOT_COMPLETE until its canonical dependencies are resolved and exact-head CI is green.

No hosted migrations, hosted seed/Auth users, Supabase/Cloudflare deployment, merge, live
identity/payment, production secret or IMG-ERP-SG operation was performed.
