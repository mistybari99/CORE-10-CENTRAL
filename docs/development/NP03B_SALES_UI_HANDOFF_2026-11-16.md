# B-014 / NP03B Sales Order UI — incumbent extension handoff

Date: 2026-11-16. Scope: an ordinary extension of the existing Central Build01 / Control Studio UI. This document supplements the [foundation](NP03B_SALES_ORDER_FOUNDATION_2026-11-16.md) and [reuse audit](NP03B_SALES_REUSE_AUDIT_2026-11-16.md); their older UI-not-built status is superseded only for the local module and evidence described here. Permanent Central navigation and hosted Sales remain NOT_DONE.

## Delivered boundary

- `core10-sales-order-client.js`: session-bound adapter over the existing signed client's `core10` RPCs; context, scoped order read, Owner Control read, save, confirm/cancel and audit read. No direct table access or separate login/configuration service.
- `core10-sales-order-ui.js`: Bangla/English order list and multiline draft, amendment, transition controls, server receipt/version/total, canonical audit history and explicit dependency/error states. Estimated totals remain advisory; PostgreSQL validates the saved total.
- `core10-sales-order-entry.js`: host attach/destroy boundary and session invalidation. It reuses the host's client, not protected legacy `BOS_CONFIG`.
- `core10-sales-order.css`: scoped extension of existing Studio tokens, layout and native controls.
- `0302_np03b_sales_audit_read`: read-only `core10.read_sales_order_audit_v1(bigint,bigint,bigint)` projection of canonical audit events joined through existing Sales command receipts. Same owner/site fence as order reads; maximum 100 events, newest first. No additional audit ledger or write authority. Down migration drops only this reader.

Commands remain non-posting: save creates/amends a draft, confirm/cancel transition an eligible draft. Confirmation does not reserve or post stock, issue an invoice or collect money. Confirmed/cancelled documents are immutable in this increment. Unsaved changes disable transition of the earlier saved version; changing scope requires explicit discard of unfinished input. Response uncertainty locks the form and scope until an explicit Retry repeats the exact command and request key. Async generation guards discard stale results; sign-out immediately clears private orders, forms and audit, including when a read remains in flight.

## Incumbent visual reuse audit

Observed source: `core10-control-studio.css`, `core10-build01.css`, Build01 HTML and the scoped Sales CSS. Root `PRODUCT.md` and `DESIGN.md` were absent; no replacement or shared design artifact was created. The Impeccable context launcher was unavailable, so existing implementation and the actual desktop/mobile captures supplied visual truth.

| Existing system | Sales reuse / observed result |
| --- | --- |
| Dark navy canvas `--bg:#101722`, panels `--panel:#1a2635` / `--panel2:#202f40`, border `--edge:#334557`, foreground `--fg:#eef3f8` | Same shell, dark fields and quiet border divisions; order detail stays inside the existing main region. |
| Mint `--sea:#77d5be`, amber `--highlight:#ddb47f`, error `--err:#f5a6a2` | Existing primary buttons/focus, boundary guidance and error roles. Sales muted text is `#b5c5d4` for readable secondary information. |
| `system-ui,"Noto Sans Bengali",sans-serif`, native inputs/selects, rounded buttons | Font inherited; labelled native controls, at least 44px Sales controls, 2px mint focus outline with 3px offset. No new font download, icon library or decorative assets. |
| Existing Build01 rail and responsive shell | Desktop retains rail and side-by-side list/detail. Sales stacks list/detail below 700px; line values become two columns below 1050px; 390px capture remains contained. |
| Semantic selected/error/disabled state | Selected order has border and `aria-pressed`; status copy names outcomes; confirmed inputs and unavailable actions are disabled. Bangla copy is visible in the mobile capture. |

The inspected screenshots show readable labels, visible focus, a clear synthetic boundary and consistent incumbent spacing/shapes at 1440px and 390px. This is a bounded visual review, not a screen-reader, measured contrast or full accessibility certification. Keep the existing rail intact until its owner adds the canonical Sales destination: the screenshot's “Setup & access” label is inherited harness chrome, not a completed Sales route.

12ui hosted generation/screenshot upload was blocked by automatic approval review. No screenshot was uploaded and no hosted generation result is claimed; the delivered UI reuses the local incumbent system.

## Exact Central host integration

The canonical host owner must register its Sales route/menu using fresh canonical context and existing permission resolution. Do not make the test harness a permanent navigation destination.

