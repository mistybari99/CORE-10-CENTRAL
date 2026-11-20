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

## Delivered ports (trunk, CI green) — how NP03B / NP05A / NP06 bind

| Port | Signature | Behaviour |
|---|---|---|
| Sales validation (NP03B) | `core10.master_validate_sales_order_v1(p_business bigint, p_site bigint, p_doc jsonb) RETURNS boolean` (0151) | Exactly the 0301 hook. FALSE (never raises) for unknown/other-business/inactive customer (must be `customer` or `both`), price list (sales, active, effective today, site null or = p_site), item, variant, UOM of another dimension than the item base UOM, quantity ≤ 0, malformed ids, or `unit_price` ≠ list price for the highest `min_quantity` tier ≤ quantity. |
| UOM conversion (NP05A) | `core10.master_uom_convert_v1(p_business, p_from_uom, p_to_uom, p_quantity) RETURNS numeric` (0151) | Identity, direct or inverse factor inside one dimension; `MASTER_UOM_SCOPE` / `MASTER_UOM_NO_CONVERSION` / `MASTER_UOM_BAD_QUANTITY`; never guesses. |
| Item status (NP05A) | `core10.master_item_usable_v1(p_business, p_item) RETURNS boolean` (0151) | Active item in that business. |
| Parties (NP06 AR/AP) | FK `(id, tenant_id, business_id)` → `core10.master_parties_v1` (0150) | `party_kind` customer/supplier/both; `status` active/inactive/blocked/draft. |

The three functions are internal (no API grant). Call them from your own SECURITY DEFINER code; replace only your own placeholder (`_mfg_master_check_v1`, NP03B `to_regprocedure` check already binds automatically). Writers (`master_save_*_v1`) are Owner-Control-enforced (`master.uom|item|party|price`); readers (`master_list_*_v1`, `master_get_*_v1`, `master_find_barcode_v1`) are STABLE, `can_see_business`-scoped.
