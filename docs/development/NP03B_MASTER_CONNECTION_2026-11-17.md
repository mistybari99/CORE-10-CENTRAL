# B-014 / NP03B — canonical Master connection

Date: 2026-11-17. Local verification is complete below. Exact pushed-head CI and delivery evidence are recorded in Draft PR109 and the live Board; this document is not operational certification. It updates the Master-disconnected description in the [2026-11-16 UI handoff](NP03B_SALES_UI_HANDOFF_2026-11-16.md) only to the extent described below.

## Actual source reused

| Existing source / owner | Actual reuse and boundary |
| --- | --- |
| NP02 `0150` Master tables | Existing canonical `items`, parties, UOMs, item variants and price-list rows hold disposable fixture data. No Sales copy of Master identities or pricing tables. |
| NP02 `0151_np02_master_rpc` | Calls the real internal `master_validate_sales_order_v1(bigint,bigint,jsonb) RETURNS boolean`. It checks active scoped customer/item/variant/UOM graph, sales price-list site/date eligibility and authoritative quantity tier. The function remains unavailable to direct authenticated callers. |
| NP02 `0152_np02_master_read` | Reuses authenticated business-scoped readers, including `master_get_price_list_v1` and `master_list_uoms_v1` for Sales validation. Master reads require signed actor plus `can_see_business`; that does not independently authorize Sales. Reader lists use bounded keyset pagination. |
| NP02 `0153_np02_master_request_lock` | Existing transaction advisory lock serializes Master writes by business/request key. Preserved unchanged; this is Master write replay, not a new Sales pricing or historical snapshot guarantee. |
| NP06 `0400_np06_finance_foundation` | Existing journal/account/period foundation inspected as downstream source. No Sales invoice, collection, refund or journal adapter is wired here; no Finance source is copied. |
| NP03B `0300` / `0301` | Own scoped Sales aggregate, expected-version/idempotency receipts, Auth/Control/approval and canonical audit command flow. Save and confirm invoke Sales validation. No stock or financial posting. |
| NP03B `0302` | Own read projection of the one canonical Audit stream through Sales command receipts. No new audit ledger. |
| NP03B `0303_np03b_master_connection` | Own replacement of the Sales validation helper adds missing currency/UOM/price-precision/tax fences around the accepted Master ports. No Master-owned function/table is modified. Down restores the prior `0301` helper and preserves Master. |

`tests/np03b/fixtures.sql` now inserts synthetic data into actual canonical Master tables and refuses to run without the real validator and pricing table. It no longer creates a synthetic implementation of the validator. The fixture remains disposable-only and refuses databases containing `auth.users`. Customer, catalog and prices are synthetic; Auth claims remain inert test UUIDs, not hosted users or GoTrue verification. Tests temporarily renaming the actual validator exercise missing-port rejection inside a rolled-back transaction.

## Validation behavior in 0303

The accepted Master validator remains authoritative for references and the applicable current price tier. FALSE/NULL raises `SALES_MASTER_REJECTED`; an absent validator raises `NOT_CONNECTED:MASTER_SALES_VALIDATION`. Sales does not recreate tier selection.

`0303` fills gaps not checked by the current Master validator:

- Currency must equal the canonical price-list header from `master_get_price_list_v1`; mismatch raises `SALES_CURRENCY_MISMATCH`. Missing required reader signatures raise `NOT_CONNECTED:MASTER_SALES_READERS`.
- Quantity must respect the active canonical UOM's decimal precision from `master_list_uoms_v1`; violation raises `SALES_UOM_PRECISION`. The preexisting Sales six-decimal and configured quantity limits still apply. A count UOM with decimals zero refuses fractional units; a mass UOM with decimals three accepts `0.125`, not `0.0001`.
- Unit price permits four decimal places, matching Master pricing precision, separately from configured money rounding. Total remains the sum of each line's rounded gross amount. For example, quantity `2` at `300.1234` rounds to `600.25` with money scale two; this passed in the disposable canonical-Master integration test.
- Nonzero tax fails closed. With Owner tax disabled, the existing `SALES_TAX_DISABLED` fence applies; even when enabled, absence of a canonical tax contract raises `NOT_CONNECTED:MASTER_SALES_TAX`. An enable switch is not tax authority. Zero-tax examples do not establish statutory policy.

