# Owner Control port — integration contract (B-010, DEC-08)

Migrations `0100`–`0102` (pack block NP02). Source of truth: `internal/migrations/0100..0102*.sql`.
Tests: `tests/migrations/np02-control-e2e.sql`, `control-registry-check.sql`, `control-race.sh`.

## What the Owner can control, per business and optionally per site

| Control | Stored as | Enforced by |
| --- | --- | --- |
| On / off | `enabled` | `core10.control_check_v1` raises `CONTROL_DISABLED:<feature>` |
| Approval stages 0–5 | `stages` (≤ catalog `max_stages`) | the feature RPC reads `stages` from the check result |
| Parameters (limits, tolerances, options) | `params`, typed by the catalog descriptor | validated on write; the feature RPC reads `params` |
| Effective date | `effective_from` (not older than 5 minutes, not later than 366 days) | version resolution |
| Site override and "follow business" | a version with `site_id`, or `inherit=true` | site → business → catalog default |
| One-time exception | `control_overrides_v1` | consumed by `control_check_v1`, audited |
| History and undo | `control_setting_versions_v1`, append-only | `control_revert_v1` writes a new version |

Writers are the tenant owner or a business owner (`core10.can_manage`, current and unexpired). Members who can
see the business (`can_see_business`) may read. Every change and exception is one event in the canonical audit
stream (`source_domain='control'`). An integrity invariant (`audit.immutability`, `tenant.isolation`,
`access.expiry_revocation`) is in the catalog with `invariant=true` and can never be changed or excepted.

## Calling the port from a feature RPC (the only supported pattern)

```sql
CREATE FUNCTION core10.example_post_v1(p_business bigint, p_site bigint, p_qty numeric, p_key text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE c jsonb;
BEGIN
 -- 1. the RPC's own Auth-port checks (can_site / can_business / can_approval_action_v1) come first
 -- 2. then the Control check; it raises CONTROL_DISABLED unless the Owner allowed the feature or granted an exception
 c := core10.control_check_v1(p_business, 'inventory.stock_event', p_site);
 IF p_qty > (c->'params'->>'max_adjust_qty')::numeric THEN RAISE EXCEPTION 'CONTROL_LIMIT:max_adjust_qty'; END IF;
 -- 3. (c->>'stages')::int is the number of approval stages the Owner requires: 0 = post now, n = open an n-stage route
 ...
END $$;
```

`control_check_v1` is not executable by API roles; only another `SECURITY DEFINER` function can call it.
`core10.control_approval_binding_v1(business, feature, site)` is the read-only view for clients and the approval engine.

## Adding a feature (every pack, every Detail ID)

1. In your own migration block, `INSERT INTO core10.control_catalog_v1(...)`: bilingual title, pack, default on/off,
   `default_stages`/`max_stages`, optional `approval_domain`/`approval_action`, and a `params` descriptor
   (`int|numeric|text|bool|enum` with default and limits). Nothing a business could want different stays a constant.
2. Register every state-changing RPC of the feature in `core10.control_rpc_map_v1` as `enforced`.
3. The RPC calls `control_check_v1` as above. The CI gate fails if an RPC is unmapped, if an `enforced` RPC does not
   call the check, or if a function is executable by `anon` or PUBLIC.

A state-changing RPC is any `VOLATILE` function in `core10` executable by `authenticated` (PostgreSQL refuses writes in
a `STABLE` function, so naming cannot hide it). A feature is not finished until it is `enforced`.

## Error codes (message prefix)

`CONTROL_SCOPE` (not visible to the caller) · `CONTROL_FORBIDDEN` (visible, not an Owner) · `CONTROL_DISABLED:<feature>` ·
`CONTROL_INVARIANT` · `CONTROL_UNKNOWN_FEATURE` · `CONTROL_STALE_VERSION:<current>` · `CONTROL_REPLAY_CONFLICT` ·
`CONTROL_PARAM_UNKNOWN|TYPE|RANGE|ENUM:<name>` · `CONTROL_PARAMS_SHAPE` · `CONTROL_STAGES` · `CONTROL_EFFECTIVE_PAST|FUTURE` ·
`CONTROL_NO_SUCH_VERSION` · `CONTROL_OVERRIDE_CLOSED` · `CONTROL_BAD_KEY|REASON|HOURS|INPUT` · `CONTROL_UNAUTHENTICATED`.

## Bindings for the NP01 lane (B-005 to B-008, ChatGPT)

Current registry rows are `pending`; each becomes `enforced` when its RPC calls the check (change the row in your own
migration, `0013`+). Keys follow `NP01_OWNER_CONTROL_HANDOFF.md`.

