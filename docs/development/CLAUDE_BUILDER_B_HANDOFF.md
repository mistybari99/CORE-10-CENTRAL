# Claude Builder B — restartable handoff (NP03A stock, B-012)

Resume from the last pushed SHA without chat history. Rules: `docs/coordination/WORK_SPLIT_AND_PROTOCOL.md`, issue #110.

| Item | Value |
|---|---|
| Branch | `build/claude-np03a-stock` (forked from trunk `ccr-15ed11dd-n3hw5h` @ `5efece2`) |
| Draft PR | into trunk (see PR list; title starts `NP03A B-012`) |
| Migration block | 0201–0299 (NP03A, Claude). 0200 already on trunk |
| Board row | B-012 |
| Hosted / deployed | **nothing.** No staging, Cloudflare or live action. IMG-ERP-SG untouched |

## P1 — stock commands (0201): reuse table (2026-11-21)

| Need | State | Source (path / PR / SHA) | Decision |
|---|---|---|---|
| Atomic ledger, balances, paired transfer, reconciliation | Existing | `internal/migrations/0200_np03a_inventory_engine.up.sql` (trunk `6396f54`) | **reuse**: call `post_stock_event` / `transfer_stock_v1` (internal) only |
| Command lifecycle draft → confirmed → posted, request key, version, location shape | Draft-only | `internal/enterprise-sql/c10_a048_inventory_commands_v1.sql` (trunk; = PR #104 `753a407` + core10 rename; PR #49 older) | **port + fix** into 0201 |
| Site deny / expiry / revoke on every location | Draft-only | A048 `inventory_action_authorized_v1` (PR #104) | **reuse as is** (pinned search_path) |
| Owner policy (staff issue/transfer, max quantity) | Draft-only, wrong engine | A048 `inventory_flow_policy_v1` + `configure_inventory_flow_v1` | **replace** by Control params (DEC-08: one Control engine); table not ported |
| Command audit | Draft-only, wrong engine | A048 `inventory_command_audit_v1` | **replace** by canonical audit `_append_canonical_audit_v1` (CHG-005) + request ledger like `master_requests_v1` |
| Owner Control switch | Partial | `inventory.stock_event` (0102/0105) | **reuse** as master switch; add `inventory.receive/issue/transfer/adjust` |
| Approval stages 1–5 | Missing for stock | GOV-002 on trunk; Finance pattern 0400 (fail closed), PR #120 0405 (adapter) | 0201 **fails closed** (`INV_APPROVAL_NOT_CONNECTED`); adapter is the next increment |
| Item active check | Existing | `master_item_usable_v1` (0151) | **reuse** |
| Same-key race fix | Existing pattern | 0153 advisory lock | **reuse** |
| Tests | Draft-only | `tests/c10_a048_inventory_commands_e2e.sql`, `tests/c10_a048_inventory_client.test.js`, `.github/workflows/core10-a048-inventory-ci.yml` | new numbered-migration tests modelled on them; legacy A048 CI left unchanged |

Fixes against the A048 draft: `search_path` was `core10,pg_catalog` (now `pg_catalog,core10`); no `control_check_v1`; private policy table and audit table; reads unbounded (now keyset pages ≤ 200); no cancel; row locked before authorization (now authorize, then lock, then re-check); replay ran before the switch check (now a switched-off feature refuses replays too).

## Done

### Checkpoint 1 — 0201 stock commands (CODED + TESTED on disposable PG17.12; GitHub CI: see PR)

- `internal/migrations/0201_np03a_inventory_commands.{up,down}.sql`
  - Control features `inventory.receive|issue|transfer|adjust` (bn/en labels, per site, 0–5 stages, params
    `max_qty`, `staff_allowed`, `separate_confirmer`, `allow_cross_site`, `reason_required`) under the master switch
    `inventory.stock_event` (its `max_adjust_qty` limits adjustments; `allow_negative_stock=true` is refused honestly
    as `INV_NEGATIVE_STOCK_NOT_CONNECTED` because the one ledger never goes below zero).
  - `create_inventory_command_v1(business, kind, source_location, destination_location, item, qty, reason, key)` and
    `advance_inventory_command_v1(command, confirm|post|cancel, version, key)`: registry `enforced`
    (`inventory.stock_event`), evidence `tests/migrations/np03a-inventory-commands-e2e.sql`.
  - Reads: `inventory_list_commands_v1(business, site, status, before_id, limit≤200)`,
    `inventory_list_balances_v1(business, site, after_location, after_item, limit≤200)`; site-scoped (explicit deny wins).
  - Tables `inventory_commands_v1`, `inventory_command_requests_v1`: RLS on, no API grants.
- Tests: `tests/migrations/np03a-inventory-commands-e2e.sql` (7 personas, ~80 assertions),
  `tests/migrations/np03a-inventory-race.sh` + `-seed.sql` (6 real concurrent rounds). Both in
  `.github/workflows/core10-b010-control-port-ci.yml`.
- Local results (PG17.12): up/down/up PASS; contract 6/6; np02 control/master tables/master rpc, np03a 0200,
  np06 finance + reversal e2e PASS; registry gate 38 RPCs = 21 enforced / 7 exempt / 10 pending; evidence 21/21;
  races: control, master, np03a, finance, finance reversal PASS; B-009 PASS; OCC browser 19/19.
- Mutation checks (each must fail the tests, all did): master switch removed, `stock.read` instead of
  `stock.post`, approval stages ignored, maker-checker off, same-key advisory lock removed (race test).

### Checkpoint 2 — 0202 GOV-002 approval adapter (CODED + TESTED on PG17.12)

- Reuse: canonical approval journal 0009–0019 and the Finance adapter pattern (PR #120, 0405). No second approval cycle.
- 0201 now posts through an internal hook `_inventory_approval_gate_v1`; 0202 replaces it (0202 down restores it).
- `inventory_request_approval_v1(command, key)`: maker only, command confirmed, stages ≥ 1, route length = stages
  (no route = 1 checker), checks `inventory.stock_event`, kind feature and `gov002.review`; registry `enforced`.
- Posting with stages > 0 needs an approved request, full stage receipts, the same route length as the current
  stages, and `verify_approval_binding_v1` on the frozen payload + version. Stage or route changes after approval
  fail closed (`INV_APPROVAL_ROUTE_MISMATCH`).
- Test `tests/migrations/np03a-inventory-approval-e2e.sql` (one checker, two-stage route, maker/self/foreign,
  CONTROL_DISABLED for stock and for review). Mutations killed: gate open, maker check off, review switch not
  checked, route mismatch ignored. Full local suite: all e2e + 5 race suites PASS; registry 22 enforced; B-009 PASS.

### Checkpoint 3 — 0203 purchase order → GRN → QC → stock (CODED + TESTED on PG17.12)

Reuse table (P2):

| Need | State | Source | Decision |
|---|---|---|---|
| Purchase document draft → confirmed → posted, lines, key | Draft-only | `internal/enterprise-sql/c10_a026_operational_docs_v1.sql` | **port + fix**: PO and GRN are separate documents; free-text counterparty replaced by Master supplier |
| Lot, expiry, inspection pass/fail | Draft-only (PR #73 `1214731`) | `c10_a058_quality_lot_recall_v1.sql` | **reuse model** as `inventory_lots_v1` + GRN QC lines; its `quality_balances_v1` second book NOT ported (CHG-035) |
| Supplier | Existing | `master_parties_v1` (0150) | **reuse** (supplier/both, active, same business) |
| Item usable | Existing | `master_item_usable_v1` | **reuse** |
| Stock receipt | Existing | `post_stock_event` (0200) | **reuse**, accepted quantity only |
| Recall, genealogy, FEFO | Draft-only (PR #73) | A058 | **later** (not in P2) |

- Controls: `procurement.purchase_order` (`max_po_amount`, `max_lines`, `manager_may_create`, `separate_approver`, 0–5 stages)
  and `procurement.goods_receipt` (`over_receipt_pct`, `qc_required`, `separate_inspector`, `require_lot`, `require_expiry`);
  GRN posting also checks `inventory.stock_event`.
- RPCs (all `enforced`): `procurement_save_po_v1`, `procurement_advance_po_v1` (approve/cancel/close),
  `procurement_receive_v1`, `procurement_inspect_v1`, `procurement_post_grn_v1`; reads `procurement_list_pos_v1`,
  `procurement_get_po_v1` (with receipts).
- Tests: `tests/migrations/np03a-procurement-e2e.sql` (5 personas), `tests/migrations/np03a-procurement-race.sh`
  (concurrent over-receipt, double posting). Mutations killed: received-instead-of-accepted, supplier rule removed,
  receive ignores switch, QC over-accept. Full local suite PASS; registry 27 enforced; evidence 27/27; B-009 PASS.
- Not done: PO approval stages > 0 (`PROC_APPROVAL_NOT_CONNECTED`; same adapter pattern as 0202 next), AP / supplier
  bill (NP06), GRN cancel/return to supplier, lot-level balances, FEFO, recall.

### Checkpoint 4 — P3 Owner multi-business dashboard (0204 + screen; CODED + TESTED locally)

- Reuse: Control Centre / Master Data styles (`core10-owner-control-centre.css`, `core10-master-data.css` tables),
  client pattern (signed session check before/after each RPC, RPC allowlist, no stored token), boot gate
  (`core10-control-centre-config.js`: CORE10 staging or loopback only, key empty until Level 2 GO), test gateway.
- `0204_np03a_owner_dashboard_read`: `owner_portfolio_v1()` (every business the caller may oversee: sites by kind,
  stock items/units, open POs and value, receipts awaiting QC/posting, open stock tasks, pending approvals for
  managers-of-business only, `not_connected: sales, cash`), `owner_business_sites_v1(business, kind, after_site, limit≤200)`.
  Set-wise aggregates + 3 indexes. Read-only (STABLE), no registry rows needed.
- Screen `core10-owner-dashboard.html` (+ `-client.js`, `-ui.js`, `.js`, `.css`): all businesses → one business's
  sites (kind filter, 50 per page) → one site (stock, purchase orders, stock tasks), breadcrumbs, bn/en, 390/1440.
  One short line says sales and cash are not connected yet; no developer blocker list.
- Tests: `tests/migrations/np03a-owner-dashboard-e2e.sql`; `tests/control-centre/owner-dashboard-browser.cjs` 7/7
  (+ `od-seed.sql`, `od-harness.*`; gateway allowlist extended). Master Data browser rerun with the extended gateway.
- Not done: link from the Central shell (Session A owns `core10-control-studio-entry.js`; add next to Master Data:
  `core10-owner-dashboard.html`); sales/cash/receivables figures (NP03B/NP06 not on trunk).

### PAUSE CHECKPOINT (2026-11-22, Owner asked to pause; nothing local-only)

- P4 started: `tests/migrations/np03a-scale.sql` (10 businesses x 400 sites = 4,000 sites, 80,000 ledger rows and
  balances, 8,000 POs, 4,000 stock tasks; correctness + time budgets + 400 real receive and 100 transfer RPC writes).
  Local PG17.12: every owner/business/site read 1–55 ms; 400 receives 3.3 s; 100 transfers 1.3 s. **One finding:**
  `inventory_list_balances_v1` for a site-only staff member over a whole business (no site filter) = 1,523 ms (budget
  1,500 ms) because `can_site` runs per balance row. Fix next: resolve the caller's readable sites once (or require
  `p_site` for site-only staff), then rerun. The scale file is committed but NOT yet a CI step (it would fail).
- **GitHub CI is RED at `bed68b9` and `3456a35`** (green at `6c7a3fa`):
  1. `core10-b010-control-port-ci` job `control-port` failed (runs 44960292006, 44960789001). The log tail shows only
     cleanup; the failing step is not read yet. It was introduced by 0203 or 0204 (or their CI steps). First action
     on resume: read the full job log, reproduce locally with the exact CI step order (all steps share ONE database:
     committed race seeds can collide with e2e ids or change counts), fix, push.
  2. `NP03B Sales Order Foundation PG17` job `sales` failed: `SALES_CORRECTION_ACCEPTANCE_FAIL: 10 unresolved security
     cases`. That is the NP03B lane's own test running on this PR. Check whether it is also red on trunk `5efece2`;
     if not, find which 02xx object it trips.
- Resume order: (1) fix CI red, (2) balance read fix + wire scale test into CI, (3) PO approval stages via GOV-002
  (same pattern as 0202), (4) Central shell link for the dashboard (Session A file).

### Not done / NOT_CONNECTED

- Approval thresholds (`approval_thresholds_v1`) apply as GOV-002 defines them: payload `amount` = quantity,
  `unit` = `base_qty`; below a configured minimum GOV-002 refuses the request (NP01 rule, not changed here).
- Quantities are in the item's base unit; UOM decimals per item are not yet enforced.
- Moves between two businesses are refused (an inter-business move is a sale/purchase, NP03B/P2).
- No UI yet (P3). Signed GoTrue / staging: not run (Session A, GO-2/GO-3).

## Next

3. P2 purchase → GRN → QC → stock (A026, PR #73 lot/expiry, Master parties).
4. P3 owner multi-business dashboard; P4 10 × 400 scale test.

### Agent C — 0206 PO approval

- Branch `agentC/po-approval` (from `build/claude-np03a-stock`), local commit only, not pushed.
- `internal/migrations/0206_np03a_po_approval.up.sql` / `.down.sql`: purchase-order approval stages > 0 now go
  through the ONE canonical GOV-002 journal, the same adapter pattern as 0202 (no second approval cycle).
  - `purchase_orders_v1.approval_request_id` (FK `approval_requests`).
  - `procurement_request_po_approval_v1(p_po, p_key)`: authorize (scope, `can_business`) before the row lock;
    `control_check_v1(p.business_id, 'procurement.purchase_order', p.site_id)` + `gov002.review`; PO must be a
    draft; caller must be the PO creator (`PROC_APPROVAL_MAKER_DENIED`); stages >= 1
    (`PROC_APPROVAL_STAGES_REQUIRED`); route length = stages, no route = exactly 1 checker
    (`PROC_APPROVAL_ROUTE_MISMATCH`); `submit_typed_approval_v1(business,'procurement','purchase_order',
    'procurement:po:'||id, PO version, server-built payload, key)`. Payload: po/business/site/supplier, `amount` =
    `total_amount`, `unit` = `currency_total`, expected_on, version, lines (item, qty, price). A live request for the
    current version blocks another (`PROC_APPROVAL_ALREADY_REQUESTED`); one bound to an earlier version of an edited
    draft can never be effective, so a fresh request is allowed. Canonical audit `procurement.po_approval_requested`.
    Registered `enforced` (feature `procurement.purchase_order`, B-012, test `tests/migrations/np03a-po-approval-e2e.sql`).
  - `procurement_advance_po_v1` (CREATE OR REPLACE): identical to 0203 except approve calls
    `_proc_po_approval_gate_v1`: stages = 0 → unchanged; else `PROC_APPROVAL_REQUIRED` /
    `PROC_APPROVAL_NOT_EFFECTIVE` / `PROC_APPROVAL_ROUTE_MISMATCH` / `PROC_APPROVAL_RECEIPTS_INCOMPLETE`, then
    `verify_approval_binding_v1` on the frozen payload + version (edited draft → `approval_stale_or_payload_changed`).
    Approval ids go into the approve audit payload and the RPC result.
  - Down: refuses once any PO carries an approval request; restores the 0203 function byte-for-byte (prosrc md5
    checked) and drops the column/helpers.
- Tests: new `tests/migrations/np03a-po-approval-e2e.sql` (tenants 1401/1402; one checker, two-stage route
  `business_owner`→`tenant_owner`, maker/self/foreign denials, `CONTROL_DISABLED:procurement.purchase_order` and
  `CONTROL_DISABLED:gov002.review`, stage change after approval fails closed, edited draft fails closed, stages 0
  unchanged); CI step added after the 0203 step. `np03a-procurement-e2e.sql`: the stages>0 assertion now expects
  `PROC_APPROVAL_REQUIRED`, and the "five procurement writers enforced" count is scoped to that file's `test_ref`
  (the new 0206 RPC would otherwise make it six).
- Not done: thresholds — `currency_total` is not a GOV-002 threshold unit code (`^[A-Z][A-Z0-9_]{1,11}$`), so a
  threshold configured on the procurement policy makes the request fail closed until a currency unit is agreed;
  no UI button yet for "request approval".