Confirm revalidates the saved document against **current** Master state. `0151` selects active lists whose dates include database `current_date` and the active matching item/variant/UOM price with highest `min_quantity` not above ordered quantity. A changed price can reject confirmation of an earlier draft; confirmation does not silently replace its saved price. Inactive/expired/wrong-site references likewise fail. No immutable historical pricing snapshot, historical-date repricing guarantee or transaction-wide Master version lock is established by this connection. `0153`'s request lock does not provide those guarantees.

## Reader projection and host lifecycle

The Sales catalog projection is a deliberately limited flat view: customers, price lists and selectable item/variant/UOM rows with one price per listed price list. The server supports quantity tiers; a single projected flat price cannot express every tier or guarantee acceptance after a quantity change. Keep server rejection visible and reload accepted Master data as needed. Do not label a displayed base price as a guaranteed historical or tier-complete quote.

`core10-sales-master-catalog.js` exports `CORE10_SALES_MASTER_CATALOG.create({client,lang})` with `load({businessId,siteId})`, `destroy()` and non-private `getState()`. Every RPC verifies the pinned signed identity before and after, uses only schema `core10` and invalidates on Auth events. Readers page completely within bounds or fail explicitly; they never present truncated pages as a complete catalog. Missing/invalid scope and partial stale responses fail closed.

The UI offers the safe common intersection of active base-item/base-UOM prices across eligible sales lists. Base tiers with one minimum of zero or one are supported; multiple tiers, variant-only pricing and required UOM conversions explicitly fail closed. The server still supports actual tier and variant validation; this deliberately narrower picker does not replace it. Canonical bilingual labels follow local language toggles, and quantity minimum/step uses canonical UOM decimals. Projection `source:'canonical_master'` identifies real Master data even when the local harness uses synthetic Auth. Signed mode refuses `synthetic_fixture` data.

Load `core10-sales-master-catalog.js` before `core10-sales-order-entry.js`. With no custom provider, the entry owns and wires the adapter automatically:

```js
const sales = CORE10_SALES_ORDER_ENTRY.attach(host, {
  client: existingSignedClient,
  backendMode: 'signed',
  lang: 'bn',
  initialScope: { businessId, siteId }
});
await sales.ready;
// On host route/context disposal:
sales.destroy();
```

The entry cleans up partial mount failures and destroys its owned catalog on Auth invalidation/disposal. A host supplying its own `catalogProvider` retains that provider's lifecycle. No login, Supabase project, route or deployment is created here.

The canonical host owns its existing authenticated client, login/configuration and navigation. Load incumbent CSS plus Sales CSS, then Sales client/UI/entry scripts and the new catalog adapter as its dependency contract requires. Create the catalog adapter with the host client; pass its `load` function through `catalogProvider` and the canonical selected `initialScope:{businessId,siteId}` to `CORE10_SALES_ORDER_ENTRY.attach`. Initial scope is checked against fresh context with manageable business and matching site; invalid input is denied without fallback.

On route/session/actor/business/site replacement, destroy the UI controller **and** the catalog adapter, clear old state, resolve fresh context and create new instances. A session-invalidated adapter must not be reused. Preserve generation guards against stale responses, immediate sign-out clearing, explicit discard of unsaved forms and response-uncertainty locks until exact-key Retry. No edits to the shared host route, login shell or global tokens are included here. The incumbent navy/mint/beige palette and system/Bengali type remain the visual authority.

## Verification status and executable checks

Local checks completed as recorded below; hosted signed authentication remains NOT_RUN. Exact-head CI is reported separately after push. Prior handoff results are historical checkpoints.

