# Claude Builder B — restartable handoff (NP03A stock, B-012)

Resume from the last pushed SHA without chat history. Rules: `docs/coordination/WORK_SPLIT_AND_PROTOCOL.md`, issue #110.

| Item | Value |
|---|---|
| Branch | `build/claude-np03a-stock` (forked from trunk `ccr-15ed11dd-n3hw5h` @ `5efece2`) |
| Draft PR | into trunk (see PR list; title starts `NP03A B-012`) |
| Migration block | 0201–0299 (NP03A, Claude). 0200 already on trunk |
| Board row | B-012 |
| Hosted / deployed | **nothing from this branch.** Trunk Session A hosted 0201–0206 on CORE10 staging via PR #129 (2026-11-22); 0207 is NOT hosted. No Cloudflare / live action here. IMG-ERP-SG untouched |

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
- **Red CI at `bed68b9` / `3456a35` / `4a8e446`: RESOLVED (2026-11-22, integrator Agent D).**
  1. `core10-b010-control-port-ci` (runs 44960292006, 44960789001, 44980645823): root cause was NOT 0203/0204. The PR
     base `ccr-15ed11dd-n3hw5h` moved and now carries NP01 0110-0114. 0111 pins every GOV-002 submission made under
     an explicit `gov002.review` setting to a route of exactly that many stages (`CONTROL_STAGE_MISMATCH` otherwise;
     a 1-stage route is `['tenant_owner']`). The 0202 e2e set `gov002.review` explicitly (off, then on, stages 1) and
     then requested on the un-routed one-checker policy. Fix `aa6d9e52` (test fixture only): the switch is proven in
     a savepoint that also proves the NP01 interplay (un-routed refused, explicit 1-stage route requests, approves,
     posts with one stage receipt), then rolled back. The new 0206 e2e had the same stale fixture; fixed the same
     way in `03d5349` (adds: business owner cannot decide a `['tenant_owner']` stage, request pinned to 1 stage).
     0202/0206 SQL unchanged: they fail closed correctly. No assertion removed.
  2. `NP03B Sales Order Foundation PG17` (`SALES_CORRECTION_ACCEPTANCE_FAIL: 10 unresolved security cases`) was the
     Sales lane's own failure, not ours: Session A reverted the Sales integration on trunk in `6d24ad8` (open security
     findings), so the workflow no longer exists on this branch after merging trunk.
- Integration (2026-11-22): merged `agentA/ci-fix` (aa6d9e52), `agentB/scale` (a010702a, 0205), `agentC/po-approval`
  (5f0d1eab, 0206), then trunk `ccr-15ed11dd-n3hw5h` @ `e609b8a1` (merge commit `99716a3`, no conflicts; migration
  numbers unique, 0205/0206 are B-012's). Only conflict: this file (both agent sections kept).
- Done from the resume order: (1) CI red fixed, (2) balance read fix 0205 + scale test in CI, (3) PO approval via
  GOV-002 0206. Still open: (4) Central shell link for the dashboard (Session A file).
- Note: trunk `e609b8a` applied 0013-0019, 0100-0106, 0110-0114 to CORE10 staging (Session A). Staging has no 02xx
  or 04xx; if 04xx is applied to a persistent database before 02xx, 0200-0206 would be refused as OUT_OF_ORDER.

#### Integration summary: 0205 + 0206 and local results at `03d5349`

- 0205: `inventory_list_balances_v1` resolves the caller's readable sites once (same rule as `can_site`, denies
  still win); staff whole-business balance read 1.2-1.5 s -> 15-19 ms. Scale test is a CI step.
- 0206: PO approval stages > 0 go through the one GOV-002 journal (maker-only request, route length = stages,
  `CONTROL_DISABLED` for `procurement.purchase_order` and `gov002.review`, stage/route drift and edited draft fail
  closed, stages 0 unchanged); registry `enforced`.