1. Load existing Studio/Build01 CSS, then Sales CSS; load Sales client, UI and entry scripts in that order.
2. Allocate a route-owned DOM host and pass the existing authenticated Supabase-compatible client. Use `backendMode:'signed'` only for that signed host; the harness uses `'synthetic'` explicitly.
3. Pass the canonical host's selected scope: `CORE10_SALES_ORDER_ENTRY.attach(host, {client, backendMode:'signed', lang:'bn', catalogProvider, initialScope:{businessId,siteId}})`, then await `controller.ready`.
4. Call `controller.destroy()` when leaving the route or on session, actor, business or site context replacement. Clear the old host, resolve fresh canonical context and create a new attachment. Never reuse a session-invalidated adapter or let old in-flight reads repopulate the new view.
5. The entry already resets private UI and destroys its adapter on non-initial Auth events. The host still owns route disposal and remount after obtaining a fresh session. Within the module, business/site selection clears scoped records/catalog/audit, guards unsaved input with explicit discard, and reloads that scope.

`initialScope:{businessId,siteId}` is validated against a **fresh** `api.context()` result: the business must have `can_manage:true` and the selected site must belong to that business in the returned context. An invalid supplied scope is denied without falling back to another business/site. The canonical host must pass its selected scope and destroy/remount on context switches; it must not retain a previous attachment or cached authorization.

Current SQL authorization is owner-only `can_manage`, plus explicit site `stock.read` as an additional deny fence. Stock access alone does not authorize Sales. Managers/cashiers/agents have no invented Sales grant. Accepted Sales-specific read/write/confirm/cancel actions and canonical shell context are pending NP01 Auth.

## Optional catalog projection contract

`catalogProvider` is an optional async host-supplied function receiving `{businessId, siteId}`. It is a projection adapter contract, **not an implemented or proposed Master reader RPC name**. The Master owner must supply accepted scoped reader bindings. Do not query Master tables from this UI or copy identities into a Sales master.

```js
async function catalogProvider({businessId, siteId}) {
  // Read through accepted canonical Master bindings, then project:
  return {
    businessId, siteId,
    source: 'canonical_master', // 'synthetic_fixture' only in synthetic mode
    customers: [{id: 7001, label: 'Master-provided customer label'}],
    priceLists: [{id: 7101, label: 'Master-provided version label', currency: 'BDT'}],
    items: [{
      id: 8101, label: 'Master-provided item label',
      variantId: 7301, // optional/null when no variant
      uomId: 7201, uomLabel: 'Master-provided unit label',
      prices: {7101: 300} // finite, nonnegative number for EVERY listed price list
    }]
  };
}
```

Example IDs/amounts above are illustrative synthetic values, not production identities. Projection requirements:

- Exact requested business/site; `source` must match backend mode. IDs are positive safe integers. Each of `customers`, `priceLists`, `items` must be a nonempty array with string labels.
- Each price list has a three-uppercase-letter currency; every item has a valid UOM, optional valid variant and a numeric price for every listed price-list ID. Treat each item/variant/UOM combination as a selectable row.
- Return only active, authorized canonical identities, immutable price-list version identities and authoritative prices suitable for the requested scope. The host must reconcile supported currency/tax settings with the Master owner; the projection is not tax authority.
- Missing provider or a null/invalid projection locks creation/amendment while scoped existing orders and audit remain readable. A provider that rejects makes scope loading fail; return null for an intentionally disconnected catalog.
- A visible valid projection does not authorize a command. SQL independently requires `core10.master_validate_sales_order_v1(bigint,bigint,jsonb) RETURNS boolean`; absent/FALSE/NULL fails closed. NP02's [contract](../coordination/NP02_B011_MASTER_DATA_CONTRACT.md) accepts that signature but currently supplies no implementation in this integration. Trunk `fe1c6b6`, merged by the integration lead, includes `0150` Master tables; accepted Master readers and the validator implementation remain pending. The test implementation is deliberately synthetic, outside migrations.

## Reproducible isolated browser inspection

Use disposable PostgreSQL17 only, with `authenticated`/`anon` roles created as in `.github/workflows/np03b-sales-ci.yml`. Never use a hosted/production database. Gateway checks require loopback `PGHOST`, database prefix `core10_np03b_ci` or `core10_np03b_local`, PG17 and absence of `auth.users`. Fixtures use inert UUID claims, not GoTrue users or JWT verification.

CI uses ordinary `psql`, without `NP03B_TEST_CONTAINER`. With Playwright 1.63.0/Chromium installed and PostgreSQL client tools available:

```sh
export PGHOST=127.0.0.1 PGUSER=postgres
# Supply the disposable server's PGPASSWORD through the local environment.
createdb core10_np03b_ci_ui
PGDATABASE=core10_np03b_ci_ui internal/migrations/run.sh up
PGDATABASE=core10_np03b_ci_ui psql -X -v ON_ERROR_STOP=1 -f tests/np03b/ui-seed.sql
PGDATABASE=core10_np03b_ci_ui node tests/np03b/browser.cjs
```

