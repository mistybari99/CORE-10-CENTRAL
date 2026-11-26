-- Rollback of 0203: fail closed once any purchase order, receipt, lot or procurement audit exists.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.purchase_orders_v1) OR EXISTS(SELECT 1 FROM core10.inventory_lots_v1) OR
    EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE source_domain='procurement') OR
    EXISTS(SELECT 1 FROM core10.control_setting_versions_v1 WHERE feature_key LIKE 'procurement.%') OR
    EXISTS(SELECT 1 FROM core10.control_overrides_v1 WHERE feature_key LIKE 'procurement.%')
 THEN RAISE EXCEPTION 'PROC_ROLLBACK_DENIED_PERSISTED_HISTORY'; END IF;
END $guard$;
DELETE FROM core10.control_rpc_map_v1 WHERE lane='Claude' AND board_row='B-012' AND rpc_name IN
 ('procurement_save_po_v1','procurement_advance_po_v1','procurement_receive_v1','procurement_inspect_v1','procurement_post_grn_v1');
DROP FUNCTION core10.procurement_get_po_v1(bigint);
DROP FUNCTION core10.procurement_list_pos_v1(bigint,bigint,text,bigint,integer);
DROP FUNCTION core10.procurement_post_grn_v1(bigint,integer,text);
DROP FUNCTION core10.procurement_inspect_v1(bigint,jsonb,integer,text);
DROP FUNCTION core10.procurement_receive_v1(bigint,bigint,jsonb,text,text);
DROP FUNCTION core10.procurement_advance_po_v1(bigint,text,integer,text);
DROP FUNCTION core10.procurement_save_po_v1(bigint,bigint,bigint,bigint,jsonb,date,text,integer,text);
DROP FUNCTION core10._proc_open_qty_v1(bigint,integer);
DROP FUNCTION core10._proc_po_json_v1(bigint);
DROP FUNCTION core10._proc_grn_json_v1(bigint);
DROP FUNCTION core10._proc_record_v1(bigint,bigint,text,text,bigint,text,text,jsonb);
DROP FUNCTION core10._proc_replay_v1(bigint,text,text,text);
DROP FUNCTION core10._proc_sha_v1(jsonb);
DROP TABLE core10.procurement_requests_v1;
DROP TABLE core10.goods_receipt_lines_v1;
DROP TABLE core10.goods_receipts_v1;
DROP TABLE core10.inventory_lots_v1;
DROP TABLE core10.purchase_order_lines_v1;
DROP TABLE core10.purchase_orders_v1;
DELETE FROM core10.control_catalog_v1 WHERE feature_key IN ('procurement.purchase_order','procurement.goods_receipt');