- Local PG17.12, every step of `core10-b010-control-port-ci` in order on one fresh database (incl. up/down/up, all
  e2e, 0206 e2e, scale, registry gate + self-test, 4 race scripts, registry evidence, B-009 drift + self-test, client
  contract, 3 real-browser tests at 390/1440 and shell nav): **28/28 PASS** (Chromium preinstalled, install step
  skipped). Other PR workflows touching migrations, replayed step by step on a fresh PG17 cluster each:
  `core10-s0-migrations-ci` 2/2 PASS; `core10-np06-finance-ci` job `finance-pg17` 10/10 PASS (job `np01-compat-pg17`
  NOT RUN locally: it fetches and merges PR #111); `np01-s1c-remainder-ci` 17/17 PASS; `core10-s1c-canonical-approval-ci`
  7/7 SQL+node PASS (Python reviewer browser smoke NOT RUN locally: no Python Playwright); `core10-np05a-manufacturing-ci`
  19/19 PASS incl. both browsers.
- GitHub CI at `03d5349` (PR #123): `core10-b010-control-port-ci` success (run 44982036105), `core10-s0-migrations-ci`
  success, `core10-np06-finance-ci` success, `core10-np05a-manufacturing-ci` success, `CORE10 S1-c canonical approval
  and audit PG17` success, `CORE 10 - Browser Smoke + Forbidden Files` success. Re-check at the doc-only head.

### Not done / NOT_CONNECTED

- Approval thresholds (`approval_thresholds_v1`) apply as GOV-002 defines them: payload `amount` = quantity,
  `unit` = `base_qty`; below a configured minimum GOV-002 refuses the request (NP01 rule, not changed here).
- Quantities are in the item's base unit; UOM decimals per item are not yet enforced.
- Moves between two businesses are refused (an inter-business move is a sale/purchase, NP03B/P2).
- No UI yet (P3). Signed GoTrue / staging: not run (Session A, GO-2/GO-3).

## Next

3. P2 purchase → GRN → QC → stock (A026, PR #73 lot/expiry, Master parties).
4. P3 owner multi-business dashboard; P4 10 × 400 scale test.

### Agent B — 0205 read scale

- New migration `internal/migrations/0205_np03a_inventory_read_scale.up.sql` / `.down.sql` (Claude block 0200-0299).
  `inventory_list_balances_v1` (same signature, error codes `INV_SCOPE` / `INV_INVALID_FILTER`, ordering, keyset
  `next_after`, 200 cap, JSON shape) now resolves the caller's readable site ids of the business ONCE and filters
  balances by `site_id = ANY(...)` (index `stock_balances_business_site_ix`), instead of `can_site` per balance row.
  Rule = `can_site(...,'stock.read')` exactly: a site where the caller has no `site_grants` row reduces to
  `can_business` (computed once); any site with a grant/deny row (live, expired or inactive) is decided by
  `core10.can_site` itself, so explicit denies still beat owner/manager rights. Down restores the exact 0201 body
  (verified: identical `md5(prosrc)` and ACL to a database that never had 0205).
- Differential check (scratch, not committed): old 0201 body vs 0205 over 8 personas (tenant owner with read/post/
  expired/inactive denies, live and expired manager, site-only staff with read/post-only/expired/inactive/denied
  grants, investor, no rights, bad/empty JWT) x 5 businesses (incl. inactive tenant, foreign tenant, missing) x all
  sites + no site + foreign site x 6 limits, walking every keyset page: 2,328 calls, 0 mismatches.
- Local PG17 timings (best of 3), before -> after: balances as branch staff over a whole business 1,152-1,297 ms ->
  15-19 ms (budget 1,500); balances business page (owner) 30-34 ms -> 3-9 ms; site page 3.6 ms -> 1-2 ms.
  `inventory_list_commands_v1` left unchanged: as branch staff over a whole business it is 75-78 ms (budget 300).
- `tests/migrations/np03a-scale.sql` is now a CI step ("B-012 P4 scale: 10 businesses x 400 sites (reads, budgets,
  RPC writes)") right after the owner dashboard e2e; budgets unchanged. Replayed the CI order on one fresh PG17
  database: contract, up/down/up (38), all e2e, scale, registry gate, inventory race: PASS.
- Note: 0205 sorts below 0400/0401 (NP06). Fine for disposable databases; a persistent database that already applied
  04xx would refuse 0205 with OUT_OF_ORDER (none does today: staging is at 0012).

### Agent C — 0206 PO approval

- Branch `agentC/po-approval` (from `build/claude-np03a-stock`); merged into `build/claude-np03a-stock` and pushed by the integrator.
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

### Agent G — 0207

- Branch `agentG/grn-return` (from `build/claude-np03a-stock` @ `54bc588`); local commits only, not pushed.
  Board conflict check (2026-11-22): B-012 row INTEGRATED + staging max 0206; 0207–0299 reserved NP03A; no open PR
  touches 0207. Only migration used: `0207_np03a_grn_cancel_supplier_return` (up + down).
- a) `procurement_cancel_grn_v1(p_grn, p_version, p_reason, p_key)`: received / inspected → `cancelled` (posted
  never); receiver or `can_manage`, plus `stock.post` at the GRN location; authorize, lock PO then GRN (same order as
  receive / post), re-authorize; `control_check_v1(…,'procurement.goods_receipt',site)`; reason 3–300
  (`PROC_CANCEL_REASON_REQUIRED`); request-key replay; audit `procurement.grn_cancel` with the freed quantities.
  `goods_receipts_v1` gets `cancelled_by/at`, `cancel_reason`; status/combination CHECKs replaced (same names) +
  `goods_receipts_v1_cancel_v1`. `_proc_open_qty_v1` ignores cancelled receipts (freed quantity can be received
  again at once); `procurement_advance_po_v1`: a cancelled receipt no longer blocks short-close, and a PO whose
  receipts are all cancelled may be cancelled (body = trunk 0206 incl. post-lock Auth re-check + those two lines);
  `owner_business_sites_v1` "receipts waiting" = received/inspected only (before: `<>'posted'`, counted cancelled).
- b) Supplier return, one document per posted GRN: `supplier_returns_v1` (draft/posted/cancelled, reason, version,
  request key, supplier from the PO) + `supplier_return_lines_v1` (GRN line, item, lot, qty, stock movement).
  `procurement_save_return_v1(p_grn, p_lines, p_reason, p_key)`: GRN must be posted (`PROC_GRN_NOT_POSTED`); per line
  qty ≤ accepted − returned − other open drafts (`PROC_RETURN_EXCEEDS_ACCEPTED`), ≤ `max_return_qty`
  (`CONTROL_LIMIT:max_return_qty`), stock on hand at the GRN location (`PROC_INSUFFICIENT_STOCK`); GRN row lock
  serializes all returns of a receipt. `procurement_advance_return_v1(p_return,'post'|'cancel',v,key)`: post =
  maker-checker (`separate_approver`, `PROC_SAME_ACTOR`), `inventory.stock_event` switch, re-check accepted − returned
  and the limit under the PO → GRN → return locks, then `core10.post_stock_event(location, item, −qty,
  'c10-ret-<id>-<line>')` (insufficient → `PROC_INSUFFICIENT_STOCK`), `returned_qty` += on GRN line and PO line
  (CHECK `returned_qty ≤ accepted`); cancel = creator or `can_manage`. A return does not reopen PO quantity.
  Owner Control feature `procurement.supplier_return` (bn/en, NP03A, max_stages 0, site scope): `reason_required`
  (default true), `separate_approver` (true), `max_return_qty` (100000). Audit `procurement.return_save/post/cancel`.
  `_proc_grn_json_v1` adds cancel fields, `returned_qty` per line and `returns`; `_proc_po_json_v1` adds `returned_qty`.
- c) `procurement_list_lots_v1(p_business, p_site, p_expiring_within_days, p_after_expires_on, p_after_lot, p_limit)`
  STABLE: lots ordered by expiry (none last), accepted / returned / net totals over POSTED receipts at the caller's
  readable sites only (0205 rule: explicit site deny wins), `days_to_expiry`, `expired`, `site_ids`; filter N days
  (0–3650, includes expired); keyset `next_after {expires_on ('infinity' = no expiry), lot_id}`, ≤ 200;
  `on_hand_by_lot: NOT_CONNECTED` (no lot balances; one ledger). Indexes on lot expiry and GRN line lot.
