# NP02 / B-011 Master Data — contract and plan (Claude, migrations 0150–0199)

Status: DESIGN + IN_PROGRESS. Nothing hosted. REUSE FIRST → FIX SECOND → BUILD MISSING LAST.

## Reuse (inspected 2026-11-16)

- `core10.items` exists (0002): `id, tenant_id, business_id, sku`, `UNIQUE(id,tenant_id,business_id)`, `UNIQUE(business_id,sku)`.
  **Kept and extended in place** (ALTER TABLE, nullable/defaulted columns), never replaced: Codex NP05A (0500) has FKs to `core10.items(id,tenant_id,business_id)`.
- No existing core10 UOM, party, variant, barcode, category or price-list tables. Legacy `c10_a055_assets_core_v1.sql` is asset-register scope, not item master.

## Ports other lanes already call (must match exactly)

| Caller | Hook | Contract |
|---|---|---|
| Codex NP03B 0301 | `core10.master_validate_sales_order_v1(p_business bigint, p_site bigint, p_doc jsonb) RETURNS boolean` | read-only; `p_doc` keys: `customer_id`, `price_list_id`, `lines[]` with `item_id`, `variant_id`, `uom_id`, `quantity`, `unit_price`, `discount_percent`, `tax_percent`. FALSE/NULL/absent ⇒ order refused. |
| Codex NP05A 0500 | `core10._mfg_master_check_v1(p_recipe bigint)` (placeholder raising `NOT_CONNECTED:MASTER_UOM`) | needs versioned UOM identities, same-dimension conversions, item status. NP02 supplies `core10.master_uom_convert_v1` / item-status checks; NP05A rebinds its placeholder. |

## Plan

1. **0150** tables: `uoms` (business-scoped, dimension count/mass/volume/length/time, decimals), `uom_conversions` (same dimension only, factor > 0), item columns (names bn/en, category, base UOM, status, version), `item_categories`, `item_variants`, `item_barcodes` (unique per business), `parties` (customer/supplier/both), `price_lists`, `price_list_items`. RLS on, no direct table grants.
2. **0151** RPCs: Control-enforced writers (`control_check_v1`, features `master.*`, registry rows + CI proof), scoped readers, `master_validate_sales_order_v1`, UOM convert/check.
3. Tests: `tests/migrations/np02-master-e2e.sql` (personas, cross-tenant negatives, Control disabled, NP03B contract cases), registry evidence, CI steps.

## Not in scope here
Stock (B-012), Money (NP06), Sales/POS (NP03B), manufacturing (NP05A).
