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

### Not done / NOT_CONNECTED

- Approval thresholds (`approval_thresholds_v1`) apply as GOV-002 defines them: payload `amount` = quantity,
  `unit` = `base_qty`; below a configured minimum GOV-002 refuses the request (NP01 rule, not changed here).
- Quantities are in the item's base unit; UOM decimals per item are not yet enforced.
- Moves between two businesses are refused (an inter-business move is a sale/purchase, NP03B/P2).
- No UI yet (P3). Signed GoTrue / staging: not run (Session A, GO-2/GO-3).

## Next

3. P2 purchase → GRN → QC → stock (A026, PR #73 lot/expiry, Master parties).
4. P3 owner multi-business dashboard; P4 10 × 400 scale test.
