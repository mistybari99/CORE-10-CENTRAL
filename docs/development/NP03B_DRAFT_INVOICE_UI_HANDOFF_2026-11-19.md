# B-014 / NP03B — draft-invoice UI handoff

Owner working date: 2026-11-19, Asia/Dhaka. This is an Operate surface extension inside incumbent Sales: open a confirmed order, save/edit its invoice draft, inspect its fixed source and audit, then validate through current Owner Control. No redesign, new app, login or authorization system is introduced.

Baseline remains latest integrated trunk `a82ae99`; no `0300–0304` migration is edited and no new migration is added. Finance CI pinning remains NP06-owned and untouched. Local verification below is executed. Exact pushed-head CI and delivery evidence are recorded in Draft PR109 and live B-014; no older green head substitutes for this increment.

## Delivered module and host integration

`core10-sales-invoice-ui.js` exports `CORE10_SALES_INVOICE_UI.mount(host, options)`. The existing `core10-sales-order-client.js` adds three invoice methods, and `core10-sales-order-entry.js` shares that one session-bound API between the Orders and Draft invoices task views. Existing CSS receives scoped invoice/tab rules. The gateway, seed, browser and client tests are test infrastructure, not a second backend.

Host load order:

```html
<!-- Existing incumbent styles first -->
<link rel="stylesheet" href="core10-control-studio.css">
<link rel="stylesheet" href="core10-build01.css">
<link rel="stylesheet" href="core10-sales-order.css">
<script src="core10-sales-master-catalog.js"></script>
<script src="core10-sales-order-client.js"></script>
<script src="core10-sales-order-ui.js"></script>
<script src="core10-sales-invoice-ui.js"></script>
<script src="core10-sales-order-entry.js"></script>
```

The invoice script is optional but must be loaded **before entry attachment** to enable invoice navigation. When absent, entry retains the Orders-only view. When present, entry renders Orders / Draft invoices task buttons and the confirmed-order “Draft invoice from this order” action. These are tasks within the existing authorized host, not permanent Central route registration.

```js
const sales = CORE10_SALES_ORDER_ENTRY.attach(existingRouteHost, {
  client: existingSignedClient,
  backendMode: 'signed',
  lang: 'bn',
  initialScope: { businessId, siteId },
  initialView: 'invoices', // omit for Orders
  initialOrderId: confirmedOrderId // optional invoice source handoff
});
await sales.ready;
// Host route/session/actor/business/site replacement:
sales.destroy();
```

`initialScope` is validated against fresh `api.context()` with a manageable business and matching contextual site. Invalid supplied scope is denied without fallback. The invoice view loads fresh scoped Orders, invoices and Control; a handed-off order missing from the latest list is fetched by exact ID, then must still be confirmed. It opens an existing source-linked invoice when one is found; otherwise it prepares unsaved input. SQL remains final authority for uniqueness, source version, permissions and current Master.

Entry owns its automatic Master catalog adapter unless the host supplies `catalogProvider`. A custom provider retains its own lifecycle. Host must destroy/remount on route or canonical context replacement; never reuse a session-invalidated API. Auth changes immediately reset private view state, invalidate the shared API/catalog and disable task navigation until a fresh attachment. No shared login/configuration/nav file is modified by this increment.

## Same-client method contract

All methods use the existing signed identity checks before and after RPC and schema `core10`.

| Client method | Input / canonical RPC |
| --- | --- |
| `readInvoices({businessId,siteId,invoiceId?})` | `read_sales_invoice_drafts_v1`; returns scoped `invoices`, current `validation_control` and explicit nonposting connection flags. |
| `saveInvoice({businessId,siteId,invoiceId,expectedVersion,orderId,orderVersion,lines,memo,requestKey})` | `save_sales_invoice_draft_v1`; creation uses null invoice/expected zero; edit requires existing ID/current version and explicit selection. Lines contain only `{order_line_no,quantity}`; null lines are allowed only on creation to select full quantities. |
| `validateInvoice({businessId,siteId,invoiceId,expectedVersion,approvalId,requestKey})` | `validate_sales_invoice_draft_v1`; approval may be null only under an applicable zero-stage policy. Successful receipt advances version with `validated:true`, while status remains `draft`. |

