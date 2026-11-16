-- Rollback of 0151. Fails closed once master changes have been recorded (audit history is never discarded).
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.master_requests_v1)
  OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE source_domain='master')
  OR EXISTS(SELECT 1 FROM core10.control_setting_versions_v1 WHERE feature_key LIKE 'master.%')
  OR EXISTS(SELECT 1 FROM core10.control_overrides_v1 WHERE feature_key LIKE 'master.%')
 THEN RAISE EXCEPTION 'MASTER_ROLLBACK_DENIED_PERSISTED_HISTORY'; END IF;
END $guard$;
DELETE FROM core10.control_rpc_map_v1 WHERE rpc_name LIKE 'master\_save\_%';
DROP FUNCTION IF EXISTS core10.master_validate_sales_order_v1(bigint,bigint,jsonb);
DROP FUNCTION IF EXISTS core10.master_uom_convert_v1(bigint,bigint,bigint,numeric);
DROP FUNCTION IF EXISTS core10.master_item_usable_v1(bigint,bigint);
DROP FUNCTION IF EXISTS core10.master_save_price_v1(bigint,bigint,bigint,bigint,bigint,numeric,numeric,boolean,integer,text);
DROP FUNCTION IF EXISTS core10.master_save_price_list_v1(bigint,text,text,text,text,text,bigint,date,date,text,integer,text);
DROP FUNCTION IF EXISTS core10.master_save_party_v1(bigint,text,text,text,text,text,text,text,integer,text);
DROP FUNCTION IF EXISTS core10.master_save_barcode_v1(bigint,text,bigint,bigint,bigint,boolean,integer,text);
DROP FUNCTION IF EXISTS core10.master_save_variant_v1(bigint,bigint,text,text,text,jsonb,text,integer,text);
DROP FUNCTION IF EXISTS core10.master_save_category_v1(bigint,text,text,text,bigint,boolean,integer,text);
DROP FUNCTION IF EXISTS core10.master_save_item_v1(bigint,text,text,text,text,bigint,bigint,text,integer,text);
DROP FUNCTION IF EXISTS core10.master_save_uom_conversion_v1(bigint,bigint,bigint,numeric,boolean,integer,text);
DROP FUNCTION IF EXISTS core10.master_save_uom_v1(bigint,text,text,text,text,smallint,boolean,integer,text);
DROP FUNCTION IF EXISTS core10._master_record_v1(bigint,bigint,text,text,bigint,integer,text,jsonb);
DROP FUNCTION IF EXISTS core10._master_replay_v1(bigint,text,text);
DROP FUNCTION IF EXISTS core10._master_gate_v1(bigint,text);
DROP TABLE IF EXISTS core10.master_requests_v1;
DELETE FROM core10.control_catalog_v1 WHERE feature_key IN ('master.uom','master.item','master.party','master.price');