| Feature key | RPCs to bind | Bind how |
| --- | --- | --- |
| `gov002.approval_policy` | `publish_approval_policy_v1` | check before publishing; use `params.ttl_minutes` as the default TTL |
| `gov002.review` | `submit_typed_approval_v1`, `configure_approval_route_v1`, `decide_approval`, `delegate_approval_stage_v1`, `revoke_approval_delegation_v1`, `withdraw_typed_approval_v1` | check on submit; the route length is `stages` from the check (0 = no route, post directly); `params.exception_escalation` toggles escalation |
| `gov003.review_export` | your 0016 readiness, risk and export RPCs | check on every call; `params.max_rows` caps exports; default is **off** |
| `setup001.profile_preview` | read-only preview (STABLE, no registry row needed) | none |
| `setup001.provision` | `build01_setup_v1`, `build01_site_v1`, `setup_business_v1`, `setup_industry_draft_v2` | check before provisioning; `params.max_sites` caps a setup |
| `inventory.stock_event` | `post_stock_event` (Claude, B-012) | not NP01 |

Rows for `build01_set_access_v1`, `change_access_v1`, `build02a_set_approval_policy_v1` are `exempt`: Auth-port
administration, not a business feature. New RPCs from your `0014`–`0016` that are VOLATILE and API-callable need a row
(`enforced` once bound, or `pending` with a board row). The `0013` TRUNCATE guard stays an invariant, not a setting.

## Registry evidence and migration order (B-020 coordination, 0103)

An RPC becomes `enforced` only when both hold:

1. Its current definition calls `core10.control_check_v1(<business>, '<its feature key>', ...)` with the exact mapped
   key (`core10._control_rpc_calls_check_v1`), and
2. Its registry row names a proof test (`test_ref`) that exists, calls the RPC, asserts `CONTROL_DISABLED`, and is run
   by a CI workflow (`tests/migrations/control-registry-evidence.sh`).

Order matters. Migrations `0013`–`0099` run before the registry exists (`0100`), so an NP01 migration cannot change
registry rows. Promotion therefore happens in a migration numbered after `0102`, through
`core10._control_registry_promote_v1(rpc, test_ref)`, which promotes only when the evidence holds and otherwise leaves the
row `pending` and says why. `0103` does this for `publish_approval_policy_v1` (your `0018`, proof
`tests/migrations/np01-control-publish-e2e.sql`): on trunk without `0018` it stays pending; with PR #107 integrated it is
enforced. The gate prints `PROMOTE_READY` for a pending RPC that already calls the check.

Numeric order is apply order, and `run.sh` now refuses `OUT_OF_ORDER` on a database that already holds a higher version.
Ranges are in `docs/coordination/MIGRATION_RESERVATIONS.json`. Consequences:

- PR #107 (`0013`–`0018`) must be integrated into trunk **before** `0100`+ reaches any persistent database (B-022).
- NP01 work that depends on the Control port, including registry promotions for your next bindings, uses the new NP01
  range `0110`–`0149` (after the Control port), not `0019`+.
- A file whose number is below a persistent database's maximum is renumbered by the trunk owner at integration
  (rename only; content and checksum unchanged).

### Registry state today

| | trunk (no PR #107) | trunk + PR #107 (verified locally) |
| --- | --- | --- |
| enforced | 0 | 1 (`publish_approval_policy_v1`) |
| exempt | 7 | 7 |
| pending | 14 | 13 |

The six RPCs your `0017` fenced (no `authenticated` execute) are not API-callable, so they need no row until you re-grant
them; re-granting requires a row in the same migration range, `enforced` with evidence or `pending` with a board row.

## Owner Control Centre (B-021)

`core10-owner-control-centre.html` (linked from the Owner header in the Central shell next to Control Studio) uses only
`build01_context_v1` and the `control_*` RPCs, including `control_audit_v1` (`0104`). Business and site selection,
on/off, approval stages, typed parameters with bilingual labels (`0105`), effective date, site override or follow-business,
history with revert, one-time exceptions, and the Control audit with chain status. Non-owners get view-only controls and no
history/exception/audit tabs; the server refuses them anyway. The page accepts only the CORE10 staging project or a loopback
test backend (`core10-control-centre-config.js`; key left empty until the Owner approves Level 2) and never the legacy
IMG-ERP-SG or a live business project. A044 Control Studio (menu placement) remains separate; folding placement into this
catalog is a later task.

## Not in this slice

The natural-language request path (A052 owner intent) and the first real consumers beyond NP01 (Master Data, NP02) follow in B-011.
No hosted database has been changed by this slice.