The adapter checks scoped source/version, draft-only and disconnected flags, fixed document/selection references, snapshot shape, line/total money-scale consistency, approval payload consistency and canonical audit receipt sequence. These are response-integrity checks; they do not substitute for SQL authorization or certify the source hash externally. A malformed write receipt is marked outcome-uncertain, because the server may already have committed.

## Invoice behavior and visible boundaries

The [0304 backend handoff](NP03B_DRAFT_INVOICE_HANDOFF_2026-11-18.md) remains the authority for source/approval semantics. The UI exposes:

- Recent scoped drafts; confirmed source selection; bilingual labels; quantity/include controls; memo; server total and separately labelled edited estimate; immutable source details/hash/confirmation audit; canonical invoice history and connection status.
- Fixed customer, price-list, currency, item/variant/UOM, unit price, discount and zero tax from the confirmed source snapshot. It does not offer replacement prices or references. Invoice money scale remains fixed; the browser estimate is advisory and server rounding determines saved amounts.
- Default full quantities when Owner partial selection is disabled. With `allow_partial_quantities:true`, quantities can be reduced and lines omitted within confirmed caps; at least one positive line remains required. Native bounds use canonical UOM precision when available. The API/SQL always enforce caps and precision.
- One draft per source order, even after partial selection. No second invoice for a remainder is promised. The existing invoice is opened through the confirmed-order handoff when available; concurrent duplicates are rejected by SQL with an explicit reload message.
- Edited saved drafts lose validation; unsaved changes block validation of the previous revision. Both `sales.invoice_draft` and `sales.invoice_validate` remain governed by actual Owner Control and default OFF. Live disable after page load can reject an action without changing the document.

Validation is review of a **draft**. Status stays DRAFT, `issued:false`, `stock_posted:false`, `financial_posted:false`; issuance, Stock and Money are NOT_CONNECTED. Tax is ZERO_ONLY, not statutory tax certification. No legal number, receipt/payment, receivable or journal is simulated.

Positive approval stages show a reference-ID input for an approval created through the existing canonical workflow. Order approval does not approve the invoice. The exact current invoice revision/source/hash/document/memo/total/stage-count binding must be approved through GOV-002. This UI creates no independent approval policy/request/reviewer flow and cannot turn a typed ID into authority.

Stale versions, changed Master price/currency/reference, duplicate source and unavailable dependencies receive explicit rejection/status copy. A changed quote is never silently repriced. Current Master date/tier checks can reject an immutable source snapshot; there is still no historical Master-version pricing acceptance guarantee.

## Uncertain responses, navigation and session clearing

Transport loss, an invalid post-commit write receipt, or an untrusted/failed read after a successful write must not announce a completed visible save or allow a fresh mutation. The invoice view holds its captured command and request key, freezes editable fields/source/scope/task navigation and offers **Retry exact request**. Retry repeats that command/key and adopts a trusted current invoice read; it must not create a second command, invoice or audit event. A definite SQL rejection, such as changed Master or disabled Control, is not reported as an uncertain success.

Unsaved memo/quantity/selection changes guard source, invoice, scope and Orders/Invoices navigation. The user saves or explicitly discards unfinished input. Saving resolves obsolete pending navigation and stays in the invoice view. Task switching destroys the previous view; generation checks prevent earlier in-flight completions from populating its replacement. Sign-out immediately clears invoice list, source snapshot, memo and audit, and late reads cannot restore them.

## Incumbent visual reuse

This extension preserves existing dark navy panels, mint action/focus states, beige guidance, quiet borders and inherited system/Bengali typography. It reuses the Orders list/detail layout, native labelled fields, 44px controls, focus outline and responsive stacking below 700px. Invoice additions are task buttons, memo textarea, native include checkbox, source details and wrapping key/value facts; there are no new global tokens or decorative assets.

