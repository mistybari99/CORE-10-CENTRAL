# C10-A036 Enterprise Owner Command Center (Claude Build 1)

Status: BUILT and TESTED IN ISOLATION. A standalone, synthetic-fixture PREVIEW. NOT integrated into the production app,
NOT connected to Supabase by default, NOT staging-verified, NOT released. No claim of live deployment or certified figures.

Owned paths only: `experimental/owner-console/**`, `tests/owner-console/**`, `.github/workflows/core10-a036-owner-console-ci.yml`, this file.
Untouched: all SQL, root HTML/CSS/JS, service worker, `core10-enterprise-client.js`, A011 Business Places UI, A034/A035 files.

## What it is
A runnable static page (`experimental/owner-console/index.html`, no build step, no dependencies) for the single Enterprise Master Owner
console with nested Business Owner views: overview KPIs, businesses (open a business -> Business Owner view), sites/stock locations
(showroom/factory/godown), module Show/Locked/Hidden (READ-ONLY), stock reconciliation with filters, purchase & sales, production &
finance cards (with the A037 BLOCK-rule note), pending approvals (read-only), Quick/Advanced setup summary, Bangla/English switch,
responsive desktop 1440 / tablet 768 / mobile 360, keyboard navigation, skip link, live region, loading/empty/error states.
Every view carries a "SYNTHETIC FIXTURE" badge; no figure is revenue or certified.

## Data providers (`providers.js`)
* `createFixtureProvider` (default) - synthetic data; the provider itself filters by session scope (master owner = own tenant;
  business owner = own business; foreign tenant never visible; consolidated KPIs master-only). Every method returns a Promise.
* `createSupabaseReadOnlyProvider` - optional, FAIL-CLOSED: needs `experimentalRead===true`, a signed Supabase client and a real authenticated
  user; select-only on an allowlist of `c10_demo` views (`tenant_consolidated_kpi_v1`, `owner_business_kpi_v1`, `owner_business_control_board_v1`,
  `business_module_settings_v1`, `business_inventory_report_v1`, `operational_business_report_v1`, `owner_module_requests_v1`, `sites`, `businesses`).
  No write/RPC method exists; no secret or service-role key is accepted. The "Preview as" selector is NOT authorization: with the bridge, RLS decides.
  The page CSP is `connect-src 'none'`; enabling the bridge requires a deliberate CSP change and the A019 release gates.

## Tests
* `tests/owner-console/provider.test.js` (Node): isolation (sibling/foreign tenant/consolidated), bridge fail-closed + allowlist + no write methods,
  i18n parity (112 keys), no secret/network/storage tokens in shipped code.
* `tests/owner-console/ui.e2e.js` (Playwright): 3 breakpoints with no horizontal overflow on all 9 views and >=44px targets, nav placement per breakpoint,
  keyboard (arrows/Home/End/Enter + focus), locale, role/business isolation sweep over every view, loading/empty/error + Retry, DEAD-BUTTON AUDIT via CDP
  (every visible button must have a click listener; 214 audited), no JS errors, no external requests.
* Negative controls proved locally: an extra handler-less button fails the audit; a provider that leaks sibling businesses fails the provider test.
Run locally: `node tests/owner-console/provider.test.js` and `NODE_PATH=$(npm root -g) node tests/owner-console/ui.e2e.js`; preview: serve the folder and open `index.html`
(`?lang=bn`, `?state=loading|empty|error`).

## Release blockers / limits
Real Supabase Auth and RLS verification, A019 staging gates, owner-approved CSP change for the bridge, write workflows (approve/reject/setup),
real-data certification, accessibility audit with assistive technology, performance at 300+ sites. Do not present as live.
