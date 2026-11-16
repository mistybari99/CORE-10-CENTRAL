-- Rollback of 0150: drop the NP02 master tables and the item columns added in place.
-- core10.items itself (0002) and its original columns are kept.
DROP TABLE IF EXISTS core10.master_price_list_items_v1;
DROP TABLE IF EXISTS core10.master_price_lists_v1;
DROP TABLE IF EXISTS core10.master_parties_v1;
DROP TABLE IF EXISTS core10.master_item_barcodes_v1;
DROP TABLE IF EXISTS core10.master_item_variants_v1;
ALTER TABLE core10.items
 DROP CONSTRAINT IF EXISTS items_base_uom_fk,
 DROP CONSTRAINT IF EXISTS items_category_fk,
 DROP CONSTRAINT IF EXISTS items_sku_format_chk,
 DROP COLUMN IF EXISTS updated_by, DROP COLUMN IF EXISTS updated_at, DROP COLUMN IF EXISTS version,
 DROP COLUMN IF EXISTS status, DROP COLUMN IF EXISTS base_uom_id, DROP COLUMN IF EXISTS category_id,
 DROP COLUMN IF EXISTS item_kind, DROP COLUMN IF EXISTS name_bn, DROP COLUMN IF EXISTS name_en;
DROP TABLE IF EXISTS core10.master_item_categories_v1;
DROP TABLE IF EXISTS core10.master_uom_conversions_v1;
DROP TABLE IF EXISTS core10.master_uoms_v1;
