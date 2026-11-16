# CORE10 S0 — canonical schema, engine ports and shell route contract

Status: S0 consolidation contract. Source: Code Gap Audit C10-AUDIT-CG-01 and Owner-delegated
decisions C10-AUDIT-CG-01-DEC (DEC-01, DEC-03, DEC-04). The Master Decision Book stays the
authority; this file is the implementation contract agents build against.

## 1. Schemas

| Schema | Purpose |
| --- | --- |
| `core10` | Canonical engine: every real table and RPC. Created by `internal/migrations` |
| `c10_demo` | Synthetic fixtures, seeds and disposable tests. No engine remains here once a module is ported |
| `c10_sim` | Simulation sandbox (PR #77), stays separate |
| `public` (IMG-ERP-SG) | Protected legacy. Never created, altered or read by canonical migrations |

`c10_gov003_demo` (PR #85) merges into `core10` during S1; it does not keep its own tenancy tables.

## 2. The five engine ports

Every feature, in every pack and every industry template, reaches an engine only through these
ports. A feature may not own a second store of the same kind.

| Port | Single engine | Entry points today (`c10_demo`, become `core10` in the named step) | A feature must not |
| --- | --- | --- | --- |
| Auth | Build01 canonical access | `actor_uid()`, `can_tenant`, `can_business`, `can_manage`, `can_site(tenant,business,site,action)`, `can_approval_action_v1` — S1 | keep its own grant/role table, or trust a submitted role |
| Master | NP02 party / item / UOM / price | to be built — S2 | copy customers, suppliers or items into module tables |
| Stock | A048 inventory command ledger | `create_inventory_command_v1`, `advance_inventory_command_v1`, `post_stock_event` — S3 | keep its own balance or movement table |
| Money | NP06 source-linked journal | to be built — S5 | keep a ledger, payable or receivable of its own |
| Approval + Audit | GOV-002 approval, one canonical audit event | reconciled from PR #78–#99 and PR #85 — S1 | run a private approval cycle or a separate audit chain |

Known violations to remove (Change Register):

| Violation | Fix | Change |
| --- | --- | --- |
| A055 assets use `am_grants` / `ami_need_cap` instead of `can_site` | Map asset capabilities to Auth-port actions | CHG-004 |
| Per-module audit tables (`wf_audit`, `am_audit`, `a056_audit`, control/engine/intent) | Emit the canonical audit event; local tables become views or are retired | CHG-005 |
| PR #73 `quality_balances_v1` / `quality_movements_v1` | Lot/QC state on top of the Stock port | CHG-035 |
| PR #78–#99 `approval_demo_stock_*` | Drop; approvals execute through the Stock port | CHG-011 |
| PR #85 own `tenants/businesses/memberships` | Read canonical hierarchy | CHG-012 |
| A056 `a056_TEST_ADAPTER_create_order_v1` | Real order adapter | CHG-042 |

### NOT_CONNECTED rule

Feature work runs in parallel with engine work (Track B beside Track A). When a port's engine is
not verified yet, the feature is written against the port contract and its link reports
`NOT_CONNECTED` (the A053 pattern). It is counted complete only after the link is real and the
persona scenarios pass.

## 3. Shell route contract

A module is done only when a signed user reaches it from the one Central app.

1. Entry is the Central shell (`index.html` / `owner.html`, `core10-shell.js`). Standalone module
   HTML pages are development surfaces, not deliverables.
2. The shell asks the server for the signed context (`build01_context_v1` → later
   `core10.context_v1`): actor, authorised businesses, sites, role, effective actions.
3. Navigation comes from the server (`pack02_nav_v1`): a module appears only when the business
   has it enabled and the actor holds at least one action in it. Hiding a menu is never the
   permission; every RPC re-checks the Auth port.
4. A module route receives `{tenant_id, business_id, site_id}` from the shell context, never from
   the URL or local storage alone, and shows an honest "not connected" state when a port is missing.
5. Switching business clears module state; sign-out purges cached data.
6. Each route works at 390 px and 1440 px, Bangla and English.

## 4. Verification model (DEC-04)

The Owner reviews with the Owner ID only. Agents run the 16 demo personas through each
template's full daily scenario (UI → RPC → database → report) with tenant, business, site, role,
expiry, revoke, replay, concurrency and rollback negatives, on disposable databases with
synthetic data. Each step ends with a persona × scenario result table at an exact commit.