Authored `tests/np03b/master-integration.sql` covers canonical valid orders; currency and UOM precision; supplier/foreign/inactive customers; wrong variants; changed-price confirm atomic rejection; expired/wrong-site lists; inactive item/UOM/price; tier price acceptance/rejection; four-place unit prices; nonzero-tax refusal even with Owner tax enabled; mass-unit decimals; internal helper closure and anonymous/foreign reader denial. The suite passed on the disposable PostgreSQL17 database.

On a fresh isolated PostgreSQL17 database matching the fixture guards, apply the complete ordered migration set and execute:

```sh
internal/migrations/run.sh up
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/sales-orders.sql
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/master-integration.sql
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/audit-read.sql
```

Use disposable environment variables and test roles as in the NP03B workflow. The browser, adapter, concurrency and migration tests above were run for this increment; exact-head GitHub CI is separately recorded in PR109. Never point these commands at hosted production.

Shared-owner coordination note: a Finance `0400` rollback guard must target Finance itself rather than assume `0400` is the highest migration. NP05A `0500` and later changes alter that assumption. The shared runner's `down` pops the highest applied migration, so a single generic `down` cannot demonstrate `0400` rollback once higher versions exist. Finance/test infrastructure owner must provide the correctly targeted disposable test sequence and retain populated-history guards. This document does not modify their tests or claim a Finance rollback pass.

## Executed local verification

- PostgreSQL17: all35 migrations up → down → up and idempotent up PASS, including0303 rollback restoring0301 and retaining canonical Master.
- Existing Sales security/approval/idempotency/RLS/atomic-audit tests PASS with actual Master fixtures; scoped audit-reader suite PASS.
- New `master-integration.sql` PASS: real active graph, foreign/supplier/inactive customers, variant mismatch, site/date/price change, authoritative tier selection, unit-price4 versus amount rounding, currency and UOM decimals, zero-tax fence, unavailable-reader rollback and no failed-confirm receipt.
- Two-session duplicate replay, CAS amendment and Control-disabled-while-waiting PASS. Canonical Master RPC regression PASS.
- Control registry/evidence PASS:20 enforced,7 exempt,11 inherited pending; both Sales mutations remain actually enforced/defaultOFF. No new mutating RPC in0303.
-13 existing Sales client +14 Master adapter mock contracts +2 entry lifecycle tests PASS. Mocks do not certify hosted Auth.
-43 real-browser checks PASS at1440px English and390px Bangla against actual Sales/Master SQL, with inert UUID Auth and synthetic canonical fixture records. Includes native count precision, bilingual product/customer/UOM labels, audit, read denial, missing reader, Master change after load, signout/stale completion and exact-key retry after real committed response loss.
- Fresh [desktop screenshot](../evidence/np03b/sales-order-desktop.png) and [mobile screenshot](../evidence/np03b/sales-order-mobile.png) are committed. No public preview or hosted validation was run.

## Exact shared-owner requests

1. **NP01 Auth:** accept and register Sales-specific read/write/confirm/cancel actions and canonical context resolution. Current owner `can_manage` plus explicit site `stock.read` fence remains; Master visibility or stock permission alone must not grant Sales.
2. **Central route owner:** register the existing module in its authorized route/menu, supply the canonical selected scope and real shared client, instantiate the catalog adapter, and destroy/remount both on context changes. Local harness navigation is not completed host integration.
3. **NP02 Master / tax owner:** accept a scoped authoritative tax/currency contract before lifting zero-tax-only behavior; agree quantity-tier projection and price/version stability semantics before claiming historical quote guarantees. Preserve existing Master reader and validator ownership.
4. **NP06 Finance / shared test owner:** repair the `0400` target assumption for a migration set containing NP05A `0500+`, then publish actual disposable rollback evidence. Separately agree immutable Sales invoice/collection/refund source linkage; the present Master connection does not implement it.

Permanent hosted sign-in, Sales authorization, canonical navigation, tax integration, invoice/POS/collection/returns and Stock/Money adapters remain NOT_DONE. Exact final source, tests, CI and coordination evidence belong in the integration lead's PR/Board after verification and push. No external message, upload, deployment, production migration or merge is part of this documentation artifact.