- d) NOT done: no business or PO currency exists in core10 (only `master_price_lists_v1.currency` 0150 and NP06
  accounts 0400), so the 0206 payload unit stays `currency_total`; a GOV-002 threshold on the procurement policy
  still fails closed. Needs an Owner decision (business base currency in setup, or PO currency from the price list).
- Registry: 3 new `enforced` rows (cancel → `procurement.goods_receipt`; save/advance return →
  `procurement.supplier_return`), test `tests/migrations/np03a-supplier-return-e2e.sql`; totals now 54/7/5.
- Down: refuses (`PROC_ROLLBACK_DENIED_RETURN_OR_CANCEL_HISTORY`) once any return, cancelled GRN, returned qty, 0207
  request, 0207 audit row or `procurement.supplier_return` setting/override exists; else restores the 0203 / 0204
  bodies and the TRUNK 0206 `procurement_advance_po_v1`. Verified: on a trunk merge, catalog snapshot (functions
  md5(prosrc)+ACL+config, constraints, columns, indexes, catalog, registry) after up→down = DB that never had 0207.
  On this branch alone the only difference is `procurement_advance_po_v1` gaining trunk's post-lock re-check
  (this branch's 0206 predates PR #129).
- Tests: `np03a-supplier-return-e2e.sql` (tenants 1701/1702; tenant owner, business owner, buyer-manager, godown
  staff, branch staff, foreign owner, unknown user) and `np03a-supplier-return-race.sh` (+ seed, tenant 1703: 4
  concurrent over-return drafts → 1; 4 posters → 1, stock once; cancel vs 3 receivers of the freed qty → ≤ 1).
  CI steps added after the 0206 e2e and after the 0203 race. Local PG17.12, full SQL order of
  `core10-b010-control-port-ci` on one fresh DB 24/24 PASS on the branch AND on a throwaway local merge with trunk
  `ccr-15ed11dd-n3hw5h` @ `98384ab` (deleted after); on the merge also PASS: NP01 bootstrap 3 e2e + race, NP05A 5 e2e
  + 3 races, NP06 e2e/reversal/races/rollback boundary, S1-c 3 e2e, NP01 0110-0114 e2e. Mutations (6, all killed):
  open-qty ignores cancel, no draft reservation, lot read without site scope, no stock switch on return post, no
  post-time re-check (tampered draft), no GRN lock on draft (race: 3 drafts won).
- Not done: UI (GRN cancel button, return screen, lot expiry list); lot-level balances / FEFO / recall; AP debit
  note for returns (NP06); signed staging run; hosted apply of 0207 (needs Owner GO).

### Checkpoint 5 — purchase screen, 0207, shell links, trunk sync (2026-11-22, Agent I integrator)

Landed on `build/claude-np03a-stock` (Draft PR #123 into trunk):
- Agent F (`32f66405`): Purchases screen `core10-purchase.html` + `core10-purchase-{client,ui}.js`, `.css`, `.js` (bn/en;
  business/site choice, paged PO list, PO detail, draft create/edit, approve, send for approval 0206, cancel/close,
  GRN with lot/made/expiry, QC accepted/rejected, post accepted qty). Test `tests/control-centre/purchase-browser.cjs`
  (+ `pu-harness.*`, `pu-seed.sql`), 390/1440. `sql-gateway.cjs`: adds purchase RPCs plus a test-only, column-locked
  table read `core10.stock_locations (id, site_id, code)` through RLS (no location-list RPC exists yet).
- Agent G (`aa7ed5cf`): `0207_np03a_grn_cancel_supplier_return` (see "Agent G — 0207" above) + e2e and race tests.
- Agent H (`6fe88668`) then `8c9d8ee4`: Owner-only shell links Owner dashboard + Purchases (header and `?biz=N`).
- Trunk sync `416a7e50` = merge of `ccr-15ed11dd-n3hw5h` @ `6424aabe`. Session A integrated our 0201–0206 as the
  isolated PR #129 (`ac86ee80`, with post-row-lock Auth re-checks in 0201/0203/0206 and a revocation race in
  `np03a-inventory-race.sh`) and hosted 0201–0206 on staging; PR #123 itself was NOT merged (kept open as this
  branch's Draft PR). Conflicts: 0201/0203/0206 up files and `np03a-inventory-race.sh` = TRUNK version; workflow,
  `sql-gateway.cjs`, this handoff = union. 0207 `procurement_advance_po_v1` = trunk 0206 body (incl. re-check) + the
  two cancelled-receipt lines, so no trunk guard is lost. Migration numbers unique; only new number is 0207.

Decision — Stock operations screen NOT built: ChatGPT lane B-038 (PR #126) already has a live signed stock workbench
(`/#/stock`). Links `core10-stock-ops-entry` / `core10-stock-ops-biz-entry` and their assertions removed (no link to
a missing page). Gaps to request from the ChatGPT lane for that workbench: balances list, cancel action, the
`inventory_request_approval_v1` (0202) path, bn/en `INV_*` / `CONTROL_*` messages, paging, item picker, PG17 tests.

Local results at `416a7e50` (PG17 disposable cluster, one fresh DB per workflow job, steps in workflow order):
| Workflow / job | Result |
|---|---|
| core10-b010-control-port-ci / control-port (incl. 5 Chromium tests) | 31/31 PASS (Chromium install skipped: preinstalled) |
| core10-s0-migrations-ci / migrations | 2/2 PASS |
| core10-s1c-canonical-approval-ci / s1c-approval-audit | 6/6 SQL+JS PASS; python Playwright smoke NOT RUN locally (module not installed; runs on GitHub) |
| np01-s1c-remainder-ci / np01-negative-proof | 17/17 PASS |
| core10-np06-finance-ci / finance-pg17 | 10/10 PASS |
| core10-np05a-manufacturing-ci / manufacturing | 19/19 PASS (browser install skipped) |
Shell navigation 16/16, purchase browser PASS, supplier-return e2e + race PASS. GitHub CI: see PR #123 checks.

Open items:
- PO approval threshold currency: core10 has no business currency (`currency_total` is not a GOV-002 unit), a
  threshold on the procurement policy still fails closed → Owner decision (business base currency vs price-list).
- Location list RPC to replace the test-gateway table read of `core10.stock_locations` (hosted client needs it).
- Lot balances / FEFO / recall (0207 has only the lot expiry read; `on_hand_by_lot: NOT_CONNECTED`).
- AP debit note for supplier returns (NP06 lane).
- UI for GRN cancel and supplier return (RPCs exist in 0207; no buttons yet).
- Signed staging GO-2 (apply 0207) and GO-3 (publish purchase screen) need Owner GO; nothing hosted from here.


### Agent K — 0209 lots

Conflict check (2026-11-22): board row B-012 (this lane) owns "lot/expiry from PR #73 on the one stock ledger";
0208–0299 reserved NP03A, 0208 = Agent J. No open PR or trunk migration has lot balances / FEFO / recall: NP05A
(trunk 0500–0504 and PR #112) carries only a free-text `lot_ref` with `lot_validation: NOT_CONNECTED`. PR #73
(A058) is a `c10_demo` draft with its own `quality_balances_v1` second book — reused for ideas only.

Migration `internal/migrations/0209_np03a_lot_balances_fefo_recall.up.sql` (+ exact `.down.sql`):
- **One book.** `core10.stock_movements` stays the only quantity ledger. New `core10.stock_movement_lots_v1` is the
  lot *dimension* of a movement (movement → lot, signed quantity, |sum| ≤ |delta|, rest untracked; append-only).
  Lot balances are derived: view `stock_lot_balances_v1`; `inventory_lot_reconciliation_v1` proves per
  location/item `0 ≤ sum(lots) ≤ on_hand`, no lot < 0. No stored lot quantity anywhere.
- **Engine path only.** `post_stock_event` / `transfer_stock_v1` (0200, internal) are re-created with identical checks
  and order plus one call to `_stock_lot_apply_v1` under the same balance row lock. The lot comes from the source
  document of the server-built request key (`c10-grn-<grn>-<line>`, `c10-ret-<return>-<line>`, `c10-inv-cmd-<id>`),
  so 0201 `advance_inventory_command_v1`, 0203 `procurement_post_grn_v1` and 0207 `procurement_advance_return_v1` are
  NOT replaced. Lot-less issue: untracked first, then released lots FEFO; a transfer's in-leg carries the out-leg's
  lots (a lot follows its stock). Existing movements are backfilled in id order with the same rules (fail closed).
- **Lot-aware commands:** `inventory_create_lot_command_v1(business, kind, source, destination, item, qty, lot, reason,
  key)` = `create_inventory_command_v1` + lot (`inventory_commands_v1.lot_id`); confirm/post through the unchanged
  0201/0202 lifecycle (GOV-002 payload now includes `lot_id` when present).
- **Hold / release:** `inventory_lot_hold_v1(lot, 'hold'|'release', reason, key)`, managers/owners only. Held,
  rejected or recalled lots: named issue/transfer refused (`INV_LOT_HELD|REJECTED|RECALLED`), lot-less issue may not
  consume their stock (`INV_LOT_BLOCKED_STOCK`); write-off (`adjust_out`) and supplier return allowed. Expired lot:
  named issue/transfer refused (`INV_LOT_EXPIRED`), write-off allowed.
- **FEFO:** `inventory_fefo_v1(business, site, item, qty)` read-only suggestion (expiry, lot, location; excludes held /
  recalled / expired; shortfall, untracked available; nothing reserved).
- **Recall:** `inventory_lot_start_recall_v1(lot, severity, reason, key)` blocks the lot and (param
  `include_genealogy`) every descendant from `inventory_lot_link_v1(parent, child, key)`; returns where the stock is
  (site/location/lot/qty), remaining total and receipts; `inventory_lot_recall_v1(recall)` scoped read;
  `inventory_lot_close_recall_v1(recall, note, key)` only at zero stock (param `close_requires_zero_stock`); recalled
  lots stay blocked after close. `inventory_list_lot_balances_v1` = scoped keyset read of lot balances.
- Owner Control features `inventory.lot_control` (reason_required, separate_releaser) and `inventory.lot_recall`
  (close_requires_zero_stock, include_genealogy), max_stages 0; 5 writers enforced in the DEC-08 registry; canonical
  audit source `inventory`; request ledger `inventory_lot_requests_v1`; pinned search_path; RLS; RPC-only; no anon.
- Lock order lot → audit chain head everywhere (the race test found a create-vs-hold deadlock; fixed by share-locking
  the lot before the inner create).

Tests: `tests/migrations/np03a-lots-e2e.sql` (tenants 1901/1902), `tests/migrations/np03a-lots-race.sh` + seed
(tenant 1903); CI steps added after the 0207 steps in `core10-b010-control-port-ci.yml`. Existing tests unmodified.
Local PG17.12: control-port workflow mirror 31/31 PASS (incl. registry gate + self-test, evidence, contract,
up/down/up, B-009 drift + self-test, scale, all races), purchase browser 12/12; exact-down catalog diff vs a 0207-only
database = identical (1529 objects); backfill on pre-0209 data (lot GRN, return, lot-less issue, transfer) + down + up
PASS; 3 mutants killed (no blocked-stock check, no in-leg lot mirror, no Control check on hold).

Not done / NOT_CONNECTED: lot UI (no screen), `procurement_list_lots_v1` still says `on_hand_by_lot: NOT_CONNECTED`
(use `inventory_list_lot_balances_v1`), supplier-return draft checks location stock not lot stock (posting checks the
lot: raw `insufficient_lot_stock`), lot creation outside GRN (manufacturing output lots: NP05A port), approval stages
for lot features (max 0), one-time Control override consumed at posting can still deadlock-abort against a hold
(PG aborts one; retry), no hosted apply (GO-2 needed).


### Checkpoint 6 — 0208 locations, purchase return/cancel UI, 0209 lots, board requests (2026-11-22, Agent M integrator)

Landed on `build/claude-np03a-stock` (Draft PR #123 into trunk; nothing hosted, nothing merged to trunk/main):
- Agent J (`0376670b`, `a685e3f8`): `0208_np03a_location_list` — `inventory_list_locations_v1(business, site)`, scoped
  read-only location list (same rows as the `location_scope_read` row policy per persona, explicit site denies win,
  `can_post`, 2000 cap, `truncated`); test `tests/migrations/np03a-locations-e2e.sql`. Purchases screen: store
  locations from 0208 (the test-only gateway table read of `core10.stock_locations` is removed from client, gateway
  and harness), GRN cancel with reason, return to supplier (draft / post / cancel with confirmation, maker-checker
  wording, formula), lot expiry list (N-days filter, keyset paging), bn/en messages.
- Agent K (`f20d6066`): `0209_np03a_lot_balances_fefo_recall` (see "Agent K — 0209 lots" above) + e2e, race + seed.
- Merges: J then K (one conflict: workflow steps, union in order 0207 → 0208 → 0209); trunk `ccr-15ed11dd-n3hw5h`
  @ `327029db` (§7b/§7c legacy move to `legacy/islamia-erp/`, central shell import; no conflict, no trunk change to
  0200–0206 or to our tests; migration numbers unique, ours are 0207/0208/0209).
- Agent M (`bcc9bbdf`): (1) supplier-return post through the 0209 lot-aware engine whose received lot no longer holds
  the quantity raised raw `insufficient_lot_stock` → `core10-purchase-client.js` maps the raw engine messages
  `insufficient_lot_stock` / `lot_blocked_stock` / `insufficient_stock` to `PROC_INSUFFICIENT_STOCK` (bn/en "this
  store does not have that much stock"), no SQL change; new browser step proves it at 1440 en and 390 bn with no
  movement written (mutant without the mapping fails). (2) Calendar time bombs removed: lot expiry dates in
  `purchase-browser.cjs` (2027-01-31 / 2027-05-01, incl. the Bangla-digit date check) and
  `np03a-procurement-e2e.sql` (2027-11-01) are now `current_date + N`; same assertions.
- Agent M: trunk's new §7b gate `core10-file-classification-ci` (job `classification`) failed on `bcc9bbdf` and
  `64da3ee6`: our five root files `core10-purchase{-client.js,-ui.js,.css,.html,.js}` were tracked but unclassified
  in `docs/coordination/FILE_CLASSIFICATION.json`. Root-cause fix: they are added as `TRUNK_UNSHIPPED` (the Purchases
  screen is not in the preview LIVE pins); the gate itself is unchanged.

**IMPORTANT for Session A review (trunk owner):** 0209 re-creates the HOSTED 0200 engine functions
`core10.post_stock_event` and `core10.transfer_stock_v1` (`CREATE OR REPLACE`, same signature, same checks in the
same order, plus one `_stock_lot_apply_v1` call under the same balance row lock), and backfills
`stock_movement_lots_v1` from existing movements (fails closed on conflict). Its down restores the exact 0200 bodies
(and 0202 `_inventory_approval_payload_v1` / `_inventory_command_json_v1`). This changes the behaviour of the one
stock ledger for every caller (lot-less issues now refuse held/recalled lot stock: `lot_blocked_stock`), so it needs
careful trunk-owner review and an Owner GO-2 before any hosted apply. 0207–0209 are branch-only.

Board requests (Coordination Board, filed by this lane):
- **B-012-REQ1** (row 43) → ChatGPT lane B-038 stock workbench (`/#/stock`, PR #126): balances list, command cancel,
  the 0202 `inventory_request_approval_v1` path, bn/en `INV_*` / `CONTROL_*` messages, paging, item picker, PG17
  tests; can now use 0208 `inventory_list_locations_v1` and 0209 lot reads/commands.
- **B-012-REQ2** (row 44) → NP06 Finance lane: AP link for GRN posting (supplier liability) and supplier returns
  (debit note); B-012 writes stock only, no money/COGS/accounting result is produced here.

Open items:
- PO approval threshold currency — Owner decision (business base currency vs price-list; threshold fails closed).
- Lot UI (hold/release, recall, FEFO suggestion, lot balances) — RPCs exist in 0209, no screen yet.
- Supplier-return draft checks location stock, not lot stock (post checks the lot; UI now shows the stock message).
- Manufacturing output lots via an NP05A port (0209 creates lots only from GRN).
- Lot features have no approval stages (Owner Control max_stages 0).
- Signed staging GO-2 (apply 0207–0209) and GO-3 (publish purchase screen) need Owner GO; nothing hosted from here.

Local results at `bcc9bbdf` (PG17.12 disposable cluster, one fresh cluster per workflow job, steps in workflow order):
| Workflow / job | Result |
|---|---|
| core10-b010-control-port-ci / control-port (incl. 5 Chromium tests) | 34/34 PASS (Chromium install skipped: preinstalled) |
| — purchase browser / shell nav / OCC / master data / owner dashboard | 18/18, 16/16, 19/19, 17/17, 7/7 PASS |
| core10-s0-migrations-ci / migrations | 2/2 PASS |
| core10-s1c-canonical-approval-ci / s1c-approval-audit | 6/6 SQL+JS PASS; python Playwright smoke NOT RUN locally (module not installed; runs on GitHub) |
| np01-s1c-remainder-ci / np01-negative-proof | 17/17 PASS |
| core10-np06-finance-ci / finance-pg17 | 10/10 PASS |
| core10-np05a-manufacturing-ci / manufacturing | 19/19 PASS (browser install skipped) |
| core10-file-classification-ci / classification (after the classification fix) | 3 node tests PASS (3/3, 1/1, 1/1) |
| after second trunk sync `3087de93` (trunk @ `2e06b753`, B-040 signed shell context; no conflict): core10-central-shell-import-ci 10/10, core10-file-classification-ci 4/4, core10-legacy-quarantine-ci 11/11 PASS (Chromium install skipped) | PASS |
GitHub CI: see PR #123 checks for the pushed head.

### Checkpoint 7 — Owner decision: PO approval currency BDT (0210)
Owner decision 2026-11-23 (typed by the Owner in chat): the currency for purchase-order approval thresholds is **BDT**.
This closes the open item "PO approval threshold currency" above (0206/0207 notes on `currency_total`).
- Code commit `514d2f5176b565d2391a50ef07e5448ba0094558` on `build/claude-np03a-stock` (Draft PR #123), NOT hosted.
- `internal/migrations/0210_np03a_po_approval_bdt.up.sql`: CREATE OR REPLACE `_proc_po_approval_payload_v1` →
  `unit` = `'BDT'`, `amount` = `total_amount::numeric(20,2)` (JSON number, ≤ 2 decimals). Request and approve gate both
  rebuild through this one builder, so submission and verification payloads are identical. `procurement_request_po_approval_v1`
  = 0206 body except an earlier request blocks a new one only when its payload digest equals the current payload.
  0206 (hosted) is unchanged; 0207 `procurement_advance_po_v1` and the 0206 gate are not redefined (they call the builder).
- Pre-0210 requests (unit `currency_total`) fail closed: approve → `approval_stale_or_payload_changed`; the PO stays a
  draft; the maker requests again and the fresh BDT request goes through threshold/route/stage checks. Proven on a real
  upgrade path (0209 DB with genuine 0206 approved + pending requests → apply 0210 → stale approve refused, both POs
  re-requested, re-approved). Down restores the exact 0206 bodies (BDT requests then fail closed the same way).
- GOV-002 rules are unchanged: amount < minimum → `approval_threshold_not_met`; a threshold with fewer decimals than the
  total → `approval_threshold_precision_invalid`; non-BDT unit (e.g. USD, KG) → `approval_threshold_unit_or_amount_invalid`;
  `currency_total` cannot be configured at all (`invalid_approval_threshold`). Threshold must be set on a new policy version
  before any request uses it (`approval_threshold_policy_in_use`).
- Test `tests/migrations/np03a-po-approval-bdt-e2e.sql` (tenants 2001/2002) + CI step after the 0209 step; it fails without 0210.
- Local PG17.12: core10-b010-control-port-ci 35/35 PASS (Chromium install skipped, preinstalled); throwaway merge with trunk
  `origin/ccr-15ed11dd-n3hw5h` @ `7b82b9d7` (clean, doc-only trunk delta, deleted after): b010 31/31 SQL+node PASS (browser
  steps skipped there), s0 2/2, s1c 6/6, np01-s1c 17/17, np06 16/16, np05a 15/15 non-browser, legacy quarantine 13/13 PASS.
  np06-crosslane and np01-bootstrap-release-gate NOT RUN locally (matrix / service DB harness; not triggered by PR #123).
- GitHub CI on `514d2f51`: 10/10 SUCCESS (b010, s0, s1c, np06, np05a, A044, A045, browser smoke, §7b classification, §7c quarantine).
- Not done: no business/PO currency column (single fixed BDT by Owner decision; multi-currency needs a new Owner decision);
  staging apply of 0207–0210 needs Owner GO-2.
