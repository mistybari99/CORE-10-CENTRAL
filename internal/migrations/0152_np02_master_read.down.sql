-- Rollback of 0152 (read-only functions; no data).
DROP FUNCTION IF EXISTS core10.master_find_barcode_v1(bigint,text);
DROP FUNCTION IF EXISTS core10.master_get_price_list_v1(bigint,bigint,integer,bigint);
DROP FUNCTION IF EXISTS core10.master_list_price_lists_v1(bigint,text);
DROP FUNCTION IF EXISTS core10.master_list_parties_v1(bigint,text,text,text,integer,bigint);
DROP FUNCTION IF EXISTS core10.master_list_uoms_v1(bigint);
DROP FUNCTION IF EXISTS core10.master_list_categories_v1(bigint);
DROP FUNCTION IF EXISTS core10.master_get_item_v1(bigint,bigint);
DROP FUNCTION IF EXISTS core10.master_list_items_v1(bigint,text,text,bigint,integer,bigint);
DROP FUNCTION IF EXISTS core10._master_like_v1(text);
DROP FUNCTION IF EXISTS core10._master_page_v1(integer);
DROP FUNCTION IF EXISTS core10._master_read_gate_v1(bigint);