A combined1440px/390px visual review and one bounded confirmation found the Invoice view consistent with incumbent Sales. The reviewer closed uncertain-result handling, obsolete discard-navigation and outside-view focus findings. Fresh committed captures: [desktop](../evidence/np03b/draft-invoice-desktop.png) and [mobile](../evidence/np03b/draft-invoice-mobile.png). This is not a whole-ERP/accessibility certification.

## Restartable verification and review

Executed local verification:

- 38-migration up/down/up PASS.
- 13 existing Sales client, 15 invoice client, 14 Master adapter and 2 entry tests PASS. These use mocks for signed client behavior and do not certify GoTrue.
- Sales/Invoice/Master/Audit security SQL, Finance0400/0401 and Stock0200 regressions PASS; Control registry/evidence PASS (23 enforced,7 exempt,10 inherited pending). Existing43-check Sales browser suite rerun PASS for this UI increment.
-36 Invoice browser acceptance checks PASS on actual0304 RPCs at1440px English/390px Bangla, plus43 preserved Sales browser checks PASS (79 total). Invoice tests include immutable source/quantity caps/line omission, create/edit/validate, edit clears validation, stale independent amendment, Master repricing denial, actual committed response loss, untrusted write/follow-up read, exact retry/audit once, saved/explicit-discard navigation, direct confirmed-order handoff, manager/tenant/site denial, Owner Control OFF before and after load, required approval refusal and sign-out race.

`tests/np03b/invoice-ui-seed.sql` reuses canonical fixture Master and creates three confirmed sources, no invoice drafts. It explicitly enables partial selection and zero-stage validation for local browser tests; those synthetic settings do not change catalog defaults. Gateway is loopback TEST-ONLY real PostgreSQL17 RPC execution with inert UUID claims, not GoTrue/JWT verification or a hosted preview. It refuses databases outside its disposable prefix or containing `auth.users`.

From repository root, with disposable PG17 credentials/API roles and Playwright/Chromium as in the NP03B workflow:

```sh
node tests/np03b/client.test.cjs
node tests/np03b/invoice-client.test.cjs
node --test tests/np03b/master-catalog.test.cjs tests/np03b/entry.test.cjs
export PGHOST=127.0.0.1 PGUSER=postgres PGDATABASE=core10_np03b_ci_invoice_ui
createdb "$PGDATABASE"
internal/migrations/run.sh up
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/invoice-ui-seed.sql
node tests/np03b/invoice-browser.cjs
```

Use a fresh dedicated database on each complete browser run: tests persist invoices and mutate fixtures/Control. The script starts/stops its own gateway. `NP03B_SHOTS` changes capture output; `NP03B_SKIP_SHOTS=1` preserves prior shots; `NP03B_CHROMIUM` chooses a local binary. CI uses ordinary `psql`; optional local `NP03B_TEST_CONTAINER` affects gateway SQL only, not every migration/seed command.

For a manual view on that same fresh seeded database, run `PORT=58219 node tests/np03b/ui-gateway.cjs`, then open `http://127.0.0.1:58219/harness.html?view=invoices&lang=bn&scope=101&site=1001`. This is a local review URL. Create a draft from a confirmed source, reduce a quantity, save, validate, then edit the memo and save to see validation clear. Inspect source/hash/audit and disconnected ports. The fixture's zero-stage validation is not a hosted maker/checker journey.

The browser emits `draft-invoice-desktop.png` and `draft-invoice-mobile.png`; reviewed captures are committed under `docs/evidence/np03b/`, and CI uploads fresh captures. Exact pushed SHA, current CI and Board/Decision Book evidence are recorded in PR109. The shared Finance compatibility SHA-pin workflow remains unchanged and assigned to the Finance Builder.

## Shared-owner next actions

NP01 must accept Sales/invoice permissions; the Central owner must register the authorized shared route and lifecycle; Master/tax owners must supply accepted tax and historical-price contracts; Money/Stock owners must accept invoice posting/fulfilment/reversal adapters. Current owner-only Sales scope/site fences remain. Hosted sign-in, legal issuance, Stock/Money posting, collection/POS/refund/returns and a full Order → Invoice → Collection → Return flow remain NOT_DONE. No production migration, upload, deployment, external message or merge is part of this document.