`browser.cjs` mutates fixtures and removes the synthetic Master validator for a negative check. Recreate a fresh browser-test database before a repeat. It starts and closes its own loopback server. `NP03B_SHOTS` changes screenshot output; `NP03B_SKIP_SHOTS=1` preserves prior captures; `NP03B_CHROMIUM` selects a local browser binary.

Local optional Docker path: set `NP03B_TEST_CONTAINER=core10-np03b-<local-suffix>` to route gateway SQL through `docker exec ... psql`. This option is gateway-specific; migration/seed commands still need to run through that same container's `psql` with repository SQL available, or through an actual loopback PostgreSQL connection. Keep `PGHOST=127.0.0.1` and `PGDATABASE` set for gateway guards. Do not assume setting this variable changes every test/migration script.

For a manual Owner review, use a fresh seeded disposable database and run:

```sh
PGDATABASE=core10_np03b_ci_ui PORT=58219 node tests/np03b/ui-gateway.cjs
```

Open `http://127.0.0.1:58219/harness.html?lang=bn` in the browser attached to the machine running the gateway. This is a loopback test URL, not a public preview.

Owner click নির্দেশনা (শুধু সিনথেটিক পরীক্ষা):

1. `demo-sweets` / `A1` রাখুন; উপরের সিনথেটিক সতর্কতা পড়ুন। “নতুন অর্ডার” চাপুন।
2. সিনথেটিক গ্রাহক/খুচরা মূল্যতালিকা রাখুন। রসগোল্লা বক্সের পরিমাণ `2`, ছাড় `5` দিন; “পণ্য যোগ করুন” দিয়ে চকলেট কেক নির্বাচন করুন। “খসড়া সংরক্ষণ” চাপুন; সার্ভারের version/মোট দেখুন।
3. প্রথম লাইনের পরিমাণ `3` করুন। সংরক্ষণের আগে নিশ্চিতকরণ বন্ধ থাকবে। আবার সংরক্ষণ করুন, তারপর অর্ডার নিশ্চিত করুন। এই fixture-এ approval stages শূন্য; এটি hosted maker/checker পরীক্ষা নয়।
4. “অডিট ইতিহাস” খুলে create/amend/confirm-এর তিনটি canonical event দেখুন। নিশ্চিত অর্ডার আর সম্পাদনাযোগ্য নয়; টাকা/স্টক পোস্ট হয়নি।
5. `?lang=bn&missing=1` খুলে নতুন খসড়া বন্ধ এবং আগের অর্ডার/অডিট পাঠযোগ্য দেখুন। `&persona=33333333-3333-4333-8333-333333333333` দিয়ে manager-denied অবস্থা দেখুন।

## Evidence and remaining work

Integration-lead final local verification: **13/13 signed-client mock contracts PASS**, **30 migrations up → down → up PASS** on disposable PostgreSQL17, existing Sales security suite PASS, new scoped audit-read suite PASS, Control registry/evidence PASS (5 enforced including 2 Sales / 7 exempt / 11 inherited pending), NP02 Master-table regression PASS, and **40/40 real-browser checks PASS** at 1440px English and 390px Bangla. Browser cases include initial-scope validation/no fallback, focus continuity, actual SQL create/amend/confirm and canonical audit, explicit unsaved discard, stale read after sign-out, response-loss exact-key retry with form/scope lock, missing catalog/provider and Owner-disabled states. The finish review closed its P2 keyboard-focus finding and residual P3 language-toggle focus finding at that scope. This is not hosted Auth or whole-ERP certification. Exact pushed SHA and GitHub CI belong in PR #109 and Board after push.

Actual local browser/SQL screenshots, visually inspected together:

- [Desktop 1440px](../evidence/np03b/sales-order-desktop.png)
- [Mobile 390px, Bangla](../evidence/np03b/sales-order-mobile.png)

These show real browser rendering and disposable SQL order/audit responses with **TEST-ONLY inert UUID Auth and synthetic Master**. They are not GoTrue, hosted Supabase or a completed deployment. Exact pushed head, workflow conclusions and final test evidence belong in [Draft PR #109](https://github.com/mistybari99/CORE-10-CENTRAL/pull/109) and the live Coordination Board after the integration lead pushes; not independently verified by this documentation pass. No Board row was written by this pass.

NOT_DONE: permanent canonical host navigation/context handoff; accepted canonical Master catalog provider and implemented validator; Sales-specific Auth actions; hosted sign-in and signed hosted negative tests; integrated approval submission and full multistage persona journeys; Stock reservation/fulfilment; invoice/POS/collection/refund/returns. No end-to-end Order → Invoice → Collection → Return or operational ERP completion is claimed.

Next executable handoff: Master owner supplies accepted scoped projection bindings and validator implementation; Auth/host owner registers Sales actions and route lifecycle; then integration lead mounts this module with the real signed client and runs exact-head hosted checks under the separate release gate. No production migration, merge, external message or upload is part of this artifact.
